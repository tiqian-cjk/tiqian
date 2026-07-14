import assert from "node:assert/strict";
import test from "node:test";

import {
  compactSnapshotManifest,
  expandSnapshotManifest,
} from "./snapshot-manifest.js";

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

  const expanded = expandSnapshotManifest(compact);
  assert.deepEqual(expanded.entries.map((entry) => entry.typography), [
    entries[0].typography,
    entries[1].typography,
  ]);
  assert.deepEqual(expanded.entries.map((entry) => entry.fontEvidence.faces[0].coverageText), [
    "中国",
    "正文",
  ]);
});

test("invalid compact table references fail closed", () => {
  const compact = compactSnapshotManifest([preparedEntry("a", "中国", "中")], {
    schema: 1,
  });
  compact.entries[0].typographyRef = 99;

  assert.throws(() => expandSnapshotManifest(compact), /SnapshotTypographyReferenceInvalid/u);
});
