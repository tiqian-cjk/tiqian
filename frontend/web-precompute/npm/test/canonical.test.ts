// The canonical encoder's cross-language golden vectors (ADR 0052). The
// Rust unit test pins the same hex strings, so both encoders produce
// identical bytes for the same inputs; the canonical bytes are the cache
// identity, so one bit of divergence would split every cache entry.

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  canonicalDigest,
  encodeCanonicalInput,
  KIND_CONTRACT,
  KIND_SNAPSHOT,
} from "../lib/canonical.js";

test("golden vectors match the Rust encoder bytes", () => {
  const vector0 = encodeCanonicalInput(
    { key: "p-1", text: "中文", maxWidthPx: 144 },
    KIND_SNAPSHOT,
  );
  assert.equal(
    vector0.toString("hex"),
    "54514353010006000000e4b8ade6968701000000000000624000000000000000000000000000000000",
  );

  const vector1 = encodeCanonicalInput({ key: "fc-1", text: "中文" }, KIND_CONTRACT);
  assert.equal(
    vector1.toString("hex"),
    "54514353010106000000e4b8ade6968700000000000000000000000000000000",
  );

  const vector2 = encodeCanonicalInput(
    {
      key: "p-2",
      text: "中文字排版",
      maxWidthPx: 144,
      semantics: [
        {
          tagName: "a",
          start: 2,
          end: 4,
          attributes: { href: "https://example.com", class: "link" },
          order: 1,
        },
        { tagName: "em", start: 0, end: 1 },
      ],
      textSpans: [
        {
          start: 0,
          end: 2,
          fontFamilies: ["Dela Gothic One"],
          fontSizePx: 18,
          fontWeight: 400,
          italic: true,
          baselineShiftPx: -0.5,
        },
        { start: 2, end: 4, fontFamilies: [] },
      ],
      inlineBoxes: [
        { start: 1, end: 2, inlineStartPx: 8, inlineEndPx: 4, outerSpacing: "Source" },
        { start: 3, end: 4 },
      ],
      sourceBoundaries: [0, 18, 36],
    },
    KIND_SNAPSHOT,
  );
  assert.equal(
    vector2.toString("hex"),
    "5451435301000f000000e4b8ade69687e5ad97e68e92e7898801000000000000624002000000070100000000000000400100000000000010400100000061000000000000f03f010200000004000000687265661300000068747470733a2f2f6578616d706c652e636f6d05000000636c617373040000006c696e6b0401000000000000000001000000000000f03f02000000656d020000001f010000000000000000010000000000000040010000000f00000044656c6120476f74686963204f6e650000000000003240000000000000794001000000000000e0bf0101000000000000004001000000000000104000000000020000000701000000000000f03f0100000000000000400000000000002040000000000000104006000000536f757263650001000000000000084001000000000000104003000000000000000000000000000000000032400000000000004240",
  );

  // Loose coercions: string numbers, a non-boolean italic, an array-shaped
  // attributes value and a null boundary all carry the JSON lane's reading.
  const vector3 = encodeCanonicalInput(
    {
      key: "p-3",
      text: " coerce ",
      maxWidthPx: "144.5",
      semantics: [{ tagName: "i", start: "1", end: 2, attributes: [["a", "1"], ["b", 2]] }],
      textSpans: [{ start: 0, end: 1, italic: "no" }],
      inlineBoxes: [{ start: 0, end: 1, outerSpacing: 7 }],
      sourceBoundaries: ["3", null],
    },
    KIND_SNAPSHOT,
  );
  assert.equal(
    vector3.toString("hex"),
    "5451435301000800000020636f6572636520010000000000106240010000000501000000000000f03f010000000000000040010000006902130000005b5b2261222c2231225d2c5b2262222c325d5d010000000001000000000000000001000000000000f03f010000000401000000000000000001000000000000f03f01000000370200000000000000000008400000000000000000",
  );
});

test("the content hash is the sha256 of the canonical bytes", () => {
  const canonical = encodeCanonicalInput({ text: "中文", maxWidthPx: 144 }, KIND_SNAPSHOT);
  assert.equal(canonicalDigest(canonical).length, 32);
  assert.equal(
    canonicalDigest(canonical).toString("hex"),
    canonicalDigest(canonical).toString("hex"),
  );
});

test("non-finite numbers and minus zero collapse the canonical way", () => {
  const withNaN = encodeCanonicalInput(
    { text: "a", maxWidthPx: Number.NaN },
    KIND_SNAPSHOT,
  );
  const withoutWidth = encodeCanonicalInput({ text: "a" }, KIND_SNAPSHOT);
  assert.deepEqual(withNaN, withoutWidth);

  const minusZero = encodeCanonicalInput(
    { text: "a", maxWidthPx: -0 },
    KIND_SNAPSHOT,
  );
  const plusZero = encodeCanonicalInput({ text: "a", maxWidthPx: 0 }, KIND_SNAPSHOT);
  assert.deepEqual(minusZero, plusZero);
});

test("a non-array semantics member is the named error", () => {
  assert.throws(
    () => encodeCanonicalInput({ text: "a", semantics: "no" }, KIND_SNAPSHOT),
    /InvalidSnapshotSemantics/u,
  );
});
