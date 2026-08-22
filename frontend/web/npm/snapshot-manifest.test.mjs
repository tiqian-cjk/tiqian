import assert from "node:assert/strict";
import test from "node:test";

import {
  compactSnapshotManifest,
  expandSnapshotManifest,
} from "./snapshot-manifest.js";
import { metricReplayKey, shapeReplayKey } from "./snapshot-schema.js";

function preparedEntry(key, coverageText, probeText) {
  const typography = {
    fontFamilies: ["Fixture CJK"],
    fontSizePx: 18,
    lineHeightPx: 27,
    locale: "zh-Hans",
  };
  return {
    key,
    sourceSha256: key.repeat(64).slice(0, 64),
    typographySha256: "t".repeat(64),
    typography,
    maxWidthPx: 360,
    renderArtifactSha256: "r".repeat(64),
    fontEvidence: {
      backendRevision: "fixture-backend",
      harfbuzzVersion: "fixture-hb",
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
        coverageText,
        probe: { text: probeText, advancePx: 18 },
      }],
      replay: {
        revision: "tiqian-server-shaping-replay-v1",
        shapes: [{
          key: JSON.stringify([key, "Fixture CJK", 400, false, "zh-Hans", "CjkText", key]),
          result: {
            faceId: "fixture-face",
            fontInstanceId: "fixture-instance",
            script: "Hani",
            features: [],
            unsafeBreakCount: 0,
            advanceEm: 1,
            glyphs: [{
              id: 1,
              advanceEm: 1,
              xEm: 0,
              yEm: 0,
              boundsEm: [0, -0.8, 1, 0.2],
            }],
          },
        }],
        metrics: [{
          key: JSON.stringify(["Fixture CJK", 400, false, "CjkText", key]),
          valuesEm: [1, 0, 0, 1, 0],
        }],
      },
    },
  };
}

test("shared manifest tables keep typography and face descriptors once", () => {
  const entries = [
    preparedEntry("a", "中国", "中"),
    preparedEntry("b", "正文", "正"),
  ];
  const compact = compactSnapshotManifest(entries, {
    schema: 1,
    paragraphSelector: "p[data-tq-snapshot-key]",
    valueStyles: [],
  });

  assert.equal(compact.typographies.length, 1);
  assert.equal(compact.fontEvidence.faces.length, 1);
  assert.equal(compact.entries[0].typography, undefined);
  assert.equal(compact.entries[0].fontEvidence, undefined);
  assert.deepEqual(compact.entries.map((entry) => entry.typographyRef), [0, 0]);
  assert.deepEqual(compact.entries.map((entry) => entry.fontFaceEvidence[0].faceRef), [0, 0]);
  assert.equal(compact.fontReplay.encoding, "shared-strings-v1");
  assert.ok(compact.fontReplay.strings.length > 0);
  assert.ok(compact.fontReplay.shapes.every(Array.isArray));
  assert.ok(compact.fontReplay.metrics.every(Array.isArray));

  const expanded = expandSnapshotManifest(compact);
  assert.deepEqual(expanded.entries.map((entry) => entry.typography), [
    entries[0].typography,
    entries[1].typography,
  ]);
  assert.deepEqual(expanded.entries.map((entry) => entry.fontEvidence.faces[0].coverageText), [
    "中国",
    "正文",
  ]);
  assert.deepEqual(expanded.fontReplay, {
    revision: "tiqian-server-shaping-replay-v1",
    shapes: entries.flatMap((entry) => entry.fontEvidence.replay.shapes),
    metrics: entries.flatMap((entry) => entry.fontEvidence.replay.metrics),
  });
});

test("shared replay tables deduplicate identical keys and reject conflicts", () => {
  const first = preparedEntry("a", "中国", "中");
  const duplicate = preparedEntry("b", "正文", "正");
  duplicate.fontEvidence.replay = structuredClone(first.fontEvidence.replay);
  const compact = compactSnapshotManifest([first, duplicate], { schema: 1 });

  assert.equal(compact.fontReplay.shapes.length, 1);
  assert.equal(compact.fontReplay.metrics.length, 1);

  const conflict = preparedEntry("c", "冲突", "冲");
  conflict.fontEvidence.replay = structuredClone(first.fontEvidence.replay);
  conflict.fontEvidence.replay.shapes[0].result.advanceEm = 2;
  assert.throws(
    () => compactSnapshotManifest([first, conflict], { schema: 1 }),
    /SnapshotFontReplayShapeConflict/u,
  );
});

test("invalid compact table references fail closed", () => {
  const compact = compactSnapshotManifest([preparedEntry("a", "中国", "中")], {
    schema: 1,
  });
  compact.entries[0].typographyRef = 99;

  assert.throws(() => expandSnapshotManifest(compact), /SnapshotTypographyReferenceInvalid/u);
});

test("invalid replay string references fail closed", () => {
  const compact = compactSnapshotManifest([preparedEntry("a", "中国", "中")], {
    schema: 1,
  });
  compact.fontReplay.shapes[0][0] = 99;

  assert.throws(() => expandSnapshotManifest(compact), /SnapshotFontReplayStringReferenceInvalid/u);
});

function stationTablesFixture() {
  return {
    schema: 2,
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
    valueStyles: ["font-variant-numeric: lining-nums"],
    fontPreloads: ["/fixture-deadbeef.woff2"],
    revisions: {
      backendRevision: "fixture-backend",
      harfbuzzVersion: "fixture-hb",
      fontReplay: "tiqian-server-shaping-replay-v1",
      fontReplayTransport: "shared-strings-v1",
    },
    strings: ["a", "Fixture CJK", "zh-Hans", "CjkText", "fixture-face", "fixture-instance", "Hani"],
    probes: [{ text: "中", advancePx: 18 }],
    metrics: [[1, 400, 0, 3, 0, 1, 0, 0, 1, 0]],
  };
}

function tablesManifestFixture(tables) {
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

test("schema-2 manifests expand through the station table", () => {
  const tables = stationTablesFixture();
  const manifest = tablesManifestFixture(tables);
  const expanded = expandSnapshotManifest(manifest, tables);

  assert.deepEqual(expanded.entries[0].typography, tables.typographies[0].value);
  assert.equal(expanded.entries[0].typographySha256, tables.typographies[0].sha256);
  assert.equal(expanded.entries[0].fontEvidence.backendRevision, "fixture-backend");
  assert.equal(expanded.entries[0].fontEvidence.harfbuzzVersion, "fixture-hb");
  const face = expanded.entries[0].fontEvidence.faces[0];
  assert.equal(face.family, "Fixture CJK");
  assert.equal(face.probe.text, "中");
  assert.equal(face.coverageText, undefined);
  assert.deepEqual(expanded.valueStyles, tables.valueStyles);
  assert.deepEqual(expanded.entries[0].fontFaceEvidence, undefined);
  assert.deepEqual(expanded.fontReplay.shapes[0].key, shapeReplayKey(
    "a",
    "Fixture CJK",
    400,
    false,
    "zh-Hans",
    "CjkText",
    "a",
  ));
  assert.deepEqual(expanded.fontReplay.metrics, [{
    key: metricReplayKey("Fixture CJK", 400, false, "CjkText", "a"),
    valuesEm: [1, 0, 0, 1, 0],
  }]);
});

test("schema-2 expansion keeps inline coverage of client contract rows", () => {
  const tables = stationTablesFixture();
  const manifest = tablesManifestFixture(tables);
  manifest.entrySource = "font-contract-v1";
  manifest.entries[0].fontFaceEvidence[0].coverageText = "中国正文";

  const expanded = expandSnapshotManifest(manifest, tables);
  assert.equal(expanded.entries[0].fontEvidence.faces[0].coverageText, "中国正文");
  assert.equal(expanded.entries[0].fontEvidence.faces[0].probe.text, "中");
});

test("schema-2 manifests fail closed without or against a broken table", () => {
  const tables = stationTablesFixture();
  const manifest = tablesManifestFixture(tables);

  assert.throws(() => expandSnapshotManifest(manifest), /SnapshotTablesMissing/u);
  assert.throws(() => expandSnapshotManifest(manifest, { ...tables, schema: 1 }), /SnapshotTablesInvalid/u);
  manifest.entries[0].fontFaceEvidence[0].probeRef = 9;
  assert.throws(() => expandSnapshotManifest(manifest, tables), /SnapshotProbeReferenceInvalid/u);
});
