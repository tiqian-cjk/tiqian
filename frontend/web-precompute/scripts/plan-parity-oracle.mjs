// Plan parity oracle (ADR 0050 amendment Verification).
//
// Runs the Kotlin/JS precompute bundle over the same deterministic fixture
// font backend and the same corpus as the Rust integration test
// `rust/tiqian-precompute/tests/plan_parity.rs`, and writes
// `build/plan-parity/oracle.json`. The Rust test byte-compares that file
// against its own dump, so both lanes must serialize the corpus in the same
// order with the same argument values.
//
// Node only: node scripts/plan-parity-oracle.mjs (from frontend/web-precompute).

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const bundleUrl = new URL(
  "../../../ffi/js/build/compileSync/js/main/productionExecutable/kotlin/Tiqian-tiqian-ffi-js.mjs",
  import.meta.url,
);

const FAMILY_SEPARATOR = "\u001f";
const RECORD_SEPARATOR = "\u001e";
const FIELD_SEPARATOR = "\u001d";

// The fixture backend of PrecomputeExportsTest.kt: one glyph per code point,
// advance and x scaled by the font size, glyph id 0 marks a missing glyph.
// The handle protocol is the synchronous Node font session contract.
function installFixtureBackend() {
  let nextHandle = 1;
  const shapes = new Map();
  const metrics = new Map();
  globalThis.__TiqianFontBackend = {
    shape(_session, displayText, _families, fontSize) {
      const handle = nextHandle++;
      const missing = String(displayText).includes("⋯");
      const glyphs = [];
      let index = 0;
      for (const _point of displayText) {
        glyphs.push({
          id: missing ? 0 : 100 + index,
          advance: fontSize,
          x: index * fontSize,
          y: 0,
          bounds: [0, -fontSize * 0.88, fontSize, fontSize * 0.12],
        });
        index += 1;
      }
      shapes.set(handle, { glyphs, advance: glyphs.length * fontSize });
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
    shapeFeatureCount: () => 0,
    shapeFeature: () => "",
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
}

function encodedTextSpan(span) {
  return [
    span.start,
    span.end,
    span.families.join(FAMILY_SEPARATOR),
    span.fontSizePx,
    span.fontWeight,
    span.italic,
    span.baselineShiftPx,
  ].join(FIELD_SEPARATOR);
}

function encodedInlineBox(box) {
  return [box.start, box.end, box.inlineStartPx, box.inlineEndPx, box.outerSpacing]
    .join(FIELD_SEPARATOR);
}

function encodedLineBreakSpan(span) {
  return [span.start, span.end, span.policy].join(FIELD_SEPARATOR);
}

// Same base values and same case list as the Rust corpus; the byte comparison
// catches drift in either direction.
function corpus() {
  const base = () => ({
    fontSessionId: "fixture-session",
    text: "",
    maxWidthPx: 36,
    fontFamilies: ["Fixture CJK"],
    fontSizePx: 18,
    lineHeightPx: 27,
    locale: "zh-Hans",
    fontWeight: 400,
    italic: false,
    firstLineIndentIc: 0,
    lineLengthGridEnabled: true,
    sourceBoundaries: [],
    textSpans: [],
    inlineBoxes: [],
    lineBreakSpans: [],
  });

  const plain = { ...base(), text: "中文中文中文中文" };

  const punctuation = { ...base(), text: "中文，中文；中文。", maxWidthPx: 72 };

  const mixed = {
    ...base(),
    text: "Hello 中文 world 字",
    maxWidthPx: 90,
    lineLengthGridEnabled: false,
  };

  const indent = { ...base(), text: "中文中文中文", firstLineIndentIc: 2 };

  const span = {
    ...base(),
    text: "中文中文",
    textSpans: [{
      start: 0,
      end: 2,
      families: ["Fixture CJK"],
      fontSizePx: 20,
      fontWeight: 700,
      italic: false,
      baselineShiftPx: 0,
    }],
  };

  const boundaries = { ...base(), text: "中文中文中文", sourceBoundaries: [2, 4] };

  const policy = {
    ...base(),
    text: "URLhttps://example.com/中文",
    maxWidthPx: 90,
    lineLengthGridEnabled: false,
    lineBreakSpans: [{ start: 0, end: 25, policy: "ProgressiveTechnical" }],
  };

  const inlineBox = {
    ...base(),
    text: "中文字中文",
    inlineBoxes: [{ start: 2, end: 3, inlineStartPx: 6, inlineEndPx: 12, outerSpacing: "Narrow" }],
  };

  const ellipsis = { ...base(), text: "……", maxWidthPx: 72 };

  return [
    ["plainWrap", plain],
    ["punctuation", punctuation],
    ["mixed", mixed],
    ["indent", indent],
    ["span", span],
    ["boundaries", boundaries],
    ["lineBreakPolicy", policy],
    ["inlineBox", inlineBox],
    ["ellipsis", ellipsis],
  ];
}

installFixtureBackend();
const runtime = await import(bundleUrl.href);

const dump = {};
for (const [name, request] of corpus()) {
  dump[name] = runtime.precomputeParagraph(
    request.fontSessionId,
    request.text,
    request.maxWidthPx,
    request.fontFamilies.join(FAMILY_SEPARATOR),
    request.fontSizePx,
    request.lineHeightPx,
    request.locale,
    request.fontWeight,
    request.italic,
    request.firstLineIndentIc,
    request.lineLengthGridEnabled,
    request.sourceBoundaries.join(","),
    request.textSpans.map(encodedTextSpan).join(RECORD_SEPARATOR),
    request.inlineBoxes.map(encodedInlineBox).join(RECORD_SEPARATOR),
    request.lineBreakSpans.map(encodedLineBreakSpan).join(RECORD_SEPARATOR),
  );
}

const outPath = resolve(here, "../build/plan-parity/oracle.json");
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, `${JSON.stringify(dump)}\n`);
process.stdout.write(`oracle dump: ${outPath} (${Object.keys(dump).length} cases)\n`);
