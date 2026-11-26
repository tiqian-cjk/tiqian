// The paragraph request the layout entries consume. It is the generated
// protocol model minus the session id, plus the render-evidence override the
// worker carries; the span aliases point at the protocol input types so a
// field rename lands in one place.

import type { ParagraphRequest } from "@tiqian/protocol/org/tiqian/protocol/ParagraphRequest";

export type PrepareParagraphRequest = Omit<ParagraphRequest, "fontSessionId"> & {
  renderEvidenceOverride: boolean | null;
};

export type TextSpanWire = ParagraphRequest["textSpans"][number];
export type InlineBoxWire = ParagraphRequest["inlineBoxes"][number];
export type LineBreakSpanWire = ParagraphRequest["lineBreakSpans"][number];
export type InlineObjectWire = ParagraphRequest["inlineObjects"][number];
export type DecorationWire = ParagraphRequest["decorations"][number];
