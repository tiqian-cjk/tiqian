// The cache and submission bridge over the native addon (ADR 0052). The
// host-side SDK absorbs the wire complexity: callers hand over plain input
// objects, this module builds the canonical bytes, packs the binary buffers
// and reads the results back. Keys arrive from Rust as opaque 32-byte values;
// the store-key combination never exists on this side.

import { addon } from "./load.js";
import {
  canonicalSubmission,
  memberOf,
  type CanonicalKind,
  type CanonicalSubmissionInput,
} from "./canonical.js";

const RESULTS_MAGIC = Buffer.from("TQSR", "ascii");
const RECORDS_MAGIC = Buffer.from("TQCR", "ascii");
const SUBMISSIONS_MAGIC = Buffer.from("TQSU", "ascii");
const BRIDGE_VERSION = 1;

/** One cache layer; snapshot paragraphs and font contracts live apart. */
export type CacheTier = "snapshot" | "fontContract";

/** The record shape of the drain and prefetch protocol. */
export interface CacheRecord {
  readonly tier: CacheTier;
  readonly key: Uint8Array;
  readonly contentHash: Uint8Array;
  readonly artifact: Uint8Array;
  readonly artifactSha: Uint8Array;
}

/** One content-carrying resend item: the canonical bytes, their hash and the
 * caller's logical key. */
export interface SubmissionItem {
  readonly hash: Uint8Array;
  readonly logicalKey: string;
  readonly canonical: Uint8Array;
}

/** One submission outcome per item. */
export type SubmissionOutcome =
  | { readonly status: "computed"; readonly artifact: Uint8Array }
  | { readonly status: "hit"; readonly artifactSha: Uint8Array }
  | { readonly status: "needContent" };

/** Builds one submission item from a wire input; the canonical bytes and
 * their hash are derived here, the caller never touches them. */
export function submissionItem(
  input: CanonicalSubmissionInput,
  kind: CanonicalKind,
): SubmissionItem {
  const { canonical, hash } = canonicalSubmission(input, kind);
  const rawKey = memberOf(input, "key");
  const logicalKey = rawKey === undefined || rawKey === null ? "" : String(rawKey);
  return { hash, logicalKey, canonical };
}

/** Grows a buffer in chunks; every multi-byte integer is little-endian. */
class BridgeWriter {
  private readonly chunks: Buffer[] = [];
  private readonly scratch = new DataView(new ArrayBuffer(4));

  private pushScratch(): void {
    this.chunks.push(Buffer.from(new Uint8Array(this.scratch.buffer, 0, 4)));
  }

  u8(value: number): void {
    this.chunks.push(Buffer.from([value]));
  }

  count(value: number): void {
    this.scratch.setUint32(0, value, true);
    this.pushScratch();
  }

  bytes(value: Uint8Array): void {
    this.count(value.length);
    this.chunks.push(Buffer.from(value));
  }

  /** Fixed-width fields (hashes) travel without a length prefix. */
  raw(value: Uint8Array): void {
    this.chunks.push(Buffer.from(value));
  }

  str(value: string): void {
    this.bytes(Buffer.from(value, "utf8"));
  }

  header(magic: Buffer): void {
    this.chunks.push(magic);
    this.u8(BRIDGE_VERSION);
  }

  finish(): Buffer {
    return Buffer.concat(this.chunks);
  }
}

/** Bounds-checked reading over one packed buffer. */
class BridgeReader {
  private readonly view: DataView;
  private cursor = 0;

  constructor(private readonly bytes: Buffer) {
    this.view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  }

  private take(length: number): Buffer {
    const end = this.cursor + length;
    if (end > this.bytes.length) {
      throw new Error("InvalidCacheBuffer");
    }
    const slice = this.bytes.subarray(this.cursor, end);
    this.cursor = end;
    return slice;
  }

  u8(): number {
    return this.take(1)[0] ?? 0;
  }

  u32(): number {
    const value = this.view.getUint32(this.cursor, true);
    this.cursor += 4;
    return value;
  }

  hash(): Buffer {
    return Buffer.from(this.take(32));
  }

  takeLength(): Uint8Array {
    const length = this.u32();
    return this.take(length);
  }

  header(magic: Buffer): number {
    if (!this.take(4).equals(magic)) {
      throw new Error("InvalidCacheMagic");
    }
    if (this.u8() !== BRIDGE_VERSION) {
      throw new Error("InvalidCacheBridgeVersion");
    }
    return this.u32();
  }

  done(): void {
    if (this.cursor !== this.bytes.length) {
      throw new Error("InvalidCacheBuffer");
    }
  }
}

function packHashes(hashes: readonly Uint8Array[]): Buffer {
  const writer = new BridgeWriter();
  for (const hash of hashes) {
    writer.raw(hash);
  }
  return writer.finish();
}

function packSubmissions(items: readonly SubmissionItem[]): Buffer {
  const writer = new BridgeWriter();
  writer.header(SUBMISSIONS_MAGIC);
  writer.count(items.length);
  for (const item of items) {
    writer.raw(item.hash);
    writer.str(item.logicalKey);
    writer.bytes(item.canonical);
  }
  return writer.finish();
}

/** Serializes records for a host store; each blob holds its own header. */
export function packRecords(records: readonly CacheRecord[]): Buffer {
  const writer = new BridgeWriter();
  writer.header(RECORDS_MAGIC);
  writer.count(records.length);
  for (const record of records) {
    writer.u8(record.tier === "fontContract" ? 1 : 0);
    writer.raw(record.key);
    writer.raw(record.contentHash);
    writer.raw(record.artifactSha);
    writer.bytes(record.artifact);
  }
  return writer.finish();
}

/** Reads records back from one packed blob. */
export function unpackRecords(buffer: Uint8Array): CacheRecord[] {
  const reader = new BridgeReader(Buffer.from(buffer));
  const count = reader.header(RECORDS_MAGIC);
  const records: CacheRecord[] = [];
  for (let index = 0; index < count; index += 1) {
    const tierCode = reader.u8();
    const tier: CacheTier = tierCode === 1 ? "fontContract" : "snapshot";
    records.push({
      tier,
      key: reader.hash(),
      contentHash: reader.hash(),
      artifactSha: reader.hash(),
      artifact: reader.takeLength(),
    });
  }
  reader.done();
  return records;
}

function unpackResults(buffer: Uint8Array): SubmissionOutcome[] {
  const reader = new BridgeReader(Buffer.from(buffer));
  const count = reader.header(RESULTS_MAGIC);
  const outcomes: SubmissionOutcome[] = [];
  for (let index = 0; index < count; index += 1) {
    const status = reader.u8();
    if (status === 0) {
      outcomes.push({ status: "computed", artifact: reader.takeLength() });
    } else if (status === 1) {
      outcomes.push({ status: "hit", artifactSha: reader.hash() });
    } else {
      outcomes.push({ status: "needContent" });
    }
  }
  reader.done();
  return outcomes;
}

/** The bridge of one precomputer handle. The wrapper hangs this off the
 * precomputer object; hosts drive it through the SDK helpers. */
export interface CacheBridge {
  /** The context fingerprint as hex; namespaces a persistent store. */
  context(): string;
  /** The hash-only lane: hits report the artifact digest, misses report
   * need-content. Content never crosses. */
  submitHashes(hashes: readonly Uint8Array[]): SubmissionOutcome[];
  /** The waiting egress: parks until every item resolved. Hits and fresh
   * computations both return the artifact bytes. */
  submitContents(items: readonly SubmissionItem[]): SubmissionOutcome[];
  /** The background egress: returns once everything queued. Failures surface
   * when the same content arrives through the waiting lane. */
  prefillContents(items: readonly SubmissionItem[]): number;
  /** Warms the memory tier with records read back from a persistent store. */
  prefetch(records: readonly CacheRecord[]): number;
  /** Takes the buffered writes for the host to persist, in write order. */
  drainWrites(): CacheRecord[];
  /** Drops memory-tier records whose store key is not listed. */
  evictExcept(keys: readonly Uint8Array[]): void;
}

/** Internal: the bridge bound to one native registry handle. */
export function createCacheBridge(handle: string): CacheBridge {
  return {
    context(): string {
      return addon.cacheContext(handle);
    },
    submitHashes(hashes: readonly Uint8Array[]): SubmissionOutcome[] {
      return unpackResults(addon.cacheSubmitHashes(handle, packHashes(hashes)));
    },
    submitContents(items: readonly SubmissionItem[]): SubmissionOutcome[] {
      return unpackResults(addon.cacheSubmitContents(handle, packSubmissions(items)));
    },
    prefillContents(items: readonly SubmissionItem[]): number {
      return addon.cachePrefillContents(handle, packSubmissions(items));
    },
    prefetch(records: readonly CacheRecord[]): number {
      return addon.cachePrefetch(handle, packRecords(records));
    },
    drainWrites(): CacheRecord[] {
      return unpackRecords(addon.cacheDrainWrites(handle));
    },
    evictExcept(keys: readonly Uint8Array[]): void {
      addon.cacheEvictExcept(handle, packHashes(keys));
    },
  };
}
