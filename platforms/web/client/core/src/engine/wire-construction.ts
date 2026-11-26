// Wire constructors.
//
// Host data enters the engine request channel through the named constructors
// below; each constructor holds the single object-literal construction for
// its wire type, so the ts-discipline gate keeps every other module free of
// hand-written request shapes.

import type {
  DecorationWire,
  InlineBoxWire,
  InlineObjectWire,
  LineBreakSpanWire,
  PrepareParagraphRequest,
  TextSpanWire,
} from "./wire-types.js";
import type {
  RenderInlineBoxWire,
  SemanticSpanWire,
  WorkerLayoutRequest,
} from "./engine-access/wire-types.js";

type WireFields<T> = T;

export function textSpanWires(fields: WireFields<TextSpanWire>[]): TextSpanWire[] {
  return fields as TextSpanWire[];
}

export function inlineBoxWires(fields: WireFields<InlineBoxWire>[]): InlineBoxWire[] {
  return fields as InlineBoxWire[];
}

export function lineBreakSpanWires(fields: WireFields<LineBreakSpanWire>[]): LineBreakSpanWire[] {
  return fields as LineBreakSpanWire[];
}

export function inlineObjectWires(fields: WireFields<InlineObjectWire>[]): InlineObjectWire[] {
  return fields as InlineObjectWire[];
}

export function decorationWires(fields: WireFields<DecorationWire>[]): DecorationWire[] {
  return fields as DecorationWire[];
}

export function semanticSpanWires(fields: WireFields<SemanticSpanWire>[]): SemanticSpanWire[] {
  return fields as SemanticSpanWire[];
}

export function renderInlineBoxWires(fields: WireFields<RenderInlineBoxWire>[]): RenderInlineBoxWire[] {
  return fields as RenderInlineBoxWire[];
}

export function prepareParagraphRequestWire(fields: WireFields<PrepareParagraphRequest>): PrepareParagraphRequest {
  return fields as PrepareParagraphRequest;
}

export function workerLayoutRequestWire(fields: WireFields<WorkerLayoutRequest>): WorkerLayoutRequest {
  return fields as WorkerLayoutRequest;
}
