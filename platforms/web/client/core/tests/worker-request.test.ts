import assert from "node:assert/strict";
import test from "node:test";

import type {
  LoweredParagraph,
  TextStyle,
  TextSpan,
  DecorationSpan,
  InlineBoxSpan,
  InlineObjectSpan,
  DomSourceSpan,
  LineBreakSpan,
} from "../src/engine/lowered-paragraph.js";
import {
  buildWorkerLayoutRequest,
  workerLayoutRequestForRoot,
  workerLayoutRequest,
} from "../src/engine/worker-request.js";
import { effectiveLineMeasure } from "../src/engine/responsive-measure.js";
import { InlineShapingStylePolicy } from "@tiqian/engine/org/tiqian/font/InlineShapingStylePolicy";


function asType<T>(value: unknown): T {
  return value as T;
}

const ROOT_SELECTOR: string = "tiqian-prose, [data-tiqian-root]";

// The responsive measure helpers, the eligibility predicate and the lifecycle
// helpers are all real now: sourceParagraphWidth reads element geometry and
// globalThis.getComputedStyle, effectiveLineMeasure is imported above,
// shouldTryParagraph reads plain element properties, and the snapshot gate,
// withRootDefaults and conformingSnapshotFontSessionId run from the stateless
// lifecycle module. No module seam exists anymore.

interface TextStyleOverrides {
  fontFamilies?: string[];
  fontSize?: number;
  fontWeight?: number;
  italic?: boolean;
  baselineShift?: number;
  locale?: string;
}

interface SpanOverrides {
  start?: number;
  end?: number;
  style?: TextStyle;
}

interface InlineBoxStyleOverrides {
  inlineStart?: number;
  inlineEnd?: number;
  marginRight?: number;
  letterSpacing?: number;
  boxDecorationBreak?: string;
}

interface DomInlineBoxStyle {
  inlineStart: number;
  inlineEnd: number;
  marginRight: number;
  letterSpacing: number;
  boxDecorationBreak: string;
}

interface ElementAttribute {
  name: string;
  value: string;
}

interface SourceSpanOverrides {
  start?: number;
  end?: number;
  element?: Element;
  depth?: number;
  cjkStrongBaseWeight?: number | null;
  computedColor?: string | null;
  inlineBoxStyle?: DomInlineBoxStyle;
}

interface ParagraphOverrides {
  text?: string;
  textStyle?: TextStyle;
  lineHeight?: number;
  spans?: TextSpan[];
  decorations?: DecorationSpan[];
  inlineBoxes?: InlineBoxSpan[];
  inlineObjects?: InlineObjectSpan[];
  domInlineObjects?: never[];
  sourceSpans?: DomSourceSpan[];
  sourceBoundaries?: number[];
  lineBreakSpans?: LineBreakSpan[];
}

interface ElementOverrides {
  width?: number;
  _computedValues?: Record<string, string>;
}

type GetBoundingClientRectFn = () => DOMRectLike;
type GetClientRectsFn = () => ClientRectListLike;

interface FakeElement {
  tagName: string;
  getBoundingClientRect: GetBoundingClientRectFn;
  getClientRects: GetClientRectsFn;
  parentElement: null;
  _computedValues?: Record<string, string>;
}

interface DOMRectLike {
  width: number;
}

interface ClientRectListLike {
  length: number;
}

const EMPTY_CLIENT_RECT_LIST: ClientRectListLike = { length: 0 };

// Helper to cast test fakes to Element at call sites (single assertion).
function asElement(fake: unknown): Element {
  return fake as Element;
}

interface FontFamilyOptions {
  cjk: null;
  latin: null;
  monospace: null;
  cjkSerif: null;
  latinSerif: null;
}

interface SnapshotFontSession {
  status: string;
  sessionId: string;
  detail: null;
}

interface EnhanceOptionsOverrides {
  fontFamilies?: FontFamilyOptions;
  fontSize?: null;
  lineHeight?: null;
  firstLineIndentIc?: number;
  emphasisDotGapEm?: number;
  strongAsEmphasisMarks?: boolean;
  paragraphSelector?: string;
  cjkDashCapability?: null;
  snapshotFontSession?: SnapshotFontSession | null;
  requireSnapshotLayoutWorker?: boolean;
}

interface EnhanceOptions {
  fontFamilies: FontFamilyOptions;
  fontSize: null;
  lineHeight: null;
  firstLineIndentIc: number;
  emphasisDotGapEm: number;
  strongAsEmphasisMarks: boolean;
  paragraphSelector: string;
  cjkDashCapability: null;
  snapshotFontSession: SnapshotFontSession | null;
  requireSnapshotLayoutWorker: boolean;
}

interface ComputedStyleValues {
  paddingLeft?: string;
  paddingRight?: string;
  borderLeftWidth?: string;
  borderRightWidth?: string;
  position?: string;
  transform?: string;
  marginLeft?: string;
  marginRight?: string;
  marginTop?: string;
  marginBottom?: string;
  display?: string;
  "text-transform"?: string;
  "font-style"?: string;
  "font-family"?: string;
  "font-size"?: string;
}

type GetPropertyValueFn = (name: string) => string;

interface ComputedStyleDouble {
  paddingLeft: string;
  paddingRight: string;
  borderLeftWidth: string;
  borderRightWidth: string;
  position: string;
  transform: string;
  marginLeft: string;
  marginRight: string;
  marginTop: string;
  marginBottom: string;
  getPropertyValue: GetPropertyValueFn;
}

interface TextSpanDto {
  start: number;
  end: number;
  families: string[];
  fontSizePx: number;
  fontWeight: number;
  italic: boolean;
  baselineShift: number;
}

interface InlineBoxDto {
  start: number;
  end: number;
  inlineStart: number;
  inlineEnd: number;
  outerSpacing: string;
}

interface LineBreakSpanDto {
  start: number;
  end: number;
  policy: string;
}

interface InlineObjectDto {
  start: number;
  end: number;
  advance: number;
  ascent: number;
  descent: number;
}

interface SemanticsEntry {
  start: number;
  end: number;
  tagName: string;
  attributes: string[][];
  sourceIndex: number;
  order: number;
}

interface RenderInlineBoxDto {
  start: number;
  end: number;
  inlineStartPx: number;
  inlineEndPx: number;
  outerSpacing: string;
}

interface WorkerRequestDto {
  text: string;
  maxWidthPx: number;
  fontFamilies: string[];
  fontSizePx: number;
  lineHeightPx: number;
  locale: string;
  fontWeight: number;
  italic: boolean;
  firstLineIndentIc: number;
  lineLengthGridEnabled: boolean;
  sourceBoundaries: number[];
  textSpans: TextSpanDto[];
  inlineBoxes: InlineBoxDto[];
  lineBreakSpans: LineBreakSpanDto[];
  inlineObjects: InlineObjectDto[];
  renderEvidence: boolean;
  semantics: SemanticsEntry[];
  renderInlineBoxes: RenderInlineBoxDto[];
  sourceTag: string;
}

interface RootParagraphOverrides {
  tagName?: string;
  text?: string;
  owner?: FakeNode | null;
  childNodes?: ChildNodesType;
  width?: number;
  computedValues?: Record<string, string>;
}

interface FakeTextNode {
  nodeType: number;
  textContent: string;
}

type GetAttributeFn = () => null;
type SetAttributeFn = () => void;
type RemoveAttributeFn = () => void;
type HasAttributeFn = () => boolean;
type MatchesFn = () => boolean;
type QuerySelectorFn = () => null;
type QuerySelectorAllFn = () => never[];
type GetClientRectsNodeFn = () => ClientRectListLike;
type ClosestFn = (selector: string) => FakeNode | null;
type GetBoundingClientRectNodeFn = () => DOMRectLike;
type IteratorFn = () => Iterator<FakeTextNode | FakeNode>;

interface IterableChildNodes {
  [Symbol.iterator]: IteratorFn;
}

type ChildNodesType = (FakeTextNode | FakeNode)[] | IterableChildNodes;

interface NodeStyle {
  getPropertyValue: GetPropertyValueFn;
  getPropertyPriority?: GetPropertyValueFn;
  setProperty?: SetAttributeFn;
  removeProperty?: RemoveAttributeFn;
}

interface FakeNode {
  nodeType?: number;
  tagName: string;
  textContent?: string;
  childNodes?: ChildNodesType;
  attributes?: never[];
  getAttribute: GetAttributeFn;
  setAttribute?: SetAttributeFn;
  removeAttribute?: RemoveAttributeFn;
  hasAttribute?: HasAttributeFn;
  matches?: MatchesFn;
  querySelector?: QuerySelectorFn;
  querySelectorAll?: QuerySelectorAllFn;
  getClientRects?: GetClientRectsNodeFn;
  style?: NodeStyle;
  closest?: ClosestFn;
  getBoundingClientRect?: GetBoundingClientRectNodeFn;
  parentElement?: null;
  _computedValues?: Record<string, string>;
  [Symbol.iterator]?: IteratorFn;
}

type ContainsFn = () => boolean;
type GetComputedStyleFn = (elt: Element, pseudoElt?: string | null) => CSSStyleDeclaration;
type FnWithReturn<T> = () => T;

interface ScopeRoot {
  tagName: string;
  contains: ContainsFn;
  closest?: ClosestFn;
  getBoundingClientRect?: GetBoundingClientRectNodeFn;
  _computedValues?: Record<string, string>;
}

function textStyle(overrides: TextStyleOverrides = {}): TextStyle {
  return {
    fontFamilies: ["Noto Serif CJK SC"],
    fontSize: 19,
    fontWeight: 400,
    italic: false,
    baselineShift: 0,
    locale: "zh-Hans",
    ...overrides,
  };
}

function makeTextSpan(overrides: SpanOverrides = {}): TextSpan {
  return {
    start: 0,
    end: 2,
    style: textStyle(),
    ...overrides,
  };
}

function inlineBoxStyle(overrides: InlineBoxStyleOverrides = {}): DomInlineBoxStyle {
  return {
    inlineStart: 0,
    inlineEnd: 0,
    marginRight: 0,
    letterSpacing: 0,
    boxDecorationBreak: "slice",
    ...overrides,
  };
}

function makeSourceSpan(overrides: SourceSpanOverrides = {}): DomSourceSpan {
  const baseElementPartial: Partial<Element> = {
    tagName: "EM",
  };
  const baseElement = baseElementPartial as Element;
  return {
    start: overrides.start ?? 0,
    end: overrides.end ?? 2,
    element: overrides.element ?? baseElement,
    depth: overrides.depth ?? 0,
    cjkStrongBaseWeight: overrides.cjkStrongBaseWeight ?? null,
    computedColor: overrides.computedColor ?? null,
    inlineBoxStyle: overrides.inlineBoxStyle ?? inlineBoxStyle(),
  };
}

function paragraph(overrides: ParagraphOverrides = {}): LoweredParagraph {
  return {
    text: "ab",
    textStyle: textStyle(),
    lineHeight: 28,
    spans: [],
    decorations: [],
    inlineBoxes: [],
    inlineObjects: [],
    domInlineObjects: [],
    sourceSpans: [],
    sourceBoundaries: [],
    lineBreakSpans: [],
    ...overrides,
  };
}

// Fake element used by workerLayoutRequest (sourceParagraphWidth reads
// getBoundingClientRect/getClientRects) and by workerLayoutRequestJson
// (sourceTag reads tagName).
function element(tagName: string = "P", overrides: ElementOverrides = {}): FakeElement {
  return {
    tagName,
    getBoundingClientRect: (): DOMRectLike => ({ width: overrides.width ?? 320 }),
    getClientRects: (): ClientRectListLike => EMPTY_CLIENT_RECT_LIST,
    parentElement: null,
    ...overrides,
  };
}

// Canonical EnhanceOptions decoded by hand (the real optionsFromJs lives in
// the stateless lifecycle module).
function canonicalOptions(overrides: EnhanceOptionsOverrides = {}): EnhanceOptions {
  return {
    fontFamilies: {
      cjk: null,
      latin: null,
      monospace: null,
      cjkSerif: null,
      latinSerif: null,
    },
    fontSize: null,
    lineHeight: null,
    firstLineIndentIc: 0,
    emphasisDotGapEm: 0.1,
    strongAsEmphasisMarks: false,
    paragraphSelector: "p, li",
    cjkDashCapability: null,
    snapshotFontSession: { status: "conforming", sessionId: "s1", detail: null },
    requireSnapshotLayoutWorker: false,
    ...overrides,
  };
}

// Computed style double: property accessors feed elementContentWidth, the
// getPropertyValue callback feeds the lowerer's computedStyle reads.
function computedStyle(values: ComputedStyleValues = {}): ComputedStyleDouble {
  const style: ComputedStyleDouble = {
    paddingLeft: "0px",
    paddingRight: "0px",
    borderLeftWidth: "0px",
    borderRightWidth: "0px",
    position: "static",
    transform: "none",
    marginLeft: "0px",
    marginRight: "0px",
    marginTop: "0px",
    marginBottom: "0px",
    getPropertyValue: (name: string): string => {
      const key: string = String(name).toLowerCase();
      return Object.prototype.hasOwnProperty.call(values, key)
        ? String(values[key as keyof ComputedStyleValues])
        : "";
    },
  };
  return style;
}

function withComputedStyle<T>(fn: FnWithReturn<T>): T {
  const real: GetComputedStyleFn = globalThis.getComputedStyle;
  globalThis.getComputedStyle = ((target: EventTarget, pseudo?: string): CSSStyleDeclaration => {
    const typedTarget = target as FakeElement & EventTarget;
    const result: ComputedStyleDouble = typedTarget && typedTarget._computedValues
      ? computedStyle(typedTarget._computedValues)
      : computedStyle();
    return result as CSSStyleDeclaration;
  }) as GetComputedStyleFn;
  try {
    return fn();
  } finally {
    globalThis.getComputedStyle = real;
  }
}

// Rich fixture exercising every wire field: quoted text with a control char,
// two multi-family spans with non-integral floats, one inline box, one inline
// object, a bogus line-break policy, two source spans with attributes, and
// unsorted duplicate source boundaries.
const RICH_PARAGRAPH_ELEMENT = element("P") as FakeElement & Element;

// Create fake Element objects for source spans with proper attributes array.
const emElementAttrs = [{ name: "class", value: "x" }];
const emElementObj = {
  tagName: "EM",
  getAttribute: (name: string): string | null => {
    const attr = emElementAttrs.find((a) => a.name === name);
    return attr ? attr.value : null;
  },
  attributes: emElementAttrs,
};
const emElement = emElementObj as typeof emElementObj & Element;

const spanElementAttrs = [
  { name: "data-x", value: "y" },
  { name: "title", value: "t" },
];
const spanElementObj = {
  tagName: "SPAN",
  getAttribute: (name: string): string | null => {
    const attr = spanElementAttrs.find((a) => a.name === name);
    return attr ? attr.value : null;
  },
  attributes: spanElementAttrs,
};
const spanElement = spanElementObj as typeof spanElementObj & Element;

const RICH_LOWERED: LoweredParagraph = paragraph({
  text: 'a"b\u0001c',
  textStyle: textStyle({ fontFamilies: ["Serif A", "Serif B"] }),
  sourceBoundaries: [4, 2, 8, 2, 4],
  spans: [
    makeTextSpan({
      start: 0,
      end: 4,
      style: textStyle({
        fontFamilies: ["A", "B"],
        fontSize: 12.5,
        fontWeight: 500,
        italic: true,
        baselineShift: 1.5,
      }),
    }),
    makeTextSpan({
      start: 4,
      end: 8,
      style: textStyle({
        fontFamilies: ["C"],
        fontSize: 13.25,
        fontWeight: 600,
        italic: false,
        baselineShift: 0,
      }),
    }),
  ],
  inlineBoxes: [{ start: 8, end: 10, inlineStart: 1.5, inlineEnd: 2.25 }],
  lineBreakSpans: [{ start: 2, end: 6, policy: "BOGUS" }],
  inlineObjects: [{ start: 10, end: 11, advance: 6.5, ascent: 5, descent: 1.25 }],
  sourceSpans: [
    makeSourceSpan({
      start: 0,
      end: 2,
      element: emElement,
      depth: 1,
    }),
    makeSourceSpan({
      start: 2,
      end: 4,
      element: spanElement,
      depth: 2,
    }),
  ],
});

const RICH_EXPECTED: WorkerRequestDto = {
  text: 'a"b\u0001c',
  maxWidthPx: 678.9,
  fontFamilies: ["Serif A", "Serif B"],
  fontSizePx: 19,
  lineHeightPx: 28,
  locale: "zh-Hans",
  fontWeight: 400,
  italic: false,
  firstLineIndentIc: 2,
  lineLengthGridEnabled: true,
  sourceBoundaries: [2, 4, 8],
  textSpans: [
    {
      start: 0,
      end: 4,
      families: ["A", "B"],
      fontSizePx: 12.5,
      fontWeight: 500,
      italic: true,
      baselineShift: 1.5,
    },
    {
      start: 4,
      end: 8,
      families: ["C"],
      fontSizePx: 13.25,
      fontWeight: 600,
      italic: false,
      baselineShift: 0,
    },
  ],
  inlineBoxes: [
    { start: 8, end: 10, inlineStart: 1.5, inlineEnd: 2.25, outerSpacing: "Narrow" },
  ],
  lineBreakSpans: [
    { start: 2, end: 6, policy: "ProgressiveTechnical" },
  ],
  inlineObjects: [
    { start: 10, end: 11, advance: 6.5, ascent: 5, descent: 1.25 },
  ],
  renderEvidence: true,
  semantics: [
    { start: 0, end: 2, tagName: "em", attributes: [["class", "x"]], sourceIndex: 0, order: 1 },
    { start: 2, end: 4, tagName: "span", attributes: [["data-x", "y"], ["title", "t"]], sourceIndex: 1, order: 2 },
  ],
  renderInlineBoxes: [
    { start: 8, end: 10, inlineStartPx: 1.5, inlineEndPx: 2.25, outerSpacing: "Narrow" },
  ],
  sourceTag: "p",
};

test("buildWorkerLayoutRequest emits the whole wire request DTO for a rich fixture", () => {
  const actual: WorkerRequestDto = buildWorkerLayoutRequest(
    RICH_PARAGRAPH_ELEMENT,
    RICH_LOWERED,
    678.9,
    2,
  );
  assert.deepEqual(actual, RICH_EXPECTED);
});

test("buildWorkerLayoutRequest DTO shape has correct textSpans array with typed objects", () => {
  const actual: WorkerRequestDto = buildWorkerLayoutRequest(
    RICH_PARAGRAPH_ELEMENT,
    RICH_LOWERED,
    678.9,
    2,
  );
  assert.ok(Array.isArray(actual.textSpans));
  assert.equal(actual.textSpans.length, 2);
  for (const spanItem of actual.textSpans) {
    assert.ok(typeof spanItem.start === "number");
    assert.ok(typeof spanItem.end === "number");
    assert.ok(Array.isArray(spanItem.families));
    assert.ok(typeof spanItem.fontSizePx === "number");
    assert.ok(typeof spanItem.fontWeight === "number");
    assert.ok(typeof spanItem.italic === "boolean");
    assert.ok(typeof spanItem.baselineShift === "number");
  }
  // Verify member order preserved
  assert.deepEqual(actual.textSpans[0].families, ["A", "B"]);
  assert.deepEqual(actual.textSpans[1].families, ["C"]);
});

test("buildWorkerLayoutRequest DTO shape has correct inlineBoxes with Narrow outerSpacing", () => {
  const actual: WorkerRequestDto = buildWorkerLayoutRequest(
    RICH_PARAGRAPH_ELEMENT,
    RICH_LOWERED,
    678.9,
    2,
  );
  assert.ok(Array.isArray(actual.inlineBoxes));
  assert.equal(actual.inlineBoxes.length, 1);
  assert.equal(actual.inlineBoxes[0].outerSpacing, "Narrow");
});

test("buildWorkerLayoutRequest DTO shape has correct lineBreakSpans with ProgressiveTechnical policy", () => {
  const actual: WorkerRequestDto = buildWorkerLayoutRequest(
    RICH_PARAGRAPH_ELEMENT,
    RICH_LOWERED,
    678.9,
    2,
  );
  assert.ok(Array.isArray(actual.lineBreakSpans));
  assert.equal(actual.lineBreakSpans.length, 1);
  assert.equal(actual.lineBreakSpans[0].policy, "ProgressiveTechnical");
});

test("buildWorkerLayoutRequest DTO shape has correct inlineObjects", () => {
  const actual: WorkerRequestDto = buildWorkerLayoutRequest(
    RICH_PARAGRAPH_ELEMENT,
    RICH_LOWERED,
    678.9,
    2,
  );
  assert.ok(Array.isArray(actual.inlineObjects));
  assert.equal(actual.inlineObjects.length, 1);
  assert.equal(actual.inlineObjects[0].advance, 6.5);
  assert.equal(actual.inlineObjects[0].ascent, 5);
  assert.equal(actual.inlineObjects[0].descent, 1.25);
});

test("buildWorkerLayoutRequest DTO carries semantics with verbatim attributes and lowercased tagName", () => {
  const actual: WorkerRequestDto = buildWorkerLayoutRequest(
    RICH_PARAGRAPH_ELEMENT,
    RICH_LOWERED,
    678.9,
    2,
  );
  assert.ok(Array.isArray(actual.semantics));
  assert.equal(actual.semantics.length, 2);
  assert.deepEqual(actual.semantics[0].attributes, [["class", "x"]]);
  assert.deepEqual(actual.semantics[1].attributes, [["data-x", "y"], ["title", "t"]]);
  assert.equal(actual.semantics[0].tagName, "em");
  assert.equal(actual.semantics[1].tagName, "span");
  assert.equal(actual.sourceTag, "p");
});

test("buildWorkerLayoutRequest DTO carries true render evidence for a sourceSpans-only lowered", () => {
  const lowered: LoweredParagraph = paragraph({
    sourceSpans: [makeSourceSpan()],
  });
  const actual: WorkerRequestDto = buildWorkerLayoutRequest(RICH_PARAGRAPH_ELEMENT, lowered, 678.9, 2);
  assert.equal(actual.renderEvidence, true);
});

test("buildWorkerLayoutRequest DTO render evidence: spans-only yields true, plain yields false", () => {
  const styled: LoweredParagraph = paragraph({ spans: [makeTextSpan()] });
  const styledActual: WorkerRequestDto = buildWorkerLayoutRequest(RICH_PARAGRAPH_ELEMENT, styled, 678.9, 2);
  assert.equal(styledActual.renderEvidence, true);

  const plain: LoweredParagraph = paragraph();
  const plainActual: WorkerRequestDto = buildWorkerLayoutRequest(RICH_PARAGRAPH_ELEMENT, plain, 678.9, 2);
  assert.equal(plainActual.renderEvidence, false);
});

test("workerLayoutRequest returns null without a conforming snapshot font session", () => {
  const nonConforming: EnhanceOptions = canonicalOptions({
    snapshotFontSession: { status: "unavailable", sessionId: "s1", detail: null },
  });
  assert.equal(workerLayoutRequest(element() as Element, paragraph(), nonConforming), null);
  const omitted: EnhanceOptions = canonicalOptions({ snapshotFontSession: null });
  assert.equal(workerLayoutRequest(element() as Element, paragraph(), omitted), null);
});

test("workerLayoutRequest returns null for a decorated paragraph", () => {
  withComputedStyle((): void => {
    const lowered: LoweredParagraph = paragraph({
      decorations: [{ start: 0, end: 2, kind: "Emphasis" }],
    });
    assert.equal(workerLayoutRequest(element() as Element, lowered, canonicalOptions()), null);
  });
});

test("workerLayoutRequest returns null for a clone edge at the inclusive epsilon", () => {
  withComputedStyle((): void => {
    const lowered: LoweredParagraph = paragraph({
      sourceSpans: [
        makeSourceSpan({ inlineBoxStyle: inlineBoxStyle({ boxDecorationBreak: "clone", inlineStart: 0.01 }) }),
      ],
    });
    assert.equal(workerLayoutRequest(element() as Element, lowered, canonicalOptions()), null);
  });
});

test("workerLayoutRequest builds for clone boxes below the epsilon", () => {
  withComputedStyle((): void => {
    const lowered: LoweredParagraph = paragraph({
      sourceSpans: [
        makeSourceSpan({
          inlineBoxStyle: inlineBoxStyle({ boxDecorationBreak: "clone", inlineStart: 0.005, inlineEnd: -0.005 }),
        }),
      ],
    });
    assert.notEqual(workerLayoutRequest(element() as Element, lowered, canonicalOptions()), null);
  });
});

test("workerLayoutRequest builds for a non-clone box with large edges", () => {
  withComputedStyle((): void => {
    const lowered: LoweredParagraph = paragraph({
      sourceSpans: [
        makeSourceSpan({ inlineBoxStyle: inlineBoxStyle({ boxDecorationBreak: "slice", inlineStart: 5, inlineEnd: -5 }) }),
      ],
    });
    assert.notEqual(workerLayoutRequest(element() as Element, lowered, canonicalOptions()), null);
  });
});

test("workerLayoutRequest returns null for a locale-mismatching span", () => {
  withComputedStyle((): void => {
    const lowered: LoweredParagraph = paragraph({
      spans: [makeTextSpan({ style: textStyle({ locale: "ja" }) })],
    });
    assert.equal(workerLayoutRequest(element() as Element, lowered, canonicalOptions()), null);
  });
});

// The real sourceParagraphWidth falls back to 320 whenever both the paragraph
// and its parent measure non-positive, so raw widths of 0 or negative are
// unreachable through the public API. A non-finite geometry (Infinity) is
// reachable and still trips the same guard.
test("workerLayoutRequest returns null for a non-finite raw width", () => {
  withComputedStyle((): void => {
    const infinite: FakeElement = element("P", { width: Number.POSITIVE_INFINITY });
    assert.equal(workerLayoutRequest(infinite as Element, paragraph(), canonicalOptions()), null);
  });
});

test("workerLayoutRequest emits 0 first-line indent for LI and the option value otherwise", () => {
  withComputedStyle((): void => {
    const li: WorkerRequestDto | null = workerLayoutRequest(
      element("LI") as Element,
      paragraph(),
      canonicalOptions({ firstLineIndentIc: 2 }),
    );
    assert.equal(li!.firstLineIndentIc, 0);

    const nonLi: WorkerRequestDto | null = workerLayoutRequest(
      element("P") as Element,
      paragraph(),
      canonicalOptions({ firstLineIndentIc: 2 }),
    );
    assert.equal(nonLi!.firstLineIndentIc, 2);
  });
});

test("workerLayoutRequest emits the effective line measure as maxWidthPx", () => {
  withComputedStyle((): void => {
    const expected: number = effectiveLineMeasure(320, 19);
    const result: WorkerRequestDto | null = workerLayoutRequest(
      element("P", { width: 320 }) as Element,
      paragraph(),
      canonicalOptions(),
    );
    assert.equal(result!.maxWidthPx, expected);
    // The measure is the fontSize-grid quantized cell, not the raw width.
    assert.notEqual(result!.maxWidthPx, 320);
  });
});

// --- Root overload (workerLayoutRequestForRoot) ---

// The lowering bridge is real now, so the fake paragraph doubles as a
// lowerable DOM: text-only children lower into a plain paragraph, a block
// child fails the formatting context, and an inline child exercises the
// inline-shaping decision callback.
function textNode(text: string): FakeTextNode {
  return { nodeType: 3, textContent: text };
}

function rootParagraph(overrides: RootParagraphOverrides = {}): FakeNode {
  const text: string = overrides.text ?? "hello";
  const owner: FakeNode | null = overrides.owner ?? null;
  return {
    tagName: overrides.tagName ?? "P",
    textContent: text,
    childNodes: overrides.childNodes ?? [textNode(text)],
    getAttribute: (): null => null,
    setAttribute: (): void => {},
    removeAttribute: (): void => {},
    style: {
      setProperty: (): void => {},
      removeProperty: (): void => {},
      getPropertyValue: (): string => "",
      getPropertyPriority: (): string => "",
    },
    closest: (selector: string): FakeNode | null => (selector === ROOT_SELECTOR ? owner : null),
    querySelectorAll: (): never[] => [],
    querySelector: (): null => null,
    getBoundingClientRect: (): DOMRectLike => ({ width: overrides.width ?? 320 }),
    getClientRects: (): ClientRectListLike => EMPTY_CLIENT_RECT_LIST,
    parentElement: null,
    _computedValues: overrides.computedValues,
  };
}

// A block-level child makes the real lowerer fail the formatting context
// with an UnsupportedInlineFormattingContext issue, which the root overload
// must discard and report as null.
function blockChild(tagName: string, text: string): FakeNode {
  return {
    nodeType: 1,
    tagName,
    textContent: text,
    childNodes: [textNode(text)],
    attributes: [],
    getAttribute: (): null => null,
    hasAttribute: (): boolean => false,
    matches: (): boolean => false,
    querySelector: (): null => null,
    querySelectorAll: (): never[] => [],
    getClientRects: (): ClientRectListLike => EMPTY_CLIENT_RECT_LIST,
    style: { getPropertyValue: (): string => "", getPropertyPriority: (): string => "" },
    _computedValues: { display: "block" },
  };
}

// An inline child with an empty client rect list lowers into a sourceSpan
// without needing a Range/document double: measuredInlineEdge returns the
// margin (0) early when the element has no boxes.
function inlineChild(tagName: string, text: string, values: ComputedStyleValues = {}): FakeNode {
  return {
    nodeType: 1,
    tagName,
    textContent: text,
    childNodes: [textNode(text)],
    attributes: [],
    getAttribute: (): null => null,
    hasAttribute: (): boolean => false,
    matches: (): boolean => false,
    querySelector: (): null => null,
    querySelectorAll: (): never[] => [],
    getClientRects: (): ClientRectListLike => EMPTY_CLIENT_RECT_LIST,
    style: { getPropertyValue: (): string => "", getPropertyPriority: (): string => "" },
    _computedValues: { display: "inline", ...values },
  };
}

function scopeRoot(containsResult: boolean = true): ScopeRoot {
  return {
    tagName: "DIV",
    contains: (): boolean => containsResult,
  };
}

test("workerLayoutRequestForRoot returns null when closest resolves to a nested owner under the root", () => {
  const owner: FakeNode = blockChild("SECTION", "nested");
  const root: ScopeRoot = scopeRoot(true);
  const paragraphEl: FakeNode = rootParagraph({ owner });
  assert.equal(
    workerLayoutRequestForRoot(asElement(root), asElement(paragraphEl), canonicalOptions()),
    null,
  );
});

test("workerLayoutRequestForRoot passes the root gate when owner is the root", () => {
  withComputedStyle((): void => {
    const root = scopeRoot();
    // Create a paragraph whose closest returns null (no owner found)
    const paragraphEl: FakeNode = rootParagraph({});
    assert.notEqual(
      workerLayoutRequestForRoot(asElement(root), asElement(paragraphEl), canonicalOptions()),
      null,
    );
  });
});

test("workerLayoutRequestForRoot passes the root gate when no owner is found", () => {
  withComputedStyle((): void => {
    const root: ScopeRoot = scopeRoot();
    const paragraphEl: FakeNode = rootParagraph();
    assert.notEqual(
      workerLayoutRequestForRoot(asElement(root), asElement(paragraphEl), canonicalOptions()),
      null,
    );
  });
});

test("workerLayoutRequestForRoot returns null when shouldTryParagraph is false", () => {
  const blank: FakeNode = rootParagraph({ text: "   ", childNodes: [] });
  assert.equal(
    workerLayoutRequestForRoot(asElement(scopeRoot()), asElement(blank), canonicalOptions()),
    null,
  );
});

test("workerLayoutRequestForRoot returns null when snapshot exact layout is disallowed", () => {
  const paragraphEl: FakeNode = rootParagraph();
  const badFontSize: EnhanceOptions["fontSize"] = asType<EnhanceOptions["fontSize"]>(20);
  const options = canonicalOptions({ fontSize: badFontSize });
  assert.equal(
    workerLayoutRequestForRoot(asElement(scopeRoot()), asElement(paragraphEl), options),
    null,
  );
});

test("workerLayoutRequestForRoot returns null when the lowering bridge throws", () => {
  withComputedStyle((): void => {
    // A child node list whose iterator throws makes the real lowerer throw
    // while walking children; the root overload reports null.
    const throwingChildNodes: IterableChildNodes = {
      [Symbol.iterator]() {
        throw new Error("lowering walk boom");
      },
    };
    const paragraphEl: FakeNode = rootParagraph({
      childNodes: throwingChildNodes,
    });
    assert.equal(
      workerLayoutRequestForRoot(asElement(scopeRoot()), asElement(paragraphEl), canonicalOptions()),
      null,
    );
  });
});

test("workerLayoutRequestForRoot returns null when lowering fails and never reads the issue", () => {
  withComputedStyle((): void => {
    // A block child fails lowering with UnsupportedInlineFormattingContext.
    // The root overload discards the issue result and reports null.
    const paragraphEl: FakeNode = rootParagraph({ childNodes: [blockChild("DIV", "blocked")] });
    assert.equal(
      workerLayoutRequestForRoot(asElement(scopeRoot()), asElement(paragraphEl), canonicalOptions()),
      null,
    );
  });
});

test("workerLayoutRequestForRoot lowers with the fixed zh-Hans locale", () => {
  withComputedStyle((): void => {
    const paragraphEl: FakeNode = rootParagraph({ text: "hello world" });
    // Widen test fakes to unknown before casting to Element for FFI call
    const rootUnknown: unknown = scopeRoot();
    const paragraphElUnknown: unknown = paragraphEl;
    const result: WorkerRequestDto | null = workerLayoutRequestForRoot(
      rootUnknown as Element,
      paragraphElUnknown as Element,
      canonicalOptions(),
    );
    assert.notEqual(result, null);
    assert.equal(result!.locale, "zh-Hans");
  });
});

test("workerLayoutRequestForRoot inlineShapingDecision wraps the ffi divergence result", () => {
  withComputedStyle((): void => {
    // The divergence decision feeds the real firstDivergentInlineShapingProperty
    // over the element and paragraph shaping-value arrays, one value per
    // InlineShapingStylePolicy.unsupportedInlineShapingProperties() position. text-transform is the
    // 15th property (index 14), so a divergent element value there fails the
    // inline element, the paragraph lowers with ok !== true, and the root
    // overload reports null.
    const unsupportedProps: string[] = InlineShapingStylePolicy.unsupportedInlineShapingProperties.slice();
    const paragraphValues: string[] = Array(unsupportedProps.length).fill("");
    const elementValues: string[] = Array(unsupportedProps.length).fill("");
    elementValues[14] = "uppercase";
    assert.equal(InlineShapingStylePolicy.firstDivergentProperty(elementValues, paragraphValues), "text-transform");
    const paragraphEl: FakeNode = rootParagraph({
      childNodes: [inlineChild("EM", "x", { "text-transform": "uppercase" })],
    });
    assert.equal(
      workerLayoutRequestForRoot(asElement(scopeRoot()), asElement(paragraphEl), canonicalOptions()),
      null,
    );
  });
});

test("workerLayoutRequestForRoot inlineShapingDecision returns null for a null divergence property", () => {
  withComputedStyle((): void => {
    const paragraphEl: FakeNode = rootParagraph({
      childNodes: [inlineChild("EM", "x", { "font-style": "italic" })],
    });
    const result: WorkerRequestDto | null = workerLayoutRequestForRoot(
      asElement(scopeRoot()),
      asElement(paragraphEl),
      canonicalOptions(),
    );
    assert.notEqual(result, null);
  });
});

test("workerLayoutRequestForRoot serializes the lowered paragraph into a Worker request DTO", () => {
  withComputedStyle((): void => {
    const paragraphEl: FakeNode = rootParagraph({ text: "hello world" });
    const result: WorkerRequestDto | null = workerLayoutRequestForRoot(
      asElement(scopeRoot()),
      asElement(paragraphEl),
      canonicalOptions(),
    );
    assert.notEqual(result, null);
    assert.equal(result!.text, "hello world");
    assert.equal(result!.firstLineIndentIc, 0);
    assert.equal(result!.sourceTag, "p");
  });
});

test("workerLayoutRequestForRoot feeds the withRootDefaults result into lowering and the request", () => {
  withComputedStyle((): void => {
    // The snapshot-eligible bag resolves through the real withRootDefaults
    // against the root; the paragraph's computed typography then flows into
    // lowering and onto the request wire.
    const root: ScopeRoot = scopeRoot();
    root._computedValues = { "font-family": "Root Inherited, sans-serif" };
    const paragraphEl: FakeNode = rootParagraph({
      text: "hello world",
      computedValues: { "font-size": "21px" },
    });
    const result: WorkerRequestDto | null = workerLayoutRequestForRoot(
      asElement(root),
      asElement(paragraphEl),
      canonicalOptions(),
    );
    assert.notEqual(result, null);
    assert.equal(result!.fontSizePx, 21);
    assert.equal(result!.firstLineIndentIc, 0);
  });
});
