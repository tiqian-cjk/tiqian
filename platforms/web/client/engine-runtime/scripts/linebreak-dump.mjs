// Line-break cutover parity dumper. Imports one implementation of the two
// line-break exports (old: ./runtime/Tiqian-tiqian-ffi-js.mjs Kotlin runtime;
// new: ./runtime/facade.mjs aggregate facade), applies a fixed fixture list,
// and writes the answers as JSON so the two runs can be diffed byte for byte.
//
//   node ./scripts/linebreak-dump.mjs <module-url> <out-json>
//
// The fixtures cover the retired Kotlin test cases (LineBreakExportsTest.kt)
// plus margin, exception-case and
// class-name families around them.

import { writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const moduleUrl = process.argv[2];
const outPath = process.argv[3];
if (moduleUrl === undefined || outPath === undefined) {
  console.error("usage: node ./scripts/linebreak-dump.mjs <module-url> <out-json>");
  process.exit(2);
}
const linebreak = await import(pathToFileURL(moduleUrl).href);

const patternFixtures = [
  `{"c":[1,0]}`,
  `{"at1":[0,0,4,0]}`,
  `{"表":[1]}`,
  `{}`,
];
const exceptionFixtures = [
  `{}`,
  `{"table":[2]}`,
  `{"tt":1}`,
];
const wordFixtures = [
  "abc",
  "cab",
  "table",
  "Table",
  "hyphenation",
  "tt",
  "表意文字",
];

const classCodePoints = [
  0x0028, // OpenPunctuation
  0x0029, // CloseParenthesis
  0x002B, // Exclamation
  0x002D, // Hyphen
  0x2014, // break-after dash family
  0x201C, // Quotation
  0x3001, // break-after CJK punctuation
  0xFF08, // OpenPunctuation
  0xFF09, // ClosePunctuation
  0x4E2D, // Other
  0x0030, // Numeric family
];

const dump = { hyphenate: [], classOf: [], throws: [] };
for (const word of wordFixtures) {
  for (const patterns of patternFixtures) {
    for (const exceptions of exceptionFixtures) {
      for (const margins of [[1, 1], [2, 3]]) {
        dump.hyphenate.push({
          word, patterns, exceptions, leftMin: margins[0], rightMin: margins[1],
          answer: linebreak.liangHyphenate(word, patterns, exceptions, margins[0], margins[1]),
        });
      }
    }
  }
}
for (const codePoint of classCodePoints) {
  dump.classOf.push({ codePoint, answer: linebreak.unicodePunctuationLineBreakClassOf(codePoint) });
}
for (const bad of [-1, 0x10FFFF + 1, 0xD800, 0xDFFF]) {
  try {
    const answer = linebreak.unicodePunctuationLineBreakClassOf(bad);
    dump.throws.push({ codePoint: bad, threw: false, answer });
  } catch (error) {
    dump.throws.push({ codePoint: bad, threw: true, name: error.name, message: error.message });
  }
}
await writeFile(outPath, JSON.stringify(dump, null, 1) + "\n");
console.log("wrote", outPath);
