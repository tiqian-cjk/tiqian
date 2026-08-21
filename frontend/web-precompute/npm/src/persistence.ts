// The host-facing persistence SDK over the cache bridge (ADR 0052). Hosts
// hand over a plain address-to-bytes store; this module derives the cache
// addresses from the context fingerprint and the content hashes, hydrates
// the memory tier from the store, drives the hash-first submission lanes,
// verifies hits against the artifact digests and persists drained records
// back. Record bytes stay opaque to the host: the store never learns the
// entry format, and a format change invalidates through the context
// fingerprint alone.

import { createHash } from "node:crypto";

import type {
  FontContractInput,
  PreparedEntry,
  Precomputer,
  SnapshotParagraphInput,
} from "./precompute.js";
import type { CacheBridge, CacheRecord, SubmissionItem } from "./cache.js";
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
}

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
  /** Persists the buffered writes; returns the record count written. */
  flush(): Promise<number>;
}

function artifactSha(artifact: Uint8Array): Buffer {
  return createHash("sha256").update(artifact).digest();
}

function parseEntry(artifact: Uint8Array): PreparedEntry {
  return JSON.parse(Buffer.from(artifact).toString("utf8")) as PreparedEntry;
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

/** Binds one precomputer to one host store. */
export function createPersistentCache(
  precomputer: Precomputer,
  store: PersistentCacheStore,
): PersistentCache {
  const bridge: CacheBridge = precomputer.cache;
  const address = (contentHash: Uint8Array): string =>
    `${bridge.context()}:${Buffer.from(contentHash).toString("hex")}`;

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
      const record = blob === undefined ? null : decodeRecord(blob);
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
    async flush(): Promise<number> {
      const records = bridge.drainWrites();
      if (records.length === 0) return 0;
      const entries = records.map(
        (record) => [address(record.contentHash), packRecords([record])] as const,
      );
      await store.write(entries);
      return records.length;
    },
  };
}
