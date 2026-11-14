// The TypeScript adapter of the single-source canonical encoder (ADR 0052).
// The byte form itself lives in the Haxe module org.tiqian.protocol.Canonical
// and arrives through the generated tree in the tiqian-protocol package
// (driver bundle protocol-ts). The bytes
// are the hash preimage of the cache layers and the content of the binary
// bridge; golden vectors in test/canonical.test.ts pin the same hex strings
// the Haxe-generated test and the Rust unit tests assert.
//
// This adapter owns only the platform seam: it walks the live JS submission
// into the generated wire value (insertion order preserved, the identity
// order of attribute pairs), raises the named issue as a JS error, and keeps
// the digest on node:crypto until the consumer rewiring task switches it to
// the generated haxe.crypto.Sha256 entry.

import { createHash } from "node:crypto";

import { Canonical } from "tiqian-protocol/org/tiqian/protocol/Canonical";
import type { WireField } from "tiqian-protocol/org/tiqian/protocol/WireField";
import type { WireValue } from "tiqian-protocol/org/tiqian/protocol/WireValue";

/** Snapshot paragraph submission: carries `maxWidthPx`. */
export const KIND_SNAPSHOT = 0;
/** Font contract submission: the capture width is derived in Rust. */
export const KIND_CONTRACT = 1;

export type CanonicalKind = typeof KIND_SNAPSHOT | typeof KIND_CONTRACT;

/**
 * The wire input the encoder reads. The members match the paragraph and
 * contract input interfaces of `precompute.ts`; the walk below applies the
 * same loose coercions the generated encoder carries.
 */
export type CanonicalSubmissionInput = Readonly<object>;

/** Walks one live JS value into the generated wire value. */
function toWire(value: unknown): WireValue {
  if (value === undefined || value === null) {
    return { kind: "WNull" };
  }
  const typeofValue = typeof value;
  if (typeofValue === "boolean") {
    return { kind: "WBool", value: value as boolean };
  }
  if (typeofValue === "number") {
    return { kind: "WNum", value: value as number };
  }
  if (typeofValue === "string") {
    return { kind: "WStr", value: value as string };
  }
  if (Array.isArray(value)) {
    return { kind: "WArr", items: value.map((item) => toWire(item)) };
  }
  const fields: WireField[] = Object.entries(value as Record<string, unknown>).map(
    ([name, member]) => ({ name, value: toWire(member) }),
  );
  return { kind: "WObj", fields };
}

/** One dynamically read member: absent and null both read as absent. */
export function memberOf(input: unknown, name: string): unknown {
  return (input as Readonly<Record<string, unknown>> | undefined)?.[name];
}

/**
 * Encodes one wire input object into its canonical bytes. `kind` selects the
 * snapshot or contract form; snapshot inputs carry `maxWidthPx`, contract
 * inputs never do.
 */
export function encodeCanonicalInput(
  input: CanonicalSubmissionInput,
  kind: CanonicalKind,
): Buffer {
  const result = Canonical.encode(toWire(input), kind);
  if (result.kind === "CErr") {
    throw new Error(result.issue);
  }
  return Buffer.from(result.bytes);
}

/** Raw SHA-256 digest, the cache-layer content hash of the canonical bytes. */
export function canonicalDigest(bytes: Uint8Array): Buffer {
  return createHash("sha256").update(bytes).digest();
}

/** The canonical bytes of one input and their content hash, in one step. */
export function canonicalSubmission(
  input: CanonicalSubmissionInput,
  kind: CanonicalKind,
): { canonical: Buffer; hash: Buffer } {
  const canonical = encodeCanonicalInput(input, kind);
  return { canonical, hash: canonicalDigest(canonical) };
}