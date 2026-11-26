// Wire types of the engine boundary, owned by core after the the retired engine facade
// removal. The field names are the public protocol the Worker channel and the
// layout-session callbacks exchange; the generated engine models use their own
// names and are translated in prepared-paragraph.ts.

/** The paragraph request shape the layout entries consume. */
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

export type TextSpanWire = PrepareParagraphRequest["textSpans"][number];
export type InlineBoxWire = PrepareParagraphRequest["inlineBoxes"][number];
export type LineBreakSpanWire = PrepareParagraphRequest["lineBreakSpans"][number];
export type InlineObjectWire = PrepareParagraphRequest["inlineObjects"][number];
export type DecorationWire = PrepareParagraphRequest["decorations"][number];

/** Worker-only wire types; these never join the generated protocol model. */
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

/** The worker layout request: the paragraph fields plus worker-only extras. */
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
