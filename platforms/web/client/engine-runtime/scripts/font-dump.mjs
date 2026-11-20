// Font cutover parity dumper. Imports one implementation of the two font
// exports (old: ./runtime/Tiqian-tiqian-ffi-js.mjs Kotlin runtime; new:
// ./runtime/facade.mjs aggregate facade), applies a fixed fixture list, and
// writes the answers as JSON lines so the two runs can be diffed line by
// line.
//
//   node ./scripts/font-dump.mjs <module-url> <out-path>
//
// The fixtures cover the retired Kotlin test cases (FontExportsTest.kt) plus
// fractional size families around
// them; on the retired runtime the fractional sizes carry f32-grid artifacts
// (TCN-45), so old-vs-new diffs are expected exactly there.

import { writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const moduleUrl = process.argv[2];
const outPath = process.argv[3];
if (moduleUrl === undefined || outPath === undefined) {
  console.error("usage: node ./scripts/font-dump.mjs <module-url> <out-path>");
  process.exit(2);
}
const font = await import(pathToFileURL(moduleUrl).href);

const sizeFixtures = [16, 16.1, 0.3, 1234.5678, 100, Number.NaN];
const roleFixtures = [
  "CjkText",
  "CjkPunctuation",
  "LatinText",
  "Symbol",
  "Emoji",
  "Unknown",
  "Bogus",
];
const lines = [];
for (const size of sizeFixtures) {
  for (const role of roleFixtures) {
    const request = {
      fontKey: "k",
      fontSize: size,
      role,
      locale: "zh-Hans",
      fontFamilies: ["A", "B"],
      fontWeight: 700,
      italic: true,
      faceSelectionText: "face",
    };
    let out;
    try {
      out = font.fontMetricsResolve(JSON.stringify(request));
    } catch (error) {
      out = "THROW:" + error.constructor.name;
    }
    lines.push(JSON.stringify(["metrics", size, role, out]));
  }
}

const fallbackFixtures = [
  ["汉字", 0, 2, "zh-Hans", { preferredFamilies: ["Noto Serif CJK SC"], locale: "zh-Hans", role: "CjkText" }],
  ["Hello", 0, 5, "en", { preferredFamilies: [], locale: "en", role: "LatinText" }],
  ["A——B中文……下句", 1, 2, "zh-Hans", { preferredFamilies: ["F"], locale: "zh-Hans", role: "Unknown" }],
  ["，。", 0, 1, "zh-Hans", { preferredFamilies: ["F"], locale: "zh-Hans", role: "CjkPunctuation" }],
  ["mixed文", 5, 6, "zh-Hans", {}],
  ["x", 0, 1, "en", null],
];
for (const [text, start, end, locale, request] of fallbackFixtures) {
  let out;
  try {
    out = font.fontFallbackResolve(text, start, end, request === null ? "null" : JSON.stringify(request));
  } catch (error) {
    out = "THROW:" + error.constructor.name;
  }
  lines.push(JSON.stringify(["fallback", text, start, end, locale, JSON.stringify(request), out]));
}

await writeFile(outPath, lines.join("\n") + "\n");
