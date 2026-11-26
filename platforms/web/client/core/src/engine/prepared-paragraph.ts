// Prepared-paragraph entries served directly by the generated engine tree.
//
// The assembly (request model -> LayoutInput), the domain validation and the
// diagnostics collection are the engine's own steps; core owns only the host
// request shape and the two host callbacks (shaping and font metrics), which
// arrive as typed engine objects rather than JSON text.

import { TextRange } from "@tiqian/engine/org/tiqian/core/TextRange";
import { TiqianTextContent } from "@tiqian/engine/org/tiqian/core/TiqianTextContent";
import { TextSpan } from "@tiqian/engine/org/tiqian/core/TextSpan";
import { TextStyle } from "@tiqian/engine/org/tiqian/core/TextStyle";
import { LineBreakSpan } from "@tiqian/engine/org/tiqian/core/LineBreakSpan";
import { LineBreakPolicy } from "@tiqian/engine/org/tiqian/core/LineBreakPolicy";
import { ParagraphStyle } from "@tiqian/engine/org/tiqian/core/ParagraphStyle";
import { LineLengthGrid } from "@tiqian/engine/org/tiqian/core/LineLengthGrid";
import { LayoutConstraints } from "@tiqian/engine/org/tiqian/core/LayoutConstraints";
import { LayoutInput } from "@tiqian/engine/org/tiqian/core/LayoutInput";
import { DecorationSpan } from "@tiqian/engine/org/tiqian/core/DecorationSpan";
import { DecorationKind } from "@tiqian/engine/org/tiqian/core/DecorationKind";
import { InlineBoxSpan } from "@tiqian/engine/org/tiqian/core/InlineBoxSpan";
import { InlineBoxOuterSpacing } from "@tiqian/engine/org/tiqian/core/InlineBoxOuterSpacing";
import { InlineObjectSpan } from "@tiqian/engine/org/tiqian/core/InlineObjectSpan";
import { ExplainableStubParagraphLayoutEngine } from "@tiqian/engine/org/tiqian/layout/ParagraphLayoutEngine";
import { LookaheadLineBreaker } from "@tiqian/engine/org/tiqian/layout/LineBreaker";
import { PlanLowering } from "@tiqian/engine/org/tiqian/layout/PlanLowering";
import { PreparedParagraphFns } from "@tiqian/engine/org/tiqian/layout/PreparedParagraph";
import { LruWidthIndependentAnnotationCache } from "@tiqian/engine/org/tiqian/layout/WidthIndependentAnnotationCache";
import { ParagraphRequestChecks } from "@tiqian/protocol/org/tiqian/protocol/ParagraphRequestChecks";
import { ParagraphRequestException } from "@tiqian/protocol/org/tiqian/protocol/ParagraphRequestException";
import type { ParagraphRequest } from "@tiqian/protocol/org/tiqian/protocol/ParagraphRequest";
import type { ShapingInput, ShapingResult } from "@tiqian/engine/org/tiqian/shaping/TextShaper";
import type { FontMetricsRequest } from "@tiqian/engine/org/tiqian/font/FontMetrics";
import type { RawFontMetrics } from "@tiqian/engine/org/tiqian/font/RawFontMetrics";
import type { PrepareParagraphRequest } from "./wire-types.js";
import type { PlanWithDiagnostics } from "@tiqian/engine/org/tiqian/layout/PreparedParagraph";
import type { Plan } from "@tiqian/protocol/org/tiqian/protocol/Plan";

export type { PlanWithDiagnostics };

/**
 * The host's two engine callbacks, as typed adapters. Object identity scopes
 * the annotation cache: a width-only relayout reuses the same callbacks and
 * therefore hits the cache instead of re-shaping every paragraph.
 */
export interface EngineCallbacks {
  readonly shape: (input: ShapingInput) => ShapingResult;
  readonly resolve: (request: FontMetricsRequest) => RawFontMetrics;
}

const annotationCacheStore = new WeakMap<EngineCallbacks, LruWidthIndependentAnnotationCache>();

function annotationCache(callbacks: EngineCallbacks): LruWidthIndependentAnnotationCache {
  let entry = annotationCacheStore.get(callbacks);
  if (entry === undefined) {
    entry = new LruWidthIndependentAnnotationCache(512);
    annotationCacheStore.set(callbacks, entry);
  }
  return entry;
}

class IllegalArgumentException extends Error {
  constructor(message: string) {
    super(message);
    this.name = "IllegalArgumentException";
  }
}

function makeIllegalArgument(message: string): Error {
  return new IllegalArgumentException(message);
}

function enumVariant<T>(table: Readonly<Record<string, T>>, qualifiedName: string, name: string): T {
  const variant = table[name];
  if (variant === undefined) {
    throw makeIllegalArgument("No enum constant " + qualifiedName + name);
  }
  return variant;
}

/**
 * Validates the assembled request. A domain failure leaves as an error named
 * IllegalArgumentException whose message is the published issue name.
 */
function validateRequest(request: ParagraphRequest): void {
  try {
    ParagraphRequestChecks.validate(request);
  } catch (error) {
    if (error instanceof ParagraphRequestException) {
      throw makeIllegalArgument(error.message);
    }
    throw error;
  }
}

function assemble(request: PrepareParagraphRequest): { model: ParagraphRequest; gapEm: number } {
  const model: ParagraphRequest = {
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
      families: span.families.slice(),
      fontSizePx: span.fontSizePx,
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
  return { model, gapEm: model.emphasisDotGapEm === null ? 0.1 : model.emphasisDotGapEm };
}

function layout(
  request: PrepareParagraphRequest,
  callbacks: EngineCallbacks,
): { result: ReturnType<ExplainableStubParagraphLayoutEngine["layout"]>; renderEvidence: boolean } {
  const { model, gapEm } = assemble(request);
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
    { resolve: (request2) => callbacks.resolve(request2) },
    null,
    null,
    null,
    null,
    new LookaheadLineBreaker(),
    null,
    { shape: (input2) => callbacks.shape(input2) },
    null,
    annotationCache(callbacks),
  ).layout(input);
  const renderEvidence =
    request.renderEvidenceOverride ??
    (model.textSpans.length > 0 ||
      model.inlineBoxes.length > 0 ||
      model.decorations.length > 0 ||
      result.input.inlineObjects.length > 0);
  return { result, renderEvidence };
}

/** Plan plus the capability-issue and advance diagnostics. */
export function preparedParagraphWithDiagnostics(
  request: PrepareParagraphRequest,
  zeroAdvanceEpsilonPx: number,
  callbacks: EngineCallbacks,
): PlanWithDiagnostics {
  const { result, renderEvidence } = layout(request, callbacks);
  return PreparedParagraphFns.toPlanWithDiagnostics(result, renderEvidence, zeroAdvanceEpsilonPx);
}

/** Plan-only entry for the layout worker; same serializer, no diagnostics pass. */
export function preparedParagraphPlan(
  request: PrepareParagraphRequest,
  callbacks: EngineCallbacks,
): Plan {
  const { result, renderEvidence } = layout(request, callbacks);
  return PlanLowering.toPlan(result, renderEvidence);
}
