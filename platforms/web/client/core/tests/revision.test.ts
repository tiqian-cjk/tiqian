import assert from "node:assert/strict";
import test from "node:test";

import {
  FONT_BACKEND_REVISION,
  FONT_REPLAY_REVISION,
  FONT_REPLAY_TRANSPORT,
  FONT_SOURCE_POLICY,
  LAYOUT_REVISION,
  RENDER_REVISION,
  SNAPSHOT_SCHEMA,
  SNAPSHOT_TABLES_SCHEMA,
} from "../src/sampler/snapshot/snapshot-schema.js";
import { Revision } from "tiqian-protocol/org/tiqian/protocol/Revision";

// Stage1-P4 (boring cutover): the manifest schema numbers and the revision
// constant family are single-sourced in
// engine-haxe/src/org/tiqian/protocol/Revision.hx and vendored as the
// generated module next to snapshot-schema.js. The Haxe lane pins the same
// literals in RevisionTest, and the Rust lane pins them in the precompute
// engine crate (schema.rs tests), so this test is the TypeScript side of
// the "same constants equal item by item" criterion.

test("the generated revision family pins the hand-written literals", () => {
  assert.equal(Revision.SNAPSHOT_SCHEMA, 1);
  assert.equal(Revision.SNAPSHOT_TABLES_SCHEMA, 2);
  assert.equal(Revision.LAYOUT_REVISION, "tiqian-layout-v2");
  assert.equal(Revision.RENDER_REVISION, "prebroken-dom-v16");
  assert.equal(Revision.FONT_SOURCE_POLICY, "host-compatible-stylesheet-v1");
  assert.equal(Revision.FONT_BACKEND_REVISION, "tiqian-shared-harfbuzz-v5");
  assert.equal(Revision.FONT_REPLAY_REVISION, "tiqian-server-shaping-replay-v1");
  assert.equal(Revision.FONT_REPLAY_TRANSPORT, "shared-strings-v1");
  assert.equal(Revision.FONT_BACKEND_PROTOCOL_REVISION, 2);
});

test("snapshot-schema re-exports the generated single source", () => {
  assert.equal(SNAPSHOT_SCHEMA, Revision.SNAPSHOT_SCHEMA);
  assert.equal(SNAPSHOT_TABLES_SCHEMA, Revision.SNAPSHOT_TABLES_SCHEMA);
  assert.equal(LAYOUT_REVISION, Revision.LAYOUT_REVISION);
  assert.equal(RENDER_REVISION, Revision.RENDER_REVISION);
  assert.equal(FONT_SOURCE_POLICY, Revision.FONT_SOURCE_POLICY);
  assert.equal(FONT_BACKEND_REVISION, Revision.FONT_BACKEND_REVISION);
  assert.equal(FONT_REPLAY_REVISION, Revision.FONT_REPLAY_REVISION);
  assert.equal(FONT_REPLAY_TRANSPORT, Revision.FONT_REPLAY_TRANSPORT);
});
