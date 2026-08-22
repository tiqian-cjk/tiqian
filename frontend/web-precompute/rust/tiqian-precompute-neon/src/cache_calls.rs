//! The cache and submission bridge exports (ADR 0052). Binary buffers in,
//! binary buffers out: the wrapper packs and unpacks on the js side with the
//! mirrored encoder, no JSON crosses this boundary. Every multi-byte integer
//! is little-endian and every buffer starts with a magic and a version byte,
//! the same family as the canonical form.
//!
//! Formats:
//! - results ("TQSR", v1): u32 count, then per item u8 status: 0 computed
//!   (u32 length + entry bytes), 1 hit (32-byte artifact digest), 2
//!   need-content.
//! - records ("TQCR", v1): u32 count, then per record u8 tier, 32-byte key,
//!   32-byte content hash, 32-byte artifact digest, u32 length + artifact.
//! - submissions ("TQSU", v1): u32 count, then per item 32-byte hash, u32
//!   length + logical key, u32 length + canonical bytes.
//! - hash arrays: raw 32-byte hashes, the count is the length divided by 32.

use neon::prelude::*;
use neon::types::buffer::TypedArray;

use tiqian_precompute::cache::{CacheRecord, CacheTier};
use tiqian_precompute::submission::{SubmissionItem, SubmissionOutcome};

use crate::registry;

const RESULTS_MAGIC: &[u8; 4] = b"TQSR";
const RECORDS_MAGIC: &[u8; 4] = b"TQCR";
const SUBMISSIONS_MAGIC: &[u8; 4] = b"TQSU";
const BRIDGE_VERSION: u8 = 1;

/// Bounds-checked reading over one packed buffer. Every failure is a named
/// issue; the wrapper's buffers come from its own encoder, so a malformed
/// buffer is a wrapper bug.
struct BridgeReader<'a> {
    bytes: &'a [u8],
    cursor: usize,
}

impl<'a> BridgeReader<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        BridgeReader { bytes, cursor: 0 }
    }

    fn take(&mut self, len: usize) -> Result<&'a [u8], String> {
        let end = self
            .cursor
            .checked_add(len)
            .ok_or_else(|| "InvalidCacheBuffer".to_string())?;
        if end > self.bytes.len() {
            return Err("InvalidCacheBuffer".to_string());
        }
        let slice = &self.bytes[self.cursor..end];
        self.cursor = end;
        Ok(slice)
    }

    fn u8(&mut self) -> Result<u8, String> {
        let slice = self.take(1)?;
        Ok(slice[0])
    }

    fn u32(&mut self) -> Result<u32, String> {
        let slice = self.take(4)?;
        Ok(u32::from_le_bytes([slice[0], slice[1], slice[2], slice[3]]))
    }

    fn length(&mut self) -> Result<usize, String> {
        usize::try_from(self.u32()?).map_err(|_| "InvalidCacheBuffer".to_string())
    }

    fn header(&mut self, magic: &[u8; 4]) -> Result<u32, String> {
        if self.take(4)? != magic {
            return Err("InvalidCacheMagic".to_string());
        }
        if self.u8()? != BRIDGE_VERSION {
            return Err("InvalidCacheBridgeVersion".to_string());
        }
        self.u32()
    }

    fn done(&self) -> Result<(), String> {
        if self.cursor == self.bytes.len() {
            Ok(())
        } else {
            Err("InvalidCacheBuffer".to_string())
        }
    }
}

fn push_u32(out: &mut Vec<u8>, value: u32) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn push_length(out: &mut Vec<u8>, len: usize) {
    push_u32(out, u32::try_from(len).unwrap_or(u32::MAX));
}

fn push_header(out: &mut Vec<u8>, magic: &[u8; 4]) {
    out.extend_from_slice(magic);
    out.push(BRIDGE_VERSION);
}

fn hex32(bytes: &[u8; 32]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(64);
    for byte in bytes {
        out.push(char::from(DIGITS[usize::from(byte >> 4)]));
        out.push(char::from(DIGITS[usize::from(byte & 0x0f)]));
    }
    out
}

/// Reads a raw hash array: 32 bytes per hash.
fn hash_array(bytes: &[u8]) -> Result<Vec<[u8; 32]>, String> {
    if bytes.len() % 32 != 0 {
        return Err("InvalidHashBuffer".to_string());
    }
    let mut hashes = Vec::with_capacity(bytes.len() / 32);
    for index in 0..bytes.len() / 32 {
        let start = index * 32;
        let mut hash = [0u8; 32];
        hash.copy_from_slice(&bytes[start..start + 32]);
        hashes.push(hash);
    }
    Ok(hashes)
}

fn read_records(bytes: &[u8]) -> Result<Vec<CacheRecord>, String> {
    let mut reader = BridgeReader::new(bytes);
    let count = reader.header(RECORDS_MAGIC)?;
    let mut records = Vec::new();
    for _ in 0..count {
        let tier = CacheTier::from_code(reader.u8()?).ok_or("InvalidCacheTier")?;
        let mut fixed = [0u8; 32];
        fixed.copy_from_slice(reader.take(32)?);
        let key = fixed;
        fixed.copy_from_slice(reader.take(32)?);
        let content_hash = fixed;
        fixed.copy_from_slice(reader.take(32)?);
        let artifact_sha = fixed;
        let artifact_len = reader.length()?;
        let artifact = reader.take(artifact_len)?.to_vec();
        records.push(CacheRecord {
            tier,
            key,
            content_hash,
            artifact,
            artifact_sha,
        });
    }
    reader.done()?;
    Ok(records)
}

fn write_records(records: &[CacheRecord]) -> Vec<u8> {
    let mut out = Vec::new();
    push_header(&mut out, RECORDS_MAGIC);
    push_u32(&mut out, u32::try_from(records.len()).unwrap_or(u32::MAX));
    for record in records {
        out.push(record.tier.code());
        out.extend_from_slice(&record.key);
        out.extend_from_slice(&record.content_hash);
        out.extend_from_slice(&record.artifact_sha);
        push_length(&mut out, record.artifact.len());
        out.extend_from_slice(&record.artifact);
    }
    out
}

fn read_items(bytes: &[u8]) -> Result<Vec<SubmissionItem>, String> {
    let mut reader = BridgeReader::new(bytes);
    let count = reader.header(SUBMISSIONS_MAGIC)?;
    let mut items = Vec::new();
    for _ in 0..count {
        let mut fixed = [0u8; 32];
        fixed.copy_from_slice(reader.take(32)?);
        let hash = fixed;
        let key_len = reader.length()?;
        let key = reader.take(key_len)?.to_vec();
        let logical_key = String::from_utf8(key).map_err(|_| "InvalidSubmissionKey")?;
        let canonical_len = reader.length()?;
        let canonical = reader.take(canonical_len)?.to_vec();
        items.push(SubmissionItem {
            hash,
            logical_key,
            canonical,
        });
    }
    reader.done()?;
    Ok(items)
}

fn write_results(outcomes: &[SubmissionOutcome]) -> Vec<u8> {
    let mut out = Vec::new();
    push_header(&mut out, RESULTS_MAGIC);
    push_u32(&mut out, u32::try_from(outcomes.len()).unwrap_or(u32::MAX));
    for outcome in outcomes {
        match outcome {
            SubmissionOutcome::Computed { artifact } => {
                out.push(0);
                push_length(&mut out, artifact.len());
                out.extend_from_slice(artifact);
            }
            SubmissionOutcome::Hit { artifact_sha } => {
                out.push(1);
                out.extend_from_slice(artifact_sha);
            }
            SubmissionOutcome::NeedContent => {
                out.push(2);
            }
        }
    }
    out
}

fn buffer_argument(cx: &mut FunctionContext, index: usize) -> NeonResult<Vec<u8>> {
    let buffer = cx.argument::<JsBuffer>(index)?;
    Ok(buffer.as_slice(cx).to_vec())
}

/// `cacheContext(handle)`: the precomputer's context fingerprint as hex. The
/// host namespaces its persistent store with it; the value stays opaque.
pub fn cache_context(mut cx: FunctionContext) -> JsResult<JsString> {
    let handle = cx.argument::<JsString>(0)?.value(&mut cx);
    let context = registry::with_precomputer(&handle, |precomputer| *precomputer.cache_context());
    match context {
        Ok(context) => Ok(cx.string(hex32(&context))),
        Err(error) => cx.throw_error(error),
    }
}

/// `cacheSubmitHashes(handle, hashes)`: the hash-only lane. Results arrive as
/// a results buffer; hits carry the artifact digest and never move content.
pub fn cache_submit_hashes(mut cx: FunctionContext) -> JsResult<JsBuffer> {
    let handle = cx.argument::<JsString>(0)?.value(&mut cx);
    let bytes = buffer_argument(&mut cx, 1)?;
    let hashes = match hash_array(&bytes) {
        Ok(hashes) => hashes,
        Err(error) => return cx.throw_error(error),
    };
    let result =
        registry::with_precomputer(&handle, |precomputer| precomputer.submit_hashes(&hashes));
    match result {
        Ok(Ok(outcomes)) => JsBuffer::from_slice(&mut cx, &write_results(&outcomes)),
        Ok(Err(error)) => cx.throw_error(error.0),
        Err(error) => cx.throw_error(error),
    }
}

/// Runs a blocking submission, keeping any resumed worker panic inside Rust:
/// the waiter reports the named issue instead of unwinding through the node
/// boundary.
fn blocking_submission<T>(
    cx: &mut FunctionContext,
    call: impl FnOnce() -> Result<T, tiqian_precompute::NamedError>,
) -> NeonResult<T> {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(call)) {
        Ok(Ok(value)) => Ok(value),
        Ok(Err(error)) => cx.throw_error(error.0),
        Err(_) => cx.throw_error("RenderJobPanicked"),
    }
}

/// `cacheSubmitContents(handle, submissions)`: the waiting egress. The call
/// parks until every item resolved; results arrive as a results buffer.
pub fn cache_submit_contents(mut cx: FunctionContext) -> JsResult<JsBuffer> {
    let handle = cx.argument::<JsString>(0)?.value(&mut cx);
    let bytes = buffer_argument(&mut cx, 1)?;
    let items = match read_items(&bytes) {
        Ok(items) => items,
        Err(error) => return cx.throw_error(error),
    };
    let shared = match registry::shared_precomputer(&handle) {
        Ok(shared) => shared,
        Err(error) => return cx.throw_error(error),
    };
    let outcomes = blocking_submission(&mut cx, || shared.submit_contents(items))?;
    JsBuffer::from_slice(&mut cx, &write_results(&outcomes))
}

/// `cachePrefillContents(handle, submissions)`: the background egress. The
/// call returns once everything queued; failures surface when the same
/// content arrives through the waiting lane.
pub fn cache_prefill_contents(mut cx: FunctionContext) -> JsResult<JsNumber> {
    let handle = cx.argument::<JsString>(0)?.value(&mut cx);
    let bytes = buffer_argument(&mut cx, 1)?;
    let items = match read_items(&bytes) {
        Ok(items) => items,
        Err(error) => return cx.throw_error(error),
    };
    let shared = match registry::shared_precomputer(&handle) {
        Ok(shared) => shared,
        Err(error) => return cx.throw_error(error),
    };
    let queued = blocking_submission(&mut cx, || shared.prefill_contents(items))?;
    let counted = u32::try_from(queued).unwrap_or(u32::MAX);
    Ok(cx.number(f64::from(counted)))
}

/// `cachePrefetch(handle, records)`: warms the memory tier with records the
/// host read back from its persistent store.
pub fn cache_prefetch(mut cx: FunctionContext) -> JsResult<JsNumber> {
    let handle = cx.argument::<JsString>(0)?.value(&mut cx);
    let bytes = buffer_argument(&mut cx, 1)?;
    let records = match read_records(&bytes) {
        Ok(records) => records,
        Err(error) => return cx.throw_error(error),
    };
    let result = registry::with_precomputer(&handle, |precomputer| {
        precomputer.cache_store().prefetch(records)
    });
    match result {
        Ok(Ok(accepted)) => {
            let counted = u32::try_from(accepted).unwrap_or(u32::MAX);
            Ok(cx.number(f64::from(counted)))
        }
        Ok(Err(error)) => cx.throw_error(error.0),
        Err(error) => cx.throw_error(error),
    }
}

/// `cacheDrainWrites(handle)`: takes the buffered writes for the host to
/// persist, as a records buffer in write order.
pub fn cache_drain_writes(mut cx: FunctionContext) -> JsResult<JsBuffer> {
    let handle = cx.argument::<JsString>(0)?.value(&mut cx);
    let drained =
        registry::with_precomputer(&handle, |precomputer| precomputer.cache_store().drain());
    match drained {
        Ok(records) => JsBuffer::from_slice(&mut cx, &write_records(&records)),
        Err(error) => cx.throw_error(error),
    }
}

/// `cacheEvictExcept(handle, keys)`: drops memory-tier records whose store
/// key is not listed; the host runs the same anti-join over its persistent
/// store.
pub fn cache_evict_except(mut cx: FunctionContext) -> JsResult<JsUndefined> {
    let handle = cx.argument::<JsString>(0)?.value(&mut cx);
    let bytes = buffer_argument(&mut cx, 1)?;
    let keys = match hash_array(&bytes) {
        Ok(keys) => keys,
        Err(error) => return cx.throw_error(error),
    };
    let keep: std::collections::HashSet<[u8; 32]> = keys.into_iter().collect();
    let result = registry::with_precomputer(&handle, |precomputer| {
        precomputer.cache_store().evict_except(&keep)
    });
    match result {
        Ok(()) => Ok(cx.undefined()),
        Err(error) => cx.throw_error(error),
    }
}
