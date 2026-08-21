// The TypeScript mirror of the Rust canonical encoder (ADR 0052). The bytes
// produced here are the hash preimage of the cache layers and the content of
// the binary bridge: hashing, sending and resupplying all consume the same
// form, so both sides agree on one identity per input. Golden vectors in
// `test/canonical.test.ts` and the Rust unit tests pin the same hex strings.
//
// The identity contract matches the Rust doc: every field is carried the way
// `JSON.stringify` would carry it. Non-finite numbers become absent fields
// and both zero signs collapse to `+0`. The caller's logical `key` is
// deliberately absent. Boundary condition inherited from the JSON lane:
// attribute objects with integer-like keys enumerate in JavaScript's own
// order (integer keys first), which differs from the document order Rust's
// parser keeps; such attribute names are outside the supported envelope.

import { createHash } from "node:crypto";

/** The canonical form's magic and version, shared with the Rust encoder. */
const CANONICAL_MAGIC = Buffer.from("TQCS", "ascii");
const CANONICAL_VERSION = 1;

/** Snapshot paragraph submission: carries `maxWidthPx`. */
export const KIND_SNAPSHOT = 0;
/** Font contract submission: the capture width is derived in Rust. */
export const KIND_CONTRACT = 1;

export type CanonicalKind = typeof KIND_SNAPSHOT | typeof KIND_CONTRACT;

const SEM_ATTRS = 0x01;
const SEM_ORDER = 0x02;
const SEM_TAG_NAME = 0x04;

const SPAN_FAMILIES = 0x01;
const SPAN_FONT_SIZE_PX = 0x02;
const SPAN_FONT_WEIGHT = 0x04;
const SPAN_ITALIC = 0x08;
const SPAN_BASELINE_SHIFT_PX = 0x10;

const BOX_INLINE_START_PX = 0x01;
const BOX_INLINE_END_PX = 0x02;
const BOX_OUTER_SPACING = 0x04;

/**
 * The wire input the encoder reads. The members match the paragraph and
 * contract input interfaces of `precompute.ts`; the encoder coerces loosely
 * at runtime, the same coercions the Rust encoder ports.
 */
export type CanonicalSubmissionInput = Readonly<Record<string, unknown>>;

/** Grows a buffer in chunks; every multi-byte integer is little-endian. */
class CanonicalWriter {
  private readonly chunks: Buffer[] = [];
  private readonly scratch = new DataView(new ArrayBuffer(8));

  constructor(kind: CanonicalKind) {
    this.chunks.push(CANONICAL_MAGIC);
    this.u8(CANONICAL_VERSION);
    this.u8(kind);
  }

  private pushScratch(length: number): void {
    this.chunks.push(Buffer.from(new Uint8Array(this.scratch.buffer, 0, length)));
  }

  u8(value: number): void {
    this.scratch.setUint8(0, value);
    this.pushScratch(1);
  }

  f64(value: number): void {
    this.scratch.setFloat64(0, value, true);
    this.pushScratch(8);
  }

  bytes(value: Buffer): void {
    this.scratch.setUint32(0, value.length, true);
    this.pushScratch(4);
    this.chunks.push(value);
  }

  str(value: string): void {
    this.bytes(Buffer.from(value, "utf8"));
  }

  count(value: number): void {
    this.scratch.setUint32(0, value, true);
    this.pushScratch(4);
  }

  finish(): Buffer {
    return Buffer.concat(this.chunks);
  }
}

/** The `??` step shared with the wire readers: absent and null read as absent. */
function coalesce(value: unknown): unknown {
  return value === undefined || value === null ? undefined : value;
}

/** `Number(member)` when the member survives, absent otherwise. */
function numberMember(input: CanonicalSubmissionInput, name: string): number | undefined {
  const resolved = coalesce(input[name]);
  if (resolved === undefined) {
    return undefined;
  }
  const number = Number(resolved);
  if (!Number.isFinite(number)) {
    return undefined;
  }
  return number === 0 ? 0 : number;
}

/** An optional numeric member: present flag plus the f64 bits. */
function numberField(writer: CanonicalWriter, value: number | undefined): void {
  if (value === undefined) {
    writer.u8(0);
  } else {
    writer.u8(1);
    writer.f64(value);
  }
}

/** Reads a list member: absent reads as empty, a non-array is a named error. */
function listMember(
  input: CanonicalSubmissionInput,
  name: string,
  issue: string,
): readonly unknown[] {
  const resolved = coalesce(input[name]);
  if (resolved === undefined) {
    return [];
  }
  if (!Array.isArray(resolved)) {
    throw new Error(issue);
  }
  return resolved;
}

function memberOf(span: unknown, name: string): unknown {
  return coalesce((span as Readonly<Record<string, unknown>>)[name]);
}

function encodeAttributes(writer: CanonicalWriter, value: unknown): void {
  if (Array.isArray(value)) {
    // The array shape is carried as its JSON text so invalid pair shapes
    // reproduce the reader's named error on the other side.
    writer.u8(2);
    writer.bytes(Buffer.from(JSON.stringify(value), "utf8"));
    return;
  }
  if (typeof value === "object" && value !== undefined && value !== null) {
    writer.u8(1);
    const entries = Object.entries(value as Record<string, unknown>);
    writer.count(entries.length);
    for (const [name, raw] of entries) {
      writer.str(name);
      writer.str(String(raw));
    }
    return;
  }
  writer.u8(0);
}

function encodeSemantics(writer: CanonicalWriter, items: readonly unknown[]): void {
  writer.count(items.length);
  for (const span of items) {
    const attributes = memberOf(span, "attributes");
    const order = numberMember(span as CanonicalSubmissionInput, "order");
    const tagName = memberOf(span, "tagName");
    let flags = 0;
    if (attributes !== undefined) {
      flags |= SEM_ATTRS;
    }
    if (order !== undefined) {
      flags |= SEM_ORDER;
    }
    if (tagName !== undefined) {
      flags |= SEM_TAG_NAME;
    }
    writer.u8(flags);
    numberField(writer, numberMember(span as CanonicalSubmissionInput, "start"));
    numberField(writer, numberMember(span as CanonicalSubmissionInput, "end"));
    if (tagName !== undefined) {
      writer.str(String(tagName));
    }
    if (order !== undefined) {
      writer.f64(order);
    }
    if (attributes !== undefined) {
      encodeAttributes(writer, attributes);
    }
  }
}

function encodeTextSpans(writer: CanonicalWriter, items: readonly unknown[]): void {
  writer.count(items.length);
  for (const span of items) {
    const fields = span as CanonicalSubmissionInput;
    const rawFamilies = memberOf(span, "fontFamilies");
    const families = Array.isArray(rawFamilies) ? rawFamilies.map(String) : undefined;
    const fontSizePx = numberMember(fields, "fontSizePx");
    const fontWeight = numberMember(fields, "fontWeight");
    const rawItalic = memberOf(span, "italic");
    const italic = typeof rawItalic === "boolean" ? rawItalic : undefined;
    const baselineShiftPx = numberMember(fields, "baselineShiftPx");
    let flags = 0;
    if (families !== undefined) {
      flags |= SPAN_FAMILIES;
    }
    if (fontSizePx !== undefined) {
      flags |= SPAN_FONT_SIZE_PX;
    }
    if (fontWeight !== undefined) {
      flags |= SPAN_FONT_WEIGHT;
    }
    if (italic !== undefined) {
      flags |= SPAN_ITALIC;
    }
    if (baselineShiftPx !== undefined) {
      flags |= SPAN_BASELINE_SHIFT_PX;
    }
    writer.u8(flags);
    numberField(writer, numberMember(fields, "start"));
    numberField(writer, numberMember(fields, "end"));
    if (families !== undefined) {
      writer.count(families.length);
      for (const name of families) {
        writer.str(name);
      }
    }
    if (fontSizePx !== undefined) {
      writer.f64(fontSizePx);
    }
    if (fontWeight !== undefined) {
      writer.f64(fontWeight);
    }
    if (italic !== undefined) {
      writer.u8(italic ? 1 : 0);
    }
    if (baselineShiftPx !== undefined) {
      writer.f64(baselineShiftPx);
    }
  }
}

function encodeInlineBoxes(writer: CanonicalWriter, items: readonly unknown[]): void {
  writer.count(items.length);
  for (const item of items) {
    const fields = item as CanonicalSubmissionInput;
    const inlineStartPx = numberMember(fields, "inlineStartPx");
    const inlineEndPx = numberMember(fields, "inlineEndPx");
    const outerSpacing = memberOf(item, "outerSpacing");
    let flags = 0;
    if (inlineStartPx !== undefined) {
      flags |= BOX_INLINE_START_PX;
    }
    if (inlineEndPx !== undefined) {
      flags |= BOX_INLINE_END_PX;
    }
    if (outerSpacing !== undefined) {
      flags |= BOX_OUTER_SPACING;
    }
    writer.u8(flags);
    numberField(writer, numberMember(fields, "start"));
    numberField(writer, numberMember(fields, "end"));
    if (inlineStartPx !== undefined) {
      writer.f64(inlineStartPx);
    }
    if (inlineEndPx !== undefined) {
      writer.f64(inlineEndPx);
    }
    if (outerSpacing !== undefined) {
      writer.str(String(outerSpacing));
    }
  }
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
  const writer = new CanonicalWriter(kind);
  const rawText = coalesce(input["text"]);
  writer.str(rawText === undefined ? "" : String(rawText));
  if (kind === KIND_SNAPSHOT) {
    numberField(writer, numberMember(input, "maxWidthPx"));
  }
  encodeSemantics(writer, listMember(input, "semantics", "InvalidSnapshotSemantics"));
  encodeTextSpans(writer, listMember(input, "textSpans", "InvalidSnapshotTextSpans"));
  encodeInlineBoxes(writer, listMember(input, "inlineBoxes", "InvalidSnapshotInlineBoxes"));
  // A non-array reads as absent boundaries, the capture loop's own rule.
  const rawBoundaries = coalesce(input["sourceBoundaries"]);
  const boundaries = Array.isArray(rawBoundaries) ? rawBoundaries : [];
  writer.count(boundaries.length);
  for (const boundary of boundaries) {
    const number = Number(boundary);
    writer.f64(Number.isFinite(number) ? (number === 0 ? 0 : number) : 0);
  }
  return writer.finish();
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
