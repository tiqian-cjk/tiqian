// The host-facing persistence SDK over the cache bridge (ADR 0052). Hosts
// hand over a plain address-to-bytes store; this module derives the cache
// addresses from the context fingerprint and the content hashes, hydrates
// the memory tier from the store, drives the hash-first submission lanes,
// verifies hits against the artifact digests and persists drained records
// back. Record bytes stay opaque to the host: the store never learns the
// entry format, and a format change invalidates through the context
// fingerprint alone. Stored blobs carry the bridge record deflated
// (ADR 0052 DeflatedStoreRecords): the artifact JSON repeats field names
// and decimal text per glyph, so the compressed row is a fraction of the
// plain form while the inflated bytes still verify against the artifact
// digest, keeping the hit contract unchanged. Plain records written before
// deflation stay readable; their next rewrite compresses.

import { createHash } from "node:crypto";
import { deflateSync, inflateSync } from "node:zlib";

import type {
  FontContractInput,
  PreparedEntry,
  SnapshotParagraphInput,
} from "./precompute.js";
import type { CacheBridge, CacheRecord, SubmissionItem } from "./cache.js";
import { backfillRenderFields } from "./precompute.js";
import { packRecords, submissionItem, unpackRecords } from "./cache.js";
import { KIND_CONTRACT, KIND_SNAPSHOT, type CanonicalKind } from "./canonical.js";

/**
 * One host-owned address-to-bytes store. Addresses and record bytes are
 * opaque: the SDK derives an address from the precomputer context and the
 * content hash, and the value is the bridge's serialized record form. Reads
 * return only the addresses the store actually holds.
 */
export interface PersistentCacheStore {
  read(
    addresses: readonly string[],
  ): Map<string, Uint8Array> | Promise<Map<string, Uint8Array>>;
  write(entries: readonly (readonly [string, Uint8Array])[]): void | Promise<void>;
  /**
   * Records article-index rows, replacing the rows of the same article
   * keys (ADR 0052 Article layer). One call must carry an article's full
   * hash set for the context: the replacement drops whatever the article
   * recorded before.
   */
  recordArticles?(
    context: string,
    articles: readonly ArticleIndexRecord[],
  ): void | Promise<void>;
  /** Reads every article row of one context. */
  readArticles?(context: string): ArticleIndexRecord[] | Promise<ArticleIndexRecord[]>;
  /** Deletes article rows by key; returns the row count removed. */
  deleteArticles?(
    context: string,
    articleKeys: readonly string[],
  ): number | Promise<number>;
  /**
   * Drops entries of one context that are not in the keep list. Article
   * rows are index data, not entries, so a prune leaves them alone.
   */
  prune?(context: string, keep: readonly string[]): number | Promise<number>;
  /**
   * Bucket-scoped eviction (ADR 0052 BucketIntersectionEviction): the host
   * hands one bucket id plus that bucket's current content hashes, and the
   * store deletes the entries the bucket's article rows attribute but the
   * list omits, protecting entries other buckets' rows still reference.
   * The bucket's hash rows are trimmed to the list and emptied article rows
   * are dropped. Returns the entry count removed. Sweeping every bucket
   * converges on the whole-context union keep set, one bounded list per call.
   */
  pruneBucket?(
    context: string,
    bucket: string,
    keep: readonly string[],
  ): number | Promise<number>;
}

/**
 * One article-index row (ADR 0052 Article layer): the unit of invalidation
 * and whole-article load. `bucket` is a host-chosen group tag; content
 * hashes are the hex form the cache addresses derive from.
 */
export interface ArticleIndexRecord {
  readonly articleKey: string;
  readonly bucket: string;
  readonly contentHashes: readonly string[];
}

/** The store surface the Article layer needs beyond plain entries. */
type ArticleIndexStore = PersistentCacheStore & {
  recordArticles(
    context: string,
    articles: readonly ArticleIndexRecord[],
  ): void | Promise<void>;
  readArticles(context: string): ArticleIndexRecord[] | Promise<ArticleIndexRecord[]>;
  deleteArticles(context: string, articleKeys: readonly string[]): number | Promise<number>;
};

/** The persistence front of one precomputer. */
export interface PersistentCache {
  /** The context fingerprint as hex; namespaces this cache's addresses. */
  context(): string;
  /** Pushes stored records into the memory tier without rendering. */
  warmSnapshots(inputs: readonly SnapshotParagraphInput[]): Promise<number>;
  /** The contract form of {@link PersistentCache.warmSnapshots}. */
  warmContracts(inputs: readonly FontContractInput[]): Promise<number>;
  /**
   * Hash-first render: stored entries hydrate the memory tier and resolve
   * from the local copies after digest verification, so their content never
   * crosses the bridge; the rest carry content once and compute. Entries
   * match the JSON lanes byte for byte.
   */
  renderSnapshots(inputs: readonly SnapshotParagraphInput[]): Promise<PreparedEntry[]>;
  /** The contract form of {@link PersistentCache.renderSnapshots}. */
  renderContracts(inputs: readonly FontContractInput[]): Promise<PreparedEntry[]>;
  /**
   * The background egress of {@link PersistentCache.renderSnapshots}: queues
   * every item at the back of the render pool and returns once queued, so a
   * host can warm content ahead of the waiting lanes. Failures surface when
   * the same content arrives through a waiting lane.
   */
  prefillSnapshots(inputs: readonly SnapshotParagraphInput[]): number;
  /** The contract form of {@link PersistentCache.prefillSnapshots}. */
  prefillContracts(inputs: readonly FontContractInput[]): number;
  /**
   * Records one article's full content-hash set for this cache's context
   * (ADR 0052 Article layer). Both input lists together must carry
   * everything this lane rendered for the article: the row replaces the
   * article's previously recorded hashes. Returns the hash list it recorded,
   * so a host assembles bucket prune keep lists without re-deriving them.
   */
  recordArticle(
    articleKey: string,
    bucket: string,
    inputs: {
      snapshots?: readonly SnapshotParagraphInput[];
      contracts?: readonly FontContractInput[];
    },
  ): Promise<readonly string[]>;
  /** The stored hash set of one article, or null when the article is unrecorded. */
  articleHashes(articleKey: string): Promise<readonly string[] | null>;
  /**
   * Whole-article load: reads the article's stored records through the
   * index and pushes them into the memory tier. Each copy verifies
   * against its address hash and digest before warming, so a corrupt row
   * is a skip, not poison. Returns the record count warmed.
   */
  warmArticle(articleKey: string): Promise<number>;
  /**
   * Bucket-intersection eviction: keeps the union of every recorded
   * article's hashes and drops this context's other entries. Articles in
   * `dropArticles` lose their index rows before the union, so entries only
   * those articles referenced go with them. Returns the entry count
   * removed.
   */
  pruneUnreferencedEntries(dropArticles?: readonly string[]): Promise<number>;
  /**
   * Bucket-scoped eviction (ADR 0052 BucketIntersectionEviction): `keep`
   * carries every content hash the bucket should retain (hex, the form
   * {@link PersistentCache.recordArticle} returns). The store deletes the
   * entries the bucket's article rows attribute but the list omits and no
   * other bucket's row references, trims the bucket's hash rows to the
   * list and drops emptied article rows. One call carries one bucket's
   * list; sweeping every bucket replaces the whole-context union prune for
   * hosts that group articles into buckets. Returns the entry count
   * removed.
   */
  pruneBucket(bucket: string, keep: readonly string[]): Promise<number>;
  /** Persists the buffered writes; returns the record count written. */
  flush(): Promise<number>;
}

function artifactSha(artifact: Uint8Array): Buffer {
  return createHash("sha256").update(artifact).digest();
}

function parseEntry(artifact: Uint8Array): PreparedEntry {
  const entry = JSON.parse(Buffer.from(artifact).toString("utf8")) as PreparedEntry;
  // Native cache bytes retain their digest; snapshot render fields belong to the TS adapter.
  return backfillRenderFields(entry);
}

/** One store blob holds exactly one record. */
function decodeRecord(blob: Uint8Array): CacheRecord | null {
  try {
    const records = unpackRecords(blob);
    return records.length === 1 ? (records[0] ?? null) : null;
  } catch {
    return null;
  }
}

// DeflatedStoreRecords: the stored envelope is a magic, a version byte and
// the deflated plain record. Blobs without the envelope are plain records
// from before deflation and read as they are; an unknown envelope version
// is a miss, and the content path recomputes and overwrites it.
const STORED_MAGIC = Buffer.from("TQZL", "ascii");
const STORED_VERSION = 1;

function packStoredRecord(record: CacheRecord): Buffer {
  return Buffer.concat([
    STORED_MAGIC,
    Buffer.from([STORED_VERSION]),
    deflateSync(packRecords([record])),
  ]);
}

function unpackStoredRecord(blob: Uint8Array): CacheRecord | null {
  if (blob.length < 5 || !Buffer.from(blob.subarray(0, 4)).equals(STORED_MAGIC)) {
    return decodeRecord(blob);
  }
  if (blob[4] !== STORED_VERSION) return null;
  try {
    return decodeRecord(inflateSync(Buffer.from(blob.subarray(5))));
  } catch {
    return null;
  }
}

/**
 * The lane host of {@link createPersistentCache}: any precomputer-like
 * object with a cache bridge. The SDK binds to the bridge alone, so hosts
 * can drive the Article index over a store without an engine attached.
 */
export type CacheLaneHost = { readonly cache: CacheBridge };

/** Binds one lane host to one host store. */
export function createPersistentCache(
  host: CacheLaneHost,
  store: PersistentCacheStore,
): PersistentCache {
  const bridge: CacheBridge = host.cache;
  const address = (contentHash: Uint8Array): string =>
    `${bridge.context()}:${Buffer.from(contentHash).toString("hex")}`;

  /** The Article layer rides the store, not the bridge: hosts without an
   * article-capable store keep their own index and the API reports by name. */
  const articleStore = (): ArticleIndexStore => {
    if (
      store.recordArticles == null ||
      store.readArticles == null ||
      store.deleteArticles == null
    ) {
      throw new Error("ArticleIndexUnavailable");
    }
    return store as ArticleIndexStore;
  };

  /** Reads and verifies the stored record addressed by one hex hash; a
   * record that fails to decode, to live under its own hash or to match
   * its digest is absent, matching the miss semantics of readStored. */
  const readIndexedRecord = async (
    hex: string,
  ): Promise<CacheRecord | null> => {
    const recordAddress = `${bridge.context()}:${hex}`;
    const blobs = await store.read([recordAddress]);
    const blob = blobs.get(recordAddress);
    if (blob === undefined) return null;
    const record = unpackStoredRecord(blob);
    if (record === null) return null;
    if (Buffer.from(record.contentHash).toString("hex") !== hex) return null;
    if (!Buffer.from(record.artifactSha).equals(artifactSha(record.artifact))) {
      return null;
    }
    return record;
  };

  /** Reads stored records for the items; a record only counts when its
   * content hash matches the item it was addressed under. */
  const readStored = async (
    items: readonly SubmissionItem[],
  ): Promise<Map<string, CacheRecord>> => {
    const itemByAddress = new Map<string, SubmissionItem>();
    for (const item of items) {
      itemByAddress.set(address(item.hash), item);
    }
    const blobs = await store.read([...itemByAddress.keys()]);
    const found = new Map<string, CacheRecord>();
    for (const [recordAddress, blob] of blobs) {
      const item = itemByAddress.get(recordAddress);
      const record = blob === undefined ? null : unpackStoredRecord(blob);
      // A store entry that fails to decode, to match its claimed content
      // hash or to verify its own digest is a miss, not an error: the
      // content path re-renders and the next flush overwrites it. The
      // digest check runs here so prefetch never receives a corrupt record.
      if (item === undefined || record === null) continue;
      if (!Buffer.from(record.contentHash).equals(Buffer.from(item.hash))) continue;
      if (!Buffer.from(record.artifactSha).equals(artifactSha(record.artifact))) continue;
      found.set(recordAddress, record);
    }
    return found;
  };

  const warmLane = async (items: readonly SubmissionItem[]): Promise<number> => {
    const found = await readStored(items);
    if (found.size === 0) return 0;
    return bridge.prefetch([...found.values()]);
  };

  const renderLane = async (
    inputs: readonly Readonly<object>[],
    kind: CanonicalKind,
  ): Promise<PreparedEntry[]> => {
    const items = inputs.map((input) => submissionItem(input, kind));
    // Hydration: found records enter the memory tier so the hash lane can
    // hit, while the same copies stay here for artifact parsing.
    const found = await readStored(items);
    if (found.size > 0) {
      bridge.prefetch([...found.values()]);
    }
    const markers = bridge.submitHashes(items.map((item) => item.hash));
    const results: Array<PreparedEntry | null> = items.map(() => null);
    const pending: number[] = [];
    for (const [index, marker] of markers.entries()) {
      const item = items[index];
      if (item === undefined) {
        throw new Error("CacheSubmissionIndexLost");
      }
      if (marker.status !== "hit") {
        pending.push(index);
        continue;
      }
      const record = found.get(address(item.hash));
      // The digest comparison is the hit contract: the local copy is the
      // entry Rust holds. A missing or mismatched copy demotes the item to
      // the content path instead of trusting stale bytes.
      if (
        record !== undefined &&
        Buffer.from(marker.artifactSha).equals(artifactSha(record.artifact))
      ) {
        results[index] = parseEntry(record.artifact);
      } else {
        pending.push(index);
      }
    }
    // The content path. A need-content after the job completed means an
    // eviction raced the write-through; one resubmit settles it.
    let queue = pending;
    for (let attempt = 0; attempt < 2 && queue.length > 0; attempt += 1) {
      const resend: SubmissionItem[] = [];
      for (const index of queue) {
        const item = items[index];
        if (item === undefined) {
          throw new Error("CacheSubmissionIndexLost");
        }
        resend.push(item);
      }
      const outcomes = bridge.submitContents(resend);
      const retry: number[] = [];
      for (const [slot, outcome] of outcomes.entries()) {
        const index = queue[slot];
        if (index === undefined) {
          throw new Error("CacheSubmissionIndexLost");
        }
        if (outcome.status === "computed") {
          results[index] = parseEntry(outcome.artifact);
        } else {
          retry.push(index);
        }
      }
      queue = retry;
    }
    const entries: PreparedEntry[] = [];
    for (const result of results) {
      // A null left after the retry pass means the submission never
      // resolved; report it by name instead of returning a short array.
      if (result === null) {
        throw new Error("CacheSubmissionUnresolved");
      }
      entries.push(result);
    }
    return entries;
  };

  return {
    context(): string {
      return bridge.context();
    },
    async warmSnapshots(inputs: readonly SnapshotParagraphInput[]): Promise<number> {
      return warmLane(inputs.map((input) => submissionItem(input, KIND_SNAPSHOT)));
    },
    async warmContracts(inputs: readonly FontContractInput[]): Promise<number> {
      return warmLane(inputs.map((input) => submissionItem(input, KIND_CONTRACT)));
    },
    async renderSnapshots(inputs: readonly SnapshotParagraphInput[]): Promise<PreparedEntry[]> {
      return renderLane(inputs, KIND_SNAPSHOT);
    },
    async renderContracts(inputs: readonly FontContractInput[]): Promise<PreparedEntry[]> {
      return renderLane(inputs, KIND_CONTRACT);
    },
    prefillSnapshots(inputs: readonly SnapshotParagraphInput[]): number {
      return bridge.prefillContents(inputs.map((input) => submissionItem(input, KIND_SNAPSHOT)));
    },
    prefillContracts(inputs: readonly FontContractInput[]): number {
      return bridge.prefillContents(inputs.map((input) => submissionItem(input, KIND_CONTRACT)));
    },
    async recordArticle(
      articleKey: string,
      bucket: string,
      inputs: {
        snapshots?: readonly SnapshotParagraphInput[];
        contracts?: readonly FontContractInput[];
      },
    ): Promise<readonly string[]> {
      const hashes = new Set<string>();
      for (const input of inputs.snapshots ?? []) {
        hashes.add(
          Buffer.from(submissionItem(input, KIND_SNAPSHOT).hash).toString("hex"),
        );
      }
      for (const input of inputs.contracts ?? []) {
        hashes.add(
          Buffer.from(submissionItem(input, KIND_CONTRACT).hash).toString("hex"),
        );
      }
      const contentHashes = [...hashes];
      await articleStore().recordArticles(bridge.context(), [
        { articleKey, bucket, contentHashes },
      ]);
      return contentHashes;
    },
    async articleHashes(articleKey: string): Promise<readonly string[] | null> {
      const rows = await articleStore().readArticles(bridge.context());
      return rows.find((row) => row.articleKey === articleKey)?.contentHashes ?? null;
    },
    async warmArticle(articleKey: string): Promise<number> {
      const rows = await articleStore().readArticles(bridge.context());
      const row = rows.find((candidate) => candidate.articleKey === articleKey);
      if (row === undefined) return 0;
      const records: CacheRecord[] = [];
      for (const hex of row.contentHashes) {
        const record = await readIndexedRecord(hex);
        if (record !== null) records.push(record);
      }
      return records.length === 0 ? 0 : bridge.prefetch(records);
    },
    async pruneUnreferencedEntries(
      dropArticles?: readonly string[],
    ): Promise<number> {
      // The index computes the keep list, so its absence reports first; a
      // store with rows but no prune keeps its entries until the host adds
      // one.
      const articles = articleStore();
      if (store.prune == null) {
        throw new Error("EntryPruneUnavailable");
      }
      const context = bridge.context();
      const dropped = new Set(dropArticles ?? []);
      if (dropped.size > 0) {
        await articles.deleteArticles(context, [...dropped]);
      }
      const rows = (await articles.readArticles(context))
        .filter((row) => !dropped.has(row.articleKey));
      const keep = new Set<string>();
      for (const row of rows) {
        for (const hex of row.contentHashes) {
          keep.add(`${context}:${hex}`);
        }
      }
      return store.prune(context, [...keep]);
    },
    async pruneBucket(bucket: string, keep: readonly string[]): Promise<number> {
      // The bucket scope lives in the article tables, so the operation rides
      // one store method: a plain prune cannot express "leave other buckets
      // and unattributed entries alone".
      if (store.pruneBucket == null) {
        throw new Error("BucketPruneUnavailable");
      }
      return store.pruneBucket(bridge.context(), bucket, keep);
    },
    async flush(): Promise<number> {
      const records = bridge.drainWrites();
      if (records.length === 0) return 0;
      const entries = records.map(
        (record) => [address(record.contentHash), packStoredRecord(record)] as const,
      );
      await store.write(entries);
      return records.length;
    },
  };
}
