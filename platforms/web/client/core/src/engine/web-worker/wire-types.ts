// Worker-only wire types: the layout request the main thread posts to the
// layout worker, plus the DOM-derived spans only that message carries. These
// never join the generated protocol model.

/** The paragraph request fields the worker consumes. */
import type { PrepareParagraphRequest } from "../wire-types.js";

/** A semantic (DOM source) span the worker tags onto the layout request. */
export interface SemanticSpanWire {
  start: number;
  end: number;
  tagName: string;
  attributes: string[][];
  sourceIndex: number;
  order: number;
}

/** An inline box measured by the main thread before the worker request. */
export interface RenderInlineBoxWire {
  start: number;
  end: number;
  inlineStartPx: number;
  inlineEndPx: number;
  outerSpacing: string;
}

/** The worker layout request: the paragraph fields plus worker-only extras. */
export interface WorkerLayoutRequest extends Omit<PrepareParagraphRequest, "renderEvidenceOverride" | "decorations" | "emphasisDotGapEm"> {
  renderEvidence: boolean;
  semantics: SemanticSpanWire[];
  renderInlineBoxes: RenderInlineBoxWire[];
  sourceTag: string;
}
