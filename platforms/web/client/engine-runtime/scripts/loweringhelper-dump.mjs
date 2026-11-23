// Lowering-helper cutover parity dumper. Imports one implementation of the
// four lowering-helper exports (old: ./runtime/Tiqian-tiqian-ffi-js.mjs
// Kotlin runtime; new: ./runtime/facade.mjs aggregate facade), applies a
// fixed fixture list, and writes the answers as JSON so the two runs can be
// diffed byte for byte.
//
//   node ./scripts/loweringhelper-dump.mjs <module-url> <out-json>
//
// The fixtures cover the retired Kotlin test cases (the two LoweringHelper
// cases formerly in FontExportsTest.kt,
// the npm test cases in package.test.mts, the 16-property and divergence
// families) plus the TextRange failure names as observed by the old
// Kotlin/JS runtime.

import { writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const moduleUrl = process.argv[2];
const outPath = process.argv[3];
if (moduleUrl === undefined || outPath === undefined) {
  console.error("usage: node ./scripts/loweringhelper-dump.mjs <module-url> <out-json>");
  process.exit(2);
}
const ffi = await import(pathToFileURL(moduleUrl).href);
const {
  classifyFontRole,
  classifyFontRoles,
  unsupportedInlineShapingProperties,
  firstDivergentInlineShapingProperty,
} = ffi;

const entries = [];
function record(fn, label, run) {
  const entry = { fn, label };
  try {
    entry.result = { kind: "value", value: run() };
  } catch (err) {
    const name =
      err instanceof Error && typeof err.name === "string" && err.name !== ""
        ? err.name
        : err instanceof Error
          ? err.constructor.name
          : String(err);
    entry.result = {
      kind: "throw",
      name,
      message: err instanceof Error ? err.message : String(err),
    };
  }
  entries.push(entry);
}

// classifyFontRole: role mapping, contextual dash/quote/ellipsis decisions,
// surrogate and symbol families, empty and out-of-bounds ranges, and the two
// TextRange failure names.
record("classifyFontRole", "cjk-text", () => classifyFontRole("汉字", 0, 2, "zh-Hans"));
record("classifyFontRole", "cjk-punct", () => classifyFontRole("，", 0, 1, "zh-Hans"));
record("classifyFontRole", "latin", () => classifyFontRole("Hello", 0, 5, "en"));
record("classifyFontRole", "dash-latin-neighbors", () => classifyFontRole("A——B", 1, 2, "zh-Hans"));
record("classifyFontRole", "quote-latin-both", () => classifyFontRole("word“中文”word", 4, 5, "zh-Hans"));
record("classifyFontRole", "quote-latin-both-2", () => classifyFontRole("word“中文”word", 7, 8, "zh-Hans"));
record("classifyFontRole", "quote-cjk-both", () => classifyFontRole("中“文”中", 1, 2, "zh-Hans"));
record("classifyFontRole", "dash-cjk-both", () => classifyFontRole("中—文", 1, 2, "zh-Hans"));
record("classifyFontRole", "dash-mixed", () => classifyFontRole("中—B", 1, 2, "zh-Hans"));
record("classifyFontRole", "ellipsis-latin", () => classifyFontRole("a…b", 1, 2, "en"));
record("classifyFontRole", "ellipsis-cjk", () => classifyFontRole("中…文", 1, 2, "zh-Hans"));
record("classifyFontRole", "emoji-surrogate", () => classifyFontRole("😀", 0, 2, "zh-Hans"));
record("classifyFontRole", "symbol", () => classifyFontRole("§", 0, 1, "en"));
record("classifyFontRole", "empty-range", () => classifyFontRole("中", 0, 0, "zh-Hans"));
record("classifyFontRole", "end-beyond-text", () => classifyFontRole("中", 0, 3, "zh-Hans"));
record("classifyFontRole", "start-beyond-text", () => classifyFontRole("中", 5, 7, "zh-Hans"));
record("classifyFontRole", "negative-start", () => classifyFontRole("中", -1, 1, "zh-Hans"));
record("classifyFontRole", "start-gt-end", () => classifyFontRole("中", 1, 0, "zh-Hans"));

// classifyFontRoles: complete-paragraph context per batch, the npm test
// fixtures, the size guard, and the batch failure name.
record("classifyFontRoles", "dash-ellipsis-context", () => classifyFontRoles("A——B中文……下句", [1, 2, 6, 7], [2, 3, 7, 8], "zh-Hans"));
record("classifyFontRoles", "quote-context", () => classifyFontRoles("word“中文”word", [4, 5, 7], [5, 6, 8], "zh-Hans"));
record("classifyFontRoles", "ellipsis-cjk-mixed", () => classifyFontRoles("中文……下句，继续。", [2, 3, 6, 7], [3, 4, 7, 8], "zh-Hans"));
record("classifyFontRoles", "quote-cjk-batch", () => classifyFontRoles("中“文”中。", [1, 2, 3, 4], [2, 3, 4, 5], "zh-Hans"));
record("classifyFontRoles", "size-mismatch", () => classifyFontRoles("A——B中文", [1, 2], [2], "zh-Hans"));
record("classifyFontRoles", "batch-negative-start", () => classifyFontRoles("中文", [-1, 0], [1, 2], "zh-Hans"));

// unsupportedInlineShapingProperties: the pinned 16-name list and order.
record("unsupportedInlineShapingProperties", "call-1", () => unsupportedInlineShapingProperties());
record("unsupportedInlineShapingProperties", "call-2", () => unsupportedInlineShapingProperties());

// firstDivergentInlineShapingProperty: identical, divergence at each of the
// 16 positions, the common-prefix clamps, and the beyond-16 clamp.
const props16 = unsupportedInlineShapingProperties();
record("firstDivergentInlineShapingProperty", "identical", () => firstDivergentInlineShapingProperty(["normal", "normal", "normal"], ["normal", "normal", "normal"]));
for (let i = 0; i < 16; i += 1) {
  const element = props16.map(() => "normal");
  const paragraph = props16.map(() => "normal");
  element[i] = "expanded";
  paragraph[i] = "condensed";
  record("firstDivergentInlineShapingProperty", "diverge@" + i, () => firstDivergentInlineShapingProperty(element, paragraph));
}
record("firstDivergentInlineShapingProperty", "elem-shorter", () => firstDivergentInlineShapingProperty(["normal", "normal"], ["normal", "normal", "expanded"]));
record("firstDivergentInlineShapingProperty", "para-shorter", () => firstDivergentInlineShapingProperty(["normal", "normal", "expanded"], ["normal", "normal"]));
record("firstDivergentInlineShapingProperty", "beyond-16", () => firstDivergentInlineShapingProperty(Array.from({ length: 20 }, (_, i) => (i === 17 ? "x" : "normal")), Array.from({ length: 20 }, (_, i) => (i === 17 ? "y" : "normal"))));
record("firstDivergentInlineShapingProperty", "real-values", () => firstDivergentInlineShapingProperty(["normal", "normal", "expanded"], ["normal", "normal", "condensed"]));

await writeFile(outPath, JSON.stringify(entries, null, 2) + "\n", "utf8");
console.log("dumped " + entries.length + " entries -> " + outPath);
