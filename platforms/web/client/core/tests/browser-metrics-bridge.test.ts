import assert from "node:assert/strict";
import test from "node:test";

import { preparedParagraphWithDiagnostics } from "../src/engine/engine-access/prepared-paragraph.js";
import type { PrepareParagraphRequest } from "../src/engine/engine-access/wire-types.js";
import { toEngineFontMetrics, toEngineShapingResult } from "../src/engine/engine-access/host-result.js";
import type { ShapingInput } from "@tiqian/engine/org/tiqian/shaping/TextShaper";
import type { FontMetricsRequest } from "@tiqian/engine/org/tiqian/font/FontMetrics";

import { createFontFamilies } from "../src/engine/canvas-fonts.js";
import { clearMeasurementCache } from "../src/engine/canvas-shaping.js";
import { createBrowserMetricsBridge } from "../src/engine/browser-metrics-bridge.js";
import type { CanvasContextLike, CanvasTextMetricsLike } from "../src/engine/canvas-metrics.js";
import type { CanvasShapingEnv, ProbeElementLike } from "../src/engine/canvas-shaping.js";
import { prepareParagraphRequestWire } from "../src/engine/wire-construction.js";
import { initializeGlobalServices } from "../src/services/global-services.js";
initializeGlobalServices();


const EXPECTED_FIRST_SHAPING_REQUEST: string =
  '{"text":"中文中文","range":{"start":0,"end":1},"style":{"fontFamilies":["Fixture CJK"],"fontSize":18,"fontWeight":400,"italic":false,"locale":"zh-Hans"},"fontDecision":{"role":"CjkText","candidateKey":"cjk-primary"},"displayText":"中","openTypeFeatures":[]}';

const EXPECTED_FIRST_METRICS_REQUEST: string =
  '{"fontKey":"cjk-primary","fontSize":18,"role":"CjkText","locale":"zh-Hans","fontFamilies":["Fixture CJK"],"fontWeight":400,"italic":false,"faceSelectionText":"中"}';

// The typed callback inputs projected onto the field shape the retired wire
// carried. These projections let the byte-lock tests keep their contract:
// the same fields with the same values reach the host callbacks.
function projectShapingInput(input: ShapingInput): unknown {
  return {
    text: input.text,
    range: { start: input.range.start, end: input.range.end },
    style: {
      fontFamilies: [...input.style.fontFamilies],
      fontSize: input.style.fontSize,
      fontWeight: input.style.fontWeight,
      italic: input.style.italic,
      locale: input.style.locale,
    },
    fontDecision: { role: input.fontDecision.role.kind, candidateKey: input.fontDecision.candidate.key },
    displayText: input.displayText,
    openTypeFeatures: [...input.openTypeFeatures],
  };
}

function projectMetricsRequest(request: FontMetricsRequest): unknown {
  return {
    fontKey: request.fontKey,
    fontSize: request.fontSize,
    role: request.role.kind,
    locale: request.locale,
    fontFamilies: [...request.fontFamilies],
    fontWeight: request.fontWeight,
    italic: request.italic,
    faceSelectionText: request.faceSelectionText,
  };
}

type FakeMeasureFn = (text: string, font: string) => CanvasTextMetricsLike;

interface FakeImageDataLike {
  data: Uint8ClampedArray;
}

interface FakeProbeRectWidth {
  width: number;
}

interface ScriptedCanvasModelCallbacks {
  shape: (input: ShapingInput) => ReturnType<typeof toEngineShapingResult>;
  resolve: (request: FontMetricsRequest) => ReturnType<typeof toEngineFontMetrics>;
}

interface ScriptedGlyphRecord {
  id: number;
  advance: number;
  x: number;
  y: number;
  bounds: number;
}

interface ScriptedShapeRecord {
  faceId: string;
  fontInstanceId: string;
  script: string;
  features: string[];
  unsafeBreakCount: number;
  advance: number;
  glyphs: ScriptedGlyphRecord[];
}

type ScriptedMetricsBox = number[];

interface PlanLineLike {
  rangeStart: number;
  rangeEnd: number;
}

interface CapabilityIssueLike {
  name: string;
  reason: string;
}

function fakeCanvasMeasurement(text: string): CanvasTextMetricsLike {
  if (text === "Hg") {
    return {
      width: 18,
      fontBoundingBoxAscent: 22,
      fontBoundingBoxDescent: 6,
      actualBoundingBoxLeft: 0,
      actualBoundingBoxAscent: 22,
      actualBoundingBoxRight: 18,
      actualBoundingBoxDescent: 6,
    };
  }
  return {
    width: 18,
    fontBoundingBoxAscent: 30,
    fontBoundingBoxDescent: 10,
    ideographicBaseline: -12,
    actualBoundingBoxLeft: -0.1,
    actualBoundingBoxAscent: 18,
    actualBoundingBoxRight: 18.1,
    actualBoundingBoxDescent: 4,
  };
}

function makeFakeEnv(customMeasure?: FakeMeasureFn): CanvasShapingEnv {
  const measureFn: FakeMeasureFn = customMeasure || fakeCanvasMeasurement;
  function createCanvasContext(): CanvasContextLike {
    return {
      canvas: { width: 0, height: 0 },
      font: "",
      measureText(text: string): CanvasTextMetricsLike {
        return measureFn(text, this.font);
      },
      setTransform(): void {},
      clearRect(x: number, y: number, w: number, h: number): void {},
      fillText(text: string, x: number, y: number): void {},
      getImageData(x: number, y: number, w: number, h: number): FakeImageDataLike {
        return { data: new Uint8ClampedArray(w * h * 4) };
      },
    };
  }
  function createProbeElement(): ProbeElementLike {
    return {
      parentNode: null,
      textContent: "",
      setAttribute(name: string, value: string): void {},
      style: {
        setProperty(name: string, value: string, priority?: string): void {},
      },
      getBoundingClientRect(): FakeProbeRectWidth {
        return { width: 0 };
      },
    };
  }
  function attachProbe(element: ProbeElementLike): void {
    if (element.parentNode == null) element.parentNode = {};
  }
  return { createCanvasContext, createProbeElement, attachProbe };
}

function makeScriptedCanvasModelCallbacks(): ScriptedCanvasModelCallbacks {
  let nextHandle: number = 1;
  const shapes = new Map<number, ScriptedShapeRecord>();
  const metrics = new Map<number, ScriptedMetricsBox>();
  return {
    shape: (input: ShapingInput) => {
      const range = { start: input.range.start, end: input.range.end };
      const fontKey: string = input.fontDecision.candidate.key;
      const displayText: string = input.displayText;
      const sourceText: string = input.text.substring(input.range.start, input.range.end);
      const handle = nextHandle++;
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
          language: input.style.locale,
          featureEvidence: null,
        }],
      });
    },
    resolve: (request: FontMetricsRequest) => {
      const cjkBox: boolean = request.role.kind === "CjkText" || request.role.kind === "CjkPunctuation";
      const ideographicDescent: number = 12;
      const handle = nextHandle++;
      const m: ScriptedMetricsBox = cjkBox
        ? [30, 10, 0, Math.max(request.fontSize - ideographicDescent, 0), Math.max(ideographicDescent, 0)]
        : [22, 6, 0, Number.NaN, Number.NaN];
      metrics.set(handle, m);
      return toEngineFontMetrics({
        ascent: m[0],
        descent: m[1],
        leading: m[2],
        source: "RawTables",
        typoAscent: Number.isNaN(m[3]) ? null : m[3],
        typoDescent: Number.isNaN(m[4]) ? null : m[4],
      });
    },
  };
}

const PLAN_NUMBER_TOLERANCE: number = 1e-9;
const toleranceHits: string[] = [];

type PlanJson = string | number | boolean | null | PlanJson[] | { [key: string]: PlanJson };

interface PlanJsonObject {
  [key: string]: PlanJson;
}

function isPlanJsonObject(value: PlanJson): value is PlanJsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function comparePlans(left: PlanJson, right: PlanJson, path: string): void {
  if (typeof left === "number" && typeof right === "number") {
    if (Object.is(left, right)) return;
    const delta = Math.abs(left - right);
    if (delta <= PLAN_NUMBER_TOLERANCE * Math.max(1, Math.abs(right))) {
      toleranceHits.push(path);
      return;
    }
    throw new Error(`plan number mismatch at ${path}: ${left} != ${right}`);
  }
  if (Array.isArray(left) && Array.isArray(right)) {
    assert.equal(left.length, right.length, `${path}.length`);
    left.forEach((value: PlanJson, index: number): void => comparePlans(value, right[index]!, `${path}[${index}]`));
    return;
  }
  if (isPlanJsonObject(left) && isPlanJsonObject(right)) {
    const leftKeys = Object.keys(left).sort();
    const rightKeys = Object.keys(right).sort();
    assert.deepEqual(leftKeys, rightKeys, `${path} keys`);
    for (const key of leftKeys) comparePlans(left[key]!, right[key]!, `${path}.${key}`);
    return;
  }
  assert.strictEqual(left, right, path);
}

// Helper to build a PrepareParagraphRequest DTO for the test paragraph
function buildTestRequest(overrides: Partial<PrepareParagraphRequest> = {}): PrepareParagraphRequest {
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
    ...overrides,
  });
}

function buildDashRequest(overrides: Partial<PrepareParagraphRequest> = {}): PrepareParagraphRequest {
  return prepareParagraphRequestWire({
    text: "——",
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
    ...overrides,
  });
}

test("API surface exposes createBrowserMetricsBridge", () => {
  assert.strictEqual(typeof createBrowserMetricsBridge, "function");
});

test("Shaping request field lock", () => {
  clearMeasurementCache();
  const fonts = createFontFamilies({
    cjk: '"Fixture CJK", sans-serif',
    latin: '"Fixture Latin", sans-serif',
  });
  const env = makeFakeEnv();
  const bridge = createBrowserMetricsBridge({
    fonts,
    cjkDashCapability: null,
    env,
  });

  const capturedShapeInputs: ShapingInput[] = [];

  const request = buildTestRequest();
  preparedParagraphWithDiagnostics(request, 0.01, {
    shape: (input: ShapingInput) => {
      capturedShapeInputs.push(input);
      return bridge.shape(input);
    },
    resolve: (req: FontMetricsRequest) => bridge.resolve(req),
  });

  assert.ok(capturedShapeInputs.length > 0);
  assert.deepEqual(projectShapingInput(capturedShapeInputs[0]!), JSON.parse(EXPECTED_FIRST_SHAPING_REQUEST));
});

test("Metrics request field lock", () => {
  clearMeasurementCache();
  const fonts = createFontFamilies({
    cjk: '"Fixture CJK", sans-serif',
    latin: '"Fixture Latin", sans-serif',
  });
  const env = makeFakeEnv();
  const bridge = createBrowserMetricsBridge({
    fonts,
    cjkDashCapability: null,
    env,
  });

  const capturedMetricsRequests: FontMetricsRequest[] = [];

  const request = buildTestRequest();
  preparedParagraphWithDiagnostics(request, 0.01, {
    shape: (input: ShapingInput) => bridge.shape(input),
    resolve: (req: FontMetricsRequest) => {
      capturedMetricsRequests.push(req);
      return bridge.resolve(req);
    },
  });

  assert.ok(capturedMetricsRequests.length > 0);
  assert.deepEqual(projectMetricsRequest(capturedMetricsRequests[0]!), JSON.parse(EXPECTED_FIRST_METRICS_REQUEST));
});

test("End-to-end plan", () => {
  clearMeasurementCache();
  const fonts = createFontFamilies({
    cjk: '"Fixture CJK", sans-serif',
    latin: '"Fixture Latin", sans-serif',
  });
  const env = makeFakeEnv();
  const bridge = createBrowserMetricsBridge({
    fonts,
    cjkDashCapability: null,
    env,
  });

  const request = buildTestRequest();
  const envelope = preparedParagraphWithDiagnostics(request, 0.01, bridge);
  const plan = envelope.plan as unknown as { lines: PlanLineLike[] };

  assert.ok(plan.lines.length > 0);
  assert.strictEqual(plan.lines[0]!.rangeStart, 0);
  assert.strictEqual(plan.lines[plan.lines.length - 1]!.rangeEnd, 4);
  assert.deepEqual(envelope.diagnostics.capabilityIssues, []);
  assert.deepEqual(envelope.diagnostics.advanceSuspects, []);
});

test("Parity against the scripted canvas-model backend", () => {
  clearMeasurementCache();
  const fonts = createFontFamilies({
    cjk: '"Fixture CJK", sans-serif',
    latin: '"Fixture Latin", sans-serif',
  });
  const env = makeFakeEnv();
  const bridge = createBrowserMetricsBridge({
    fonts,
    cjkDashCapability: null,
    env,
  });

  const request = buildTestRequest();
  const envelope = preparedParagraphWithDiagnostics(request, 0.01, bridge);
  const planA = envelope.plan as unknown as PlanJson;

  const scriptedCallbacks = makeScriptedCanvasModelCallbacks();

  let planB: PlanJson;
  try {
    const requestDiag = buildTestRequest();
    planB = preparedParagraphWithDiagnostics(requestDiag, 0.0, scriptedCallbacks).plan as unknown as PlanJson;
  } finally {
    // no globals to restore
  }

  const linesOf = (value: PlanJson): number[][] => {
    const lines = (value as unknown as { lines: PlanLineLike[] }).lines;
    return lines.map((line: PlanLineLike): number[] => [line.rangeStart, line.rangeEnd]);
  };
  assert.deepEqual(linesOf(planA), linesOf(planB));
  comparePlans(planA, planB, "$");
});

test("Dash capability passthrough", () => {
  clearMeasurementCache();
  const fonts = createFontFamilies({
    cjk: '"Fixture CJK", sans-serif',
    latin: '"Fixture Latin", sans-serif',
  });
  const env = makeFakeEnv();
  const bridge = createBrowserMetricsBridge({
    fonts,
    cjkDashCapability: { status: "partial", detail: "probe-detail" },
    env,
  });

  const request = buildDashRequest();
  const envelope = preparedParagraphWithDiagnostics(request, 0.01, bridge);

  const issue = envelope.diagnostics.capabilityIssues.find(
    (item: CapabilityIssueLike): boolean => item.name === "NoConformingCjkDashGlyph",
  );
  assert.ok(issue, "Expected NoConformingCjkDashGlyph capability issue");
  assert.ok(
    issue.reason.includes("; status=partial; probe-detail"),
    `Expected reason to contain '; status=partial; probe-detail', got: ${issue.reason}`,
  );
});
