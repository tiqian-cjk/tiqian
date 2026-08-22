// Prepared DOM lowering golden corpus (ADR 0050).
//
// Builds the shared fixture consumed by BOTH parity lanes: the Rust
// integration test `rust/tiqian-precompute/tests/prepared_dom_corpus.rs` and
// the js test `frontend/web/npm/prepared-dom-corpus.test.mjs`. The js module
// `prepared-dom.js` is the oracle; regenerating the fixture is deliberate:
//
//   node scripts/build-prepared-dom-corpus.mjs   (from frontend/web-precompute)

import { writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { renderPreparedParagraphArtifact } from "../../web/npm/prepared-dom.js";

const here = dirname(fileURLToPath(import.meta.url));

function plan(lines, height = 48, width = 320) {
  return { schema: 1, layoutRevision: "tiqian-layout-v2", width, height, lines };
}

function cell(rangeStart, rangeEnd, source, display, drawX, naturalWidth, extra = {}) {
  const { leadingLayoutAdvance = 0, ...rest } = extra;
  return { rangeStart, rangeEnd, source, display, drawX, naturalWidth, leadingLayoutAdvance, ...rest };
}

function line(cells, options = {}) {
  return {
    rangeStart: options.rangeStart ?? cells[0]?.rangeStart ?? 0,
    rangeEnd: options.rangeEnd ?? cells.at(-1)?.rangeEnd ?? 0,
    top: options.top ?? 0,
    bottom: options.bottom ?? 32,
    baseline: options.baseline ?? 24,
    indent: options.indent ?? 0,
    visualWidth: options.visualWidth ?? (cells.length ? cells.at(-1).drawX + cells.at(-1).naturalWidth : 0),
    hyphenAdvance: options.hyphenAdvance ?? 0,
    endReason: options.endReason ?? "ParagraphEnd",
    cells,
  };
}

const STYLE_CLASS_MODES = {
  "declaration-length": (declaration) => `tqc-${declaration.length}`,
};

const cases = [
  {
    name: "plain-merge",
    plan: plan([
      line([
        cell(0, 1, "排", "排", 0, 16),
        cell(1, 2, "版", "版", 16, 16),
        cell(2, 3, "引", "引", 32, 16),
      ]),
    ]),
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "letter-spacing-merge",
    plan: plan([
      line([
        cell(0, 1, "排", "排", 0, 16),
        cell(1, 2, "版", "版", 16.5, 16),
        cell(2, 3, "引", "引", 33, 16),
      ], { visualWidth: 49.5 }),
    ]),
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "letter-spacing-with-classes",
    plan: plan([
      line([
        cell(0, 1, "排", "排", 0, 16),
        cell(1, 2, "版", "版", 16.5, 16),
      ], { visualWidth: 32.5 }),
    ]),
    locale: "zh-Hans",
    options: { styleClassFor: "declaration-length" },
  },
  {
    name: "overlap-margin",
    plan: plan([
      line([
        cell(0, 1, "排", "排", 0, 16),
        cell(1, 2, "版", "版", 15.5, 16),
      ], { visualWidth: 31.5 }),
    ]),
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "trailing-letter-carrier",
    plan: plan([
      line([cell(0, 2, "排版", "排版", 0, 16)], { visualWidth: 16.4 }),
    ]),
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "dyadic-tie-px",
    plan: plan([
      line([cell(0, 1, "排", "排", 0, 16)], { visualWidth: 16.015625 }),
    ]),
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "semantics-nested",
    plan: plan([
      line([
        cell(0, 1, "强", "强", 0, 16),
        cell(1, 2, "大", "大", 16, 16),
        cell(2, 3, "的", "的", 32, 16),
        cell(3, 4, "排", "排", 48, 16),
        cell(4, 5, "版", "版", 64, 16),
      ]),
    ]),
    locale: "zh-Hans",
    options: {
      semantics: [
        { start: 0, end: 5, tagName: "strong" },
        { start: 1, end: 3, tagName: "em" },
      ],
    },
  },
  {
    name: "semantic-anchor-attributes",
    plan: plan([
      line([
        cell(0, 1, "入", "入", 0, 16),
        cell(1, 2, "口", "口", 16, 16),
        cell(2, 3, "在", "在", 32, 16),
      ]),
    ]),
    locale: "zh-Hans",
    options: {
      semantics: [
        { start: 1, end: 2, tagName: "a", attributes: [["title", "入口"], ["href", "/entry"], ["class", "x"]] },
      ],
    },
  },
  {
    name: "render-text-span-projection",
    plan: plan([
      line([
        cell(0, 1, "c", "c", 0, 8),
        cell(1, 2, "o", "o", 8, 8),
        cell(2, 3, "d", "d", 16, 8),
        cell(3, 4, "e", "e", 24, 8),
        cell(4, 5, "排", "排", 32, 16),
      ]),
    ]),
    locale: "zh-Hans",
    options: {
      renderTextSpans: [{ start: 0, end: 4, fontFamilies: ["Fira Code", " Mono "] }],
    },
  },
  {
    name: "inline-box-edges",
    plan: plan([
      line([
        cell(0, 2, "甲", "甲", 0, 10, { leadingLayoutAdvance: 3 }),
        cell(2, 4, "乙", "乙", 15, 10),
      ], { visualWidth: 25 }),
    ]),
    locale: "zh-Hans",
    options: {
      inlineBoxes: [{ start: 0, end: 2, inlineStartPx: 3, inlineEndPx: 2 }],
    },
  },
  {
    name: "hyphen-locale-gap",
    plan: plan([
      line([cell(0, 2, "示例", "示例", 0, 32)], { visualWidth: 36, hyphenAdvance: 8 }),
    ]),
    locale: "zh-Hant",
    options: {},
  },
  {
    name: "mandatory-break",
    plan: plan([
      line([
        cell(0, 1, "甲", "甲", 0, 16),
        cell(1, 2, "乙", "乙", 16, 16),
      ], { endReason: "MandatoryBreak" }),
      line([
        cell(2, 3, "丙", "丙", 0, 16),
      ], { top: 32, bottom: 64, baseline: 56 }),
    ]),
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "soft-wrap-br",
    plan: plan([
      line([
        cell(0, 1, "甲", "甲", 0, 16),
        cell(1, 2, "乙", "乙", 16, 16),
      ], { endReason: "AutoWrap" }),
      line([
        cell(2, 3, "丙", "丙", 0, 16),
      ], { top: 32, bottom: 64, baseline: 56 }),
    ]),
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "crossing-boundary",
    plan: plan([
      line([
        cell(0, 1, "甲", "甲", 0, 16),
        cell(1, 2, "乙", "乙", 16, 16),
      ], { endReason: "AutoWrap" }),
      line([
        cell(2, 3, "丙", "丙", 0, 16),
        cell(3, 4, "丁", "丁", 16, 16),
      ], { top: 32, bottom: 64, baseline: 56 }),
    ]),
    locale: "zh-Hans",
    options: {
      semantics: [{ start: 0, end: 4, tagName: "em" }],
    },
  },
  {
    name: "shaping-boundary",
    plan: plan([
      line([cell(0, 2, "😀", "😀", 0, 16, { shapingBoundary: true })]),
    ]),
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "open-type-features",
    plan: plan([
      line([cell(0, 1, "1", "1", 0, 8, { openTypeFeatures: ["pwid", "palt"] })]),
    ]),
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "open-type-features-full-width",
    plan: plan([
      line([cell(0, 1, "1", "1", 0, 8, { openTypeFeatures: ["fwid"] })]),
    ]),
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "source-display-diff",
    plan: plan([
      line([cell(0, 1, "　", " ", 0, 16)]),
    ]),
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "empty-line",
    plan: plan([line([])]),
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "error-leading-layout-advance",
    plan: plan([
      line([
        cell(0, 1, "甲", "甲", 0, 16, { leadingLayoutAdvance: 3 }),
        cell(1, 2, "乙", "乙", 16, 16),
      ]),
    ]),
    locale: "zh-Hans",
    options: {
      inlineBoxes: [{ start: 0, end: 1, inlineStartPx: 5, inlineEndPx: 0 }],
    },
    expectError: "SnapshotRenderFlowMismatch:line=0;leading-layout-advance",
  },
  {
    name: "error-layout-revision",
    plan: { ...plan([line([cell(0, 1, "排", "排", 0, 16)])]), layoutRevision: "tiqian-layout-v1" },
    locale: "zh-Hans",
    options: {},
    expectError: "UnsupportedPreparedLayoutRevision",
  },
  {
    name: "error-open-type-features",
    plan: plan([
      line([cell(0, 1, "1", "1", 0, 8, { openTypeFeatures: ["pwid"] })]),
    ]),
    locale: "zh-Hans",
    options: {},
    expectError: "UnsupportedPreparedOpenTypeFeatures: pwid",
  },
  {
    name: "error-conflicting-render-text-span",
    plan: plan([
      line([cell(0, 2, "甲乙", "甲乙", 0, 32)]),
    ]),
    locale: "zh-Hans",
    options: {
      renderTextSpans: [
        { start: 0, end: 2, fontFamilies: ["A"] },
        { start: 0, end: 2, fontFamilies: ["B"] },
      ],
    },
    expectError: "ConflictingPreparedRenderTextSpan",
  },
  {
    name: "error-invalid-render-text-span",
    plan: plan([
      line([cell(0, 2, "甲乙", "甲乙", 0, 32)]),
    ]),
    locale: "zh-Hans",
    options: {
      renderTextSpans: [{ start: 0, end: 99, fontFamilies: ["A"] }],
    },
    expectError: "InvalidPreparedRenderTextSpan",
  },
];

const fixture = { cases: [] };
for (const entry of cases) {
  const { name, plan: planValue, locale, options, expectError } = entry;
  const styleMode = options.styleClassFor;
  const callOptions = { ...options };
  delete callOptions.styleClassFor;
  if (styleMode) callOptions.styleClassFor = STYLE_CLASS_MODES[styleMode];
  let expect;
  try {
    const lowered = renderPreparedParagraphArtifact(JSON.stringify(planValue), locale, callOptions);
    if (expectError) throw new Error(`expected error ${expectError}, got a render`);
    expect = {
      kind: "ok",
      html: lowered.html,
      artifact: JSON.stringify(lowered.artifact),
      liveSemanticCount: lowered.liveSemanticCount,
      markerCount: lowered.markerCount,
    };
  } catch (error) {
    if (!expectError) throw error;
    if (error.message !== expectError) {
      throw new Error(`case ${name}: expected ${expectError}, got ${error.message}`);
    }
    expect = { kind: "error", error: error.message };
  }
  fixture.cases.push({ name, plan: JSON.stringify(planValue), locale, options, expect });
}

const target = resolve(here, "../../web/npm/prepared-dom-corpus.fixture.json");
writeFileSync(target, `${JSON.stringify(fixture, null, 2)}\n`);
console.log(`wrote ${fixture.cases.length} cases to ${target}`);
