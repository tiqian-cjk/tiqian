import type { WorkerLayoutRequestBody } from "./worker-channel.js";
import { LAYOUT_REQUEST_FIELDS } from "./assembly-record-fields.js";

/**
 * Layout identity of one worker request. LAYOUT_REQUEST_FIELDS is generated
 * from ParagraphRequest.hx, so it carries every layout input, including
 * lineLengthGridEnabled. The render-only fields (renderEvidence, semantics,
 * renderInlineBoxes, sourceTag) are worker-channel extras outside the engine
 * request model, so they stay out of the key: two requests that differ only in
 * those fields share one plan.
 */
export function layoutRequestKey(request: WorkerLayoutRequestBody | null | undefined): string {
  return JSON.stringify(LAYOUT_REQUEST_FIELDS.map((field) => request?.[field] ?? null));
}
