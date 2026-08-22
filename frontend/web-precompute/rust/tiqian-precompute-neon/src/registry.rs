//! Process-wide registries keyed by generated handle strings. Sessions keep
//! the ids the Rust session layer assigned; precomputers and HTML preparers
//! are addressable only through this registry, so several preparers can share
//! one precomputer while the caller keeps using it directly.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use tiqian_precompute::precompute_html::HtmlPreparer;
use tiqian_precompute::precomputer::Precomputer;
use tiqian_precompute::session::FontSession;
use tiqian_precompute::snapshot_tables::SnapshotTables;

static SESSIONS: OnceLock<Mutex<HashMap<String, FontSession>>> = OnceLock::new();
static PRECOMPUTERS: OnceLock<Mutex<HashMap<String, Arc<Precomputer>>>> = OnceLock::new();
static HTML_PREPARERS: OnceLock<Mutex<HashMap<String, HtmlPreparer>>> = OnceLock::new();
static SNAPSHOT_TABLES: OnceLock<Mutex<HashMap<String, SnapshotTables>>> = OnceLock::new();
static NEXT_HANDLE: AtomicU64 = AtomicU64::new(0);

fn sessions() -> &'static Mutex<HashMap<String, FontSession>> {
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn precomputers() -> &'static Mutex<HashMap<String, Arc<Precomputer>>> {
    PRECOMPUTERS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn html_preparers() -> &'static Mutex<HashMap<String, HtmlPreparer>> {
    HTML_PREPARERS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn snapshot_tables() -> &'static Mutex<HashMap<String, SnapshotTables>> {
    SNAPSHOT_TABLES.get_or_init(|| Mutex::new(HashMap::new()))
}

fn next_handle(prefix: &str) -> String {
    let value = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
    format!("{prefix}-{value}")
}

/// Locks a registry mutex, recovering the guard after a panic in another
/// thread: the maps stay structurally valid, so lookups and inserts on the
/// recovered guard remain safe and no call panics on poisoning.
fn recover<T>(lock: Result<T, std::sync::PoisonError<T>>) -> T {
    lock.unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Registers a created session and returns its id.
pub fn insert(session: FontSession) -> String {
    let id = session.session_id.clone();
    let mut map = recover(sessions().lock());
    map.insert(id.clone(), session);
    id
}

/// Runs `call` with the session for `id`, holding the registry lock.
pub fn with_session<T>(id: &str, call: impl FnOnce(&mut FontSession) -> T) -> Result<T, String> {
    let mut map = recover(sessions().lock());
    match map.get_mut(id) {
        Some(session) => Ok(call(session)),
        None => Err(format!("UnknownFontSession:{id}")),
    }
}

/// Wraps a created precomputer in its shared handle, registers it and
/// returns the handle together with the handle the preparers share.
pub fn insert_precomputer(precomputer: Precomputer) -> (String, Arc<Precomputer>) {
    let shared = Arc::new(precomputer);
    let handle = next_handle("tq-precomputer");
    recover(precomputers().lock()).insert(handle.clone(), Arc::clone(&shared));
    (handle, shared)
}

/// The shared precomputer behind `handle`.
pub fn shared_precomputer(handle: &str) -> Result<Arc<Precomputer>, String> {
    recover(precomputers().lock())
        .get(handle)
        .cloned()
        .ok_or_else(|| format!("UnknownPrecomputer:{handle}"))
}

/// Runs `call` with the precomputer for `handle`. The registry lock is
/// released before the call; every precomputer method takes `&self`, so
/// concurrent callers (including the batch renderer pool) share one
/// precomputer without a lock held across a computation.
pub fn with_precomputer<T>(
    handle: &str,
    call: impl FnOnce(&Precomputer) -> T,
) -> Result<T, String> {
    let shared = shared_precomputer(handle)?;
    Ok(call(&shared))
}

/// Registers a created HTML preparer and returns its handle.
pub fn insert_preparer(preparer: HtmlPreparer) -> String {
    let handle = next_handle("tq-html-preparer");
    recover(html_preparers().lock()).insert(handle.clone(), preparer);
    handle
}

/// Runs `call` with the HTML preparer for `handle`.
pub fn with_preparer<T>(
    handle: &str,
    call: impl FnOnce(&mut HtmlPreparer) -> T,
) -> Result<T, String> {
    let mut map = recover(html_preparers().lock());
    match map.get_mut(handle) {
        Some(preparer) => Ok(call(preparer)),
        None => Err(format!("UnknownHtmlPreparer:{handle}")),
    }
}

/// Registers a created snapshot-table set and returns its handle. A build
/// absorbs article by article, freezes once, then renders against the frozen
/// rows, so every call goes through the registry with the lock held.
pub fn insert_snapshot_tables(tables: SnapshotTables) -> String {
    let handle = next_handle("tq-snapshot-tables");
    recover(snapshot_tables().lock()).insert(handle.clone(), tables);
    handle
}

/// Runs `call` with the snapshot tables for `handle`.
pub fn with_snapshot_tables<T>(
    handle: &str,
    call: impl FnOnce(&mut SnapshotTables) -> T,
) -> Result<T, String> {
    let mut map = recover(snapshot_tables().lock());
    match map.get_mut(handle) {
        Some(tables) => Ok(call(tables)),
        None => Err(format!("UnknownSnapshotTables:{handle}")),
    }
}

/// Drops the snapshot tables for `handle`; a miss reports false.
pub fn remove_snapshot_tables(handle: &str) -> bool {
    recover(snapshot_tables().lock()).remove(handle).is_some()
}
