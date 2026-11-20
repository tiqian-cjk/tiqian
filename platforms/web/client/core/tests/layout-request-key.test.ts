import test from "node:test";
import assert from "node:assert/strict";
import { layoutRequestKey } from "../src/engine/web-worker/layout-request-key.js";
import type { WorkerLayoutRequestBody } from "../src/engine/web-worker/worker-channel.js";

function baseRequest(): WorkerLayoutRequestBody {
  return {
    text: "正文",
    maxWidthPx: 320,
    fontFamilies: ["Test"],
    fontSizePx: 16,
    lineHeightPx: 24,
    locale: "zh-Hans",
    fontWeight: 400,
    italic: false,
    firstLineIndentIc: 0,
    lineLengthGridEnabled: false,
    sourceBoundaries: [],
    textSpans: [],
    inlineBoxes: [],
    lineBreakSpans: [],
    inlineObjects: [],
    renderEvidence: false,
    semantics: [],
    renderInlineBoxes: [],
    sourceTag: "",
  };
}

test("lineLengthGridEnabled distinguishes layout keys", () => {
  const off = { ...baseRequest(), lineLengthGridEnabled: false };
  const on = { ...baseRequest(), lineLengthGridEnabled: true };
  assert.notEqual(layoutRequestKey(off), layoutRequestKey(on));
});

test("renderEvidence stays out of the layout key", () => {
  const withoutEvidence = { ...baseRequest(), renderEvidence: false };
  const withEvidence = { ...baseRequest(), renderEvidence: true };
  assert.equal(layoutRequestKey(withoutEvidence), layoutRequestKey(withEvidence));
});
