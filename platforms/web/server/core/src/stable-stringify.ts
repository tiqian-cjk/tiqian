// The TypeScript counterpart of the Rust `stable_stringify` that feeds every
// snapshot artifact hash (precompute/engine/src/schema.rs:52-80). Both sides
// must produce the same bytes for the same artifact tree: primitives render
// through JSON.stringify, arrays keep element order, and object keys sort by
// UTF-16 code units (Array.prototype.sort's default order). The digest uses
// the generated haxe.crypto.Sha256 entry, so Node, the browser, and Rust share
// one hash implementation.
//
// The cross-gold test test/stable-stringify-cross-gold.test.ts pins one
// artifact sha produced by the Rust renderer against this composition.

import { Sha256 } from "@tiqian/protocol/haxe/crypto/Sha256";

const textEncoder = new TextEncoder();

/**
 * Renders one JSON value the way the Rust `stable_stringify` does. Inputs are
 * snapshot artifacts: JSON values only, so `undefined` has no Rust
 * counterpart and renders as `null`.
 */
export function stableStringify(value: unknown): string {
  const encoded = stableEncode(value);
  return encoded === undefined ? "null" : encoded;
}

function stableEncode(value: unknown): string | undefined {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  const record = value as Record<string, unknown>;
  const entries = Object.keys(record)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${stableStringify(record[key])}`);
  return `{${entries.join(",")}}`;
}

/** Hex SHA-256 of the UTF-8 bytes of one string, the Rust `sha256_hex` form. */
export function sha256Hex(value: string): string {
  const digest = Sha256.make(textEncoder.encode(value));
  let hex = "";
  for (const byte of digest) hex += byte.toString(16).padStart(2, "0");
  return hex;
}
