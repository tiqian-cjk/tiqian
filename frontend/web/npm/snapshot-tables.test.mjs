import assert from "node:assert/strict";
import test from "node:test";

import {
  loadedSnapshotTablesForRoot,
  parseSnapshotTables,
  prefetchSnapshotTables,
  snapshotTablesForRoot,
} from "./snapshot-tables.js";

const TABLE_JSON = JSON.stringify({
  schema: 2,
  typologies: [],
  typographies: [],
  faces: [],
  valueStyles: [],
  fontPreloads: [],
  revisions: {},
  strings: [],
  probes: [],
  metrics: [],
});

async function sha256Text(value) {
  const bytes = new TextEncoder().encode(value);
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
    return { ok: true, text: async () => reply };
  };
  return {
    calls,
    restore() {
      globalThis.fetch = previousFetch;
    },
  };
}

test("table references load by url and dedupe through the global map", async () => {
  const key = "https://tables.test/dedupe-deadbeef.json";
  const stub = installFetch({ [key]: [TABLE_JSON] });
  try {
    const first = await snapshotTablesForRoot(rootWithTables(key), null);
    const second = await snapshotTablesForRoot(rootWithTables(key), null, first.sha256);
    assert.equal(second.json, first.json);
    assert.equal(second.sha256, await sha256Text(TABLE_JSON));
    assert.deepEqual(stub.calls, [key]);
    assert.equal(loadedSnapshotTablesForRoot(rootWithTables(key)).sha256, first.sha256);
  } finally {
    stub.restore();
  }
});

test("page element references load in-page bytes", async () => {
  const element = { textContent: TABLE_JSON };
  const documentObject = { getElementById: (id) => (id === "station-tables" ? element : null) };
  const table = await snapshotTablesForRoot(rootWithTables("#station-tables"), documentObject);
  assert.equal(table.json.schema, 2);
  assert.equal(table.sha256, await sha256Text(TABLE_JSON));
});

test("failed loads stay uncached so a later root can retry", async () => {
  const key = "https://tables.test/retry-deadbeef.json";
  const stub = installFetch({
    [key]: [new Error("offline"), TABLE_JSON],
  });
  try {
    const failing = rootWithTables(key);
    assert.equal(await snapshotTablesForRoot(failing), null);
    assert.equal(loadedSnapshotTablesForRoot(failing), null);
    const retrying = await snapshotTablesForRoot(rootWithTables(key));
    assert.equal(retrying.json.schema, 2);
    assert.deepEqual(stub.calls, [key, key]);
  } finally {
    stub.restore();
  }
});

test("a digest mismatch walks to the next reference of the attribute", async () => {
  const stale = "https://tables.test/stale-cafe.json";
  const fresh = "https://tables.test/fresh-beef.json";
  const otherJson = TABLE_JSON.replace('"strings":[]', '"strings":["x"]');
  const stub = installFetch({ [stale]: [TABLE_JSON], [fresh]: [otherJson] });
  try {
    const expected = await sha256Text(otherJson);
    const table = await snapshotTablesForRoot(
      rootWithTables(`${stale} ${fresh}`),
      null,
      expected,
    );
    assert.equal(table.text, otherJson);
    assert.deepEqual(stub.calls, [stale, fresh]);
    assert.equal(await snapshotTablesForRoot(rootWithTables(stale), null, expected), null);
  } finally {
    stub.restore();
  }
});

test("invalid table bytes fail closed on parse", () => {
  assert.throws(() => parseSnapshotTables("{not json"), /SnapshotTablesInvalid/u);
  assert.throws(() => parseSnapshotTables("{}"), /SnapshotTablesInvalid/u);
  const parsed = JSON.parse(TABLE_JSON);
  assert.throws(
    () => parseSnapshotTables(JSON.stringify({ ...parsed, valueStyles: [17] })),
    /SnapshotTablesInvalid/u,
  );
});

test("the document pre-scan starts loading every referenced table", async () => {
  const key = "https://tables.test/prefetch-deadbeef.json";
  const stub = installFetch({ [key]: [TABLE_JSON] });
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
