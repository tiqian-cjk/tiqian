// Field and issue-name equality between the generated host request model
// (@tiqian/protocol, driver bundle protocol-ts) and the domain contract the
// two replaced lanes publish (the retired ParagraphWireCodec.kt:279-297,
// precompute/engine/src/paragraph.rs:72-131). Run:
//   (cd platforms/web/server/core && npm test -- paragraph-request)
import test from "node:test";
import assert from "node:assert/strict";
import { ParagraphRequestChecks } from "@tiqian/protocol/org/tiqian/protocol/ParagraphRequestChecks";
import type { ParagraphRequest } from "@tiqian/protocol/org/tiqian/protocol/ParagraphRequest";
import { ParagraphRequestException } from "@tiqian/protocol/org/tiqian/protocol/ParagraphRequestException";

const ideographicSpace = String.fromCodePoint(0x3000);
const nbsp = String.fromCodePoint(0x00a0);
const narrowNoBreak = String.fromCodePoint(0x202f);
const zeroWidthSpace = String.fromCodePoint(0x200b);

function request(): ParagraphRequest {
  return {
    fontSessionId: "tq-font-test-1",
    text: "正文一段",
    maxWidthPx: 80,
    fontFamilies: ["Fake CJK"],
    fontSizePx: 16,
    lineHeightPx: 24,
    locale: "zh-Hans",
    fontWeight: 400,
    italic: false,
    firstLineIndentIc: 0,
    lineLengthGridEnabled: false,
    emphasisDotGapEm: null,
    sourceBoundaries: [],
    textSpans: [],
    lineBreakSpans: [],
    inlineBoxes: [],
    inlineObjects: [],
    decorations: [],
  };
}

function issueOf(modified: ParagraphRequest): string {
  try {
    ParagraphRequestChecks.validate(modified);
  } catch (error) {
    if (error instanceof ParagraphRequestException) {
      return ParagraphRequestException.describe(error.error);
    }
    throw error;
  }
  return "";
}

test("plain request validates", () => {
  ParagraphRequestChecks.validate(request());
});

test("paragraph checks report the domain names in order", () => {
  assert.equal(issueOf({ ...request(), text: "   " }), "EmptyParagraph");
  assert.equal(issueOf({ ...request(), text: ideographicSpace }), "EmptyParagraph");
  assert.equal(issueOf({ ...request(), maxWidthPx: 0 }), "InvalidMaximumMeasure");
  assert.equal(issueOf({ ...request(), maxWidthPx: Number.NaN }), "InvalidMaximumMeasure");
  assert.equal(issueOf({ ...request(), fontSizePx: -1 }), "InvalidFontSize");
  assert.equal(issueOf({ ...request(), lineHeightPx: Number.POSITIVE_INFINITY }), "InvalidLineHeight");
  assert.equal(issueOf({ ...request(), firstLineIndentIc: Number.NaN }), "InvalidFirstLineIndent");
  assert.equal(issueOf({ ...request(), fontWeight: 0 }), "InvalidFontWeight");
  assert.equal(issueOf({ ...request(), fontWeight: 1001 }), "InvalidFontWeight");
  assert.equal(issueOf({ ...request(), emphasisDotGapEm: -0.1 }), "InvalidEmphasisDotGapEm");
  assert.equal(issueOf({ ...request(), fontFamilies: ["  "] }), "MissingExplicitFontFamilies");
});

test("span checks cover range families and numbers", () => {
  const modified = request();
  const span = {
    start: 2,
    end: 1,
    families: ["Fake CJK"],
    fontSizePx: 16,
    fontWeight: 400,
    italic: false,
    baselineShift: 0,
  };
  modified.textSpans = [span];
  assert.equal(issueOf(modified), "InvalidTextSpanRange");
  span.start = 0;
  span.end = 9;
  assert.equal(issueOf(modified), "InvalidTextSpanRange");
  span.end = 2;
  span.families = [" "];
  assert.equal(issueOf(modified), "MissingTextSpanFontFamilies");
  span.families = [zeroWidthSpace];
  assert.equal(issueOf(modified), "");
  span.families = ["Fake CJK"];
  span.fontSizePx = 0;
  assert.equal(issueOf(modified), "InvalidTextSpanFontSize");
  span.fontSizePx = 16;
  span.fontWeight = 1001;
  assert.equal(issueOf(modified), "InvalidTextSpanFontWeight");
  span.fontWeight = 400;
  span.baselineShift = Number.NaN;
  assert.equal(issueOf(modified), "InvalidTextSpanBaselineShift");
});

test("boundaries use the utf-16 length", () => {
  const astral = { ...request(), text: "😀字" };
  astral.sourceBoundaries = [3];
  ParagraphRequestChecks.validate(astral);
  astral.sourceBoundaries = [4];
  assert.equal(issueOf(astral), "InvalidSourceBoundary");
});

test("whitespace edge set matches the Kotlin lane", () => {
  assert.equal(issueOf({ ...request(), text: " " }), "EmptyParagraph");
  assert.equal(issueOf({ ...request(), text: ideographicSpace }), "EmptyParagraph");
  ParagraphRequestChecks.validate({ ...request(), text: nbsp });
  ParagraphRequestChecks.validate({ ...request(), text: narrowNoBreak });
  ParagraphRequestChecks.validate({ ...request(), text: zeroWidthSpace });
});

test("inline object and decoration checks", () => {
  const objects = request();
  objects.inlineObjects = [{ start: 0, end: 9, advance: 1, ascent: 1, descent: 1 }];
  assert.equal(issueOf(objects), "InvalidInlineObjectRange");
  objects.inlineObjects[0].end = 2;
  objects.inlineObjects[0].advance = -1;
  assert.equal(issueOf(objects), "InvalidInlineObjectAdvance");
  objects.inlineObjects[0].advance = 1;
  objects.inlineObjects[0].ascent = Number.NaN;
  assert.equal(issueOf(objects), "InvalidInlineObjectVerticalGeometry");
  const decorations = request();
  decorations.decorations = [{ start: 3, end: 2, kind: "Underline" }];
  assert.equal(issueOf(decorations), "InvalidDecorationRange");
});
