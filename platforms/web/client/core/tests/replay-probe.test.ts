import assert from "node:assert/strict";
import test from "node:test";

import {
  createServerReplayFontSession,
} from "../src/measurement/browser-font-replay.js";
import type { ServerReplayFontReplay, ServerReplayFontSessionOptions } from "../src/measurement/browser-font-replay.js";
import type { ReplayProbe } from "../src/measurement/browser-font-replay.js";
import type { SnapshotManifestFace } from "../src/sampler/snapshot/snapshot-manifest.js";
import {
  normalizeReplayNumber,
  scaleMetricReplayItem,
  scaleShapeReplayItem,
} from "../src/measurement/replay-entry-codec.js";
import type { ReplayShapeItem, ReplayMetricItem } from "../src/measurement/replay-entry-codec.js";
import {
  CJK_METRIC_PROBE_TEXT,
  LATIN_METRIC_PROBE_TEXT,
  probeMetricReplayValues,
  probeShapeReplayResult,
  replayProbeCssFont,
  REPLAY_PROBE_FACE_PREFIX,
  ZERO_ADVANCE_EPSILON,
} from "../src/measurement/replay-probe.js";
import type { ProbeMeasureResult, ProbeMeasure } from "../src/measurement/replay-probe.js";
import {
  FONT_REPLAY_REVISION,
  metricReplayKey,
  shapeReplayKey,
} from "../src/sampler/snapshot/snapshot-schema.js";
import { initializeGlobalServices } from "../src/services/global-services.js";
import { metricsRequest, shapingInput } from "./engine-input.js";
import type { ShapingInput, ShapingResult } from "@tiqian/engine/org/tiqian/shaping/TextShaper";
import type { FontMetricsRequest } from "@tiqian/engine/org/tiqian/font/FontMetrics";
import type { RawFontMetrics } from "@tiqian/engine/org/tiqian/font/RawFontMetrics";
initializeGlobalServices();


type MeasureFunction = (font: string, text: string) => ProbeMeasureResult | null;

interface TestProbe {
  measure: MeasureFunction;
}

const fixtureReplay: ServerReplayFontReplay = {
  revision: FONT_REPLAY_REVISION,
  shapes: [
    {
      key: shapeReplayKey("init", "InitFamily", 400, false, "zh-Hans", "CjkText", "init"),
      result: {
        faceId: "fixture-face",
        fontInstanceId: "",
        script: "",
        features: [],
        unsafeBreakCount: 0,
        advanceEm: 1,
        glyphs: [{ id: 1, advanceEm: 1, xEm: 0, yEm: 0, boundsEm: null }],
      },
    },
  ],
  metrics: [
    {
      key: metricReplayKey("InitFamily", 400, false, "CjkText", ""),
      valuesEm: [0.8, 0.2, 0, 0.8, 0.2],
    },
  ],
};

interface ShapeResponseGlyph {
  id: number;
  advance: number;
  x: number;
  y: number;
  bounds: number[] | null;
}

interface ShapeResponseGlyphRun {
  glyphs: readonly ShapeResponseGlyph[];
  advance: number;
  openTypeFeatures: readonly string[];
}

interface ShapeResponseDecision {
  resolvedFace?: string;
  glyphsWithoutInkBounds: number;
}

interface ShapeResponse {
  glyphRuns: readonly ShapeResponseGlyphRun[];
  decisions: readonly ShapeResponseDecision[];
}

interface SimpleShapeResponseGlyphRun {
  advance: number;
}

interface SimpleShapeResponse {
  glyphRuns: readonly SimpleShapeResponseGlyphRun[];
}

interface MetricsResponse {
  ascent: number;
  descent: number;
  leading: number;
  typoAscent: number | null;
  typoDescent: number | null;
}

interface CjkMetricsResponse {
  ascent: number;
  descent: number;
  leading: number;
  typoAscent: number;
  typoDescent: number;
}

interface ZeroWidthGlyph {
  advance: number;
}

interface ZeroWidthGlyphRun {
  advance: number;
  glyphs: readonly ZeroWidthGlyph[];
}

interface ZeroWidthShapeResponse {
  glyphRuns: readonly ZeroWidthGlyphRun[];
}

interface SimpleAdvanceGlyphRun {
  advance: number;
}

interface SimpleAdvanceShapeResponse {
  glyphRuns: readonly SimpleAdvanceGlyphRun[];
}

type CloseFn = () => void;

interface TestSession {
  shape: (input: ShapingInput) => ShapingResult;
  resolve: (request: FontMetricsRequest) => RawFontMetrics;
  close: CloseFn;
}

async function createTestSession(probe: TestProbe | null = null): Promise<TestSession> {
  const faceMetadata: SnapshotManifestFace[] = [{
    family: "Noto Sans SC",
    style: "normal",
    weight: [400, 400],
    unicodeRange: "",
    publicUrl: "",
    sourceSha256: "",
    sfntSha256: "",
    faceIndex: 0,
    sourceOrder: 0,
    axes: {},
    localNames: [],
  }];
  const options: ServerReplayFontSessionOptions = {
    replay: fixtureReplay,
    faceMetadata,
    probe: probe ?? undefined,
  };
  return createServerReplayFontSession([{}], options);
}

test("shape miss with valid probe measures canvas, backfills session, and returns scaled shape handle", async () => {
  let measureCount: number = 0;
  const session = await createTestSession({
    measure(font: string, text: string): ProbeMeasureResult | null {
      measureCount++;
      assert.equal(font, "normal 400 32px Noto Sans SC, serif");
      assert.equal(text, "测");
      return { width: 16 };
    },
  });
  const shapeRequest = shapingInput({
    text: "测",
    range: { start: 0, end: 1 },
    style: { fontFamilies: ["Noto Sans SC", "serif"], fontSize: 32, fontWeight: 400, italic: false, locale: "zh-Hans" },
    fontDecision: { role: "CjkText", candidateKey: "cjk-primary" },
    displayText: "测",
    openTypeFeatures: [],
  });
  const shapeResponse: unknown = session.shape(shapeRequest);
  const response: ShapeResponse = shapeResponse as ShapeResponse;
  assert.equal(measureCount, 1);
  assert.equal(response.glyphRuns[0].glyphs.length, 1);
  assert.equal(response.glyphRuns[0].glyphs[0].id, 0);
  assert.equal(response.glyphRuns[0].glyphs[0].advance, 16);
  assert.equal(response.glyphRuns[0].glyphs[0].x, 0);
  assert.equal(response.glyphRuns[0].glyphs[0].y, 0);
  // Probe-derived glyphs carry no ink bounds; the wire marks them null.
  assert.equal(response.glyphRuns[0].glyphs[0].bounds, null);
  assert.equal(response.glyphRuns[0].advance, 16);
  assert.ok(response.decisions[0].resolvedFace?.startsWith(REPLAY_PROBE_FACE_PREFIX));
  assert.ok(response.decisions[0].resolvedFace?.includes("Noto Sans SC, serif"));
  assert.equal(response.glyphRuns[0].openTypeFeatures.length, 0);
  assert.equal(response.decisions[0].glyphsWithoutInkBounds, 1);
  session.close();
});

test("subsequent shape requests for probed key hit the session table without calling measure again", async () => {
  let measureCount: number = 0;
  const session = await createTestSession({
    measure(_font: string, _text: string): ProbeMeasureResult | null {
      measureCount++;
      return { width: 16 };
    },
  });
  const families: string = ["Noto Sans SC", "serif"].join("\u001f");
  const shapeRequest = shapingInput({
    text: "复",
    range: { start: 0, end: 1 },
    style: { fontFamilies: ["Noto Sans SC", "serif"], fontSize: 32, fontWeight: 400, italic: false, locale: "zh-Hans" },
    fontDecision: { role: "CjkText", candidateKey: "cjk-primary" },
    displayText: "复",
    openTypeFeatures: [],
  });
  const shapeResponse1: unknown = session.shape(shapeRequest);
  const response1: SimpleShapeResponse = shapeResponse1 as SimpleShapeResponse;
  assert.equal(measureCount, 1);
  const shapeResponse2: unknown = session.shape(shapeRequest);
  const response2: SimpleShapeResponse = shapeResponse2 as SimpleShapeResponse;
  assert.equal(measureCount, 1);
  assert.equal(response1.glyphRuns[0].advance, response2.glyphRuns[0].advance);
  session.close();
});

test("shape miss with probe failure throws MissingServerShapingReplay verbatim", async () => {
  const session = await createTestSession({
    measure(): ProbeMeasureResult | null {
      return null;
    },
  });
  const key: string = shapeReplayKey("缺", "Noto Sans SC", 400, false, "zh-Hans", "CjkText", "缺");
  const shapeRequest = shapingInput({
    text: "缺",
    range: { start: 0, end: 1 },
    style: { fontFamilies: ["Noto Sans SC"], fontSize: 32, fontWeight: 400, italic: false, locale: "zh-Hans" },
    fontDecision: { role: "CjkText", candidateKey: "cjk-primary" },
    displayText: "缺",
    openTypeFeatures: [],
  });
  assert.throws(
    () => session.shape(shapeRequest),
    (err: unknown): boolean => err instanceof Error && err.message === `MissingServerShapingReplay:shape:${key}`,
  );

  const session2 = await createTestSession({
    measure(): ProbeMeasureResult | null {
      return { width: Number.NaN };
    },
  });
  assert.throws(
    () => session2.shape(shapeRequest),
    (err: unknown): boolean => err instanceof Error && err.message === `MissingServerShapingReplay:shape:${key}`,
  );
  session.close();
  session2.close();
});

test("session without probe throws MissingServerShapingReplay on miss", async () => {
  const session = await createTestSession(null);
  const key: string = shapeReplayKey("无", "Noto Sans SC", 400, false, "zh-Hans", "CjkText", "无");
  const shapeRequest = shapingInput({
    text: "无",
    range: { start: 0, end: 1 },
    style: { fontFamilies: ["Noto Sans SC"], fontSize: 32, fontWeight: 400, italic: false, locale: "zh-Hans" },
    fontDecision: { role: "CjkText", candidateKey: "cjk-primary" },
    displayText: "无",
    openTypeFeatures: [],
  });
  assert.throws(
    () => session.shape(shapeRequest),
    (err: unknown): boolean => err instanceof Error && err.message === `MissingServerShapingReplay:shape:${key}`,
  );
  const metricKey: string = metricReplayKey("Noto Sans SC", 400, false, "Unknown", "");
  const metricsInput = metricsRequest({
    fontKey: "cjk-primary",
    fontSize: 32,
    role: "Unknown",
    locale: "zh-Hans",
    fontFamilies: ["Noto Sans SC"],
    fontWeight: 400,
    italic: false,
    faceSelectionText: "",
  });
  assert.throws(
    () => session.resolve(metricsInput),
    (err: unknown): boolean => err instanceof Error && err.message === `MissingServerShapingReplay:metrics:${metricKey}`,
  );
  session.close();
});

test("metric miss with latin role probe populates ascent/descent and keeps typo pair NaN", async () => {
  let probedText: string = "";
  const session = await createTestSession({
    measure(_font: string, text: string): ProbeMeasureResult | null {
      probedText = text;
      return {
        width: 15,
        fontBoundingBoxAscent: 24,
        fontBoundingBoxDescent: 8,
      };
    },
  });
  const metricsInput = metricsRequest({
    fontKey: "cjk-primary",
    fontSize: 16,
    role: "Unknown",
    locale: "zh-Hans",
    fontFamilies: ["Roboto"],
    fontWeight: 400,
    italic: false,
    faceSelectionText: "",
  });
  const metricsResponse: unknown = session.resolve(metricsInput);
  const response: MetricsResponse = metricsResponse as MetricsResponse;
  assert.equal(probedText, LATIN_METRIC_PROBE_TEXT);
  assert.equal(response.ascent, 24);
  assert.equal(response.descent, 8);
  assert.equal(response.leading, 0);
  assert.ok(response.typoAscent === null);
  assert.ok(response.typoDescent === null);
  session.close();
});

test("metric miss with CJK role probe calculates typo metrics from ideographic baseline and normalizes em", async () => {
  let probedText: string = "";
  const session = await createTestSession({
    measure(_font: string, text: string): ProbeMeasureResult | null {
      probedText = text;
      return {
        width: 32,
        actualBoundingBoxAscent: 30,
        actualBoundingBoxDescent: 10,
        ideographicBaseline: -12,
      };
    },
  });
  const metricsInput = metricsRequest({
    fontKey: "cjk-primary",
    fontSize: 32,
    role: "CjkText",
    locale: "zh-Hans",
    fontFamilies: ["Noto Sans SC"],
    fontWeight: 400,
    italic: false,
    faceSelectionText: "",
  });
  const metricsResponse: unknown = session.resolve(metricsInput);
  const response: CjkMetricsResponse = metricsResponse as CjkMetricsResponse;
  assert.equal(probedText, CJK_METRIC_PROBE_TEXT);
  assert.equal(response.ascent, 30);
  assert.equal(response.descent, 10);
  assert.equal(response.leading, 0);
  assert.equal(response.typoAscent, 20);
  assert.equal(response.typoDescent, 12);

  const valuesEm: readonly (number | null)[] | null = probeMetricReplayValues(
    { serializedFamilies: "Noto Sans SC\u001fserif", fontSize: 32, fontWeight: 400, italic: false, role: "CjkText" },
    (): ProbeMeasureResult | null => ({
      width: 32,
      actualBoundingBoxAscent: 30,
      actualBoundingBoxDescent: 10,
      ideographicBaseline: -12,
    }),
  );
  assert.ok(valuesEm != null);
  assert.deepEqual(valuesEm, [
    normalizeReplayNumber(30, 32),
    normalizeReplayNumber(10, 32),
    0,
    normalizeReplayNumber(20, 32),
    normalizeReplayNumber(12, 32),
  ]);
  assert.deepEqual(valuesEm, [0.9375, 0.3125, 0, 0.625, 0.375]);

  session.close();
});

test("metric miss with measure width <= epsilon throws MissingServerShapingReplay", async () => {
  const session = await createTestSession({
    measure(): ProbeMeasureResult | null {
      return {
        width: 0.005,
        fontBoundingBoxAscent: 20,
        fontBoundingBoxDescent: 5,
      };
    },
  });
  const key: string = metricReplayKey("Noto Sans SC", 400, false, "CjkText", "");
  const metricsInput = metricsRequest({
    fontKey: "cjk-primary",
    fontSize: 32,
    role: "CjkText",
    locale: "zh-Hans",
    fontFamilies: ["Noto Sans SC"],
    fontWeight: 400,
    italic: false,
    faceSelectionText: "",
  });
  assert.throws(
    () => session.resolve(metricsInput),
    (err: unknown): boolean => err instanceof Error && err.message === `MissingServerShapingReplay:metrics:${key}`,
  );
  session.close();
});

test("metric miss with missing ascent in measure throws MissingServerShapingReplay", async () => {
  const session = await createTestSession({
    measure(): ProbeMeasureResult | null {
      return {
        width: 10,
        fontBoundingBoxDescent: 5,
      };
    },
  });
  const key: string = metricReplayKey("Noto Sans SC", 400, false, "CjkText", "");
  const metricsInput = metricsRequest({
    fontKey: "cjk-primary",
    fontSize: 32,
    role: "CjkText",
    locale: "zh-Hans",
    fontFamilies: ["Noto Sans SC"],
    fontWeight: 400,
    italic: false,
    faceSelectionText: "",
  });
  assert.throws(
    () => session.resolve(metricsInput),
    (err: unknown): boolean => err instanceof Error && err.message === `MissingServerShapingReplay:metrics:${key}`,
  );
  session.close();
});

test("measure function throwing an error fails closed without leaking exception", async () => {
  const session = await createTestSession({
    measure(): ProbeMeasureResult | null {
      throw new Error("CanvasContextCrash");
    },
  });
  const shapeKey: string = shapeReplayKey("崩", "Noto Sans SC", 400, false, "zh-Hans", "CjkText", "崩");
  const shapeRequest = shapingInput({
    text: "崩",
    range: { start: 0, end: 1 },
    style: { fontFamilies: ["Noto Sans SC"], fontSize: 32, fontWeight: 400, italic: false, locale: "zh-Hans" },
    fontDecision: { role: "CjkText", candidateKey: "cjk-primary" },
    displayText: "崩",
    openTypeFeatures: [],
  });
  assert.throws(
    () => session.shape(shapeRequest),
    (err: unknown): boolean => err instanceof Error && err.message === `MissingServerShapingReplay:shape:${shapeKey}`,
  );
  const metricKey: string = metricReplayKey("Noto Sans SC", 400, false, "CjkText", "");
  const metricsInput = metricsRequest({
    fontKey: "cjk-primary",
    fontSize: 32,
    role: "CjkText",
    locale: "zh-Hans",
    fontFamilies: ["Noto Sans SC"],
    fontWeight: 400,
    italic: false,
    faceSelectionText: "",
  });
  assert.throws(
    () => session.resolve(metricsInput),
    (err: unknown): boolean => err instanceof Error && err.message === `MissingServerShapingReplay:metrics:${metricKey}`,
  );
  session.close();
});

test("zero-width display text probing succeeds, records 0 advance, and hits cache on revisit", async () => {
  let measureCount: number = 0;
  const session = await createTestSession({
    measure(): ProbeMeasureResult | null {
      measureCount++;
      return { width: 0 };
    },
  });
  const shapeRequest = shapingInput({
    text: "\u200B",
    range: { start: 0, end: 1 },
    style: { fontFamilies: ["Noto Sans SC"], fontSize: 32, fontWeight: 400, italic: false, locale: "zh-Hans" },
    fontDecision: { role: "CjkText", candidateKey: "cjk-primary" },
    displayText: "\u200B",
    openTypeFeatures: [],
  });
  const shapeResponse1: unknown = session.shape(shapeRequest);
  const response1: ZeroWidthShapeResponse = shapeResponse1 as ZeroWidthShapeResponse;
  assert.equal(measureCount, 1);
  assert.equal(response1.glyphRuns[0].advance, 0);
  assert.equal(response1.glyphRuns[0].glyphs[0].advance, 0);

  const shapeResponse2: unknown = session.shape(shapeRequest);
  const response2: SimpleAdvanceShapeResponse = shapeResponse2 as SimpleAdvanceShapeResponse;
  assert.equal(measureCount, 1);
  assert.equal(response2.glyphRuns[0].advance, 0);

  session.close();
});

type EmptyObject = Record<string, never>;

interface InvalidProbeOptions {
  replay: ServerReplayFontReplay;
  faceMetadata: readonly SnapshotManifestFace[];
  probe: EmptyObject;
}

interface InvalidMeasureProbe {
  measure: string;
}

interface InvalidMeasureProbeOptions {
  replay: ServerReplayFontReplay;
  faceMetadata: readonly SnapshotManifestFace[];
  probe: InvalidMeasureProbe;
}

test("probe options validation rejects non-function measure with ServerShapingReplayProbeInvalid", async () => {
  const invalidFaceMetadata: SnapshotManifestFace[] = [{
    family: "Noto Sans SC",
    style: "normal",
    weight: [400, 400],
    unicodeRange: "",
    publicUrl: "",
    sourceSha256: "",
    sfntSha256: "",
    faceIndex: 0,
    sourceOrder: 0,
    axes: {},
    localNames: [],
  }];
  // Deliberately passing empty object to test validation rejects it.
  await assert.rejects(
    async () => createServerReplayFontSession([{}], {
      replay: fixtureReplay,
      faceMetadata: invalidFaceMetadata,
      // @ts-expect-error Testing runtime validation of invalid probe
      probe: {},
    }),
    (err: unknown): boolean => err instanceof Error && err.message === "ServerShapingReplayProbeInvalid",
  );

  const invalidMeasureFaceMetadata: SnapshotManifestFace[] = [{
    family: "Noto Sans SC",
    style: "normal",
    weight: [400, 400],
    unicodeRange: "",
    publicUrl: "",
    sourceSha256: "",
    sfntSha256: "",
    faceIndex: 0,
    sourceOrder: 0,
    axes: {},
    localNames: [],
  }];
  // Deliberately passing string as measure to test validation rejects it.
  await assert.rejects(
    async () => createServerReplayFontSession([{}], {
      replay: fixtureReplay,
      faceMetadata: invalidMeasureFaceMetadata,
      // @ts-expect-error Testing runtime validation of non-function measure
      probe: { measure: "not a function" },
    }),
    (err: unknown): boolean => err instanceof Error && err.message === "ServerShapingReplayProbeInvalid",
  );
});

const constantWidthMeasure: MeasureFunction = (): ProbeMeasureResult | null => ({ width: 32 });

const cjkMetricMeasure: MeasureFunction = (): ProbeMeasureResult | null => ({
  width: 16,
  fontBoundingBoxAscent: 14,
  fontBoundingBoxDescent: 4,
  ideographicBaseline: -4,
});

test("probed entries pass scaleShapeReplayItem and scaleMetricReplayItem without throwing", () => {
  const probedShape = probeShapeReplayResult(
    {
      displayText: "测试",
      serializedFamilies: "Noto Sans SC\u001fserif",
      fontSize: 16,
      fontWeight: 400,
      italic: false,
    },
    constantWidthMeasure,
  );
  assert.ok(probedShape);
  const shapeItemForScale: ReplayShapeItem = { key: "", result: probedShape };
  const scaledShape = scaleShapeReplayItem(shapeItemForScale, 16);
  assert.equal(scaledShape.advance, 32);
  assert.equal(scaledShape.glyphs.length, 1);
  assert.equal(scaledShape.glyphs[0].advance, 32);

  const probedMetrics: readonly (number | null)[] | null = probeMetricReplayValues(
    {
      serializedFamilies: "Noto Sans SC\u001fserif",
      fontSize: 16,
      fontWeight: 400,
      italic: false,
      role: "CjkText",
    },
    cjkMetricMeasure,
  );
  assert.ok(probedMetrics);
  const metricItemForScale: ReplayMetricItem = { key: "", valuesEm: probedMetrics as (number | null)[] };
  const scaledMetrics: number[] = scaleMetricReplayItem(metricItemForScale, 16);
  assert.equal(scaledMetrics[0], 14);
  assert.equal(scaledMetrics[1], 4);
  assert.equal(scaledMetrics[2], 0);
  assert.equal(scaledMetrics[3], 12);
  assert.equal(scaledMetrics[4], 4);
});

test("replayProbeCssFont unit tests format css font strings correctly", () => {
  const fontNormal: string = replayProbeCssFont(
    ["Noto Sans SC", "serif"].join("\u001f"),
    400,
    false,
    32,
  );
  assert.equal(fontNormal, "normal 400 32px Noto Sans SC, serif");

  const fontItalic: string = replayProbeCssFont(
    ["Noto Sans SC", "serif"].join("\u001f"),
    700,
    true,
    16,
  );
  assert.equal(fontItalic, "italic 700 16px Noto Sans SC, serif");
});
