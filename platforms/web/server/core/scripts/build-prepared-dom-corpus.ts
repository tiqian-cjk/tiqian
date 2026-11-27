// Prepared DOM lowering golden corpus (ADR 0050).
//
// Builds the shared fixture consumed by the parity lanes: the js test
// `platforms/web/client/web-component/tests/prepared-dom-corpus.test.ts` and the
// shared-renderer replay in `snapshot-bundle-data-corpus.test.ts`. The js module
// `prepared-dom.js` is the oracle; regenerating the fixture is deliberate:
//
//   node scripts/build-prepared-dom-corpus.ts   (from platforms/web/server/core)

import { writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { renderPreparedParagraphArtifact } from "../../../client/web-component/prepared-dom.js";

const here: string = dirname(fileURLToPath(import.meta.url));

interface CellExtra {
  leadingLayoutAdvance?: number;
  advance?: number;
  shapingBoundary?: boolean;
  openTypeFeatures?: string[];
  dashStrategy?: string;
  shapingLanguage?: string;
  resolvedFace?: string;
  glyphIds?: string;
  shapingEvidence?: string;
  renderFontFamily?: string;
  punctuationInkFloor?: number;
  punctuationBodyWidth?: number;
  style?: { fontSize: number; fontWeight: number };
  latin?: boolean;
  inlineObject?: number;
}

interface PlanCell {
  rangeStart: number;
  rangeEnd: number;
  source: string;
  display: string;
  drawX: number;
  naturalWidth: number;
  leadingLayoutAdvance: number;
  [key: string]: unknown;
}

interface LineOptions {
  rangeStart?: number;
  rangeEnd?: number;
  top?: number;
  bottom?: number;
  baseline?: number;
  indent?: number;
  visualWidth?: number;
  hyphenAdvance?: number;
  endReason?: string;
}

interface PlanLine {
  rangeStart: number;
  rangeEnd: number;
  top: number;
  bottom: number;
  baseline: number;
  indent: number;
  visualWidth: number;
  hyphenAdvance: number;
  endReason: string;
  cells: PlanCell[];
}

interface LayoutPlan {
  schema: number;
  layoutRevision: string;
  width: number;
  height: number;
  lines: PlanLine[];
  emphasisRanges?: [number, number][];
  inlineEdges?: { offset: number; inlineEnd: number }[];
  spacingCarrierAdvances?: { rangeStart: number; rangeEnd: number; advance: number }[];
  rubyDecisions?: {
    baseRangeStart: number;
    baseRangeEnd: number;
    text: string;
    fontSize: number;
    fontWeight: number;
    centerX: number;
    baselineY: number;
    fontFamilies: string[];
    ascent?: number;
  }[];
  bopomofoDecisions?: {
    baseRangeStart: number;
    baseRangeEnd: number;
    text: string;
    fontWeight: number;
    fontFamilies: string[];
    placements: { role: string; text: string; left: number; top: number; width: number; height: number }[];
  }[];
  fontSize?: number;
  overlayWidth?: number;
  decorationSegments?: { kind: string; left: number; top: number; right: number }[];
  emphasisDots?: { clusterRangeStart?: number; anchorX: number; anchorY: number; dotDiameter: number }[];
}

interface SemanticOption {
  start: number;
  end: number;
  tagName: string;
  attributes?: [string, string][];
}

interface RenderTextSpanOption {
  start: number;
  end: number;
  fontFamilies: string[];
}

interface InlineBoxOption {
  start: number;
  end: number;
  inlineStartPx: number;
  inlineEndPx: number;
}

interface CjkStrongSemanticEntry {
  start: number;
  end: number;
  weight: number;
}

interface CaseOptions {
  styleClassFor?: string;
  emphasisDotColor?: string;
  semantics?: SemanticOption[];
  renderTextSpans?: RenderTextSpanOption[];
  inlineBoxes?: InlineBoxOption[];
  cjkStrongSemantics?: CjkStrongSemanticEntry[];
}

interface CorpusCase {
  name: string;
  plan: LayoutPlan;
  locale: string;
  options: CaseOptions;
  expectError?: string;
}

interface FixtureResultOk {
  kind: "ok";
  html: string;
  artifact: string;
  liveSemanticCount: number;
  markerCount: number;
}

interface FixtureResultError {
  kind: "error";
  error: string;
}

type FixtureResult = FixtureResultOk | FixtureResultError;

interface FixtureEntry {
  name: string;
  plan: string;
  locale: string;
  options: CaseOptions;
  expect: FixtureResult;
}

interface Fixture {
  cases: FixtureEntry[];
}

function plan(lines: PlanLine[], height: number = 48, width: number = 320): LayoutPlan {
  return { schema: 1, layoutRevision: "tiqian-layout-v2", width, height, lines };
}

function cell(rangeStart: number, rangeEnd: number, source: string, display: string, drawX: number, naturalWidth: number, extra: CellExtra = {}): PlanCell {
  const { leadingLayoutAdvance = 0, ...rest } = extra;
  return { rangeStart, rangeEnd, source, display, drawX, naturalWidth, leadingLayoutAdvance, ...rest };
}

function line(cells: PlanCell[], options: LineOptions = {}): PlanLine {
  return {
    rangeStart: options.rangeStart ?? cells[0]?.rangeStart ?? 0,
    rangeEnd: options.rangeEnd ?? cells.at(-1)?.rangeEnd ?? 0,
    top: options.top ?? 0,
    bottom: options.bottom ?? 32,
    baseline: options.baseline ?? 24,
    indent: options.indent ?? 0,
    visualWidth: options.visualWidth ?? (cells.length ? cells.at(-1)!.drawX + cells.at(-1)!.naturalWidth : 0),
    hyphenAdvance: options.hyphenAdvance ?? 0,
    endReason: options.endReason ?? "ParagraphEnd",
    cells,
  };
}

const STYLE_CLASS_MODES: Record<string, (declaration: string) => string> = {
  "declaration-length": (declaration: string): string => `tqc-${declaration.length}`,
};

const EMPHASIS_DOT_COLOR_MODES: Record<string, () => string> = {
  "fixed-color": (): string => "rgb(17, 34, 51)",
};

const cases: CorpusCase[] = [
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
    name: "inline-spacing-carrier",
    plan: {
      ...plan([
        line([
          cell(0, 5, "Hello", "Hello", 0, 40),
          cell(5, 10, "World", "World", 52, 44),
          cell(10, 11, "中", "中", 100, 16),
        ], { visualWidth: 120 }),
      ]),
      spacingCarrierAdvances: [{ rangeStart: 0, rangeEnd: 11, advance: 4.5 }],
    },
    locale: "zh-Hans",
    options: { semantics: [{ start: 0, end: 10, tagName: "u" }] },
  },
  {
    name: "inline-spacing-carrier-with-classes",
    plan: {
      ...plan([
        line([
          cell(0, 5, "Hello", "Hello", 0, 40),
          cell(5, 10, "World", "World", 52, 44),
        ], { visualWidth: 96 }),
      ]),
      spacingCarrierAdvances: [{ rangeStart: 0, rangeEnd: 10, advance: 4.5 }],
    },
    locale: "zh-Hans",
    options: { styleClassFor: "declaration-length" },
  },
  {
    name: "inline-spacing-carrier-evidence-face",
    plan: {
      ...plan([
        line([
          cell(0, 2, "——", "——", 0, 32, { renderFontFamily: "Dash Evidence" }),
          cell(2, 3, "中", "中", 36, 16),
          cell(3, 4, "文", "文", 52, 16),
        ], { visualWidth: 68 }),
      ]),
      spacingCarrierAdvances: [{ rangeStart: 0, rangeEnd: 4, advance: 4.5 }],
    },
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
    // FloatDustSpacingZeroing: justified lines can carry real stretch of a
    // few thousandths of a pixel per cluster boundary. The gap must survive
    // as letter spacing so the accumulated flow still matches the plan.
    name: "justified-sub-epsilon-stretch",
    plan: plan([
      line([
        cell(0, 1, "排", "排", 0, 16),
        cell(1, 2, "版", "版", 16.004795074462894, 16),
        cell(2, 3, "引", "引", 32.00959014892579, 16),
      ], { endReason: "AutoWrap", visualWidth: 48.00959014892579 }),
    ]),
    locale: "zh-Hans",
    options: {},
  },
  {
    // Arithmetic dust below SPACING_DUST_EPSILON still zeroes so plain lines
    // do not emit letter-spacing for float residue.
    name: "float-dust-gap",
    plan: plan([
      line([
        cell(0, 1, "排", "排", 0, 16),
        cell(1, 2, "版", "版", 16.0000000000005, 16),
      ], { visualWidth: 32.0000000000005 }),
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
      line([cell(0, 2, "\u{1F600}", "\u{1F600}", 0, 16, { shapingBoundary: true })]),
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
      line([cell(0, 1, "\u3000", " ", 0, 16)]),
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
  {
    name: "dash-evidence-attributes",
    plan: plan([
      line([
        cell(0, 1, "\u2014", "\u2014", 0, 18, {
          dashStrategy: "ReplaceEmDash",
          shapingLanguage: "zh-Hans",
          resolvedFace: "FaceA",
          glyphIds: "71,72",
          shapingEvidence: "ShapingReason",
          renderFontFamily: "Han Face",
        }),
      ], { bottom: 27, baseline: 20 }),
    ], 27),
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "dash-run-isolates-punctuation",
    plan: plan([
      line([
        cell(0, 1, "前", "前", 0, 18),
        cell(1, 2, "\u2014", "\u2014", 18, 18, {
          dashStrategy: "ReplaceEmDash",
          punctuationInkFloor: 2.5,
          punctuationBodyWidth: 16,
        }),
        cell(2, 3, "后", "后", 36, 18),
      ], { bottom: 27, baseline: 20 }),
    ], 27),
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "style-delta-split",
    plan: plan([
      line([
        cell(0, 1, "甲", "甲", 0, 18),
        cell(1, 2, "乙", "乙", 18, 18, { style: { fontSize: 12, fontWeight: 700 } }),
        cell(2, 3, "丙", "丙", 36, 18),
      ], { bottom: 27, baseline: 20 }),
    ], 27),
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "latin-emphasis-italic",
    plan: {
      ...plan([
        line([
          cell(0, 1, "A", "A", 0, 10, { latin: true }),
        ], { bottom: 27, baseline: 20 }),
      ], 27),
      emphasisRanges: [[0, 1]],
    },
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "latin-no-emphasis-italic",
    plan: {
      ...plan([
        line([
          cell(1, 2, "B", "B", 0, 10, { latin: true }),
        ], { bottom: 27, baseline: 20 }),
      ], 27),
      emphasisRanges: [[0, 1]],
    },
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "inline-object-placeholder-keeps-flow",
    plan: plan([
      line([
        cell(0, 1, "\uFFFC", "\uFFFC", 0, 18, { inlineObject: 18 }),
        cell(1, 2, "字", "字", 18, 18),
      ], { bottom: 27, baseline: 20, visualWidth: 36 }),
    ], 27),
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "plan-inline-edges-precedence",
    plan: {
      ...plan([
        line([
          cell(0, 1, "前", "前", 0, 18),
          cell(1, 2, "后", "后", 22, 18),
        ], { bottom: 27, baseline: 20, visualWidth: 40 }),
      ], 27),
      inlineEdges: [{ offset: 1, inlineEnd: 4 }],
    },
    locale: "zh-Hans",
    options: {
      inlineBoxes: [{ start: 1, end: 1, inlineStartPx: 0, inlineEndPx: 10 }],
    },
  },
  {
    name: "ruby-annotation",
    plan: {
      ...plan([
        line([
          cell(0, 1, "京", "京", 0, 18),
        ], { bottom: 27, baseline: 20, visualWidth: 18 }),
      ], 27),
      rubyDecisions: [{
        baseRangeStart: 0,
        baseRangeEnd: 1,
        text: "B\u011Bij\u012Bng",
        fontSize: 10,
        fontWeight: 500,
        centerX: 9,
        baselineY: 5,
        fontFamilies: ["Ruby Face"],
      }],
    },
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "bopomofo-annotation",
    plan: {
      ...plan([
        line([
          cell(0, 1, "只", "只", 0, 18, { advance: 24 }),
        ], { bottom: 27, baseline: 20, visualWidth: 24 }),
      ], 27),
      bopomofoDecisions: [{
        baseRangeStart: 0,
        baseRangeEnd: 1,
        text: "\u3113\u02C7",
        fontWeight: 500,
        fontFamilies: ["Bopomofo Face"],
        placements: [
          { role: "Symbol", text: "\u3113", left: 0, top: 2, width: 6, height: 8 },
          { role: "Tone", text: "\u02C7", left: 6, top: 2, width: 4, height: 8 },
        ],
      }],
    },
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "interlinear-and-dot-overlays",
    plan: {
      ...plan([
        line([
          cell(0, 1, "中", "中", 0, 18),
        ], { bottom: 27, baseline: 20, visualWidth: 18 }),
      ], 27),
      fontSize: 20,
      overlayWidth: 120,
      decorationSegments: [
        { kind: "ProperNoun", left: 0, top: 20, right: 60 },
        { kind: "BookTitle", left: 60, top: 20, right: 120 },
      ],
      emphasisDots: [
        { anchorX: 10, anchorY: 25, dotDiameter: 5 },
      ],
    },
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "error-overlay-geometry",
    plan: {
      ...plan([
        line([
          cell(0, 1, "中", "中", 0, 18),
        ], { bottom: 27, baseline: 20, visualWidth: 18 }),
      ], 27),
      decorationSegments: [
        { kind: "ProperNoun", left: 0, top: 20, right: 60 },
      ],
    },
    locale: "zh-Hans",
    options: {},
    expectError: "InvalidPreparedOverlayGeometry",
  },
  {
    name: "ruby-annotation-plan-ascent",
    plan: {
      ...plan([
        line([
          cell(0, 1, "京", "京", 0, 18),
        ], { bottom: 27, baseline: 20, visualWidth: 18 }),
      ], 27),
      rubyDecisions: [{
        baseRangeStart: 0,
        baseRangeEnd: 1,
        text: "B\u011Bij\u012Bng",
        fontSize: 10,
        fontWeight: 500,
        centerX: 9,
        baselineY: 5,
        fontFamilies: ["Ruby Face"],
        ascent: 7,
      }],
    },
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "emphasis-dot-color",
    plan: {
      ...plan([
        line([
          cell(0, 1, "中", "中", 0, 18),
        ], { bottom: 27, baseline: 20, visualWidth: 18 }),
      ], 27),
      fontSize: 20,
      overlayWidth: 120,
      emphasisDots: [
        { clusterRangeStart: 0, anchorX: 10, anchorY: 25, dotDiameter: 5 },
        { clusterRangeStart: 1, anchorX: 50, anchorY: 25, dotDiameter: 5 },
      ],
    },
    locale: "zh-Hans",
    options: { emphasisDotColor: "fixed-color" },
  },
  {
    name: "cjk-emphasis-attribute",
    plan: {
      ...plan([
        line([
          cell(0, 1, "排", "排", 0, 16),
          cell(1, 2, "版", "版", 16, 16),
        ]),
      ]),
      emphasisRanges: [[0, 2]],
    },
    locale: "zh-Hans",
    options: {
      semantics: [{ start: 0, end: 2, tagName: "strong" }],
      cjkStrongSemantics: [{ start: 0, end: 2, weight: 700 }],
    },
  },
  {
    name: "second-line-indent",
    plan: plan([
      line([
        cell(0, 1, "甲", "甲", 0, 16),
        cell(1, 2, "乙", "乙", 16, 16),
      ], { endReason: "AutoWrap" }),
      line([
        cell(2, 3, "丙", "丙", 32, 16),
      ], { top: 32, bottom: 64, baseline: 56, indent: 32 }),
    ]),
    locale: "zh-Hans",
    options: {},
  },
  {
    name: "style-delta-three-lines",
    plan: plan([
      line([
        cell(0, 1, "甲", "甲", 0, 16),
      ], { endReason: "AutoWrap" }),
      line([
        cell(1, 2, "乙", "乙", 0, 16, { style: { fontSize: 12, fontWeight: 700 } }),
      ], { top: 32, bottom: 64, baseline: 56, endReason: "AutoWrap" }),
      line([
        cell(2, 3, "丙", "丙", 0, 16),
      ], { top: 64, bottom: 96, baseline: 88 }),
    ]),
    locale: "zh-Hans",
    options: {
      semantics: [{ start: 0, end: 3, tagName: "em" }],
    },
  },
  {
    name: "inline-edges-and-render-text-span",
    plan: {
      ...plan([
        line([
          cell(0, 1, "c", "c", 0, 8),
          cell(1, 2, "o", "o", 8, 8),
          cell(2, 3, "d", "d", 16, 8),
          cell(3, 4, "e", "e", 24, 8),
          cell(4, 5, "排", "排", 32, 16),
        ]),
      ]),
      inlineEdges: [{ offset: 1, inlineEnd: 4 }],
    },
    locale: "zh-Hans",
    options: {
      renderTextSpans: [{ start: 0, end: 4, fontFamilies: ["Fira Code", " Mono "] }],
    },
  },
];

const fixture: Fixture = { cases: [] };
for (const entry of cases) {
  const { name, plan: planValue, locale, options, expectError } = entry;
  const styleMode: string | undefined = options.styleClassFor;
  const dotColorMode: string | undefined = options.emphasisDotColor;
  const callOptions: Record<string, unknown> = { ...options };
  delete callOptions.styleClassFor;
  delete callOptions.emphasisDotColor;
  if (styleMode !== undefined) callOptions.styleClassFor = STYLE_CLASS_MODES[styleMode];
  if (dotColorMode !== undefined) callOptions.emphasisDotColor = EMPHASIS_DOT_COLOR_MODES[dotColorMode];
  let expect: FixtureResult;
  try {
    const lowered = renderPreparedParagraphArtifact(JSON.stringify(planValue), locale, callOptions as Record<string, unknown>);
    if (expectError !== undefined) throw new Error(`expected error ${expectError}, got a render`);
    expect = {
      kind: "ok",
      html: lowered.html,
      artifact: JSON.stringify(lowered.artifact),
      liveSemanticCount: lowered.liveSemanticCount,
      markerCount: lowered.markerCount,
    };
  } catch (error: unknown) {
    if (expectError === undefined) throw error;
    const message = error instanceof Error ? error.message : String(error);
    if (message !== expectError) {
      throw new Error(`case ${name}: expected ${expectError}, got ${message}`, { cause: error });
    }
    expect = { kind: "error", error: message };
  }
  fixture.cases.push({ name, plan: JSON.stringify(planValue), locale, options, expect });
}

const target: string = resolve(here, "../../../client/web-component/tests/prepared-dom-corpus.fixture.json");
writeFileSync(target, `${JSON.stringify(fixture, null, 2)}\n`);
console.log(`wrote ${fixture.cases.length} cases to ${target}`);
