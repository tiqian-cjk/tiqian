//! The layered cache of one precomputer (ADR 0052): a memory tier every
//! computation writes through, plus an adapter that persists. Records are
//! keyed by the store key ([`crate::canonical::store_key`]), which combines
//! the context fingerprint and the content hash inside Rust; adapters treat
//! keys as opaque bytes. Hash-first submission never reaches the adapter: the
//! submission path resolves hits against this store before any adapter
//! interaction.

use std::collections::{HashMap, HashSet, VecDeque};

use tiqian::NamedError;

use crate::canonical::digest;

/// The cache layers. Snapshot paragraphs and font contracts live in separate
/// namespaces of the same stores.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum CacheTier {
    Snapshot,
    FontContract,
}

impl CacheTier {
    pub fn code(self) -> u8 {
        match self {
            CacheTier::Snapshot => 0,
            CacheTier::FontContract => 1,
        }
    }

    pub fn from_code(code: u8) -> Option<Self> {
        match code {
            0 => Some(CacheTier::Snapshot),
            1 => Some(CacheTier::FontContract),
            _ => None,
        }
    }
}

/// One cached entry: the prepared-entry JSON bytes, their digest, and the
/// identities the drain protocol reports to the host.
#[derive(Clone)]
pub struct CacheRecord {
    pub tier: CacheTier,
    pub key: [u8; 32],
    pub content_hash: [u8; 32],
    pub artifact: Vec<u8>,
    pub artifact_sha: [u8; 32],
}

/// The persistence side of the layered store. Methods work in tiers, keys,
/// the context and bytes (ADR 0052); keys arrive as content-derived store
/// keys and adapters stay ignorant of how they were computed. Calls are
/// batch-shaped so a bridge crossing amortizes; no method re-enters the
/// engine.
pub trait CacheAdapter: Send + Sync {
    /// Reads records by key; `None` per missing key.
    fn read(&self, context: &[u8; 32], keys: &[[u8; 32]]) -> Vec<Option<CacheRecord>>;

    /// Writes complete records.
    fn write(&self, context: &[u8; 32], records: Vec<CacheRecord>);

    /// Removes records by key.
    fn remove(&self, context: &[u8; 32], keys: &[[u8; 32]]);

    /// A short adapter name for diagnostics.
    fn label(&self) -> &'static str;
}

/// The default adapter: nothing persists. The memory tier still serves
/// within-process repeats.
pub struct NoCache;

impl CacheAdapter for NoCache {
    fn read(&self, _context: &[u8; 32], keys: &[[u8; 32]]) -> Vec<Option<CacheRecord>> {
        vec![None; keys.len()]
    }

    fn write(&self, _context: &[u8; 32], _records: Vec<CacheRecord>) {}

    fn remove(&self, _context: &[u8; 32], _keys: &[[u8; 32]]) {}

    fn label(&self) -> &'static str {
        "none"
    }
}

/// The host-declared write budget of [`DrainQueueAdapter`], as a posture
/// tier rather than raw bytes (ADR 0052): the host knows its environment by
/// feel while the record sizes that anchor the mapping are measured
/// engine-side, so the host picks a tier and the engine owns the byte table.
/// Every tier must clear the largest single record; the largest observed
/// article product is about 3 MiB.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum WriteBudgetTier {
    /// For constrained runners such as CI containers.
    Tight,
    /// The default; matches the historical fixed budget.
    Normal,
    /// For hosts that queue far between flushes (long SSR batches).
    Generous,
}

impl WriteBudgetTier {
    pub fn from_code(code: u8) -> Option<Self> {
        match code {
            0 => Some(WriteBudgetTier::Tight),
            1 => Some(WriteBudgetTier::Normal),
            2 => Some(WriteBudgetTier::Generous),
            _ => None,
        }
    }

    /// `Tight` clears the largest measured record twice over; `Generous`
    /// stays a small fraction of the observed build memory peaks.
    pub fn bytes(self) -> usize {
        match self {
            WriteBudgetTier::Tight => 8 * 1024 * 1024,
            WriteBudgetTier::Normal => 32 * 1024 * 1024,
            WriteBudgetTier::Generous => 128 * 1024 * 1024,
        }
    }
}

/// The adapter behind the Neon bridge: writes collect in a queue the host
/// drains per batch, reads come only from the prefetch direction (the host
/// writes warmed entries into the memory tier directly), so this adapter
/// answers reads with misses. No computation ever calls back into JS through
/// it.
pub struct DrainQueueAdapter {
    queue: std::sync::Mutex<Vec<CacheRecord>>,
    max_bytes: usize,
}

impl DrainQueueAdapter {
    pub fn new(budget: WriteBudgetTier) -> Self {
        DrainQueueAdapter {
            queue: std::sync::Mutex::new(Vec::new()),
            max_bytes: budget.bytes(),
        }
    }

    /// Takes the buffered writes, in write order.
    pub fn drain(&self) -> Vec<CacheRecord> {
        let mut queue = crate::parallel::recover(self.queue.lock());
        std::mem::take(&mut *queue)
    }

    /// Whether one more record of `incoming` bytes stays within the budget.
    pub fn has_room_for(&self, incoming: usize) -> bool {
        let queue = crate::parallel::recover(self.queue.lock());
        let buffered = queue
            .iter()
            .map(|record| record.artifact.len())
            .sum::<usize>();
        buffered.saturating_add(incoming) <= self.max_bytes
    }
}

/// The [`CacheAdapter`] view of a shared drain queue: the store boxes this
/// forwarder, both sides reach the same queue.
struct SharedDrainQueue(std::sync::Arc<DrainQueueAdapter>);

impl CacheAdapter for SharedDrainQueue {
    fn read(&self, _context: &[u8; 32], keys: &[[u8; 32]]) -> Vec<Option<CacheRecord>> {
        vec![None; keys.len()]
    }

    fn write(&self, _context: &[u8; 32], records: Vec<CacheRecord>) {
        let mut queue = crate::parallel::recover(self.0.queue.lock());
        for record in records {
            queue.push(record);
        }
    }

    fn remove(&self, _context: &[u8; 32], _keys: &[[u8; 32]]) {}

    fn label(&self) -> &'static str {
        "drain-queue"
    }
}

/// Memory tier bound: entries evict in insertion order when the tier exceeds
/// this many records. Build-time reuse concentrates near the insert point, so
/// old entries are the safe ones to drop.
const MEMORY_TIER_MAX_RECORDS: usize = 8192;

struct MemoryTier {
    map: HashMap<[u8; 32], std::sync::Arc<CacheRecord>>,
    order: VecDeque<[u8; 32]>,
    max_records: usize,
}

impl MemoryTier {
    fn new() -> Self {
        MemoryTier {
            map: HashMap::new(),
            order: VecDeque::new(),
            max_records: MEMORY_TIER_MAX_RECORDS,
        }
    }

    fn get(&self, key: &[u8; 32]) -> Option<std::sync::Arc<CacheRecord>> {
        self.map.get(key).cloned()
    }

    fn insert(&mut self, record: CacheRecord) -> std::sync::Arc<CacheRecord> {
        let key = record.key;
        let shared = std::sync::Arc::new(record);
        if self.map.insert(key, shared.clone()).is_none() {
            self.order.push_back(key);
        }
        while self.order.len() > self.max_records {
            let Some(oldest) = self.order.pop_front() else {
                break;
            };
            self.map.remove(&oldest);
        }
        shared
    }

    fn evict_except(&mut self, keep: &HashSet<[u8; 32]>) {
        self.order.retain(|key| keep.contains(key));
        self.map.retain(|key, _| keep.contains(key));
    }
}

/// The layered store of one precomputer: context, memory tier, adapter.
pub struct LayeredCacheStore {
    context: [u8; 32],
    memory: std::sync::RwLock<MemoryTier>,
    adapter: Box<dyn CacheAdapter>,
    drain_queue: Option<std::sync::Arc<DrainQueueAdapter>>,
}

impl LayeredCacheStore {
    pub fn new(context: [u8; 32], adapter: Box<dyn CacheAdapter>) -> Self {
        LayeredCacheStore {
            context,
            memory: std::sync::RwLock::new(MemoryTier::new()),
            adapter,
            drain_queue: None,
        }
    }

    /// The bridge store: a drain queue shared between the adapter box and
    /// the handle the Neon layer drains through.
    pub fn with_drain_queue(
        context: [u8; 32],
        budget: WriteBudgetTier,
    ) -> (Self, std::sync::Arc<DrainQueueAdapter>) {
        let queue = std::sync::Arc::new(DrainQueueAdapter::new(budget));
        (
            LayeredCacheStore {
                context,
                memory: std::sync::RwLock::new(MemoryTier::new()),
                adapter: Box::new(SharedDrainQueue(queue.clone())),
                drain_queue: Some(queue.clone()),
            },
            queue,
        )
    }

    pub fn context(&self) -> &[u8; 32] {
        &self.context
    }

    pub fn adapter_label(&self) -> &'static str {
        self.adapter.label()
    }

    /// Looks records up: memory first, then the adapter for whatever missed;
    /// adapter hits promote into memory.
    pub fn lookup(&self, keys: &[[u8; 32]]) -> Vec<Option<std::sync::Arc<CacheRecord>>> {
        let mut results: Vec<Option<std::sync::Arc<CacheRecord>>> = Vec::with_capacity(keys.len());
        let mut missing: Vec<usize> = Vec::new();
        {
            let memory = crate::parallel::recover(self.memory.read());
            for (index, key) in keys.iter().enumerate() {
                match memory.get(key) {
                    Some(record) => results.push(Some(record)),
                    None => {
                        results.push(None);
                        missing.push(index);
                    }
                }
            }
        }
        if missing.is_empty() {
            return results;
        }
        let adapter_keys: Vec<[u8; 32]> = missing.iter().map(|index| keys[*index]).collect();
        let adapter_records = self.adapter.read(&self.context, &adapter_keys);
        let mut memory = crate::parallel::recover(self.memory.write());
        for (index, record) in missing.into_iter().zip(adapter_records) {
            if let Some(record) = record {
                results[index] = Some(memory.insert(record));
            }
        }
        results
    }

    /// Write-through: memory tier first, then the adapter. A buffered drain
    /// queue reports a named error once its budget is exhausted; the host
    /// drains and continues.
    pub fn store(&self, record: CacheRecord) -> Result<std::sync::Arc<CacheRecord>, NamedError> {
        if let Some(queue) = &self.drain_queue {
            if !queue.has_room_for(record.artifact.len()) {
                return Err(NamedError("CacheWriteBufferFull".to_string()));
            }
        }
        let shared = {
            let mut memory = crate::parallel::recover(self.memory.write());
            memory.insert(record.clone())
        };
        self.adapter.write(&self.context, vec![record]);
        Ok(shared)
    }

    /// Prefetch: the host pushes warmed records into the memory tier. The
    /// digest and the key combination are verified here so a corrupted or
    /// foreign record cannot enter under a borrowed key.
    pub fn prefetch(&self, records: Vec<CacheRecord>) -> Result<usize, NamedError> {
        let mut memory = crate::parallel::recover(self.memory.write());
        let mut accepted = 0;
        for record in records {
            if digest(&record.artifact) != record.artifact_sha {
                return Err(NamedError("CachePrefetchDigestMismatch".to_string()));
            }
            if crate::canonical::store_key(&self.context, &record.content_hash) != record.key {
                return Err(NamedError("CachePrefetchKeyMismatch".to_string()));
            }
            memory.insert(record);
            accepted += 1;
        }
        Ok(accepted)
    }

    /// Drops memory-tier records whose key is not in `keep`. Persistent
    /// eviction is the host's anti-join over article indexes; this keeps the
    /// memory tier consistent with it.
    pub fn evict_except(&self, keep: &HashSet<[u8; 32]>) {
        let mut memory = crate::parallel::recover(self.memory.write());
        memory.evict_except(keep);
    }

    /// Takes the buffered drain-queue writes; only the bridge store has one.
    pub fn drain(&self) -> Vec<CacheRecord> {
        match &self.drain_queue {
            Some(queue) => queue.drain(),
            None => Vec::new(),
        }
    }
}

/// Tests for the layered store over a counting in-memory adapter.
#[cfg(test)]
mod tests {
    use super::*;

    struct CountingAdapter {
        entries: std::sync::RwLock<HashMap<[u8; 32], CacheRecord>>,
    }

    impl CountingAdapter {
        fn new() -> Self {
            CountingAdapter {
                entries: std::sync::RwLock::new(HashMap::new()),
            }
        }
    }

    impl CacheAdapter for CountingAdapter {
        fn read(&self, _context: &[u8; 32], keys: &[[u8; 32]]) -> Vec<Option<CacheRecord>> {
            let entries = self.entries.read().unwrap();
            keys.iter().map(|key| entries.get(key).cloned()).collect()
        }

        fn write(&self, _context: &[u8; 32], records: Vec<CacheRecord>) {
            let mut entries = self.entries.write().unwrap();
            for record in records {
                entries.insert(record.key, record);
            }
        }

        fn remove(&self, _context: &[u8; 32], keys: &[[u8; 32]]) {
            let mut entries = self.entries.write().unwrap();
            for key in keys {
                entries.remove(key);
            }
        }

        fn label(&self) -> &'static str {
            "counting"
        }
    }

    fn record(key_byte: u8, content_byte: u8) -> CacheRecord {
        let content_hash = [content_byte; 32];
        CacheRecord {
            tier: CacheTier::Snapshot,
            key: [key_byte; 32],
            content_hash,
            artifact: format!("artifact-{key_byte}").into_bytes(),
            artifact_sha: digest(format!("artifact-{key_byte}").as_bytes()),
        }
    }

    #[test]
    fn store_then_lookup_hits_memory() {
        let store = LayeredCacheStore::new([1; 32], Box::new(CountingAdapter::new()));
        let stored = store.store(record(7, 3)).expect("store succeeds");
        assert_eq!(stored.artifact, b"artifact-7");
        let hits = store.lookup(&[[7; 32]]);
        assert!(hits[0].is_some());
    }

    #[test]
    fn adapter_hit_promotes_into_memory() {
        // A record that exists only behind the adapter is served once from
        // the adapter and then from the memory tier.
        struct EmptyThenReadAdapter {
            served: std::sync::atomic::AtomicUsize,
        }
        impl CacheAdapter for EmptyThenReadAdapter {
            fn read(&self, _context: &[u8; 32], _keys: &[[u8; 32]]) -> Vec<Option<CacheRecord>> {
                if self
                    .served
                    .fetch_add(1, std::sync::atomic::Ordering::SeqCst)
                    == 0
                {
                    vec![Some(record(5, 9))]
                } else {
                    vec![None]
                }
            }
            fn write(&self, _context: &[u8; 32], _records: Vec<CacheRecord>) {}
            fn remove(&self, _context: &[u8; 32], _keys: &[[u8; 32]]) {}
            fn label(&self) -> &'static str {
                "empty-then-read"
            }
        }
        let store = LayeredCacheStore::new(
            [2; 32],
            Box::new(EmptyThenReadAdapter {
                served: std::sync::atomic::AtomicUsize::new(0),
            }),
        );
        assert!(store.lookup(&[[5; 32]])[0].is_some());
        assert!(store.lookup(&[[5; 32]])[0].is_some());
    }

    #[test]
    fn prefetch_rejects_a_damaged_artifact() {
        let store = LayeredCacheStore::new([1; 32], Box::new(NoCache));
        let mut damaged = record(4, 4);
        damaged.artifact.push(b'!');
        let error = store.prefetch(vec![damaged]).expect_err("rejects");
        assert_eq!(error.0, "CachePrefetchDigestMismatch");
    }

    #[test]
    fn prefetch_rejects_a_foreign_key() {
        // A record whose key does not combine the context and content hash
        // cannot enter the tier, even with a self-consistent digest.
        let context = [1; 32];
        let mut foreign = record(4, 4);
        let artifact = format!("artifact-{}", 4).into_bytes();
        foreign.artifact = artifact.clone();
        foreign.artifact_sha = digest(&artifact);
        foreign.key = [250; 32];
        let store = LayeredCacheStore::new(context, Box::new(NoCache));
        let error = store.prefetch(vec![foreign]).expect_err("rejects");
        assert_eq!(error.0, "CachePrefetchKeyMismatch");
    }

    #[test]
    fn eviction_keeps_the_listed_keys() {
        let store = LayeredCacheStore::new([1; 32], Box::new(NoCache));
        store.store(record(1, 1)).expect("store succeeds");
        store.store(record(2, 2)).expect("store succeeds");
        let mut keep = HashSet::new();
        keep.insert([2; 32]);
        store.evict_except(&keep);
        assert!(store.lookup(&[[1; 32]])[0].is_none());
        assert!(store.lookup(&[[2; 32]])[0].is_some());
    }

    #[test]
    fn drain_queue_adapter_collects_writes_in_order() {
        let adapter = std::sync::Arc::new(DrainQueueAdapter::new(WriteBudgetTier::Normal));
        let view = SharedDrainQueue(adapter.clone());
        let context = [3; 32];
        CacheAdapter::write(&view, &context, vec![record(1, 1)]);
        CacheAdapter::write(&view, &context, vec![record(2, 2)]);
        let drained = adapter.drain();
        assert_eq!(drained.len(), 2);
        assert_eq!(drained[0].artifact, b"artifact-1");
        assert_eq!(drained[1].artifact, b"artifact-2");
        assert!(adapter.drain().is_empty());
    }

    #[test]
    fn write_budget_tiers_round_trip_and_order_bytes() {
        assert_eq!(WriteBudgetTier::from_code(0), Some(WriteBudgetTier::Tight));
        assert_eq!(WriteBudgetTier::from_code(1), Some(WriteBudgetTier::Normal));
        assert_eq!(
            WriteBudgetTier::from_code(2),
            Some(WriteBudgetTier::Generous)
        );
        assert_eq!(WriteBudgetTier::from_code(3), None);
        assert!(WriteBudgetTier::Tight.bytes() < WriteBudgetTier::Normal.bytes());
        assert!(WriteBudgetTier::Normal.bytes() < WriteBudgetTier::Generous.bytes());
        // Every tier must clear the largest observed article product
        // (about 3 MiB); Tight is the binding constraint.
        assert!(WriteBudgetTier::Tight.bytes() > 4 * 1024 * 1024);
    }

    #[test]
    fn drain_queue_reports_named_error_past_its_budget() {
        let (store, queue) = LayeredCacheStore::with_drain_queue([4; 32], WriteBudgetTier::Tight);
        let mut oversized = record(9, 9);
        // Tight is 8 MiB; this record alone exceeds it.
        oversized.artifact = vec![b'x'; WriteBudgetTier::Tight.bytes() + 1];
        let error = match store.store(oversized) {
            Ok(_) => panic!("oversized store fails"),
            Err(error) => error,
        };
        assert_eq!(error.0, "CacheWriteBufferFull");
        // The failed record never entered the queue: the buffer stayed empty.
        assert!(queue.drain().is_empty());
        let fitting = record(1, 1);
        assert!(store.store(fitting).is_ok());
        assert_eq!(queue.drain().len(), 1);
    }
}
