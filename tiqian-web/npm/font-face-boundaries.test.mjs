import assert from "node:assert/strict";
import test from "node:test";

import {
  mergeSerializedSourceBoundaries,
  workerExactSubsetSourceBoundaries,
} from "./font-face-boundaries.js";

function face(sourceOrder, unicodeRange, publicUrl) {
  return {
    family: "MiSans VF",
    localNames: ["MiSans VF"],
    style: "normal",
    weight: [100, 900],
    unicodeRange,
    publicUrl,
    faceIndex: 0,
    sourceOrder,
  };
}

test("Worker recreates an exact subset boundary between Latin and curly-quote shards", () => {
  const faces = [
    face(0, "U+0041-005A", "/fonts/latin.woff2"),
    face(1, "U+201D", "/fonts/punctuation.woff2"),
  ];
  const request = {
    text: "B”",
    fontFamilies: "MiSans VF\u001fui-sans-serif",
    fontSizePx: 18,
    fontWeight: 460,
    italic: false,
    textSpans: "",
  };

  assert.deepEqual(workerExactSubsetSourceBoundaries(faces, request), [1]);
  assert.equal(mergeSerializedSourceBoundaries("", [1]), "1");
});

test("Worker subset boundaries preserve DOM style boundaries and UTF-16 offsets", () => {
  const faces = [
    face(0, "U+0041-005A", "/fonts/latin.woff2"),
    face(1, "U+201D", "/fonts/punctuation.woff2"),
  ];
  const request = {
    text: "B”B",
    fontFamilies: "MiSans VF",
    fontSizePx: 18,
    fontWeight: 460,
    italic: false,
    textSpans: [
      "2",
      "3",
      "MiSans VF",
      "18",
      "700",
      "false",
      "0",
    ].join("\u001d"),
  };

  assert.deepEqual(workerExactSubsetSourceBoundaries(faces, request), [1, 2]);
  assert.equal(mergeSerializedSourceBoundaries("2,0", [1, 2]), "0,1,2");
});

test("Worker follows CSS source order when subset declarations overlap", () => {
  const faces = [
    face(0, "U+0041-005A", "/fonts/latin-a.woff2"),
    face(1, "U+0042", "/fonts/latin-b.woff2"),
  ];
  const request = {
    text: "AB",
    fontFamilies: "MiSans VF",
    fontSizePx: 18,
    fontWeight: 460,
    italic: false,
    textSpans: "",
  };

  assert.deepEqual(workerExactSubsetSourceBoundaries(faces, request), [1]);
});

test("Worker does not require a font face for zero-width soft-break controls", () => {
  const faces = [
    face(0, "U+0041-005A", "/fonts/latin.woff2"),
    face(1, "U+201D", "/fonts/punctuation.woff2"),
  ];
  const request = {
    text: "B\u200B”",
    fontFamilies: "MiSans VF",
    fontSizePx: 18,
    fontWeight: 460,
    italic: false,
    textSpans: "",
  };

  assert.deepEqual(workerExactSubsetSourceBoundaries(faces, request), [2]);
});

test("Worker does not require font coverage for mandatory-break controls", () => {
  const faces = [
    face(0, "U+4E00-9FFF", "/fonts/cjk.woff2"),
  ];
  const request = {
    text: "甲\n\v\f\r\u0085\u2028\u2029乙",
    fontFamilies: "MiSans VF",
    fontSizePx: 18,
    fontWeight: 460,
    italic: false,
    textSpans: "",
  };

  assert.deepEqual(workerExactSubsetSourceBoundaries(faces, request), []);
});

test("Worker preserves UTF-16 face boundaries across CRLF", () => {
  const faces = [
    face(0, "U+4E00-9FFF", "/fonts/cjk.woff2"),
    face(1, "U+0041-005A", "/fonts/latin.woff2"),
  ];
  const request = {
    text: "甲\r\nB",
    fontFamilies: "MiSans VF",
    fontSizePx: 18,
    fontWeight: 460,
    italic: false,
    textSpans: "",
  };

  assert.deepEqual(workerExactSubsetSourceBoundaries(faces, request), [3]);
});
