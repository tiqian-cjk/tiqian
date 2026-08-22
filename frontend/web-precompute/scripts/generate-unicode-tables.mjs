// Generates rust/tiqian-precompute/src/unicode_tables.rs from the Unicode
// property classes of this Node's regex engine. The plain-text issue checks of
// the snapshot orchestration read \p{Extended_Pictographic}, \p{Cf},
// \p{Script=Han} and \p{Script=Common}; the generated range tables keep the
// Rust port on the same data as the js oracle. Regenerate after a Node Unicode
// upgrade and review the diff.
//
// node scripts/generate-unicode-tables.mjs (from frontend/web-precompute)

import { writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const MAX_CODE_POINT = 0x10ffff;

function rangesOf(predicate) {
  const ranges = [];
  let start = -1;
  for (let point = 0; point <= MAX_CODE_POINT; point += 1) {
    const hit = predicate(String.fromCodePoint(point));
    if (hit && start < 0) start = point;
    if (!hit && start >= 0) {
      ranges.push([start, point - 1]);
      start = -1;
    }
  }
  if (start >= 0) ranges.push([start, MAX_CODE_POINT]);
  return ranges;
}

const EXTENDED_PICTOGRAPHIC = /\p{Extended_Pictographic}/u;
const FORMAT = /\p{Cf}/u;
const SCRIPT_HAN = /\p{Script=Han}/u;
const SCRIPT_COMMON = /\p{Script=Common}/u;

function emit(name, source, ranges) {
  const lines = [
    `/// ${source}`,
    `pub static ${name}: &[(u32, u32)] = &[`,
  ];
  for (const [low, high] of ranges) {
    lines.push(`    (0x${low.toString(16)}, 0x${high.toString(16)}),`);
  }
  lines.push("];");
  return lines.join("\n");
}

const body = [
  "//! Generated Unicode range tables for the plain-text issue checks. DO NOT",
  "//! EDIT: regenerate with scripts/generate-unicode-tables.mjs, which reads",
  "//! the property classes of the Node build that runs it.",
  "",
  emit(
    "EXTENDED_PICTOGRAPHIC",
    "The \\\\p{Extended_Pictographic} class.",
    rangesOf((point) => EXTENDED_PICTOGRAPHIC.test(point)),
  ),
  "",
  emit(
    "FORMAT_CHARACTERS",
    "The \\\\p{Cf} class.",
    rangesOf((point) => FORMAT.test(point)),
  ),
  "",
  emit(
    "SCRIPT_HAN",
    "The \\\\p{Script=Han} class.",
    rangesOf((point) => SCRIPT_HAN.test(point)),
  ),
  "",
  emit(
    "SCRIPT_COMMON",
    "The \\\\p{Script=Common} class.",
    rangesOf((point) => SCRIPT_COMMON.test(point)),
  ),
  "",
  "/// True when `point` falls inside one of the table's ranges.",
  "pub fn table_contains(table: &[(u32, u32)], point: u32) -> bool {",
  "    table",
  "        .binary_search_by(|&(low, high)| {",
  "            if point < low {",
  "                std::cmp::Ordering::Greater",
  "            } else if point > high {",
  "                std::cmp::Ordering::Less",
  "            } else {",
  "                std::cmp::Ordering::Equal",
  "            }",
  "        })",
  "        .is_ok()",
  "}",
  "",
].join("\n");

const outPath = resolve(here, "../rust/tiqian-precompute/src/unicode_tables.rs");
writeFileSync(outPath, body);
process.stdout.write(
  `unicode tables: ${outPath} (pictographic, format, han, common)\n`,
);
