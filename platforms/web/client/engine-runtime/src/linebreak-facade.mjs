// The line-break capability exports of `@tiqian/ffi`, served directly by the
// single-source generated tree under ../engine-gen (copied by hand from the
// bundle driver product engine-haxe/out/ts/gen; do not edit the vendored
// files). The JSON-through-JavaScript wire matches the retired Kotlin/JS
// exports: pattern/exception data enters as JSON strings, break offsets leave
// as a JSON array string, and line-break classes leave as their published
// class names.

import { LiangHyphenator } from "./engine-gen/org/tiqian/linebreak/LiangHyphenator.js";
import { SortedTable } from "./engine-gen/runtime.js";
import { UnicodePunctuationLineBreak } from "./engine-gen/org/tiqian/linebreak/UnicodePunctuationLineBreak.js";

/**
 * Decodes one JSON object of `{ patternKey: number[] }` into the generated
 * sorted table the single-source hyphenator reads. Coercions mirror the
 * retired Kotlin decoder: a null document is an empty table, a non-array
 * value is an empty level list, and a non-numeric level (including NaN)
 * becomes 0.
 */
function toPatternTable(json) {
  const raw = JSON.parse(json);
  if (raw === null || raw === undefined || typeof raw !== "object") {
    return SortedTable.mapBuilder(SortedTable.compareStrings).build();
  }
  const builder = SortedTable.mapBuilder(SortedTable.compareStrings);
  for (const key of Object.keys(raw)) {
    const levels = Array.isArray(raw[key]) ? raw[key] : [];
    builder.put(key, levels.map((level) => typeof level === "number" ? (Number.isNaN(level) ? 0 : Math.trunc(level)) : 0));
  }
  return builder.build();
}

/**
 * Hyphenates `word` with Frank Liang's algorithm using JSON-encoded
 * `patternsJson` (map from pattern key to inter-letter level array) and
 * `exceptionsJson` (map from lowercased word to explicit break offsets).
 * `leftMin`/`rightMin` keep the engine defaults. Returns a JSON array of
 * break offsets (codepoint indices, ascending), e.g. `"[2]"`.
 */
export function liangHyphenate(word, patternsJson, exceptionsJson, leftMin = 2, rightMin = 3) {
  const hyphenator = new LiangHyphenator(
    toPatternTable(patternsJson),
    toPatternTable(exceptionsJson),
    leftMin,
    rightMin,
  );
  return JSON.stringify([...hyphenator.hyphenate(word)]);
}

/**
 * Returns the UAX #14 punctuation line-break class name for `codePoint`
 * (e.g. `"OpenPunctuation"`, `"CloseParenthesis"`, `"Other"`). Requires a
 * Unicode scalar value; throws on surrogates per the engine contract.
 */
export function unicodePunctuationLineBreakClassOf(codePoint) {
  try {
    return UnicodePunctuationLineBreak.classOf(codePoint).kind;
  } catch (error) {
    // Wire translation: the single-source engine raises
    // TiqianIllegalArgumentException; the retired Kotlin/JS export surfaced
    // the same message as an IllegalArgumentException, so the JSON-through-
    // JavaScript contract keeps that observable shape.
    if (error instanceof Error && error.name === "TiqianIllegalArgumentException") {
      const translated = new Error(error.message);
      translated.name = "IllegalArgumentException";
      throw translated;
    }
    throw error;
  }
}