// Precompute cutover parity dumper. Imports one implementation of the two
// precompute exports (old: ./runtime/Tiqian-tiqian-ffi-js.mjs Kotlin runtime;
// new: ./runtime/facade.mjs aggregate facade), applies a fixed fixture list
// with deterministic shaping/metrics callbacks, and writes the answers as
// JSON so two runs can be diffed.
//
//   node ./scripts/precompute-dump.mjs <module-url> <out-json>
//
// Recorded per entry: the returned plan JSON string, or the thrown error
// name and message (the old Kotlin runtime surfaced a domain validation
// issue as an IllegalArgumentException whose message is the issue name).
// The shaping and metrics callbacks record their request JSONs so the dump
// also pins the callback-reversal traffic (ADR 0053).

import { writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const moduleUrl = process.argv[2];
const outPath = process.argv[3];
if (moduleUrl === undefined || outPath === undefined) {
  console.error("usage: node ./scripts/precompute-dump.mjs <module-url> <out-json>");
  process.exit(2);
}
const ffi = await import(pathToFileURL(moduleUrl).href);
const {
  precomputeParagraphWithDiagnostics,
  precomputeParagraphWithBrowserMetrics,
} = ffi;

// Deterministic host callbacks: one cluster per UTF-16 unit is not shape
// realism, but it is stable and exercises the full request/response JSON
// traffic of both callbacks.
function makeCallbacks() {
  const calls = [];
  const shapeJson = (requestJson) => {
    calls.push({ cb: "shapeJson", request: JSON.parse(requestJson) });
    const raw = JSON.parse(requestJson);
    const s = raw.range?.start ?? 0;
    const e = raw.range?.end ?? s + Array.from(raw.text ?? "").length;
    const cluster = {
      range: { start: s, end: e },
      text: raw.text ?? "",
      displayText: raw.displayText ?? raw.text ?? "",
      fontKey: raw.fontDecision?.candidateKey ?? raw.style?.fontFamilies?.[0] ?? "font",
      advance: 10 * (e - s),
      baselineShift: 0,
    };
    return JSON.stringify({
      clusters: [cluster],
      glyphRuns: [{
        range: { start: s, end: e },
        fontKey: cluster.fontKey,
        glyphs: [{
          id: 65,
          clusterRange: { start: s, end: e },
          advance: 10 * (e - s),
          x: 0,
          y: 0,
        }],
        advance: 10 * (e - s),
        openTypeFeatures: [],
      }],
      decisions: [{
        range: { start: s, end: e },
        sourceText: raw.text ?? "",
        displayText: raw.displayText ?? "",
        fontKey: cluster.fontKey,
        glyphCount: 1,
        advance: 10 * (e - s),
        source: "Fallback",
        reason: "dump",
        glyphsWithoutInkBounds: 0,
        missingGlyphs: 0,
      }],
    });
  };
  const metricsJson = (requestJson) => {
    calls.push({ cb: "metricsJson", request: JSON.parse(requestJson) });
    return JSON.stringify({
      ascent: 0.8,
      descent: -0.2,
      leading: 0,
      source: "RawTables",
    });
  };
  return { shapeJson, metricsJson, calls };
}

function baseRequest(overrides = {}) {
  return {
    text: "汉字，",
    maxWidthPx: 200,
    fontFamilies: ["Test", "Fallback"],
    fontSizePx: 16,
    lineHeightPx: 24,
    locale: "zh-Hans",
    fontWeight: 400,
    italic: false,
    firstLineIndentIc: 0,
    lineLengthGridEnabled: false,
    sourceBoundaries: [],
    textSpans: [],
    inlineBoxes: [],
    lineBreakSpans: [],
    inlineObjects: [],
    decorations: [],
    emphasisDotGapEm: null,
    renderEvidenceOverride: null,
    ...overrides,
  };
}

const entries = [];
function record(fn, label, request, run) {
  const callbacks = makeCallbacks();
  const entry = { fn, label };
  try {
    entry.result = { kind: "value", value: run(request, callbacks) };
  } catch (err) {
    entry.result = {
      kind: "throw",
      name: err instanceof Error && typeof err.name === "string" && err.name !== "" ? err.name : String(err),
      message: err instanceof Error ? err.message : String(err),
    };
  }
  entry.callbackCalls = callbacks.calls;
  entries.push(entry);
}

const withSpans = baseRequest({
  textSpans: [{ start: 0, end: 1, fontFamilies: ["Span"], fontSize: 18, fontWeight: 700, italic: true, baselineShift: 2 }],
  lineBreakSpans: [{ start: 0, end: 1, policy: "ProgressiveTechnical" }],
  emphasisDotGapEm: 0.2,
});
const withBoxes = baseRequest({
  inlineBoxes: [{ start: 0, end: 1, inlineStart: 1, inlineEnd: 9, outerSpacing: "Narrow" }],
  decorations: [{ start: 0, end: 1, kind: "Emphasis" }],
  inlineObjects: [{ start: 0, end: 1, advance: 12, ascent: 8, descent: 4 }],
  sourceBoundaries: [1, 2],
});

// WithDiagnostics: happy paths and the evidence override.
record("precomputeParagraphWithDiagnostics", "plain", baseRequest(),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "spans-grid-gap", withSpans,
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "boxes-objects-decorations", withBoxes,
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "evidence-override", baseRequest({ renderEvidenceOverride: true }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "epsilon-zero", baseRequest(),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0, c.shapeJson, c.metricsJson));

// WithDiagnostics: domain validation names, in check order.
record("precomputeParagraphWithDiagnostics", "empty-text", baseRequest({ text: "" }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "blank-text", baseRequest({ text: " 　" }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "zero-width", baseRequest({ maxWidthPx: 0 }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "nan-width", baseRequest({ maxWidthPx: Number.NaN }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "zero-font-size", baseRequest({ fontSizePx: 0 }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "zero-line-height", baseRequest({ lineHeightPx: 0 }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "nan-indent", baseRequest({ firstLineIndentIc: Number.NaN }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "weight-0", baseRequest({ fontWeight: 0 }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "negative-gap", baseRequest({ emphasisDotGapEm: -0.1 }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "blank-families", baseRequest({ fontFamilies: [" "] }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "span-range-beyond", baseRequest({ textSpans: [{ start: 0, end: 9, fontFamilies: ["S"], fontSize: 16, fontWeight: 400, italic: false, baselineShift: 0 }] }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "span-blank-family", baseRequest({ textSpans: [{ start: 0, end: 1, fontFamilies: [""], fontSize: 16, fontWeight: 400, italic: false, baselineShift: 0 }] }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "span-zero-size", baseRequest({ textSpans: [{ start: 0, end: 1, fontFamilies: ["S"], fontSize: 0, fontWeight: 400, italic: false, baselineShift: 0 }] }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "boundary-beyond", baseRequest({ sourceBoundaries: [99] }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "break-span-range", baseRequest({ lineBreakSpans: [{ start: 2, end: 1, policy: "Strict" }] }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "box-range", baseRequest({ inlineBoxes: [{ start: 0, end: 9, inlineStart: 0, inlineEnd: 1, outerSpacing: "Narrow" }] }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "object-negative-advance", baseRequest({ inlineObjects: [{ start: 0, end: 1, advance: -1, ascent: 8, descent: 4 }] }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));
record("precomputeParagraphWithDiagnostics", "decoration-range", baseRequest({ decorations: [{ start: 0, end: 9, kind: "Emphasis" }] }),
  (r, c) => precomputeParagraphWithDiagnostics(r, 0.05, c.shapeJson, c.metricsJson));

// WithBrowserMetrics: the callbacks-object form of the same entries.
record("precomputeParagraphWithBrowserMetrics", "plain", baseRequest(),
  (r, c) => precomputeParagraphWithBrowserMetrics(r, 0.05, { shapeJson: c.shapeJson, metricsJson: c.metricsJson }));
record("precomputeParagraphWithBrowserMetrics", "spans-grid-gap", withSpans,
  (r, c) => precomputeParagraphWithBrowserMetrics(r, 0.05, { shapeJson: c.shapeJson, metricsJson: c.metricsJson }));
record("precomputeParagraphWithBrowserMetrics", "boxes-objects-decorations", withBoxes,
  (r, c) => precomputeParagraphWithBrowserMetrics(r, 0.05, { shapeJson: c.shapeJson, metricsJson: c.metricsJson }));
record("precomputeParagraphWithBrowserMetrics", "empty-text", baseRequest({ text: "" }),
  (r, c) => precomputeParagraphWithBrowserMetrics(r, 0.05, { shapeJson: c.shapeJson, metricsJson: c.metricsJson }));

await writeFile(outPath, JSON.stringify(entries, null, 2) + "\n", "utf8");
console.log("dumped " + entries.length + " entries -> " + outPath);
