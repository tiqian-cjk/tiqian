// The precompute capability exports of `@tiqian/ffi`, served directly by the
// single-source generated trees under ./engine-gen (copied from the bundle
// driver products engine-haxe/out/ts/gen and engine-haxe/out/protocol-ts/gen;
// do not edit the vendored files). This module retires the last two
// Kotlin/JS @JsExport entries (PrecomputeExports.kt + the
// ParagraphWireCodec.kt / WireJson.kt bridging it reached through).
//
// Request shape and domain validation come from the generated protocol tree
// (org/tiqian/protocol, Stage1-P5): the host request model
// (PrepareParagraphRequest -> ParagraphRequest) is checked by
// ParagraphRequestChecks.validate, and a domain failure leaves with the
// same channel the retired Kotlin facade used: an error named
// "IllegalArgumentException" whose message is the published issue name
// (EmptyParagraph, InvalidMaximumMeasure, ...). The wire-packing names of
// the old separator encoding (Invalid*Wire) have no carrier here.
//
// Callback inversion (ADR 0053) is preserved verbatim: the host passes its
// shaping and metrics functions in, and the engine calls them on the same
// synchronous stack. What used to be the cross-language callbacks
// JsCallbackTextShaper / JsCallbackFontMetricsResolver (Kotlin lambdas over
// JSON strings) becomes the same-language adapter objects below: they
// serialize the engine's typed ShapingInput / FontMetricsRequest to the
// same JSON the retired WireJson.kt append helpers produced, invoke the
// host function, and parse the response JSON back into the typed
// ShapingResult / RawFontMetrics the generated engine consumes. No
// environment global is read.
//
// The plan JSON itself is produced by the generated tree:
// PreparedParagraphFns.toPlanWithDiagnosticsJson (engine-haxe/src/org/
// tiqian/layout/PreparedParagraph.hx toPlanWithDiagnosticsJson). When P3
// lands its single-source PlanJson serializer, the call site moves to it
// with no wire change.

import { ParagraphRequestChecks } from "./engine-gen/org/tiqian/protocol/ParagraphRequestChecks.js";
import { ParagraphRequestException } from "./engine-gen/org/tiqian/protocol/ParagraphRequestException.js";
import { TextRange } from "./engine-gen/org/tiqian/core/TextRange.js";
import { TextSpan } from "./engine-gen/org/tiqian/core/TextSpan.js";
import { TextStyle } from "./engine-gen/org/tiqian/core/TextStyle.js";
import { TiqianTextContent } from "./engine-gen/org/tiqian/core/TiqianTextContent.js";
import { ParagraphStyle } from "./engine-gen/org/tiqian/core/ParagraphStyle.js";
import { LayoutConstraints } from "./engine-gen/org/tiqian/core/LayoutConstraints.js";
import { LayoutInput } from "./engine-gen/org/tiqian/core/LayoutInput.js";
import { LineBreakSpan } from "./engine-gen/org/tiqian/core/LineBreakSpan.js";
import { LineLengthGrid } from "./engine-gen/org/tiqian/core/LineLengthGrid.js";
import { LineBreakPolicy } from "./engine-gen/org/tiqian/core/LineBreakPolicy.js";
import { InlineBoxSpan } from "./engine-gen/org/tiqian/core/InlineBoxSpan.js";
import { InlineBoxOuterSpacing } from "./engine-gen/org/tiqian/core/InlineBoxOuterSpacing.js";
import { InlineObjectSpan } from "./engine-gen/org/tiqian/core/InlineObjectSpan.js";
import { DecorationSpan } from "./engine-gen/org/tiqian/core/DecorationSpan.js";
import { DecorationKind } from "./engine-gen/org/tiqian/core/DecorationKind.js";
import { Cluster } from "./engine-gen/org/tiqian/core/Cluster.js";
import { Glyph } from "./engine-gen/org/tiqian/core/Glyph.js";
import { Rect } from "./engine-gen/org/tiqian/core/Rect.js";
import { GlyphRun } from "./engine-gen/org/tiqian/core/GlyphRun.js";
import { ShapingDecisionInfo } from "./engine-gen/org/tiqian/core/ShapingDecisionInfo.js";
import { FontMetricsRequest } from "./engine-gen/org/tiqian/font/FontMetrics.js";
import { RawFontMetrics } from "./engine-gen/org/tiqian/font/RawFontMetrics.js";
import { FontMetricSource } from "./engine-gen/org/tiqian/font/FontMetricSource.js";
import { ShapingInput, ShapingResult } from "./engine-gen/org/tiqian/shaping/TextShaper.js";
import { ExplainableStubParagraphLayoutEngine } from "./engine-gen/org/tiqian/layout/ParagraphLayoutEngine.js";
import { LookaheadLineBreaker } from "./engine-gen/org/tiqian/layout/LineBreaker.js";
import { PreparedParagraphFns } from "./engine-gen/org/tiqian/layout/PreparedParagraph.js";
import { PlanLowering } from "./engine-gen/org/tiqian/layout/PlanLowering.js";
import { LruWidthIndependentAnnotationCache } from "./engine-gen/org/tiqian/layout/WidthIndependentAnnotationCache.js";

/**
 * Per-shaping-session annotation cache. The engine's width-independent
 * annotation cache (shaping results) is keyed only by text and style, so it
 * must be scoped per shaper: a cache shared across font sessions would
 * return annotations shaped by the wrong session. The host shapeJson
 * function identity scopes the cache; a width-only relayout reuses the same
 * function and therefore hits the cache instead of re-shaping every
 * paragraph. Weak keys let the cache be collected when its host releases
 * the font session or replaces the browser measurement bridge.
 */
const annotationCacheStore = new WeakMap();

function cachedAnnotationCache(shaperKey) {
  let entry = annotationCacheStore.get(shaperKey);
  if (entry === undefined) {
    entry = new LruWidthIndependentAnnotationCache(512);
    annotationCacheStore.set(shaperKey, entry);
  }
  return entry;
}

/** Mirrors the identity of Kotlin's IllegalArgumentException on this wire. */
class IllegalArgumentException extends Error {
  constructor(message) {
    super(message);
    this.name = "IllegalArgumentException";
  }
}

function makeIllegalArgument(message) {
  return new IllegalArgumentException(message);
}

/**
 * Validates the generated request and keeps the name-as-message channel:
 * the retired Kotlin codec caught ParagraphRequestException and rethrew
 * IllegalArgumentException with the issue name as the message
 * (ParagraphWireCodec.kt:62-69).
 */
function validateRequest(request) {
  try {
    ParagraphRequestChecks.validate(request);
  } catch (error) {
    if (error instanceof ParagraphRequestException) {
      throw makeIllegalArgument(error.message);
    }
    throw error;
  }
}

/** Kotlin enum valueOf identity: unknown names raise IllegalArgumentException. */
function enumVariant(enumTable, qualifiedName, name) {
  const variant = enumTable[name];
  if (variant === undefined) {
    throw makeIllegalArgument("No enum constant " + qualifiedName + name);
  }
  return variant;
}

function stringMember(raw, name) {
  if (raw === null) return "";
  const value = raw[name];
  return typeof value === "string" ? value : "";
}

function numberMember(raw, name) {
  if (raw === null) return Number.NaN;
  const value = raw[name];
  return typeof value === "number" ? value : Number.NaN;
}

/**
 * Reads an optional number member the way the Haxe Cluster constructor
 * defaults it: engine-haxe/src/org/tiqian/core/Cluster.hx:23 spells the
 * member as "baselineShift == null ? 0.0 : baselineShift", so a shaping
 * response that carries no baseline shift means exactly 0. A present,
 * non-numeric value is a malformed response and stays NaN so the broken
 * field still surfaces instead of passing as 0.
 */
function optionalNumberMember(raw, name) {
  if (raw === null) return 0.0;
  const value = raw[name];
  if (value === undefined || value === null) return 0.0;
  return typeof value === "number" ? value : Number.NaN;
}

/**
 * Reads glyph ink bounds the way WireJson.kt parseBounds did: a missing or
 * non-object member is null, and a missing side reads as 0. The punctuation
 * geometry stage needs these bounds to choose the compressed body frame
 * (ADR 0014 InkBoundsFittedBodyCompression); without them every punctuation
 * atom falls back to ProfileGlueFallbackWithoutFontGeometry.
 */
function boundsMember(raw) {
  const value = raw === null ? null : raw.bounds;
  if (value === null || value === undefined || typeof value !== "object") return null;
  const side = (name) => (typeof value[name] === "number" ? value[name] : 0);
  return new Rect(side("left"), side("top"), side("right"), side("bottom"));
}

/** Reads a JSON string array the way WireJson.kt parseDynamicStringList does. */
function stringListMember(raw, name) {
  if (raw === null) return [];
  const value = raw[name];
  if (!Array.isArray(value)) return [];
  return value.map((item) => (typeof item === "string" ? item : ""));
}

/** Renders one wire number like the retired WireJson.kt appendJsonNumber. */
function appendJsonNumber(out, value) {
  if (Number.isNaN(value)) {
    out.push("NaN");
  } else if (value === Number.POSITIVE_INFINITY) {
    out.push("Infinity");
  } else if (value === Number.NEGATIVE_INFINITY) {
    out.push("-Infinity");
  } else if (value === 0) {
    out.push("0");
  } else {
    out.push(String(value));
  }
}

/** Renders one wire string exactly like WireJson.kt appendJsonString. */
function appendJsonString(out, value) {
  out.push(JSON.stringify(value));
}

function appendJsonStringArray(out, items) {
  out.push("[");
  for (let i = 0; i < items.length; i += 1) {
    if (i > 0) out.push(",");
    appendJsonString(out, items[i]);
  }
  out.push("]");
}

/**
 * Serializes a ShapingInput exactly like the retired
 * WireJson.kt appendShapingInputJson (WireJson.kt:59-87): field order and
 * number spelling are the ABI the host callbacks were written against.
 */
function appendShapingInputJson(input) {
  const out = [];
  out.push('{"text":');
  appendJsonString(out, input.text);
  out.push(',"range":{"start":');
  out.push(String(input.range.start));
  out.push(',"end":');
  out.push(String(input.range.end));
  out.push('},"style":{"fontFamilies":');
  appendJsonStringArray(out, input.style.fontFamilies);
  out.push(',"fontSize":');
  appendJsonNumber(out, input.style.fontSize);
  out.push(',"fontWeight":');
  out.push(String(input.style.fontWeight));
  out.push(',"italic":');
  out.push(String(input.style.italic));
  out.push(',"locale":');
  appendJsonString(out, input.style.locale);
  out.push('},"fontDecision":{"role":');
  appendJsonString(out, input.fontDecision.role.kind);
  out.push(',"candidateKey":');
  appendJsonString(out, input.fontDecision.candidate.key);
  out.push('},"displayText":');
  appendJsonString(out, input.displayText);
  out.push(',"openTypeFeatures":');
  appendJsonStringArray(out, input.openTypeFeatures);
  out.push("}");
  return out.join("");
}

/** Parses a response the way WireJson.kt parseShapingResultJson does. */
function parseShapingResultJson(json) {
  let raw = null;
  try {
    raw = JSON.parse(json);
  } catch {
    raw = null;
  }
  if (raw === null || typeof raw !== "object") {
    return new ShapingResult([], [], []);
  }
  const list = (value, build) => {
    if (!Array.isArray(value)) return [];
    return value.map((item) =>
      item === null || item === undefined || typeof item !== "object" ? build({}) : build(item),
    );
  };
  const range = (value) => {
    if (value === null || value === undefined || typeof value !== "object") return new TextRange(0, 0);
    return new TextRange(
      Math.trunc(typeof value.start === "number" ? value.start : 0),
      Math.trunc(typeof value.end === "number" ? value.end : 0),
    );
  };
  const clusters = list(raw.clusters, (c) => new Cluster(
    range(c.range),
    stringMember(c, "text"),
    stringMember(c, "fontKey"),
    numberMember(c, "advance"),
    stringMember(c, "displayText"),
    optionalNumberMember(c, "baselineShift"),
  ));
  const glyphRuns = list(raw.glyphRuns, (g) => new GlyphRun(
    range(g.range),
    stringMember(g, "fontKey"),
    list(g.glyphs, (glyph) => new Glyph(
      typeof glyph.id === "number" ? Math.trunc(glyph.id) : 0,
      range(glyph.clusterRange),
      numberMember(glyph, "advance"),
      numberMember(glyph, "x"),
      numberMember(glyph, "y"),
      null,
      boundsMember(glyph),
    )),
    numberMember(g, "advance"),
    stringListMember(g, "openTypeFeatures"),
  ));
  const decisions = list(raw.decisions, (d) => new ShapingDecisionInfo(
    range(d.range),
    stringMember(d, "sourceText"),
    stringMember(d, "displayText"),
    stringMember(d, "fontKey"),
    typeof d.glyphCount === "number" ? Math.trunc(d.glyphCount) : 0,
    numberMember(d, "advance"),
    stringMember(d, "source"),
    stringMember(d, "reason"),
    typeof d.glyphsWithoutInkBounds === "number" ? Math.trunc(d.glyphsWithoutInkBounds) : 0,
    typeof d.missingGlyphs === "number" ? Math.trunc(d.missingGlyphs) : 0,
    typeof d.resolvedFace === "string" ? d.resolvedFace : null,
    typeof d.script === "string" ? d.script : null,
    typeof d.language === "string" ? d.language : null,
    typeof d.strategy === "string" ? d.strategy : null,
    typeof d.featureEvidence === "string" ? d.featureEvidence : null,
    typeof d.capabilityIssue === "string" ? d.capabilityIssue : null,
  ));
  return new ShapingResult(clusters, glyphRuns, decisions);
}

/**
 * Serializes a FontMetricsRequest exactly like the retired
 * WireJson.kt appendFontMetricsRequestJson (WireJson.kt:89-111).
 */
function appendFontMetricsRequestJson(request) {
  const out = [];
  out.push('{"fontKey":');
  appendJsonString(out, request.fontKey);
  out.push(',"fontSize":');
  appendJsonNumber(out, request.fontSize);
  out.push(',"role":');
  appendJsonString(out, request.role.kind);
  out.push(',"locale":');
  appendJsonString(out, request.locale);
  out.push(',"fontFamilies":');
  appendJsonStringArray(out, request.fontFamilies);
  out.push(',"fontWeight":');
  out.push(String(request.fontWeight));
  out.push(',"italic":');
  out.push(String(request.italic));
  out.push(',"faceSelectionText":');
  appendJsonString(out, request.faceSelectionText);
  out.push("}");
  return out.join("");
}

/** Parses a response the way WireJson.kt parseRawFontMetricsJson does. */
function parseRawFontMetricsJson(json) {
  let raw = null;
  try {
    raw = JSON.parse(json);
  } catch {
    raw = null;
  }
  if (raw === null || typeof raw !== "object") {
    return new RawFontMetrics(Number.NaN, Number.NaN);
  }
  const num = (name) => {
    const value = raw[name];
    return typeof value === "number" ? value : Number.NaN;
  };
  const source =
    typeof raw.source === "string"
      ? enumVariant(FontMetricSource, "org.tiqian.font.FontMetricSource.", raw.source)
      : FontMetricSource.RawTables;
  return new RawFontMetrics(
    num("ascent"),
    num("descent"),
    typeof raw.leading === "number" ? raw.leading : 0,
    source,
    typeof raw.typoAscent === "number" ? raw.typoAscent : null,
    typeof raw.typoDescent === "number" ? raw.typoDescent : null,
  );
}

/**
 * The adapter objects injected into the generated engine: the same-language
 * form of the retired JsCallbackTextShaper / JsCallbackFontMetricsResolver
 * (JsCallbackAdapters.kt). The control flow is identical - serialize the
 * engine's typed request to JSON, invoke the host function, parse the JSON
 * response into the typed result - with the cross-language boundary removed.
 */
function callbackTextShaper(shapeJson) {
  return {
    shape: (input) => parseShapingResultJson(shapeJson(appendShapingInputJson(input))),
  };
}

function callbackFontMetricsResolver(metricsJson) {
  return {
    resolve: (request) => parseRawFontMetricsJson(metricsJson(appendFontMetricsRequestJson(request))),
  };
}

/**
 * Builds the generated ParagraphRequest from the published DTO shape
 * (PrepareParagraphRequest) and assembles the LayoutInput exactly like the
 * retired ParagraphWireCodec.layout(PrepareParagraphRequestDto)
 * (ParagraphWireCodec.kt:436-505): the engine's prepared-paragraph pipeline
 * runs from the generated tree, with the host callbacks inverted in.
 */
function layoutWithDiagnostics(request, zeroAdvanceEpsilonPx, textShaper, fontMetricsResolver, annotationCache) {
  const model = {
    fontSessionId: "",
    text: request.text,
    maxWidthPx: request.maxWidthPx,
    fontFamilies: request.fontFamilies.slice(),
    fontSizePx: request.fontSizePx,
    lineHeightPx: request.lineHeightPx,
    locale: request.locale,
    fontWeight: request.fontWeight,
    italic: request.italic,
    firstLineIndentIc: request.firstLineIndentIc,
    lineLengthGridEnabled: request.lineLengthGridEnabled,
    emphasisDotGapEm: request.emphasisDotGapEm === undefined ? null : request.emphasisDotGapEm,
    sourceBoundaries: request.sourceBoundaries.slice(),
    textSpans: request.textSpans.map((span) => ({
      start: span.start,
      end: span.end,
      families: span.fontFamilies.slice(),
      fontSizePx: span.fontSize,
      fontWeight: span.fontWeight,
      italic: span.italic,
      baselineShift: span.baselineShift,
    })),
    lineBreakSpans: request.lineBreakSpans.map((span) => ({
      start: span.start,
      end: span.end,
      policy: span.policy,
    })),
    inlineBoxes: request.inlineBoxes.map((box) => ({
      start: box.start,
      end: box.end,
      inlineStart: box.inlineStart,
      inlineEnd: box.inlineEnd,
      outerSpacing: box.outerSpacing === undefined ? "Narrow" : box.outerSpacing,
    })),
    inlineObjects: request.inlineObjects.map((object) => ({
      start: object.start,
      end: object.end,
      advance: object.advance,
      ascent: object.ascent,
      descent: object.descent,
    })),
    decorations: request.decorations.map((deco) => ({
      start: deco.start,
      end: deco.end,
      kind: deco.kind,
    })),
  };
  validateRequest(model);
  const gapEm = model.emphasisDotGapEm === null ? 0.1 : model.emphasisDotGapEm;
  const input = new LayoutInput(
    new TiqianTextContent(
      model.text,
      model.textSpans.map((span) => new TextSpan(
        new TextRange(span.start, span.end),
        new TextStyle(
          span.families.filter((family) => family.trim().length > 0),
          span.fontSizePx,
          request.locale,
          span.fontWeight,
          span.italic,
          span.baselineShift,
        ),
      )),
      model.sourceBoundaries.slice(),
      model.lineBreakSpans.map((span) => new LineBreakSpan(
        new TextRange(span.start, span.end),
        enumVariant(LineBreakPolicy, "org.tiqian.core.LineBreakPolicy.", span.policy),
      )),
    ),
    new TextStyle(
      model.fontFamilies.filter((family) => family.trim().length > 0),
      model.fontSizePx,
      model.locale,
      model.fontWeight,
      model.italic,
    ),
    new ParagraphStyle(
      null,
      null,
      model.lineHeightPx,
      model.firstLineIndentIc,
      null,
      null,
      new LineLengthGrid(model.lineLengthGridEnabled),
      null,
      null,
      gapEm,
    ),
    new LayoutConstraints(model.maxWidthPx),
    null,
    model.decorations.map((deco) => new DecorationSpan(
      new TextRange(deco.start, deco.end),
      enumVariant(DecorationKind, "org.tiqian.core.DecorationKind.", deco.kind),
    )),
    null,
    model.inlineBoxes.map((box) => new InlineBoxSpan(
      new TextRange(box.start, box.end),
      box.inlineStart,
      box.inlineEnd,
      enumVariant(InlineBoxOuterSpacing, "org.tiqian.core.InlineBoxOuterSpacing.", box.outerSpacing),
    )),
    model.inlineObjects.map((object) => new InlineObjectSpan(
      new TextRange(object.start, object.end),
      object.advance,
      object.ascent,
      object.descent,
    )),
  );
  const result = new ExplainableStubParagraphLayoutEngine(
    null,
    null,
    null,
    fontMetricsResolver,
    null,
    null,
    null,
    null,
    new LookaheadLineBreaker(),
    null,
    textShaper,
    null,
    annotationCache,
  ).layout(input);
  const renderEvidence =
    request.renderEvidenceOverride ??
    (model.textSpans.length > 0 ||
      model.inlineBoxes.length > 0 ||
      model.decorations.length > 0 ||
      result.input.inlineObjects.length > 0);
  return { result, renderEvidence };
}

function planWithDiagnosticsJson(request, zeroAdvanceEpsilonPx, textShaper, fontMetricsResolver, annotationCache) {
  const { result, renderEvidence } = layoutWithDiagnostics(
    request,
    zeroAdvanceEpsilonPx,
    textShaper,
    fontMetricsResolver,
    annotationCache,
  );
  return PreparedParagraphFns.toPlanWithDiagnosticsJson(result, renderEvidence, zeroAdvanceEpsilonPx);
}

function planWithDiagnostics(request, zeroAdvanceEpsilonPx, textShaper, fontMetricsResolver, annotationCache) {
  const { result, renderEvidence } = layoutWithDiagnostics(
    request,
    zeroAdvanceEpsilonPx,
    textShaper,
    fontMetricsResolver,
    annotationCache,
  );
  return PreparedParagraphFns.toPlanWithDiagnostics(result, renderEvidence, zeroAdvanceEpsilonPx);
}

/**
 * Plan-plus-diagnostics envelope for the TsHost web-host prepare step. The
 * host passes its own ZERO_ADVANCE_EPSILON so the layout module holds no
 * host policy; the returned object carries the plan plus the capability-issue
 * and suspicious-advance facts for the host-side checks. Shaping and
 * metrics arrive through the host-provided [shapeJson] / [metricsJson]
 * functions (ADR 0053 callback inversion, now same-language).
 */
export function precomputeParagraphWithDiagnostics(
  request,
  zeroAdvanceEpsilonPx,
  shapeJson,
  metricsJson,
) {
  return planWithDiagnostics(
    request,
    zeroAdvanceEpsilonPx,
    callbackTextShaper(shapeJson),
    callbackFontMetricsResolver(metricsJson),
    cachedAnnotationCache(shapeJson),
  );
}

/**
 * Plan-only entry for the layout worker. The worker discards the diagnostics,
 * so this entry skips the toPlanWithDiagnostics collection passes; the main
 * thread keeps the diagnostics entry. PlanLowering.toPlan is the same
 * serializer the diagnostics and JSON entries use, so the plan bytes are
 * unchanged.
 */
export function precomputeParagraphPlan(request, zeroAdvanceEpsilonPx, shapeJson, metricsJson) {
  const { result, renderEvidence } = layoutWithDiagnostics(
    request,
    zeroAdvanceEpsilonPx,
    callbackTextShaper(shapeJson),
    callbackFontMetricsResolver(metricsJson),
    cachedAnnotationCache(shapeJson),
  );
  return PlanLowering.toPlan(result, renderEvidence);
}

/**
 * Plan-plus-diagnostics envelope using the host-provided browser
 * measurement callbacks object ({ shapeJson, metricsJson }): the exact
 * BrowserMetricsCallbacks shape of the retired Kotlin entry. The callbacks
 * run on the same synchronous call stack, and every shape() request
 * re-sends the segment text.
 */
export function precomputeParagraphWithBrowserMetrics(request, zeroAdvanceEpsilonPx, callbacks) {
  return planWithDiagnosticsJson(
    request,
    zeroAdvanceEpsilonPx,
    callbackTextShaper((requestJson) => callbacks.shapeJson(requestJson)),
    callbackFontMetricsResolver((requestJson) => callbacks.metricsJson(requestJson)),
    cachedAnnotationCache(callbacks),
  );
}
