import assert from "node:assert/strict";
import test from "node:test";

import { expandSnapshotManifest } from "../src/sampler/snapshot/snapshot-manifest.js";
import type { SnapshotManifestWire, SnapshotTablesPin } from "../src/sampler/snapshot/snapshot-manifest.js";
import { metricReplayKey, shapeReplayKey } from "../src/sampler/snapshot/snapshot-schema.js";
import { writeBinaryTable } from "../src/sampler/snapshot/table-binary-encode.js";
import type { BinaryTableInput } from "../src/sampler/snapshot/table-binary-encode.js";
import { decodeSnapshotTableBinary } from "../src/sampler/snapshot/snapshot-table-binary.js";

/** Helper to create a valuesEm array with nulls */
function valuesEm(...values: Array<number | null>): (number | null)[] {
  return values;
}

function snapshotTablesFixture(): BinaryTableInput {
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
  return decodeSnapshotTableBinary(writeBinaryTable(snapshotTablesFixture()));
}

function tablesManifestFixture(): SnapshotManifestWire {
  const tablesPin: SnapshotTablesPin = { snapshot: "0".repeat(64) };
  const shapeRow: [number, number, number, number, number, number, number, number, number, number, number[], number, number, number[]] = [
    0, 1, 400, 0, 2, 3, 0, 4, 5, 6, [], 0, 1, [1, 1, 0, 0, 0, -0.8, 1, 0.2],
  ];
  return {
    schema: 2,
    tables: tablesPin,
    layoutRevision: "tiqian-layout-v2",
    renderRevision: "prebroken-dom-v17",
    fontSourcePolicy: "host-compatible-stylesheet-v1",
    paragraphSelector: "p[data-tq-snapshot-key]",
    renderFontFamilies: ["Fixture CJK"],
    fontReplay: {
      revision: "tiqian-server-shaping-replay-v1",
      encoding: "shared-strings-v1",
      shapes: [shapeRow],
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

test("manifests expand through the snapshot table", () => {
  const tables = tableViewFixture();
  const manifest = tablesManifestFixture();
  const expanded = expandSnapshotManifest(manifest, tables);

  const typographyRecord = tables.typographyAt(0) as { sha256: string; value: unknown };
  assert.deepEqual(expanded.entries[0].typography, typographyRecord.value);
  assert.equal(expanded.entries[0].typographySha256, typographyRecord.sha256);
  assert.equal(expanded.entries[0].fontEvidence.backendRevision, "fixture-backend");
  assert.equal(expanded.entries[0].fontEvidence.harfbuzzVersion, "fixture-hb");
  const face = expanded.entries[0].fontEvidence.faces[0];
  assert.equal(face.family, "Fixture CJK");
  if (face.probe == null) throw new Error("Expected probe on face");
  assert.equal(face.probe.text, "中");
  assert.equal(face.coverageText, undefined);
  assert.deepEqual(expanded.valueStyles, ["font-variant-numeric: lining-nums"]);
  // fontFaceEvidence is a wire field that gets removed during expansion - split assertion into two steps
  const entryIntermediate = expanded.entries[0] as unknown;
  const entryRecord = entryIntermediate as Record<string, unknown>;
  assert.equal(entryRecord.fontFaceEvidence, undefined);
  if (expanded.fontReplay == null) throw new Error("Expected font replay");
  assert.deepEqual(expanded.fontReplay.shapes[0].key, shapeReplayKey(
    tables.stringAt(0) as string,
    tables.stringAt(1) as string,
    400,
    false,
    tables.stringAt(2) as string,
    tables.stringAt(3) as string,
    tables.stringAt(0) as string,
  ));
  assert.deepEqual(expanded.fontReplay.metrics, []);
  assert.equal(metricReplayKey("Fixture CJK", 400, false, "CjkText", "a"),
    JSON.stringify(["Fixture CJK", 400, false, "CjkText", "a"]));
});

test("expansion keeps inline coverage of client contract rows", () => {
  const tables = tableViewFixture();
  const manifest = tablesManifestFixture();
  manifest.entrySource = "font-contract-v1";
  if (manifest.entries[0].fontFaceEvidence.length === 0) throw new Error("Expected at least one evidence");
  manifest.entries[0].fontFaceEvidence[0].coverageText = "中国正文";

  const expanded = expandSnapshotManifest(manifest, tables);
  assert.equal(expanded.entries[0].fontEvidence.faces[0].coverageText, "中国正文");
  if (expanded.entries[0].fontEvidence.faces[0].probe == null) throw new Error("Expected probe");
  assert.equal(expanded.entries[0].fontEvidence.faces[0].probe.text, "中");
});

test("manifests fail closed without, before, or against a broken table", () => {
  const tables = tableViewFixture();
  const manifest = tablesManifestFixture();

  assert.throws(() => expandSnapshotManifest(manifest), /SnapshotTablesMissing/u);
  // Split the double assertion into two separate statements per ADR 0053 StrictTsDiscipline
  const tablesIntermediate = undefined as unknown;
  const tablesValue = tablesIntermediate as SnapshotTablesPin;
  assert.throws(
    () => expandSnapshotManifest({ ...manifest, tables: tablesValue }),
    /SnapshotManifestTablesInvalid/u,
  );
  assert.throws(() => expandSnapshotManifest(manifest, null), /SnapshotTablesMissing/u);
  if (manifest.entries[0].fontFaceEvidence.length === 0) throw new Error("Expected at least one evidence");
  manifest.entries[0].fontFaceEvidence[0].probeRef = 9;
  assert.throws(() => expandSnapshotManifest(manifest, tables), /SnapshotProbeReferenceInvalid/u);
});
