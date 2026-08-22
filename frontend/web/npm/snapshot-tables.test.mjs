import assert from "node:assert/strict";
import test from "node:test";

import {
  loadedSnapshotTablesForRoot,
  prefetchSnapshotTables,
  snapshotTablesForRoot,
  snapshotTablesFromBytes,
} from "./snapshot-tables.js";
import { writeBinaryTable } from "./table-binary-writer.mjs";

const TABLE_BYTES = writeBinaryTable({
  replayStrings: [],
  metrics: [],
  probes: [{ text: "中", advancePx: 18, fontSizePx: 18, fontWeight: 400, italic: false, script: "Hani", language: "zh-Hans", features: [] }],
  typographies: [{ sha256: "t".repeat(64), value: { fontFamilies: ["Fixture CJK"] } }],
  faces: [],
  valueStyles: [],
  fontPreloads: [],
  revisions: { backendRevision: "fixture-backend", harfbuzzVersion: "fixture-hb" },
});
const OTHER_TABLE_BYTES = writeBinaryTable({
  replayStrings: [],
  metrics: [],
  probes: [],
  typographies: [],
  faces: [],
  valueStyles: [".tq-root { line-height: 1.7; }"],
  fontPreloads: [],
  revisions: {},
});

async function sha256Bytes(bytes) {
  const digest = await globalThis.crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function rootWithTables(attribute) {
  return { getAttribute: (name) => (name === "tq-tables" ? attribute : null) };
}

/** Installs a fetch stub keyed by URL; each entry is [responses...], popped per call. */
function installFetch(responses) {
  const calls = [];
  const previousFetch = globalThis.fetch;
  globalThis.fetch = async (url) => {
    calls.push(url);
    const reply = responses[url]?.shift();
    if (reply instanceof Error) throw reply;
    return { ok: true, arrayBuffer: async () => reply };
  };
  return {
    calls,
    restore() {
      globalThis.fetch = previousFetch;
    },
  };
}

test("table references load by url and dedupe through the global map", async () => {
  const key = "https://tables.test/dedupe-deadbeef.tiqtbl";
  const stub = installFetch({ [key]: [TABLE_BYTES] });
  try {
    const first = await snapshotTablesForRoot(rootWithTables(key));
    const second = await snapshotTablesForRoot(rootWithTables(key), first.sha256);
    assert.equal(second.sha256, first.sha256);
    assert.deepEqual([...second.bytes], [...first.bytes]);
    assert.equal(first.view.binary, true);
    assert.equal(first.view.revisions().backendRevision, "fixture-backend");
    assert.equal(first.sha256, await sha256Bytes(TABLE_BYTES));
    assert.deepEqual(stub.calls, [key]);
    assert.equal(loadedSnapshotTablesForRoot(rootWithTables(key)).sha256, first.sha256);
  } finally {
    stub.restore();
  }
});

test("failed loads stay uncached so a later root can retry", async () => {
  const key = "https://tables.test/retry-deadbeef.tiqtbl";
  const stub = installFetch({
    [key]: [new Error("offline"), TABLE_BYTES],
  });
  try {
    const failing = rootWithTables(key);
    assert.equal(await snapshotTablesForRoot(failing), null);
    assert.equal(loadedSnapshotTablesForRoot(failing), null);
    const retrying = await snapshotTablesForRoot(rootWithTables(key));
    assert.deepEqual(retrying.view.valueStyles(), []);
    assert.deepEqual(stub.calls, [key, key]);
  } finally {
    stub.restore();
  }
});

test("a digest mismatch walks to the next reference of the attribute", async () => {
  const stale = "https://tables.test/stale-cafe.tiqtbl";
  const fresh = "https://tables.test/fresh-beef.tiqtbl";
  const stub = installFetch({ [stale]: [TABLE_BYTES], [fresh]: [OTHER_TABLE_BYTES] });
  try {
    const expected = await sha256Bytes(OTHER_TABLE_BYTES);
    const table = await snapshotTablesForRoot(
      rootWithTables(`${stale} ${fresh}`),
      expected,
    );
    assert.deepEqual([...table.bytes], [...OTHER_TABLE_BYTES]);
    assert.deepEqual(stub.calls, [stale, fresh]);
    assert.equal(await snapshotTablesForRoot(rootWithTables(stale), expected), null);
  } finally {
    stub.restore();
  }
});

test("bytes without the station-table magic fail closed", () => {
  assert.throws(
    () => snapshotTablesFromBytes(new TextEncoder().encode("{\"schema\":2}")),
    /SnapshotTablesInvalid/u,
  );
  assert.throws(
    () => snapshotTablesFromBytes(new Uint8Array([0x7b, 0x22, 0x61, 0xff, 0xff])),
    /SnapshotTablesInvalid/u,
  );
  assert.throws(
    () => snapshotTablesFromBytes(TABLE_BYTES.subarray(0, TABLE_BYTES.length - 1)),
    /SnapshotTablesInvalid/u,
  );
});

test("the document pre-scan starts loading every referenced table", async () => {
  const key = "https://tables.test/prefetch-deadbeef.tiqtbl";
  const stub = installFetch({ [key]: [TABLE_BYTES] });
  const previousDocument = globalThis.document;
  globalThis.document = {
    querySelectorAll: (selector) => selector === "[tq-tables]" ? [rootWithTables(key)] : [],
  };
  try {
    prefetchSnapshotTables();
    assert.deepEqual(stub.calls, [key]);
  } finally {
    globalThis.document = previousDocument;
    stub.restore();
  }
});
