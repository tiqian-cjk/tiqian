import assert from "node:assert/strict";
import test from "node:test";

import {
  cssWeightPreference,
  fontRecordMatchesFamily,
  parseUnicodeRange,
  selectShapeFace,
  shapingPolicyForRole,
} from "./precompute-fonts.js";
import {
  createPrecomputer,
  renderPreparedParagraph,
  renderSnapshotBundle,
  renderSnapshotTemplate,
  snapshotPlainTextIssue,
} from "./precompute.js";

function snapshotFixturePlan() {
  return {
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: 27,
    lines: [{
      rangeStart: 0,
      rangeEnd: 2,
      top: 0,
      bottom: 27,
      baseline: 20,
      indent: 0,
      visualWidth: 36,
      hyphenAdvance: 0,
      endReason: "ParagraphEnd",
      cells: [{
        rangeStart: 0,
        rangeEnd: 2,
        source: "正文",
        display: "正文",
        drawX: 0,
        naturalWidth: 36,
        leadingLayoutAdvance: 0,
      }],
    }],
  };
}

test("exact font aliases resolve the host family from the OpenType name table", () => {
  const record = {
    family: "Tiqian Internal IBM Plex Sans SC",
    localNames: ["IBM Plex Sans SC", "IBM Plex Sans SC Medium", "IBMPlexSansSC-Medium"],
  };

  assert.equal(fontRecordMatchesFamily(record, "IBM Plex Sans SC"), true);
  assert.equal(fontRecordMatchesFamily(record, "tiqian internal ibm plex sans sc"), true);
  assert.equal(fontRecordMatchesFamily(record, "A Different Font"), false);
});

test("CSS weight matching lets a requested regular weight use the nearest medium face", () => {
  assert.deepEqual(cssWeightPreference([500, 500], 400), [1, 100]);
  assert.deepEqual(cssWeightPreference([400, 700], 500), [0, 0]);
  assert.ok(cssWeightPreference([300, 300], 400)[0] > cssWeightPreference([500, 500], 400)[0]);
});

test("display substitutions require real exact-face glyph coverage", () => {
  class FixtureFont {
    constructor(face) {
      this.face = face;
    }

    setScale() {}

    nominalGlyph(codePoint) {
      return this.face.glyphs.has(codePoint) ? codePoint : null;
    }
  }
  const record = (faceId, unicodeRange, glyphs) => ({
    faceId,
    family: "Fixture CJK",
    localNames: [],
    style: "normal",
    weightRange: [400, 400],
    unicodeRanges: parseUnicodeRange(unicodeRange),
    axisInfos: {},
    face: { upem: 1000, glyphs: new Set(glyphs) },
    hb: { Font: FixtureFont },
  });
  const sourceFace = record("source-ellipsis", "U+2026", [0x2026]);
  const declaredOnlyFace = record("declared-midline", "U+22EF", []);
  const families = ["Fixture CJK"];

  const fallback = selectShapeFace(
    { records: [declaredOnlyFace, sourceFace] },
    families,
    400,
    false,
    "⋯",
    "…",
  );
  assert.equal(fallback.record.faceId, "source-ellipsis");
  assert.equal(fallback.displayCovered, false);

  const midlineFace = record("real-midline", "U+22EF", [0x22ef]);
  const preferred = selectShapeFace(
    { records: [declaredOnlyFace, midlineFace, sourceFace] },
    families,
    400,
    false,
    "⋯",
    "…",
  );
  assert.equal(preferred.record.faceId, "real-midline");
  assert.equal(preferred.displayCovered, true);
});

test("Node Kotlin/JS precompute runs the real layout pipeline through a synchronous font session", async () => {
  const shapes = new Map();
  const metrics = new Map();
  const shapeCalls = [];
  let nextHandle = 1;
  globalThis.__TiqianFontBackend = {
    shape(_session, displayText, _families, fontSize, _weight, _italic, _locale, role) {
      const handle = nextHandle++;
      let cursor = 0;
      const glyphs = Array.from(displayText, (_point, index) => {
        const glyph = {
          id: 100 + index,
          advance: fontSize,
          x: cursor,
          y: 0,
          bounds: [0, -fontSize * 0.88, fontSize, fontSize * 0.12],
        };
        cursor += fontSize;
        return glyph;
      });
      const features = role === "LatinText" && /[‘’“”]/u.test(displayText)
        ? ["pwid", "palt"]
        : [];
      shapeCalls.push({ displayText, role, features });
      shapes.set(handle, { glyphs, advance: cursor, features });
      return handle;
    },
    shapeGlyphCount: (handle) => shapes.get(handle).glyphs.length,
    shapeGlyphId: (handle, index) => shapes.get(handle).glyphs[index].id,
    shapeGlyphAdvance: (handle, index) => shapes.get(handle).glyphs[index].advance,
    shapeGlyphX: (handle, index) => shapes.get(handle).glyphs[index].x,
    shapeGlyphY: (handle, index) => shapes.get(handle).glyphs[index].y,
    shapeGlyphBound: (handle, index, edge) => shapes.get(handle).glyphs[index].bounds[edge],
    shapeAdvance: (handle) => shapes.get(handle).advance,
    shapeFaceId: () => "Fixture CJK",
    shapeFontInstanceId: () => "fixture-sha:0:wght=400",
    shapeScript: () => "Hani",
    shapeFeatureCount: (handle) => shapes.get(handle).features.length,
    shapeFeature: (handle, index) => shapes.get(handle).features[index],
    shapeUnsafeBreakCount: () => 0,
    releaseShape: (handle) => shapes.delete(handle),
    metrics(_session, _families, fontSize) {
      const handle = nextHandle++;
      metrics.set(handle, [fontSize * 1.04, fontSize * 0.28, 0, fontSize * 0.88, fontSize * 0.12]);
      return handle;
    },
    metricValue: (handle, index) => metrics.get(handle)[index],
    releaseMetrics: (handle) => metrics.delete(handle),
  };

  const runtime = await import(`./precompute-runtime/Tiqian-tiqian-web-precompute.mjs?test=${Date.now()}`);
  const plan = JSON.parse(runtime.precomputePlainParagraph(
    "fixture-session",
    "中文中文",
    36,
    "Fixture CJK",
    18,
    27,
    "zh-Hans",
    400,
    false,
    0,
    true,
  ));

  assert.equal(plan.schema, 1);
  assert.equal(plan.layoutRevision, "tiqian-layout-v2");
  assert.equal(plan.lines.length, 2);
  assert.deepEqual(plan.lines.map((line) => line.cells.length), [2, 2]);
  assert.equal(shapes.size, 0);
  assert.equal(metrics.size, 0);

  const html = renderPreparedParagraph(plan, { locale: "zh-Hans" });
  assert.match(html, /data-tq-line-index="0"/);
  assert.match(html, /data-tq-engine-break="AutoWrap"/);
  assert.equal(html.match(/data-tq-shaping-boundary/gu)?.length ?? 0, 0);
  assert.equal(html.match(/data-tq-advance/gu)?.length ?? 0, 0);
  assert.match(html, /<\/span>中文<span/u);

  const quotePlan = JSON.parse(runtime.precomputePlainParagraph(
    "fixture-session",
    "中“文”中；that’s James’ ’90s；（如 ‘O’, ‘Q’）",
    1_000,
    "Fixture CJK",
    18,
    27,
    "zh-Hans",
    400,
    false,
    0,
    true,
  ));
  const quoteCells = quotePlan.lines
    .flatMap((line) => line.cells)
    .filter((cell) => /[‘’“”]/u.test(cell.source));
  const quoteCount = (cells) => cells.reduce(
    (count, cell) => count + Array.from(cell.source).filter((char) => /[‘’“”]/u.test(char)).length,
    0,
  );
  const proportionalQuoteCells = quoteCells.filter((cell) =>
    JSON.stringify(cell.openTypeFeatures) === JSON.stringify(["pwid", "palt"]));
  const cjkQuoteCells = quoteCells.filter((cell) => cell.openTypeFeatures == null);
  const multiCodeUnitCells = quotePlan.lines
    .flatMap((line) => line.cells)
    .filter((cell) => cell.rangeEnd - cell.rangeStart > 1);

  assert.equal(quoteCount(proportionalQuoteCells), 7, JSON.stringify(shapeCalls));
  assert.equal(quoteCount(cjkQuoteCells), 2, JSON.stringify(shapeCalls));
  assert.ok(multiCodeUnitCells.length > 0);
  assert.ok(multiCodeUnitCells.every((cell) => cell.shapingBoundary === true));
  assert.match(
    renderPreparedParagraph(quotePlan, { locale: "zh-Hans" }),
    /data-tq-open-type-features="pwid,palt"/u,
  );
  assert.equal(shapes.size, 0);
  assert.equal(metrics.size, 0);
});

test("snapshot template keeps the prepared DOM inert and Pagefind-ignored", () => {
  const prepared = {
    status: "prepared",
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    renderRevision: "prebroken-dom-v13",
    renderFontFamilies: ["Snapshot Sans"],
    key: "p-1",
    renderArtifactSha256: "c".repeat(64),
    sourceSha256: "a".repeat(64),
    typographySha256: "b".repeat(64),
    typography: {
      fontFamilies: ["Fixture CJK"],
      fontSizePx: 18,
      lineHeightPx: 27,
      locale: "zh-Hans",
      fontWeight: 400,
      italic: false,
      firstLineIndentIc: 0,
      lineLengthGridEnabled: true,
      letterSpacingPx: 0,
      fontFeatureSettings: "normal",
      fontVariationSettings: "normal",
    },
    maxWidthPx: 360,
    fontEvidence: {
      backendRevision: "tiqian-shared-harfbuzz-v5",
      harfbuzzVersion: "fixture",
      faces: [{
        family: "Fixture CJK",
        coverageText: "正文",
        probe: { text: "正" },
      }],
      replay: {
        revision: "tiqian-server-shaping-replay-v1",
        shapes: [],
        metrics: [],
      },
    },
    plan: snapshotFixturePlan(),
    html: "<span>正文</span>",
  };
  const template = renderSnapshotTemplate([prepared], { id: "tq-page" });
  assert.match(template, /^<template /);
  assert.match(template, /data-pagefind-ignore/);
  assert.match(template, /data-tq-snapshot-manifest/);
  assert.match(template, /data-tq-entry="p-1"/);
  assert.doesNotMatch(template, / style=/u);
  assert.match(template, /class="tq-line tqv-0"/u);
});

test("snapshot bundle exposes compact SSR artifacts without inline geometry", () => {
  const prepared = {
    status: "prepared",
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    renderRevision: "prebroken-dom-v13",
    renderFontFamilies: ["Snapshot Sans"],
    key: "p-1",
    renderArtifactSha256: "c".repeat(64),
    sourceSha256: "a".repeat(64),
    typographySha256: "b".repeat(64),
    typography: {
      fontFamilies: ["Fixture CJK"],
      fontSizePx: 18,
      lineHeightPx: 27,
      locale: "zh-Hans",
      fontWeight: 400,
      italic: false,
      firstLineIndentIc: 0,
      lineLengthGridEnabled: true,
      letterSpacingPx: 0,
      fontFeatureSettings: "normal",
      fontVariationSettings: "normal",
    },
    maxWidthPx: 360,
    fontEvidence: {
      backendRevision: "tiqian-shared-harfbuzz-v5",
      harfbuzzVersion: "fixture",
      faces: [{
        family: "Fixture CJK",
        publicUrl: "/fonts/fixture-deadbeef.woff2",
        coverageText: "正文",
        probe: { text: "正" },
      }],
      replay: {
        revision: "tiqian-server-shaping-replay-v1",
        shapes: [],
        metrics: [],
      },
    },
    plan: snapshotFixturePlan(),
    html: "<span>正文</span>",
  };

  const bundle = renderSnapshotBundle([prepared], { id: "tq-page" });

  assert.equal(bundle.id, "tq-page");
  assert.equal(bundle.entries.length, 1);
  assert.equal(bundle.entries[0].key, "p-1");
  assert.match(bundle.entries[0].html, /class="tq-line tqv-0"/u);
  assert.doesNotMatch(bundle.entries[0].html, / style=/u);
  assert.match(bundle.initialStyle, /tiqian-prose\[snapshot-ref="tq-page"\]/u);
  assert.match(bundle.initialStyle, /--tq-exact-render-font-family:"Snapshot Sans"/u);
  assert.match(
    bundle.initialStyle,
    /\[data-tiqian-exact-render-font=true\].*\[data-tq-rendered=true\]\{font-family:var\(--tq-exact-render-font-family\)!important;font-kerning:normal!important;font-optical-sizing:none!important\}/u,
  );
  assert.match(bundle.initialStyle, /\.tqv-0\{/u);
  assert.deepEqual(bundle.renderFontFamilies, ["Snapshot Sans"]);
  assert.deepEqual(bundle.fontPreloads, ["/fonts/fixture-deadbeef.woff2"]);
  assert.deepEqual(bundle.rootAttributes, { "data-tiqian-exact-render-font": "true" });
  assert.match(bundle.template, /^<template /u);
  assert.match(bundle.template, /server-dom-v1/u);
  assert.doesNotMatch(bundle.template, /data-tq-entry=/u);
  assert.match(bundle.inertTemplate, /^<template /u);
  assert.match(bundle.inertTemplate, /data-tq-entry="p-1"/u);
  assert.doesNotMatch(bundle.inertTemplate, /server-dom-v1/u);
  assert.match(bundle.clientTemplate, /font-contract-v1/u);
  assert.doesNotMatch(bundle.clientTemplate, /data-tq-entry=/u);
  assert.ok(bundle.clientTemplate.length < bundle.template.length);

  const laterFace = {
    ...prepared,
    key: "p-2",
    sourceSha256: "d".repeat(64),
    fontEvidence: {
      ...prepared.fontEvidence,
      faces: [{
        ...prepared.fontEvidence.faces[0],
        publicUrl: "/fonts/below-fold-deadbeef.woff2",
        coverageText: "后文",
        probe: { text: "后" },
      }],
    },
  };
  const boundedPreloads = renderSnapshotBundle([prepared, laterFace], { id: "tq-page-two" });
  assert.deepEqual(boundedPreloads.fontPreloads, ["/fonts/fixture-deadbeef.woff2"]);

  const semanticContract = renderSnapshotBundle([prepared], {
    id: "tq-page-semantic",
    fontContractParagraphs: [laterFace],
  });
  assert.equal(semanticContract.entries.length, 1);
  assert.equal(semanticContract.entries[0].key, "p-1");
  assert.match(semanticContract.template, /fontContractEntries/u);
  assert.match(semanticContract.template, /below-fold-deadbeef/u);
  assert.match(semanticContract.clientTemplate, /below-fold-deadbeef/u);
});

test("snapshot template refuses a stale prepared render revision", () => {
  const stale = {
    status: "prepared",
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    renderRevision: "prebroken-dom-v0",
    key: "p-1",
  };
  assert.throws(
    () => renderSnapshotTemplate([stale], { id: "tq-stale" }),
    /SnapshotTemplateContainsStalePreparedParagraph/u,
  );
});

test("v1 snapshot candidates stay aligned with the paragraph observer contract", () => {
  const prepared = {
    status: "prepared",
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    renderRevision: "prebroken-dom-v13",
    renderFontFamilies: ["Snapshot Sans"],
    key: "p-1",
    renderArtifactSha256: "c".repeat(64),
  };
  assert.throws(
    () => renderSnapshotTemplate([prepared], {
      id: "tq-custom-selector",
      paragraphSelector: ".paragraph[data-tq-snapshot-key]",
    }),
    /UnsupportedSnapshotParagraphSelector/u,
  );
});

test("v1 snapshot typography stays aligned with the browser fallback contract", async () => {
  const base = {
    faces: [],
    typography: {
      fontFamilies: ["Fixture CJK"],
      fontSizePx: 18,
      lineHeightPx: 27,
    },
  };
  await assert.rejects(
    createPrecomputer({ ...base, typography: { ...base.typography, locale: "ja" } }),
    /UnsupportedSnapshotLocale/u,
  );
  await assert.rejects(
    createPrecomputer({ ...base, typography: { ...base.typography, lineLengthGridEnabled: false } }),
    /UnsupportedSnapshotLineLengthGrid/u,
  );
  await assert.rejects(
    createPrecomputer({
      ...base,
      typography: { ...base.typography, fontVariantNumeric: "oldstyle-nums" },
    }),
    /UnsupportedFontVariantNumeric/u,
  );
});

test("engine-owned hyphens are visual-only in the source-faithful copy contract", () => {
  const html = renderPreparedParagraph({
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: 27,
    lines: [{
      rangeStart: 0,
      rangeEnd: 3,
      top: 0,
      bottom: 27,
      baseline: 20,
      indent: 0,
      visualWidth: 25,
      hyphenAdvance: 5,
      endReason: "AutoWrap",
      cells: [{
        rangeStart: 0,
        rangeEnd: 3,
        source: "int",
        display: "int",
        drawX: 0,
        naturalWidth: 25,
        leadingLayoutAdvance: 0,
      }],
    }],
  }, { locale: "zh-Hans" });
  assert.match(html, /<span [^>]*aria-hidden="true"[^>]*data-tq-copy-ignore="true"[^>]*>-<\/span>/u);
  assert.match(html, /data-tq-line-flow-width="30"/u);
  assert.match(html, /data-tq-line-width="30"/u);
  assert.doesNotMatch(html, /data-tq-shaping-boundary[^>]*margin-right/u);
  assert.match(html, /data-tq-engine-hyphen="true"/u);
  assert.doesNotMatch(html, /(?:all:unset|display:inline-block|white-space:pre)/u);
});

test("snapshot lowering rejects a first-cell placement it cannot reproduce in inline flow", () => {
  assert.throws(
    () => renderPreparedParagraph({
      schema: 1,
      layoutRevision: "tiqian-layout-v2",
      height: 27,
      lines: [{
        rangeStart: 0,
        rangeEnd: 1,
        top: 0,
        bottom: 27,
        baseline: 20,
        indent: 0,
        visualWidth: 18,
        hyphenAdvance: 0,
        endReason: "ParagraphEnd",
        cells: [{
          rangeStart: 0,
          rangeEnd: 1,
          source: "中",
          display: "中",
          drawX: 2,
          naturalWidth: 18,
          leadingLayoutAdvance: 2,
        }],
      }],
    }, { locale: "zh-Hans" }),
    /SnapshotRenderFlowMismatch/u,
  );
});

test("plain CJK snapshot wire keeps ordinary text out of geometry spans", () => {
  const cellCount = 1000;
  const html = renderPreparedParagraph({
    schema: 1,
    layoutRevision: "tiqian-layout-v2",
    height: 27,
    lines: [{
      rangeStart: 0,
      rangeEnd: cellCount,
      top: 0,
      bottom: 27,
      baseline: 20,
      indent: 0,
      visualWidth: cellCount * 18,
      hyphenAdvance: 0,
      endReason: "ParagraphEnd",
      cells: Array.from({ length: cellCount }, (_, index) => ({
        rangeStart: index,
        rangeEnd: index + 1,
        source: "中",
        display: "中",
        drawX: index * 18,
        naturalWidth: 18,
        leadingLayoutAdvance: 0,
      })),
    }],
  }, { locale: "zh-Hans" });

  assert.equal(html.match(/data-tq-advance/gu)?.length ?? 0, 0);
  assert.equal(html.match(/data-tq-geometry="true"/gu)?.length, 2);
  assert.ok(html.length / cellCount < 2, `wire grew to ${html.length / cellCount} bytes/cell`);
});

test("build-time unicode-range parser handles wildcard subsets", () => {
  assert.deepEqual(parseUnicodeRange("U+4E??, U+2013-2014"), [
    [0x4e00, 0x4eff],
    [0x2013, 0x2014],
  ]);
});

test("shared curly quotes use role-aware scripts and replayable proportional features", () => {
  assert.deepEqual(shapingPolicyForRole("CjkPunctuation", "’"), {
    script: "Hani",
    features: [],
  });
  assert.deepEqual(shapingPolicyForRole("CjkText", "‘"), {
    script: "Hani",
    features: [],
  });
  assert.deepEqual(shapingPolicyForRole("LatinText", "that’s"), {
    script: "Latn",
    features: ["pwid", "palt"],
  });
  assert.deepEqual(shapingPolicyForRole("LatinText", "thats"), {
    script: "Latn",
    features: [],
  });
});

test("v1 plain-text snapshots reject scripts whose browser shaping cannot be replayed exactly", () => {
  assert.equal(snapshotPlainTextIssue("中文 Latin 123，。"), null);
  assert.equal(snapshotPlainTextIssue("Ελληνικά"), "UnsupportedSnapshotScript");
  assert.equal(snapshotPlainTextIssue("Блог"), "UnsupportedSnapshotScript");
  assert.equal(snapshotPlainTextIssue("ㄅㄆㄇ"), "UnsupportedSnapshotScript");
  assert.equal(snapshotPlainTextIssue("a\u0301"), "UnsupportedSnapshotScript");
  assert.equal(snapshotPlainTextIssue("ạ"), "UnsupportedSnapshotScript");
  assert.equal(snapshotPlainTextIssue("Ａ"), "UnsupportedSnapshotScript");
});
