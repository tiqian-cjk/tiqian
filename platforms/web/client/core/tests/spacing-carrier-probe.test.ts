import assert from "node:assert/strict";
import test from "node:test";

import { preparedParagraphWithDiagnostics } from "../src/engine/prepared-paragraph.js";
import { toEngineFontMetrics, toEngineShapingResult } from "../src/engine/host-result.js";
import { prepareParagraphRequestWire } from "../src/engine/wire-construction.js";
import type { ShapingInput } from "@tiqian/engine/org/tiqian/shaping/TextShaper";
import { initializeGlobalServices } from "../src/services/global-services.js";
initializeGlobalServices();

const request = prepareParagraphRequestWire({
  text: "汉字排版测试",
  maxWidthPx: 200,
  fontFamilies: ["Test"],
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
});

function shapeCell(input: ShapingInput) {
  const start = input.range.start;
  const end = input.range.end;
  const advance = 10 * (end - start);
  return toEngineShapingResult({
    clusters: [{ range: { start, end }, text: "字", displayText: "字", fontKey: "font", advance, baselineShift: 0 }],
    glyphRuns: [{ range: { start, end }, fontKey: "font", glyphs: [{ id: 65, clusterRange: { start, end }, advance, x: 0, y: 0 }], advance, openTypeFeatures: [] }],
    decisions: [],
  });
}

const resolve = () => toEngineFontMetrics({ ascent: 0.8, descent: -0.2, leading: 0, source: "RawTables" });

test("a host shaper that cannot shape the U+00A0 carrier probe still lays out", () => {
  let probeCalls = 0;
  const { plan } = preparedParagraphWithDiagnostics(request, 0.05, {
    shape: (input: ShapingInput) => {
      if (input.text === " ") {
        probeCalls += 1;
        throw new Error("MissingServerShapingReplay:shape:probe");
      }
      return shapeCell(input);
    },
    resolve,
  });
  assert.ok(probeCalls > 0, "the engine probed U+00A0 through the host shaper");
  assert.ok(plan.lines.length > 0, "the paragraph still lays out");
  assert.equal(plan.spacingCarrierAdvances.length, 0, "a failed probe leaves no carrier advance");
});

test("a host shaper failure on body text surfaces the host error unchanged", () => {
  const hostError = new Error("MissingServerShapingReplay:shape:body");
  assert.throws(
    () => preparedParagraphWithDiagnostics(request, 0.05, {
      shape: () => {
        throw hostError;
      },
      resolve,
    }),
    (error: unknown) => error === hostError,
  );
});

test("a host shaper that shapes U+00A0 records the carrier advance", () => {
  const { plan } = preparedParagraphWithDiagnostics(request, 0.05, { shape: shapeCell, resolve });
  assert.ok(plan.spacingCarrierAdvances.length > 0, "the plan carries the carrier advance table");
  assert.equal(plan.spacingCarrierAdvances[0]!.advance, 10);
});
