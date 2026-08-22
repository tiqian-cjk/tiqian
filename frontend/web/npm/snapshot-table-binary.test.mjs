import assert from "node:assert/strict";
import test from "node:test";

import { writeBinaryTable } from "./table-binary-writer.mjs";
import { decodeSnapshotTableBinary } from "./snapshot-table-binary.js";
import { snapshotTablesForRoot, snapshotTablesFromBytes } from "./snapshot-tables.js";
import { expandSnapshotManifest } from "./snapshot-manifest.js";

/**
 * One table held in both file forms. The strings list follows the binary
 * encoder's intern order (replay strings, metric strings, then probe scan
 * order) so integer references mean the same row in both lanes.
 */
const TABLE = {
  replayStrings: ["源", "Noto Serif CJK", "zh-Hans", "body",
    "noto-serif-1", "noto-serif-i1", "hani"],
  metrics: [
    {
      serializedFamilies: "Noto Serif CJK",
      fontWeight: 400,
      italic: false,
      role: "body",
      faceSelectionText: '{"weight":400}',
      valuesEm: [0.5, null, null, null, null],
    },
    {
      serializedFamilies: "Noto Serif CJK",
      fontWeight: 700,
      italic: true,
      role: "body",
      faceSelectionText: '{"weight":400}',
      valuesEm: [0.5, 0.6, 0.7, 0.8, 0.9],
    },
  ],
  probes: [
    {
      text: "永",
      advancePx: 16,
      fontSizePx: 16,
      fontWeight: 400,
      italic: false,
      script: "hani",
      language: "ZH",
      features: ["kern"],
    },
    {
      text: "永",
      advancePx: 16.5,
      fontSizePx: 16,
      fontWeight: 700,
      italic: true,
      script: "hani",
      language: "ZH",
      features: [],
    },
  ],
  faces: [{ family: "Noto Serif CJK", sourceOrder: 0 }],
  typographies: [{ sha256: "aa", value: { lines: [] } }],
  valueStyles: [".tq-root[data-v=da0e] { line-height: 1.7; }"],
  fontPreloads: [],
  revisions: { backendRevision: "r123", harfbuzzVersion: "11.0.1" },
};

/** A manifest whose references address the fixture table. */
function manifestPinning() {
  return {
    tables: { snapshot: "0".repeat(64) },
    fontReplay: {
      revision: "tiqian-server-shaping-replay-v1",
      encoding: "shared-strings-v1",
      shapes: [[
        0, 1, 400, 0, 2, 3, 0, 4, 5, 6,
        [10], 0, 1,
        [1001, 1, 0, 0, null, null, null, null],
      ]],
    },
    entries: [{
      key: "p1",
      sourceSha256: "bb",
      typographyRef: 0,
      maxWidthPx: 360,
      fontFaceEvidence: [{ faceRef: 0, coverageText: "永远", probeRef: 1 }],
      renderArtifactSha256: "cc",
    }],
  };
}

test("binary table rows read back through the accessors", () => {
  const bytes = writeBinaryTable(TABLE);
  const view = decodeSnapshotTableBinary(bytes);
  assert.equal(view.binary, true);
  assert.equal(view.stringAt(0), "源");
  assert.equal(view.stringAt(10), "kern");
  assert.throws(() => view.stringAt(11), /SnapshotFontReplayStringReferenceInvalid/u);

  const rows = view.metricRows();
  assert.deepEqual(rows[0], TABLE.metrics[0]);
  assert.deepEqual(rows[1], TABLE.metrics[1]);

  assert.deepEqual(view.probeAt(0), TABLE.probes[0]);
  assert.deepEqual(view.probeAt(1), TABLE.probes[1]);
  assert.throws(() => view.probeAt(2), /SnapshotProbeReferenceInvalid/u);

  assert.deepEqual(view.typographyAt(0), TABLE.typographies[0]);
  assert.deepEqual(view.faceAt(0), TABLE.faces[0]);
  assert.deepEqual(view.valueStyles(), TABLE.valueStyles);
  assert.deepEqual(view.revisions(), TABLE.revisions);
});

test("damaged binary bytes fail closed", () => {
  const bytes = writeBinaryTable(TABLE);
  assert.throws(
    () => decodeSnapshotTableBinary(bytes.subarray(0, bytes.length - 1)),
    /SnapshotTablesInvalid/u,
  );
  assert.throws(
    () => decodeSnapshotTableBinary(bytes.subarray(0, 60)),
    /SnapshotTablesInvalid/u,
  );
  const wrongMagic = new Uint8Array(bytes);
  wrongMagic[4] = "9".charCodeAt(0);
  assert.throws(() => decodeSnapshotTableBinary(wrongMagic), /SnapshotTablesInvalid/u);
  // The revision tail parses during decode; trailing bytes break the parse
  // and the file fails closed.
  const overstuffed = new Uint8Array([...bytes, 0]);
  assert.throws(() => decodeSnapshotTableBinary(overstuffed), /SnapshotTablesInvalid/u);
});

test("the binary lane loads through the transport", async () => {
  const bytes = writeBinaryTable(TABLE);
  const key = "https://tables.test/station-deadbeef.tiqtbl";
  const previousFetch = globalThis.fetch;
  globalThis.fetch = async () => ({ ok: true, arrayBuffer: async () => bytes });
  try {
    const root = { getAttribute: (name) => (name === "tq-tables" ? key : null) };
    const table = await snapshotTablesForRoot(root, null);
    assert.equal(table.view.binary, true);
    assert.deepEqual([...table.bytes], [...bytes]);
    assert.equal(new TextDecoder().decode(table.bytes.subarray(0, 8)), "TIQTBL03");
  } finally {
    globalThis.fetch = previousFetch;
  }
});

test("the binary table expands the manifest it pins", () => {
  const binary = expandSnapshotManifest(
    manifestPinning(),
    decodeSnapshotTableBinary(writeBinaryTable(TABLE)),
  );
  assert.equal(binary.entries[0].fontEvidence.faces[0].probe.advancePx, 16.5);
  assert.equal(binary.entries[0].fontEvidence.faces[0].probe.features.length, 0);
  assert.equal(binary.fontReplay.shapes[0].result.features[0], "kern");
  assert.equal(binary.fontReplay.metrics.length, 2);
  assert.throws(
    () => expandSnapshotManifest(
      manifestPinning(),
      snapshotTablesFromBytes(new TextEncoder().encode("{\"schema\":2}")),
    ),
    /SnapshotTablesInvalid/u,
  );
});
