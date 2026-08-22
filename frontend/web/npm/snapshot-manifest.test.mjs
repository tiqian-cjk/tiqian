import assert from "node:assert/strict";
import test from "node:test";

import { expandSnapshotManifest } from "./snapshot-manifest.js";
import { metricReplayKey, shapeReplayKey } from "./snapshot-schema.js";
import { writeBinaryTable } from "./table-binary-writer.mjs";
import { decodeSnapshotTableBinary } from "./snapshot-table-binary.js";

function stationTablesFixture() {
  return {
    replayStrings: ["a", "Fixture CJK", "zh-Hans", "CjkText", "fixture-face", "fixture-instance", "Hani"],
    typographies: [{
      sha256: "t".repeat(64),
      value: {
        fontFamilies: ["Fixture CJK"],
        fontSizePx: 18,
        lineHeightPx: 27,
        locale: "zh-Hans",
      },
    }],
    faces: [{
      family: "Fixture CJK",
      style: "normal",
      weight: [400, 400],
      unicodeRange: "U+4E00-9FFF",
      publicUrl: "/fixture-deadbeef.woff2",
      sourceSha256: "a".repeat(64),
      sfntSha256: "b".repeat(64),
      faceIndex: 0,
      sourceOrder: 0,
      axes: {},
      localNames: ["Fixture CJK"],
    }],
    metrics: [],
    probes: [{ text: "中", advancePx: 18, fontSizePx: 18, fontWeight: 400, italic: false, script: "Hani", language: "zh-Hans", features: [] }],
    valueStyles: ["font-variant-numeric: lining-nums"],
    fontPreloads: ["/fixture-deadbeef.woff2"],
    revisions: {
      backendRevision: "fixture-backend",
      harfbuzzVersion: "fixture-hb",
    },
  };
}

function tableViewFixture() {
  return decodeSnapshotTableBinary(writeBinaryTable(stationTablesFixture()));
}

function tablesManifestFixture() {
  return {
    schema: 2,
    tables: { snapshot: "0".repeat(64) },
    layoutRevision: "tiqian-layout-v2",
    renderRevision: "prebroken-dom-v15",
    fontSourcePolicy: "host-compatible-stylesheet-v1",
    paragraphSelector: "p[data-tq-snapshot-key]",
    renderFontFamilies: ["Fixture CJK"],
    fontReplay: {
      revision: "tiqian-server-shaping-replay-v1",
      encoding: "shared-strings-v1",
      shapes: [[0, 1, 400, 0, 2, 3, 0, 4, 5, 6, [], 0, 1, [1, 1, 0, 0, 0, -0.8, 1, 0.2]]],
    },
    entries: [{
      key: "a",
      sourceSha256: "a".repeat(64),
      typographyRef: 0,
      maxWidthPx: 360,
      fontFaceEvidence: [{ faceRef: 0, probeRef: 0 }],
      renderArtifactSha256: "r".repeat(64),
    }],
  };
}

test("manifests expand through the station table", () => {
  const tables = tableViewFixture();
  const manifest = tablesManifestFixture();
  const expanded = expandSnapshotManifest(manifest, tables);

  assert.deepEqual(expanded.entries[0].typography, tables.typographyAt(0).value);
  assert.equal(expanded.entries[0].typographySha256, tables.typographyAt(0).sha256);
  assert.equal(expanded.entries[0].fontEvidence.backendRevision, "fixture-backend");
  assert.equal(expanded.entries[0].fontEvidence.harfbuzzVersion, "fixture-hb");
  const face = expanded.entries[0].fontEvidence.faces[0];
  assert.equal(face.family, "Fixture CJK");
  assert.equal(face.probe.text, "中");
  assert.equal(face.coverageText, undefined);
  assert.deepEqual(expanded.valueStyles, ["font-variant-numeric: lining-nums"]);
  assert.deepEqual(expanded.entries[0].fontFaceEvidence, undefined);
  assert.deepEqual(expanded.fontReplay.shapes[0].key, shapeReplayKey(
    tables.stringAt(0),
    tables.stringAt(1),
    400,
    false,
    tables.stringAt(2),
    tables.stringAt(3),
    tables.stringAt(0),
  ));
  assert.deepEqual(expanded.fontReplay.metrics, []);
  assert.equal(metricReplayKey("Fixture CJK", 400, false, "CjkText", "a"),
    JSON.stringify(["Fixture CJK", 400, false, "CjkText", "a"]));
});

test("expansion keeps inline coverage of client contract rows", () => {
  const tables = tableViewFixture();
  const manifest = tablesManifestFixture();
  manifest.entrySource = "font-contract-v1";
  manifest.entries[0].fontFaceEvidence[0].coverageText = "中国正文";

  const expanded = expandSnapshotManifest(manifest, tables);
  assert.equal(expanded.entries[0].fontEvidence.faces[0].coverageText, "中国正文");
  assert.equal(expanded.entries[0].fontEvidence.faces[0].probe.text, "中");
});

test("manifests fail closed without, before, or against a broken table", () => {
  const tables = tableViewFixture();
  const manifest = tablesManifestFixture();

  assert.throws(() => expandSnapshotManifest(manifest), /SnapshotTablesMissing/u);
  assert.throws(
    () => expandSnapshotManifest({ ...manifest, tables: undefined }),
    /SnapshotManifestTablesInvalid/u,
  );
  assert.throws(() => expandSnapshotManifest(manifest, {}), /SnapshotTablesInvalid/u);
  manifest.entries[0].fontFaceEvidence[0].probeRef = 9;
  assert.throws(() => expandSnapshotManifest(manifest, tables), /SnapshotProbeReferenceInvalid/u);
});
