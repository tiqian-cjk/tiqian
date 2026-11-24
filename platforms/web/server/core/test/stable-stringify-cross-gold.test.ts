// Cross-gold gate of the shared-layer render switch (TL ruling A,
// constraint 1): the TS `stableStringify` + `sha256` composition must
// reproduce the exact artifact sha the Rust renderer produced, or moving the
// render loop to the shared module would change every manifest entry.
//
// The vectors are the shared renderer's committed output: the corpus fixture
// `platforms/web/client/web-component/tests/prepared-dom-corpus.fixture.json`
// is asserted byte-for-byte by the shared renderer in
// `platforms/web/server/core/test/snapshot-bundle-data-corpus.test.ts`, and
// artifact trees contain arrays and strings only, so `stableStringify` over
// the fixture artifact reproduces the committed hash preimage exactly.
//
// The second vector covers the value-class path the bundle data phase mints
// (`styleClassFor` -> `tqv-N`); its literal is the shared renderer's output
// for the same plan and callback.

import { test } from "node:test";
import assert from "node:assert/strict";

import { renderPreparedParagraphArtifact } from "@tiqian/web-component/prepared-dom";

import { sha256Hex, stableStringify } from "../lib/stable-stringify.js";

const JUSTIFIED_PLAN = '{"schema":1,"layoutRevision":"tiqian-layout-v2","width":320,"height":48,"lines":[{"rangeStart":0,"rangeEnd":3,"top":0,"bottom":32,"baseline":24,"indent":0,"visualWidth":48.00959014892579,"hyphenAdvance":0,"endReason":"AutoWrap","cells":[{"rangeStart":0,"rangeEnd":1,"source":"排","display":"排","drawX":0,"naturalWidth":16,"leadingLayoutAdvance":0},{"rangeStart":1,"rangeEnd":2,"source":"版","display":"版","drawX":16.004795074462894,"naturalWidth":16,"leadingLayoutAdvance":0},{"rangeStart":2,"rangeEnd":3,"source":"引","display":"引","drawX":32.00959014892579,"naturalWidth":16,"leadingLayoutAdvance":0}]}]}';

const VALUE_CLASS_PLAN = '{"schema":1,"layoutRevision":"tiqian-layout-v2","width":320,"height":48,"lines":[{"rangeStart":0,"rangeEnd":2,"top":0,"bottom":32,"baseline":24,"indent":0,"visualWidth":32.5,"hyphenAdvance":0,"endReason":"ParagraphEnd","cells":[{"rangeStart":0,"rangeEnd":1,"source":"排","display":"排","drawX":0,"naturalWidth":16,"leadingLayoutAdvance":0},{"rangeStart":1,"rangeEnd":2,"source":"版","display":"版","drawX":16.5,"naturalWidth":16,"leadingLayoutAdvance":0}]}]}';

// schema.rs: stable_stringify_sorts_object_keys_and_keeps_array_order
test("sorts object keys by UTF-16 code unit and keeps array order", () => {
  assert.equal(
    stableStringify({ z: 1, a: [2, 1], m: { k: "v" } }),
    '{"a":[2,1],"m":{"k":"v"},"z":1}',
  );
});

// schema.rs: stable_stringify_renders_primitives_like_json
test("renders primitives like JSON (including -0 and NaN)", () => {
  assert.equal(stableStringify(null), "null");
  assert.equal(stableStringify(true), "true");
  assert.equal(stableStringify(400.5), "400.5");
  assert.equal(stableStringify(-0), "0");
  assert.equal(stableStringify(NaN), "null");
  assert.equal(stableStringify('a"b'), '"a\\"b"');
  assert.equal(stableStringify([]), "[]");
  assert.equal(stableStringify({}), "{}");
});

// schema.rs: stable_stringify_orders_keys_by_utf16_units
test("orders keys by UTF-16 code units and emits astral scalars raw", () => {
  const input: Record<string, number> = {};
  input["\uFFFD"] = 1;
  input["\u{10000}"] = 2;
  assert.equal(stableStringify(input), '{"\u{10000}":2,"\uFFFD":1}');
});

// font_source.rs: sha256_hex(b"abc")
test("sha256 hex matches the Rust sha256_hex preimage", () => {
  assert.equal(
    sha256Hex("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  );
});

test("artifact sha of the justified corpus case matches the Rust renderer", () => {
  const rendered = renderPreparedParagraphArtifact(JUSTIFIED_PLAN, "zh-Hans");
  assert.equal(
    sha256Hex(stableStringify(rendered.artifact)),
    "796993e400295918bd166ebf492b569b7ece9aa47f7bc5ad5973a14f89549f45",
  );
});

test("artifact sha of the value-class plan matches the Rust renderer", () => {
  let index = 0;
  const rendered = renderPreparedParagraphArtifact(VALUE_CLASS_PLAN, "zh-Hans", {
    styleClassFor: () => "tqv-" + index++,
  });
  assert.match(rendered.html, /class="tq-line tqv-0"/u);
  assert.equal(
    sha256Hex(stableStringify(rendered.artifact)),
    "1dcfeae255f6d824cc0f1fd36cab9bb931554d336b7e047acf5c886b68d7a8c7",
  );
});
