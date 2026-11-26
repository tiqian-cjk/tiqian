import assert from "node:assert/strict";
import test from "node:test";

import {
  preparedParagraphPlan,
  preparedParagraphWithDiagnostics,
} from "../src/engine/prepared-paragraph.js";
import type { PrepareParagraphRequest } from "../src/engine/wire-types.js";
import { toEngineFontMetrics, toEngineShapingResult } from "../src/engine/host-result.js";
import type { ShapingInput, ShapingResult } from "@tiqian/engine/org/tiqian/shaping/TextShaper";
import type { FontMetricsRequest } from "@tiqian/engine/org/tiqian/font/FontMetrics";
import type { RawFontMetrics } from "@tiqian/engine/org/tiqian/font/RawFontMetrics";
import { createProbeBootstrapFontSession } from "../src/engine/web-worker/session-bootstrap.js";
import { prepareParagraphRequestWire } from "../src/engine/wire-construction.js";
import { initializeGlobalServices } from "../src/services/global-services.js";
initializeGlobalServices();


interface CanvasMeasurementResult {
  width: number;
  fontBoundingBoxAscent: number;
  fontBoundingBoxDescent: number;
  ideographicBaseline?: number;
}

interface GlyphRun {
  id: number;
  clusterRange: Range;
  advance: number;
  x: number;
  y: number;
  bounds: null;
}

interface Range {
  start: number;
  end: number;
}

interface Cluster {
  range: Range;
  text: string;
  displayText: string;
  fontKey: string;
  advance: number;
}

interface GlyphRunWithCluster {
  range: Range;
  fontKey: string;
  glyphs: GlyphRun[];
  advance: number;
  openTypeFeatures: never[];
}

interface DecisionRecord {
  range: Range;
  sourceText: string;
  displayText: string;
  fontKey: string;
  glyphCount: number;
  advance: number;
  source: string;
  reason: string;
  glyphsWithoutInkBounds: number;
  missingGlyphs: number;
  resolvedFace: string;
  script: string;
  language: string;
  featureEvidence: null;
}

interface ShapeResponse {
  clusters: Cluster[];
  glyphRuns: GlyphRunWithCluster[];
  decisions: DecisionRecord[];
}

interface MetricsResponse {
  ascent: number;
  descent: number;
  leading: number;
  source: string;
  typoAscent: number | null;
  typoDescent: number | null;
}

type ShapeFn = (input: ShapingInput) => ShapingResult;
type MetricsFn = (request: FontMetricsRequest) => RawFontMetrics;

interface ScriptedCanvasModelCallbacks {
  shape: ShapeFn;
  resolve: MetricsFn;
}

interface ShapeRequest {
  range: Range;
  text: string;
  displayText: string;
  fontDecision: FontDecision;
}

interface FontDecision {
  candidateKey: string;
}

interface StyleContext {
  locale: string;
}

interface MetricsRequest {
  role: string;
  fontSize: number;
}

interface TestRequest {
  text: string;
  maxWidthPx: number;
  fontFamilies: string[];
  fontSizePx: number;
  lineHeightPx: number;
  locale: string;
  fontWeight: number;
  italic: boolean;
  firstLineIndentIc: number;
  lineLengthGridEnabled: boolean;
  sourceBoundaries: never[];
  textSpans: never[];
  inlineBoxes: never[];
  lineBreakSpans: never[];
  inlineObjects: never[];
  decorations: never[];
  emphasisDotGapEm: null;
  renderEvidenceOverride: null;
}

interface LayoutLine {
  rangeStart: number;
  rangeEnd: number;
}

interface PlanEnvelope {
  plan: string;
}

function fakeCanvasMeasurement(text: string): CanvasMeasurementResult {
  if (text === "Hg") {
    return { width: 18, fontBoundingBoxAscent: 22, fontBoundingBoxDescent: 6 };
  }
  return {
    width: 18,
    fontBoundingBoxAscent: 30,
    fontBoundingBoxDescent: 10,
    ideographicBaseline: -12,
  };
}

function makeScriptedCanvasModelCallbacks(): ScriptedCanvasModelCallbacks {
  let nextHandle: number = 1;
  const shapes: Map<number, unknown> = new Map();
  const metrics: Map<number, [number, number, number, number, number]> = new Map();
  return {
    shape: (input: ShapingInput): ShapingResult => {
      const range = { start: input.range.start, end: input.range.end };
      const fontKey: string = input.fontDecision.candidate.key;
      const displayText: string = input.displayText;
      const sourceText: string = input.text.substring(input.range.start, input.range.end);
      // Canvas-model shape: one glyph per cluster, id 0, x 0, no ink bounds.
      const handle: number = nextHandle++;
      shapes.set(handle, {
        faceId: "",
        fontInstanceId: "",
        script: "",
        features: [],
        unsafeBreakCount: 0,
        advance: 18,
        glyphs: [{ id: 0, advance: 18, x: 0, y: 0, bounds: Number.NaN }],
      });
      return toEngineShapingResult({
        clusters: [{
          range,
          text: sourceText,
          displayText,
          fontKey,
          advance: 18,
        }],
        glyphRuns: [{
          range,
          fontKey,
          glyphs: [{ id: 0, clusterRange: range, advance: 18, x: 0, y: 0, bounds: null }],
          advance: 18,
          openTypeFeatures: [],
        }],
        decisions: [{
          range,
          sourceText,
          displayText,
          fontKey,
          glyphCount: 1,
          advance: 18,
          source: "HarfBuzz",
          reason: "test",
          glyphsWithoutInkBounds: 1,
          missingGlyphs: 1,
          resolvedFace: "",
          script: "",
          language: fontKey,
          featureEvidence: null,
        }],
      });
    },
    resolve: (request: FontMetricsRequest): RawFontMetrics => {
      // WebCanvasFontMetricsResolver in px: CJK boxes derive the 字身框 from
      // ideographicBaseline (-12), Latin roles leave typo values unset.
      const cjkBox: boolean = request.role.kind === "CjkText" || request.role.kind === "CjkPunctuation";
      const ideographicDescent: number = 12;
      const handle: number = nextHandle++;
      const metricTuple: [number, number, number, number, number] = cjkBox
        ? [30, 10, 0, Math.max(request.fontSize - ideographicDescent, 0), Math.max(ideographicDescent, 0)]
        : [22, 6, 0, Number.NaN, Number.NaN];
      metrics.set(handle, metricTuple);
      return toEngineFontMetrics({
        ascent: metricTuple[0],
        descent: metricTuple[1],
        leading: metricTuple[2],
        source: "RawTables",
        typoAscent: Number.isNaN(metricTuple[3]) ? null : metricTuple[3],
        typoDescent: Number.isNaN(metricTuple[4]) ? null : metricTuple[4],
      });
    },
  };
}

function buildTestRequest(): PrepareParagraphRequest {
  return prepareParagraphRequestWire({
    text: "中文中文",
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
    inlineObjects: [],
    decorations: [],
    emphasisDotGapEm: null,
    renderEvidenceOverride: null,
  });
}

const toleranceHits: string[] = [];

function comparePlans(left: unknown, right: unknown, path: string): void {
  if (typeof left === "number" && typeof right === "number") {
    if (Object.is(left, right)) return;
    const delta: number = Math.abs(left - right);
    const PLAN_NUMBER_TOLERANCE: number = 1e-9;
    if (delta <= PLAN_NUMBER_TOLERANCE * Math.max(1, Math.abs(right))) {
      toleranceHits.push(path);
      return;
    }
    throw new Error(`plan number mismatch at ${path}: ${left} != ${right}`);
  }
  if (Array.isArray(left) && Array.isArray(right)) {
    assert.equal(left.length, right.length, `${path}.length`);
    left.forEach((value: unknown, index: number) => comparePlans(value, right[index], `${path}[${index}]`));
    return;
  }
  if (left !== null && right !== null && typeof left === "object" && typeof right === "object") {
    const leftKeys: string[] = Object.keys(left).sort();
    const rightKeys: string[] = Object.keys(right).sort();
    assert.deepEqual(leftKeys, rightKeys, `${path} keys`);
    for (const key of leftKeys) comparePlans((left as Record<string, unknown>)[key], (right as Record<string, unknown>)[key], `${path}.${key}`);
    return;
  }
  assert.strictEqual(left, right, path);
}

test("probe bootstrap plan matches the canvas model plan end to end", async () => {
  const measureCalls: string[] = [];
  const probeSession = await createProbeBootstrapFontSession("parity-a", {
    measureAdapter: (cssFont: string, text: string): CanvasMeasurementResult => {
      measureCalls.push(`${cssFont} :: ${text}`);
      return fakeCanvasMeasurement(text);
    },
  });

  let planA: unknown;
  try {
    const request: PrepareParagraphRequest = buildTestRequest();
    const envelope = preparedParagraphWithDiagnostics(request, 0.0, {
      shape: probeSession.shape,
      resolve: probeSession.resolve,
    });
    planA = envelope.plan;
  } finally {
    probeSession.close();
  }

  // Use scripted canvas model callbacks
  const scriptedCallbacks = makeScriptedCanvasModelCallbacks();

  let planB: unknown;
  try {
    const request: PrepareParagraphRequest = buildTestRequest();
    const envelope = preparedParagraphWithDiagnostics(request, 0.0, scriptedCallbacks);
    planB = envelope.plan;
  } finally {
    // no globals to restore
  }

  assert.ok(measureCalls.length > 0);
  assert.deepEqual(
    (planA as { lines: LayoutLine[] }).lines.map((line: LayoutLine) => [line.rangeStart, line.rangeEnd]),
    (planB as { lines: LayoutLine[] }).lines.map((line: LayoutLine) => [line.rangeStart, line.rangeEnd]),
  );
  comparePlans(planA, planB, "$");
  console.log(
    "tolerance-hit field paths:",
    toleranceHits.length === 0 ? "(none)" : JSON.stringify(toleranceHits),
  );
});

test("the plan-only entry matches the diagnostics entry byte for byte", () => {
  const callbacks = makeScriptedCanvasModelCallbacks();
  const request = buildTestRequest();
  const planOnly = preparedParagraphPlan(request, callbacks);
  const structured = preparedParagraphWithDiagnostics(request, 0.0, callbacks);
  assert.equal(
    JSON.stringify(planOnly),
    JSON.stringify(structured.plan),
    "the worker entry and the main-thread entry serialize the same plan",
  );
});
