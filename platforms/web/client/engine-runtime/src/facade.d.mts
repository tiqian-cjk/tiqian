// Type surface of the public entry (src/facade.mjs). All twelve exports are
// declared here beside their JavaScript implementations in the facade
// modules; every value is served by the single-source generated tree
// (./engine-gen). The export order matches src/facade.mjs and the
// compatibility contract in package.test.mts.

// The published request shape of the two precompute entries: the field set
// the retired Kotlin/JS @JsExport interface PrepareParagraphRequest carried
// (LayoutRequestDtos.kt), now validated by the generated protocol model
// (org/tiqian/protocol ParagraphRequestChecks).
export interface PrepareParagraphRequest {
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
  sourceBoundaries: number[];
  textSpans: Array<{
    start: number;
    end: number;
    fontFamilies: string[];
    fontSize: number;
    fontWeight: number;
    italic: boolean;
    baselineShift: number;
  }>;
  inlineBoxes: Array<{
    start: number;
    end: number;
    inlineStart: number;
    inlineEnd: number;
    outerSpacing: string;
  }>;
  lineBreakSpans: Array<{
    start: number;
    end: number;
    policy: string;
  }>;
  inlineObjects: Array<{
    start: number;
    end: number;
    advance: number;
    ascent: number;
    descent: number;
  }>;
  decorations: Array<{
    start: number;
    end: number;
    kind: string;
  }>;
  emphasisDotGapEm: number | null;
  renderEvidenceOverride: boolean | null;
}

// Wire element types of the layout request channel. The Kotlin/JS @JsExport
// interfaces they carried (the retired Kotlin/JS LayoutRequestDtos.kt, removed
// with the JS cutover) keep their public field
// names: precompute-facade.mjs translates these names onto the generated
// engine-internal ones (span.fontFamilies -> families, span.fontSize ->
// fontSizePx), so the wire names are the public protocol and must not be
// aliased onto TextSpanInput and friends. The declarations above are the
// single source: each type is derived from PrepareParagraphRequest instead
// of repeating its field list.
export type TextSpanWire = PrepareParagraphRequest["textSpans"][number];
export type InlineBoxWire = PrepareParagraphRequest["inlineBoxes"][number];
export type LineBreakSpanWire = PrepareParagraphRequest["lineBreakSpans"][number];
export type InlineObjectWire = PrepareParagraphRequest["inlineObjects"][number];
export type DecorationWire = PrepareParagraphRequest["decorations"][number];

// Worker-only wire types. SemanticSpanWire and RenderInlineBoxWire never
// entered the generated ParagraphRequest protocol model, so no generated
// counterpart exists; their shapes are declared here as the single source,
// matching the retired Kotlin/JS @JsExport interfaces field for field.
export interface SemanticSpanWire {
  start: number;
  end: number;
  tagName: string;
  attributes: string[][];
  sourceIndex: number;
  order: number;
}

export interface RenderInlineBoxWire {
  start: number;
  end: number;
  inlineStartPx: number;
  inlineEndPx: number;
  outerSpacing: string;
}

// The worker layout request: the shared paragraph fields plus the
// worker-only extras (renderEvidence, semantics, renderInlineBoxes,
// sourceTag). Mirrors the retired @JsExport interface WorkerLayoutRequest.
export interface WorkerLayoutRequest {
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
  sourceBoundaries: number[];
  textSpans: TextSpanWire[];
  inlineBoxes: InlineBoxWire[];
  lineBreakSpans: LineBreakSpanWire[];
  inlineObjects: InlineObjectWire[];
  renderEvidence: boolean;
  semantics: SemanticSpanWire[];
  renderInlineBoxes: RenderInlineBoxWire[];
  sourceTag: string;
}

declare function liangHyphenate(
  word: string,
  patternsJson: string,
  exceptionsJson: string,
  leftMin?: number,
  rightMin?: number,
): string;
declare function unicodePunctuationLineBreakClassOf(codePoint: number): string;
declare function bopomofoParse(reading: string): string;
declare function numberSymbolCohesionUnbreakableRanges(text: string): string;
declare function fontMetricsResolve(requestJson: string): string;
declare function fontFallbackResolve(
  text: string,
  start: number,
  end: number,
  requestJson: string,
): string;
declare function classifyFontRole(text: string, start: number, end: number, locale: string): string;
declare function classifyFontRoles(
  text: string,
  starts: number[],
  ends: number[],
  locale: string,
): string[];
declare function unsupportedInlineShapingProperties(): string[];
declare function firstDivergentInlineShapingProperty(
  elementValues: string[],
  paragraphValues: string[],
): string | null;

/** The structured plan-plus-diagnostics envelope of the diagnostics entry. */
export interface PlanWithDiagnostics {
  plan: Record<string, unknown>;
  diagnostics: {
    capabilityIssues: Array<{ name: string; reason: string; rangeStart: number; rangeEnd: number }>;
    advanceSuspects: Array<{ displayText: string; advance: string; reason: string; rangeStart: number; rangeEnd: number }>;
  };
}

declare function precomputeParagraphWithDiagnostics(
  request: PrepareParagraphRequest,
  zeroAdvanceEpsilonPx: number,
  shapeJson: (requestJson: string) => string,
  metricsJson: (requestJson: string) => string,
): PlanWithDiagnostics;
declare function precomputeParagraphPlan(
  request: PrepareParagraphRequest,
  zeroAdvanceEpsilonPx: number,
  shapeJson: (requestJson: string) => string,
  metricsJson: (requestJson: string) => string,
): Record<string, unknown>;
declare function precomputeParagraphWithBrowserMetrics(
  request: PrepareParagraphRequest,
  zeroAdvanceEpsilonPx: number,
  callbacks: { shapeJson: (requestJson: string) => string; metricsJson: (requestJson: string) => string },
): string;

export {
  bopomofoParse,
  numberSymbolCohesionUnbreakableRanges,
  fontMetricsResolve,
  fontFallbackResolve,
  liangHyphenate,
  unicodePunctuationLineBreakClassOf,
  classifyFontRole,
  classifyFontRoles,
  unsupportedInlineShapingProperties,
  firstDivergentInlineShapingProperty,
  precomputeParagraphWithDiagnostics,
  precomputeParagraphWithBrowserMetrics,
  precomputeParagraphPlan,
};