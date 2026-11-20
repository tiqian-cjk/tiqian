// Markdown paragraph lowering for the enhance pipeline.
//
// ES module exporting lowerMarkdown() as the single entry point. The lowerer
// returns a plain object carrying either the lowered paragraph
// ({ ok: true, lowered: ... }) or the first capability issue it hit
// ({ ok: false, issue: { name, detail } }).

// Ambient global declarations pulled in via import type from owner modules.
import type {
  TextStyle,
  LoweredParagraph,
  TextSpan,
  DecorationSpan,
  InlineBoxSpan,
  InlineObjectSpan,
  DomInlineObject,
  DomSourceSpan,
  LineBreakSpan,
} from "./lowered-paragraph.js";
import { textStylesEqual } from "./lowered-paragraph.js";
import { isNonTextInlineTag, isOpaqueInlineDisplay, isOpaqueInlineLevelDisplay } from "./eligibility.js";
import {
  appendProjectedStrongStyles,
  type ClassifyRolesFn,
  type PendingStrongTextRange,
} from "./strong-emphasis-lowering.js";

// --- Internal types (module-scoped) ---

/** White-space mode string constant. */
type WhiteSpaceMode = string;

/** Inline style context carried through the lowering tree. */
interface InlineStyleContext {
  textStyle: TextStyle;
  whiteSpace: WhiteSpaceMode;
  cjkStrongBaseWeight: number | null;
}

/** Geometric measurement of an opaque inline object's advance/ascent/descent. */
interface InlineObjectGeometry {
  advance: number;
  ascent: number;
  descent: number;
}

/** Whitespace projection result: projected text plus offset boundary map. */
interface WhitespaceProjection {
  text: string;
  boundaryMap: Int32Array;
}

/** Lowering options passed from the host (mirrors loweringOptionsJs). */
interface LoweringOptions {
  fontSize?: number | null;
  lineHeight?: number | null;
  locale?: string;
  strongAsEmphasisMarks?: boolean;
  [key: string]: unknown;
}

type ClassifyRoleFn = (text: string, start: number, end: number, locale: string) => string;
interface InlineShapingDecisionResult {
  name: string;
  detail: string;
}

type InlineShapingDecisionFn = (
  tag: string,
  elementValues: string[],
  paragraphValues: string[],
) => InlineShapingDecisionResult | null;

/** Inline-shaping helpers provided by the host for role classification. */
interface InlineShapingHelpers {
  classifyRole?: ClassifyRoleFn;
  classifyRoles?: ClassifyRolesFn;
  inlineShapingProperties?: string[];
  inlineShapingDecision?: InlineShapingDecisionFn;
  [key: string]: unknown;
}

/** Minimal DOM-node shape consumed by appendNode in canonicalPreparedPlainSource. */
interface AppendNodeLike {
  readonly nodeType: number;
  textContent: string | null;
  readonly nextSibling: Node | null;
  readonly childNodes: NodeList;
  hasAttribute(name: string): boolean;
  getAttribute(name: string): string | null;
  readonly tagName: string;
}

/** Normalized inline-shaping helpers after null-guarding. */
interface NormalizedInlineShapingHelpers {
  classifyRole: ClassifyRoleFn;
  classifyRoles: ClassifyRolesFn;
  inlineShapingProperties: string[];
  inlineShapingDecision: InlineShapingDecisionFn;
}

/** Mutable lowering issue accumulator (name and detail assigned before read). */
interface LoweringIssue {
  name: string | null;
  detail: string | null;
  [key: string]: unknown;
}

interface LoweringSuccessResult {
  ok: true;
  lowered: LoweredParagraph;
}

interface LoweringFailureResult {
  ok: false;
  issue: LoweringIssue;
}

/** Discriminated union for the lower() return. */
type LoweringResult = LoweringSuccessResult | LoweringFailureResult;

type ProbeAction<T> = () => T;

interface SpanRangeItem {
  start: number;
  end: number;
}

type ProjectedRangeCopyFn<T> = (item: T, range: [number, number]) => T;

// --- End internal types ---

const DEFAULT_FONT_SIZE = 19;
const DEFAULT_LINE_HEIGHT_MULTIPLIER = 1.75;
const INLINE_EDGE_EPSILON = 0.01;
const INLINE_OBJECT_REPLACEMENT_CHAR = "\uFFFC";

const MODE_COLLAPSE = "collapse";
const MODE_COLLAPSE_PRESERVE_BREAKS = "collapse-preserve-breaks";
const MODE_PRESERVE = "preserve";

function computedStyle(element: Element, property: string): string {
  return globalThis.getComputedStyle(element).getPropertyValue(property);
}

function parseCssPx(value: string | null | undefined): number | null {
  if (value === null || value === undefined) return null;
  const trimmed = String(value).trim();
  if (trimmed.length < 2 || trimmed.slice(-2) !== "px") return null;
  const number = Number(trimmed.slice(0, -2).trim());
  return Number.isFinite(number) ? number : null;
}

// NullCoalescingSubstitute: the Kotlin JS parser that validates the
// embedded @JsFun body does not accept the ?? operator, so every
// null-coalescing choice is spelled through this helper instead.
function firstDefined<T>(value: T | null | undefined, fallback: T): T {
  return value !== null && value !== undefined ? value : fallback;
}

function parseCssLineHeight(value: string | null | undefined, fontSize: number): number | null {
  if (value === null || value === undefined) return null;
  const trimmed = String(value).trim();
  const px = parseCssPx(trimmed);
  if (px !== null) return px;
  const number = Number(trimmed);
  return Number.isFinite(number) ? number * fontSize : null;
}

function parseCssFontWeight(value: string | null | undefined): number | null {
  if (value === null || value === undefined) return null;
  const trimmed = String(value).trim().toLowerCase();
  if (trimmed === "normal") return 400;
  if (trimmed === "bold") return 700;
  if (trimmed === "lighter" || trimmed === "bolder") return null;
  const number = Number(trimmed);
  if (!Number.isFinite(number)) return null;
  const weight = Math.trunc(number);
  return Math.min(900, Math.max(1, weight));
}

function parseCssItalic(value: string | null | undefined): boolean | null {
  if (value === null || value === undefined) return null;
  const trimmed = String(value).trim().toLowerCase();
  if (trimmed === "") return null;
  return trimmed.startsWith("italic") || trimmed.startsWith("oblique");
}

function parseCssFontFamilies(value: string): string[] {
  const families: string[] = [];
  let token = "";
  let quote: string | null = null;
  const flush = function () {
    let family = token.trim();
    if (
      family.length >= 2 &&
      family[0] === '"' &&
      family[family.length - 1] === '"'
    ) {
      family = family.slice(1, -1);
    } else if (
      family.length >= 2 &&
      family[0] === "'" &&
      family[family.length - 1] === "'"
    ) {
      family = family.slice(1, -1);
    }
    if (family !== "") families.push(family);
    token = "";
  };
  for (let i = 0; i < value.length; i++) {
    const char = value[i];
    if (quote !== null && char === quote) {
      quote = null;
      token += char;
    } else if (quote !== null) {
      token += char;
    } else if (char === "'" || char === '"') {
      quote = char;
      token += char;
    } else if (char === ",") {
      flush();
    } else {
      token += char;
    }
  }
  flush();
  return families;
}

function cssWhiteSpaceMode(value: string | null | undefined, fallback?: WhiteSpaceMode | null): WhiteSpaceMode {
  if (fallback === null || fallback === undefined) fallback = MODE_COLLAPSE;
  const normalized = String(value).trim().toLowerCase();
  if (
    normalized === "normal" ||
    normalized === "nowrap" ||
    normalized === "collapse" ||
    normalized.startsWith("collapse ")
  ) {
    return MODE_COLLAPSE;
  }
  if (
    normalized === "pre-line" ||
    normalized.startsWith("preserve-breaks")
  ) {
    return MODE_COLLAPSE_PRESERVE_BREAKS;
  }
  if (
    normalized === "pre" ||
    normalized === "pre-wrap" ||
    normalized === "break-spaces" ||
    normalized.startsWith("preserve ")
  ) {
    return MODE_PRESERVE;
  }
  return fallback;
}

function isCssCollapsibleWhitespace(char: string): boolean {
  return char === " " || char === "\t" || char === "\n" || char === "\r" || char === "\u000C";
}

// CssWhiteSpaceCollapseProjection: DOM source formatting is projected through
// the host's 'white-space' semantics before it becomes Tiqian source text.
// Only a real <br> is marked separately as a structural mandatory break.
// The boundary map keeps every projected span's offsets in the source space
// so ranges survive the projection for the returned lower object.
function cssWhiteSpaceCollapseProjection(text: string, modes: WhiteSpaceMode[], hardBreakOffsets: number[]): WhitespaceProjection {
  if (modes.length !== text.length) {
    throw new Error(
      "Whitespace mode count " + modes.length + " must match source length " + text.length,
    );
  }
  const hardBreakSet = new Set();
  for (let hb = 0; hb < hardBreakOffsets.length; hb++) hardBreakSet.add(hardBreakOffsets[hb] as never);
  let projected = "";
  const boundaryMap = new Int32Array(text.length + 1);
  let pendingStart = -1;
  let pendingEnd = -1;

  const resolvePendingWhitespace = function (emit: boolean): void {
    if (pendingStart < 0) return;
    const before = projected.length;
    if (emit && projected.length > 0 && projected[projected.length - 1] !== "\n") {
      projected += " ";
    }
    const after = projected.length;
    boundaryMap[pendingStart] = before;
    for (let boundary = pendingStart + 1; boundary <= pendingEnd; boundary++) {
      boundaryMap[boundary] = after;
    }
    pendingStart = -1;
    pendingEnd = -1;
  };

  const deferCollapsedWhitespace = function (index: number): void {
    if (pendingStart < 0) {
      pendingStart = index;
      boundaryMap[index] = projected.length;
    }
    pendingEnd = index + 1;
  };

  const appendPreserved = function (index: number, char: string): void {
    resolvePendingWhitespace(true);
    boundaryMap[index] = projected.length;
    projected += char;
    boundaryMap[index + 1] = projected.length;
  };

  let index = 0;
  while (index < text.length) {
    if (hardBreakSet.has(index)) {
      resolvePendingWhitespace(false);
      boundaryMap[index] = projected.length;
      projected += "\n";
      boundaryMap[index + 1] = projected.length;
      index += 1;
      continue;
    }
    const char = text[index];
    const mode = modes[index];
    if (mode === MODE_COLLAPSE) {
      if (isCssCollapsibleWhitespace(char)) {
        deferCollapsedWhitespace(index);
      } else {
        appendPreserved(index, char);
      }
      index += 1;
    } else if (mode === MODE_COLLAPSE_PRESERVE_BREAKS) {
      if (char === "\r" || char === "\n") {
        resolvePendingWhitespace(false);
        boundaryMap[index] = projected.length;
        projected += "\n";
        boundaryMap[index + 1] = projected.length;
        if (
          char === "\r" &&
          index + 1 < text.length &&
          text[index + 1] === "\n" &&
          modes[index + 1] === MODE_COLLAPSE_PRESERVE_BREAKS &&
          !hardBreakSet.has(index + 1)
        ) {
          boundaryMap[index + 2] = projected.length;
          index += 2;
        } else {
          index += 1;
        }
      } else if (isCssCollapsibleWhitespace(char)) {
        deferCollapsedWhitespace(index);
        index += 1;
      } else {
        appendPreserved(index, char);
        index += 1;
      }
    } else {
      if (char === "\r") {
        resolvePendingWhitespace(true);
        boundaryMap[index] = projected.length;
        projected += "\n";
        boundaryMap[index + 1] = projected.length;
        if (
          index + 1 < text.length &&
          text[index + 1] === "\n" &&
          modes[index + 1] === MODE_PRESERVE &&
          !hardBreakSet.has(index + 1)
        ) {
          boundaryMap[index + 2] = projected.length;
          index += 2;
        } else {
          index += 1;
        }
      } else {
        appendPreserved(index, char);
        index += 1;
      }
    }
  }
  resolvePendingWhitespace(false);
  boundaryMap[text.length] = projected.length;
  return { text: projected, boundaryMap: boundaryMap };
}

function projectionRange(projection: WhitespaceProjection, start: number, end: number): [number, number] | null {
  const projectedStart = projection.boundaryMap[start];
  const projectedEnd = projection.boundaryMap[end];
  if (projectedEnd > projectedStart) return [projectedStart, projectedEnd];
  return null;
}

// NestedInlineBoxEdgeOwnership: compare an inline's flow edge with its direct
// in-flow content boundary. A descendant semantic box owns its own padding,
// margins and pseudo content, so an outer <sup>/<span> must not reserve that
// same edge again merely because Range.getClientRects() ends on a deep text leaf.
function measuredInlineEdge(element: Element, side: "start" | "end"): number {
  const style = getComputedStyle(element);
  const margin = Number.parseFloat(
    side === "start" ? style.marginLeft : style.marginRight,
  ) || 0;
  const boxes = Array.from(element.getClientRects()).filter(function (rect) {
    return rect.width || rect.height;
  });
  if (!boxes.length) return margin;
  const boundary = function (node: Node): number | null {
    if (node.nodeType === Node.TEXT_NODE) {
      const range = document.createRange();
      range.selectNodeContents(node);
      const rects = Array.from(range.getClientRects()).filter(function (rect) {
        return rect.width || rect.height;
      });
      if (!rects.length) return null;
      return side === "start" ? rects[0].left : rects[rects.length - 1].right;
    }
    if (node.nodeType !== Node.ELEMENT_NODE) return null;
    const childStyle = getComputedStyle(node as Element);
    if (
      childStyle.display === "none" ||
      childStyle.position === "absolute" ||
      childStyle.position === "fixed"
    ) {
      return null;
    }
    const rects = Array.from((node as Element).getClientRects()).filter(function (rect) {
      return rect.width || rect.height;
    });
    if (rects.length) {
      const rect = side === "start" ? rects[0] : rects[rects.length - 1];
      const childMargin = Number.parseFloat(
        side === "start" ? childStyle.marginLeft : childStyle.marginRight,
      ) || 0;
      return side === "start" ? rect.left - childMargin : rect.right + childMargin;
    }
    const children = Array.from(node.childNodes);
    if (side === "end") children.reverse();
    for (let i = 0; i < children.length; i++) {
      const value = boundary(children[i]);
      if (value != null) return value;
    }
    return null;
  };
  let contentBoundary = null;
  const firstChildren = Array.from(element.childNodes);
  if (side === "end") firstChildren.reverse();
  for (let i = 0; i < firstChildren.length; i++) {
    contentBoundary = boundary(firstChildren[i]);
    if (contentBoundary != null) break;
  }
  if (contentBoundary == null) return margin;
  const flowEdge = side === "start"
    ? boxes[0].left - margin
    : boxes[boxes.length - 1].right + margin;
  return side === "start"
    ? Math.max(0, contentBoundary - flowEdge)
    : Math.max(0, flowEdge - contentBoundary);
}

function measuredInlineBaselineShift(element: Element): number {
  if (!element.parentNode || getComputedStyle(element).display === "contents") return 0;
  const makeProbe = function (): HTMLSpanElement {
    const probe = document.createElement("span");
    probe.setAttribute("data-tq-baseline-probe", "");
    probe.style.cssText = "display:inline-block!important;width:0!important;height:0!important;" +
      "margin:0!important;padding:0!important;border:0!important;font-size:0!important;" +
      "line-height:0!important;vertical-align:baseline!important;position:static!important;";
    return probe;
  };
  const outer = makeProbe();
  const inner = makeProbe();
  try {
    element.parentNode.insertBefore(outer, element);
    element.insertBefore(inner, element.firstChild);
    return inner.getBoundingClientRect().bottom - outer.getBoundingClientRect().bottom;
  } finally {
    inner.remove();
    outer.remove();
  }
}

function measuredOpaqueInlineObjectGeometry(element: Element): string {
  const parent = element.parentNode;
  if (!parent) return "";
  const style = getComputedStyle(element);
  if (
    style.position === "absolute" ||
    style.position === "fixed" ||
    style.getPropertyValue("float") !== "none" ||
    style.transform !== "none"
  ) {
    return "";
  }
  const rect = element.getBoundingClientRect();
  if (
    !Number.isFinite(rect.width) ||
    !Number.isFinite(rect.height) ||
    rect.width <= 0 ||
    rect.height <= 0
  ) {
    return "";
  }
  const number = function (value: string): number {
    return Number.parseFloat(value) || 0;
  };
  const probe = document.createElement("span");
  probe.setAttribute("data-tq-baseline-probe", "");
  probe.style.cssText = "display:inline-block!important;width:0!important;height:0!important;" +
    "margin:0!important;padding:0!important;border:0!important;font-size:0!important;" +
    "line-height:0!important;vertical-align:baseline!important;position:static!important;";
  try {
    parent.insertBefore(probe, element.nextSibling);
    const baseline = probe.getBoundingClientRect().bottom;
    const advance = rect.width + number(style.marginLeft) + number(style.marginRight);
    const ascent = Math.max(0, baseline - rect.top + number(style.marginTop));
    const descent = Math.max(0, rect.bottom - baseline + number(style.marginBottom));
    return [advance, ascent, descent].join(",");
  } finally {
    probe.remove();
  }
}

function isCloneSafeOpaqueInlineObject(element: Element): boolean {
  if (element.hasAttribute("data-tiqian-static-inline-object")) return true;
  const name = element.localName || "";
  if (name.includes("-")) return false;
  const interactive = "a,button,input,select,textarea,iframe,object,embed,audio,video,canvas,[contenteditable='true'],[tabindex]";
  if (element.matches(interactive) || element.querySelector(interactive)) return false;
  const nodes = [element].concat(Array.from(element.querySelectorAll("*")));
  return !nodes.some(function (node) {
    return Array.from(node.attributes || []).some(function (attr) {
      return attr.name.toLowerCase().startsWith("on");
    });
  });
}

// RootGeneratedInlineContentMustStayNative: a pseudo directly on the paragraph
// has no source range to which InlineBoxSpan can attach. Descendant semantic
// elements are supported instead: measuredInlineEdge() reserves their actual
// ::before/::after advance while the one cloned semantic element keeps the host
// pseudo, copy, accessibility and interaction behavior intact.
function flowParticipatingPseudoContent(element: Element, pseudo: "::before" | "::after"): string | null {
  const style = getComputedStyle(element, pseudo);
  const content = style.getPropertyValue("content").trim();
  if (!content || content === "none" || content === "normal" || content === "\"\"" || content === "''") {
    return null;
  }
  if (style.display === "none" || style.position === "absolute" || style.position === "fixed") {
    return null;
  }
  return content;
}

function generatedPseudoContentIssue(element: Element): string | null {
  const pseudos = ["::before", "::after"];
  for (let i = 0; i < pseudos.length; i++) {
    const content = flowParticipatingPseudoContent(element, pseudos[i] as "::before" | "::after");
    if (content !== null) {
      return element.tagName.toLowerCase() + pseudos[i] + ":" + String(content).trim();
    }
  }
  return null;
}

// InlineShapingStyleParityContract: TextStyle currently models family, size,
// weight, italic and baseline shift. The renderer preserves semantic wrappers,
// so an inherited shaping property that changes only inside such a wrapper
// would otherwise make browser glyph advances diverge from LayoutResult.
// The host decides which property diverges; the lowering engine only collects
// the normalized computed facts and asks through the inlineShapingDecision
// callback (same shape as classifyRole).
function collectShapingValues(element: Element, properties: string[]): string[] {
  const values: string[] = [];
  for (let i = 0; i < properties.length; i++) {
    values.push(computedStyle(element, properties[i]).trim().toLowerCase());
  }
  return values;
}

// LocaleChannel: the lowerer must answer the same default locale as the
// Kotlin core TextStyle ("zh-Hans") because locale travels into LayoutInput
// and drives font selection plus the punctuation profile. An explicit
// non-empty options.locale overrides that default.
function resolveLocale(options: LoweringOptions): string {
  return typeof options.locale === "string" && options.locale !== ""
    ? options.locale
    : "zh-Hans";
}

function defaultTextStyle(locale: string): TextStyle {
  return {
    fontFamilies: [],
    fontSize: DEFAULT_FONT_SIZE,
    fontWeight: 400,
    italic: false,
    baselineShift: 0,
    locale: locale,
  };
}

function computedTextStyle(element: Element, fallback: TextStyle): TextStyle {
  const families = parseCssFontFamilies(computedStyle(element, "font-family"));
  const fontFamilies = families.length > 0 ? families : fallback.fontFamilies;
  const fontSize = firstDefined(parseCssPx(computedStyle(element, "font-size")), fallback.fontSize);
  const fontWeight = firstDefined(parseCssFontWeight(computedStyle(element, "font-weight")), fallback.fontWeight);
  const italic = firstDefined(parseCssItalic(computedStyle(element, "font-style")), fallback.italic);
  return {
    fontFamilies: fontFamilies,
    fontSize: fontSize,
    fontWeight: fontWeight,
    italic: italic,
    baselineShift: fallback.baselineShift,
    locale: fallback.locale,
  };
}

function computedInlineBaselineShift(element: Element): number {
  let relativeShift = 0;
  if (computedStyle(element, "position").trim().toLowerCase() === "relative") {
    const top = parseCssPx(computedStyle(element, "top"));
    const bottom = parseCssPx(computedStyle(element, "bottom"));
    relativeShift = top !== null ? top : (bottom !== null ? -bottom : 0);
  }
  const verticalAlign = computedStyle(element, "vertical-align").trim().toLowerCase();
  if (verticalAlign === "" || verticalAlign === "baseline") return relativeShift;
  const vaPx = parseCssPx(verticalAlign);
  if (vaPx !== null) return relativeShift - vaPx;
  const measured = measuredInlineBaselineShift(element);
  return Number.isFinite(measured) ? measured : 0;
}

function computedInlineStyle(element: Element, fallback: InlineStyleContext): InlineStyleContext {
  const computed = computedTextStyle(element, fallback.textStyle);
  const localBaselineShift = computedInlineBaselineShift(element);
  return {
    textStyle: {
      fontFamilies: computed.fontFamilies,
      fontSize: computed.fontSize,
      fontWeight: computed.fontWeight,
      italic: computed.italic,
      baselineShift: fallback.textStyle.baselineShift + localBaselineShift,
      locale: computed.locale,
    },
    whiteSpace: cssWhiteSpaceMode(computedStyle(element, "white-space"), fallback.whiteSpace),
    cjkStrongBaseWeight: fallback.cjkStrongBaseWeight,
  };
}

function parseOpaqueInlineObjectGeometry(value: string): InlineObjectGeometry | null {
  const rawParts = String(value).split(",");
  const parts: number[] = [];
  for (let i = 0; i < rawParts.length; i++) {
    const number = Number(rawParts[i]);
    if (Number.isFinite(number)) parts.push(number);
  }
  if (parts.length !== 3) return null;
  const advance = parts[0];
  const ascent = parts[1];
  const descent = parts[2];
  if (!Number.isFinite(advance) || advance <= INLINE_EDGE_EPSILON) return null;
  if (!Number.isFinite(ascent) || ascent < 0 || !Number.isFinite(descent) || descent < 0) {
    return null;
  }
  if (ascent + descent <= INLINE_EDGE_EPSILON) return null;
  return { advance: advance, ascent: ascent, descent: descent };
}

// CanonicalPreparedHostStyleProbe: a direct-SSR prepared paragraph carries
// 'data-tq-rendered', so the public replay CSS intentionally gives it
// 'line-height: 0' and 'white-space: pre'. When a width miss falls back to
// runtime layout, those are renderer-owned values rather than host
// typography. Suppress the replay selector only while sampling computed
// paragraph styles, then restore the attribute synchronously before any
// layout mutation can be painted.
function withCanonicalPreparedHostStyleProbe<T>(paragraph: Element, block: ProbeAction<T>): T {
  const rendered = paragraph.getAttribute("data-tq-rendered");
  paragraph.removeAttribute("data-tq-rendered");
  try {
    return block();
  } finally {
    if (rendered === null) {
      paragraph.removeAttribute("data-tq-rendered");
    } else {
      paragraph.setAttribute("data-tq-rendered", rendered);
    }
  }
}

// ConfiguredFontSizeSingleSource: an explicit engine font size must be live
// while descendant computed styles are sampled. Otherwise inherited links
// and code runs are lowered at the host size even though the base run is
// measured at the override. The host is restored before raw-DOM backup transfer;
// the renderer then applies the same size for the enhanced paragraph.
function withConfiguredFontSizeProbe<T>(paragraph: Element, fontSize: number | null | undefined, block: ProbeAction<T>): T {
  if (fontSize === null || fontSize === undefined) return block();
  const originalStyle = paragraph.getAttribute("style");
  (paragraph as HTMLElement).style.setProperty("font-size", String(fontSize) + "px", "important");
  try {
    return block();
  } finally {
    if (originalStyle === null) {
      paragraph.removeAttribute("style");
    } else {
      paragraph.setAttribute("style", originalStyle);
    }
  }
}

function canonicalPreparedPlainSource(parent: Element): string {
  let result = "";
  const appendNode = function (node: AppendNodeLike): void {
    if (node.nodeType === 3) {
      result += node.textContent || "";
      return;
    }
    if (node.nodeType !== 1) return;
    if (node.hasAttribute("data-tq-copy-ignore")) return;
    if (node.hasAttribute("data-tq-src")) {
      const following = node.nextSibling;
      const followingElement = following !== null && following.nodeType === 1 ? following : null;
      const pairedMandatoryBreak = node.hasAttribute("data-tq-hard-break") &&
        followingElement !== null &&
        (followingElement as Element).tagName.toUpperCase() === "BR" &&
        (followingElement as Element).getAttribute("data-tq-engine-break") === "MandatoryBreak";
      if (!pairedMandatoryBreak) result += node.getAttribute("data-tq-src") || "";
      return;
    }
    if (node.tagName.toUpperCase() === "BR") {
      if (node.getAttribute("data-tq-engine-break") === "MandatoryBreak") result += "\n";
      return;
    }
    const children = node.childNodes;
    for (let index = 0; index < children.length; index++) {
      const child = children.item ? children.item(index) : children[index];
      if (child) appendNode(child as Element);
    }
  };
  const nodes = parent.childNodes;
  for (let index = 0; index < nodes.length; index++) {
    const node = nodes.item ? nodes.item(index) : nodes[index];
    if (node) appendNode(node as Element);
  }
  return result;
}

function lowerWithCurrentStyles(
  paragraph: Element,
  options: LoweringOptions,
  locale: string,
  helpers: NormalizedInlineShapingHelpers,
  canonicalPrepared: boolean,
  issue: LoweringIssue,
): LoweredParagraph | null {
  const fallbackStyle = defaultTextStyle(locale);
  const computedParagraphStyle = computedTextStyle(paragraph, fallbackStyle);
  const fontSize = options.fontSize !== null && options.fontSize !== undefined
    ? options.fontSize
    : computedParagraphStyle.fontSize;
  const baseStyle: TextStyle = {
    fontFamilies: computedParagraphStyle.fontFamilies,
    fontSize: fontSize,
    fontWeight: computedParagraphStyle.fontWeight,
    italic: computedParagraphStyle.italic,
    baselineShift: computedParagraphStyle.baselineShift,
    locale: computedParagraphStyle.locale,
  };
  const lineHeight = options.lineHeight !== null && options.lineHeight !== undefined
    ? options.lineHeight
    : firstDefined(
        parseCssLineHeight(computedStyle(paragraph, "line-height"), fontSize),
        fontSize * DEFAULT_LINE_HEIGHT_MULTIPLIER
      );
  const baseInlineStyle: InlineStyleContext = {
    textStyle: baseStyle,
    whiteSpace: cssWhiteSpaceMode(computedStyle(paragraph, "white-space")),
    cjkStrongBaseWeight: null,
  };

  if (canonicalPrepared) {
    const source = canonicalPreparedPlainSource(paragraph);
    if (String(source).trim() === "") {
      issue.name = "EmptyParagraph";
      issue.detail = "paragraph has no text";
      return null;
    }
    return {
      text: source,
      textStyle: baseStyle,
      lineHeight: lineHeight,
      spans: [],
      decorations: [],
      inlineBoxes: [],
      inlineObjects: [],
      domInlineObjects: [],
      sourceSpans: [],
      sourceBoundaries: [],
      lineBreakSpans: [],
    };
  }

  const pseudoIssue = generatedPseudoContentIssue(paragraph);
  if (pseudoIssue !== null) {
    issue.name = "UnsupportedGeneratedInlineContent";
    issue.detail = pseudoIssue;
    return null;
  }

  const builder = new (LoweringBuilder as LoweringBuilderConstructor)(
    paragraph,
    baseInlineStyle,
    lineHeight,
    options.strongAsEmphasisMarks === true,
    helpers,
    issue,
  );
  if (!builder.appendChildren(paragraph, baseInlineStyle, 0)) return null;
  const lowered = builder.build();
  if (String(lowered.text).trim() === "") {
    issue.name = "EmptyParagraph";
    issue.detail = "paragraph has no text";
    return null;
  }
  return lowered;
}

interface LoweringBuilderInstance {
  sourceElement: Element;
  baseInlineStyle: InlineStyleContext;
  baseLineHeight: number;
  strongAsEmphasisMarks: boolean;
  helpers: NormalizedInlineShapingHelpers;
  issue: LoweringIssue;
  inlineShapingParagraphValues: string[];
  text: string;
  spans: TextSpan[];
  decorations: DecorationSpan[];
  inlineBoxes: InlineBoxSpan[];
  inlineObjects: InlineObjectSpan[];
  domInlineObjects: DomInlineObject[];
  sourceSpans: DomSourceSpan[];
  sourceBoundaries: number[];
  whitespaceModes: WhiteSpaceMode[];
  hardBreakOffsets: number[];
  pendingStrongTextRanges: PendingStrongTextRange[];
}

interface LoweringBuilderMethods {
  addBoundary(offset: number): void;
  unsupported(name: string, detail: string): false;
  appendRawText(value: string, whiteSpace: WhiteSpaceMode): void;
  appendChildren(element: Element, style: InlineStyleContext, depth: number): boolean;
  appendNode(node: Node, style: InlineStyleContext, depth: number): boolean;
  appendElement(element: Element, style: InlineStyleContext, depth: number): boolean;
  appendOpaqueInlineObject(element: Element, whiteSpace: WhiteSpaceMode): boolean;
  appendSemantic(element: Element, style: InlineStyleContext, depth: number, cjkStrongBaseWeight: number | null): boolean;
  appendText(value: string, style: InlineStyleContext): void;
  appendTextSegment(value: string, style: TextStyle, whiteSpace: WhiteSpaceMode): void;
  build(): LoweredParagraph;
}

type LoweringBuilder = LoweringBuilderInstance & LoweringBuilderMethods;

interface LoweringBuilderConstructor {
  (
    this: LoweringBuilder,
    sourceElement: Element,
    baseInlineStyle: InlineStyleContext,
    baseLineHeight: number,
    strongAsEmphasisMarks: boolean,
    helpers: NormalizedInlineShapingHelpers,
    issue: LoweringIssue,
  ): void;
  new (
    sourceElement: Element,
    baseInlineStyle: InlineStyleContext,
    baseLineHeight: number,
    strongAsEmphasisMarks: boolean,
    helpers: NormalizedInlineShapingHelpers,
    issue: LoweringIssue,
  ): LoweringBuilder;
}

function LoweringBuilder(
  this: LoweringBuilder,
  sourceElement: Element,
  baseInlineStyle: InlineStyleContext,
  baseLineHeight: number,
  strongAsEmphasisMarks: boolean,
  helpers: NormalizedInlineShapingHelpers,
  issue: LoweringIssue,
): void {
  this.sourceElement = sourceElement;
  this.baseInlineStyle = baseInlineStyle;
  this.baseLineHeight = baseLineHeight;
  this.strongAsEmphasisMarks = strongAsEmphasisMarks;
  this.helpers = helpers;
  this.issue = issue;
  this.inlineShapingParagraphValues = collectShapingValues(sourceElement, helpers.inlineShapingProperties);
  this.text = "";
  this.spans = [];
  this.decorations = [];
  this.inlineBoxes = [];
  this.inlineObjects = [];
  this.domInlineObjects = [];
  this.sourceSpans = [];
  this.sourceBoundaries = [];
  this.whitespaceModes = [];
  this.hardBreakOffsets = [];
  this.pendingStrongTextRanges = [];
}

LoweringBuilder.prototype.addBoundary = function (this: LoweringBuilder, offset: number): void {
  if (this.sourceBoundaries.indexOf(offset) < 0) this.sourceBoundaries.push(offset);
};

LoweringBuilder.prototype.unsupported = function (this: LoweringBuilder, name: string, detail: string): false {
  this.issue.name = name;
  this.issue.detail = detail;
  return false;
};

LoweringBuilder.prototype.appendRawText = function (this: LoweringBuilder, value: string, whiteSpace: WhiteSpaceMode): void {
  this.text += value;
  for (let i = 0; i < value.length; i++) this.whitespaceModes.push(whiteSpace);
};

LoweringBuilder.prototype.appendChildren = function (this: LoweringBuilder, element: Element, style: InlineStyleContext, depth: number): boolean {
  const nodes = element.childNodes;
  for (let i = 0; i < nodes.length; i++) {
    const node = nodes.item ? nodes.item(i) : nodes[i];
    if (!node) continue;
    if (!this.appendNode(node, style, depth)) return false;
  }
  return true;
};

LoweringBuilder.prototype.appendNode = function (this: LoweringBuilder, node: Node, style: InlineStyleContext, depth: number): boolean {
  if (node.nodeType === 3) {
    this.appendText(node.textContent || "", style);
    return true;
  }
  if (node.nodeType === 1) return this.appendElement(node as Element, style, depth);
  return true;
};

LoweringBuilder.prototype.appendElement = function (this: LoweringBuilder, element: Element, style: InlineStyleContext, depth: number): boolean {
  const tag = element.tagName.toUpperCase();
  if (tag === "BR") {
    this.hardBreakOffsets.push(this.text.length);
    this.appendRawText("\n", style.whiteSpace);
    return true;
  }
  const display = computedStyle(element, "display").trim().toLowerCase();
  const opaqueCandidate = isNonTextInlineTag(tag) ||
    tag.indexOf("-") !== -1 ||
    isOpaqueInlineDisplay(display);
  if (opaqueCandidate) {
    if (!isOpaqueInlineLevelDisplay(display)) {
      return this.unsupported(
        "UnsupportedInlineFormattingContext",
        tag.toLowerCase() + ":" + display,
      );
    }
    if (!isCloneSafeOpaqueInlineObject(element)) {
      return this.unsupported("UnsupportedStatefulInlineObject", tag.toLowerCase());
    }
    return this.appendOpaqueInlineObject(element, style.whiteSpace);
  }
  if (display !== "inline" && display !== "contents") {
    return this.unsupported(
      "UnsupportedInlineFormattingContext",
      tag.toLowerCase() + ":" + display,
    );
  }
  // RuntimeInlineCodeUsesResolvedBrowserFont: build-time snapshots
  // must fail closed without exact monospace font/box evidence, but
  // the live browser already exposes the resolved host font and box
  // metrics. Lower that run normally and let the sliced browser
  // shaping fallback handle Worker-ineligible rich paragraphs.
  if (this.helpers.inlineShapingDecision !== null && this.helpers.inlineShapingProperties.length > 0) {
    const elementValues = collectShapingValues(element, this.helpers.inlineShapingProperties);
    const decision = this.helpers.inlineShapingDecision(
      tag.toLowerCase(),
      elementValues,
      this.inlineShapingParagraphValues,
    );
    if (decision) {
      return this.unsupported(decision.name, decision.detail);
    }
  }
  const inheritedStrongWeight = style.cjkStrongBaseWeight;
  let strongBaseWeight: number | null = null;
  if (tag === "STRONG" && this.strongAsEmphasisMarks) {
    strongBaseWeight = inheritedStrongWeight !== null && inheritedStrongWeight !== undefined
      ? inheritedStrongWeight
      : style.textStyle.fontWeight;
  }
  const computed = computedInlineStyle(element, style);
  let elementStyle: InlineStyleContext = computed;
  if (tag === "STRONG" && this.strongAsEmphasisMarks) {
    elementStyle = {
      textStyle: computed.textStyle,
      whiteSpace: computed.whiteSpace,
      cjkStrongBaseWeight: strongBaseWeight,
    };
  }
  return this.appendSemantic(element, elementStyle, depth, strongBaseWeight);
};

LoweringBuilder.prototype.appendOpaqueInlineObject = function (this: LoweringBuilder, element: Element, whiteSpace: WhiteSpaceMode): boolean {
  const geometry = parseOpaqueInlineObjectGeometry(measuredOpaqueInlineObjectGeometry(element));
  if (!geometry) {
    return this.unsupported("InvalidInlineObjectGeometry", element.tagName.toLowerCase());
  }
  const start = this.text.length;
  this.appendRawText(INLINE_OBJECT_REPLACEMENT_CHAR, whiteSpace);
  const end = this.text.length;
  this.addBoundary(start);
  this.addBoundary(end);
  this.inlineObjects.push({
    start: start,
    end: end,
    advance: geometry.advance,
    ascent: geometry.ascent,
    descent: geometry.descent,
  });
  this.domInlineObjects.push({
    start: start,
    end: end,
    element: element,
    marginRight: firstDefined(parseCssPx(computedStyle(element, "margin-right")), 0),
  });
  return true;
};

LoweringBuilder.prototype.appendSemantic = function (this: LoweringBuilder, element: Element, style: InlineStyleContext, depth: number, cjkStrongBaseWeight: number | null): boolean {
  const inlineStart = measuredInlineEdge(element, "start");
  const inlineEnd = measuredInlineEdge(element, "end");
  if (!Number.isFinite(inlineStart) || !Number.isFinite(inlineEnd)) {
    return this.unsupported("InvalidInlineBoxGeometry", element.tagName.toLowerCase());
  }
  const start = this.text.length;
  if (!this.appendChildren(element, style, depth + 1)) return false;
  const end = this.text.length;
  if (end > start) {
    this.addBoundary(start);
    this.addBoundary(end);
    if (
      Math.abs(inlineStart) >= INLINE_EDGE_EPSILON ||
      Math.abs(inlineEnd) >= INLINE_EDGE_EPSILON
    ) {
      this.inlineBoxes.push({
        start: start,
        end: end,
        inlineStart: inlineStart,
        inlineEnd: inlineEnd,
      });
    }
    const computedColor = computedStyle(element, "color");
    this.sourceSpans.push({
      start: start,
      end: end,
      element: element,
      depth: depth,
      cjkStrongBaseWeight: cjkStrongBaseWeight,
      computedColor: String(computedColor).trim() !== "" ? computedColor : null,
      inlineBoxStyle: {
        inlineStart: inlineStart,
        inlineEnd: inlineEnd,
        marginRight: firstDefined(parseCssPx(computedStyle(element, "margin-right")), 0),
        letterSpacing: firstDefined(parseCssPx(computedStyle(element, "letter-spacing")), 0),
        boxDecorationBreak: computedStyle(element, "box-decoration-break").trim().toLowerCase(),
      },
    });
  }
  return true;
};

LoweringBuilder.prototype.appendText = function (this: LoweringBuilder, value: string, style: InlineStyleContext): void {
  if (value.length === 0) return;
  const strongBaseWeight = style.cjkStrongBaseWeight;
  if (strongBaseWeight === null || strongBaseWeight === undefined) {
    this.appendTextSegment(value, style.textStyle, style.whiteSpace);
    return;
  }
  const start = this.text.length;
  this.appendRawText(value, style.whiteSpace);
  const end = this.text.length;
  this.pendingStrongTextRanges.push({
    start: start,
    end: end,
    style: style.textStyle,
    strongBaseWeight: strongBaseWeight,
  });
  this.addBoundary(start);
  this.addBoundary(end);
};

LoweringBuilder.prototype.appendTextSegment = function (this: LoweringBuilder, value: string, style: TextStyle, whiteSpace: WhiteSpaceMode): void {
  if (value.length === 0) return;
  const start = this.text.length;
  this.appendRawText(value, whiteSpace);
  const end = this.text.length;
  if (!textStylesEqual(style, this.baseInlineStyle.textStyle)) {
    this.spans.push({ start: start, end: end, style: style });
    this.addBoundary(start);
    this.addBoundary(end);
  }
};

function mapProjectedRanges<T extends SpanRangeItem>(
  items: T[],
  projection: WhitespaceProjection,
  copy: ProjectedRangeCopyFn<T>,
): T[] {
  const result: T[] = [];
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    const range = projectionRange(projection, item.start, item.end);
    if (!range) continue;
    result.push(copy(item, range));
  }
  return result;
}

function buildLineBreakSpans(sourceSpans: DomSourceSpan[], projection: WhitespaceProjection): LineBreakSpan[] {
  const result: LineBreakSpan[] = [];
  const seen: Record<string, boolean> = {};
  for (let i = 0; i < sourceSpans.length; i++) {
    const span = sourceSpans[i];
    const tag = span.element.tagName.toUpperCase();
    if (tag !== "A" && tag !== "CODE") continue;
    const range = projectionRange(projection, span.start, span.end);
    if (!range) continue;
    // Prose link labels retain word shaping; technical fallback can split a
    // long label into unkerned characters even when normal word breaks fit.
    if (tag === "A" && /[ \t\n\r\f]/u.test(projection.text.slice(range[0], range[1]))) continue;

    const key = range[0] + ":" + range[1] + ":ProgressiveTechnical";
    if (seen[key]) continue;
    seen[key] = true;
    result.push({ start: range[0], end: range[1], policy: "ProgressiveTechnical" });
  }
  return result;
}

function buildSourceBoundaries(sourceBoundaries: number[], projection: WhitespaceProjection, loweredText: string): number[] {
  const mapped: number[] = [];
  const seen: Record<number, boolean> = {};
  for (let i = 0; i < sourceBoundaries.length; i++) {
    const boundary = projection.boundaryMap[sourceBoundaries[i]];
    if (boundary > 0 && boundary < loweredText.length && !seen[boundary]) {
      seen[boundary] = true;
      mapped.push(boundary);
    }
  }
  mapped.sort(function (left, right) { return left - right; });
  return mapped;
}

LoweringBuilder.prototype.build = function (this: LoweringBuilder): LoweredParagraph {
  const projection = cssWhiteSpaceCollapseProjection(this.text, this.whitespaceModes, this.hardBreakOffsets);
  const loweredText = projection.text;
  const spanCopy = function (item: TextSpan, range: [number, number]): TextSpan {
    return { start: range[0], end: range[1], style: item.style };
  };
  const decorationCopy = function (item: DecorationSpan, range: [number, number]): DecorationSpan {
    return { start: range[0], end: range[1], kind: item.kind };
  };
  const inlineBoxCopy = function (item: InlineBoxSpan, range: [number, number]): InlineBoxSpan {
    return {
      start: range[0],
      end: range[1],
      inlineStart: item.inlineStart,
      inlineEnd: item.inlineEnd,
    };
  };
  const inlineObjectCopy = function (item: InlineObjectSpan, range: [number, number]): InlineObjectSpan {
    return {
      start: range[0],
      end: range[1],
      advance: item.advance,
      ascent: item.ascent,
      descent: item.descent,
    };
  };
  const domInlineObjectCopy = function (item: DomInlineObject, range: [number, number]): DomInlineObject {
    return {
      start: range[0],
      end: range[1],
      element: item.element,
      marginRight: item.marginRight,
    };
  };
  const sourceSpanCopy = function (item: DomSourceSpan, range: [number, number]): DomSourceSpan {
    return {
      start: range[0],
      end: range[1],
      element: item.element,
      depth: item.depth,
      cjkStrongBaseWeight: item.cjkStrongBaseWeight,
      computedColor: item.computedColor,
      inlineBoxStyle: item.inlineBoxStyle,
    };
  };
  const spans = mapProjectedRanges(this.spans, projection, spanCopy);
  const decorations = mapProjectedRanges(this.decorations, projection, decorationCopy);
  appendProjectedStrongStyles(
    this.pendingStrongTextRanges,
    loweredText,
    function (start: number, end: number): [number, number] | null {
      return projectionRange(projection, start, end);
    },
    this.helpers.classifyRoles,
    this.baseInlineStyle.textStyle,
    spans,
    decorations,
  );
  spans.sort(function (left, right) { return left.start - right.start || left.end - right.end; });
  decorations.sort(function (left, right) { return left.start - right.start || left.end - right.end; });
  return {
    text: loweredText,
    textStyle: this.baseInlineStyle.textStyle,
    lineHeight: this.baseLineHeight,
    spans: spans,
    decorations: decorations,
    inlineBoxes: mapProjectedRanges(this.inlineBoxes, projection, inlineBoxCopy),
    inlineObjects: mapProjectedRanges(this.inlineObjects, projection, inlineObjectCopy),
    domInlineObjects: mapProjectedRanges(this.domInlineObjects, projection, domInlineObjectCopy),
    sourceSpans: mapProjectedRanges(this.sourceSpans, projection, sourceSpanCopy),
    lineBreakSpans: buildLineBreakSpans(this.sourceSpans, projection),
    sourceBoundaries: buildSourceBoundaries(this.sourceBoundaries, projection, loweredText),
  };
};

/**
 * Lower a paragraph element against the live DOM and return either the
 * lowered paragraph or the first capability issue.
 */
export function lowerMarkdown(paragraph: Element, options: LoweringOptions, helpers: InlineShapingHelpers): LoweringResult {
  options = options as LoweringOptions || {};
  const locale = resolveLocale(options);
  const classifyRole = (helpers && typeof helpers.classifyRole === "function")
    ? helpers.classifyRole
    : function (): string { return "other"; };
  const classifyRoles = (helpers && typeof helpers.classifyRoles === "function")
    ? helpers.classifyRoles
    : function (text: string, starts: number[], ends: number[], locale: string): string[] {
        return starts.map(function (start, index) {
          return classifyRole(text, start, ends[index], locale);
        });
      };
  const inlineShapingProperties: string[] = Array.isArray(helpers?.inlineShapingProperties)
    ? helpers.inlineShapingProperties
    : [];
  const inlineShapingDecision = (helpers && typeof helpers.inlineShapingDecision === "function")
    ? helpers.inlineShapingDecision
    : null;
  const safeHelpers: NormalizedInlineShapingHelpers = {
    classifyRole: classifyRole,
    classifyRoles: classifyRoles,
    inlineShapingProperties: inlineShapingProperties,
    inlineShapingDecision: inlineShapingDecision as NormalizedInlineShapingHelpers["inlineShapingDecision"],
  };
  const issue: LoweringIssue = { name: null, detail: null };
  const canonicalPrepared =
    paragraph.getAttribute("data-tq-rendered") === "true" &&
    paragraph.getAttribute("data-tq-canonical-plain") === "true";
  const lowered = withConfiguredFontSizeProbe(paragraph, options.fontSize, function () {
    if (canonicalPrepared) {
      return withCanonicalPreparedHostStyleProbe(paragraph, function () {
        return lowerWithCurrentStyles(paragraph, options, locale, safeHelpers, true, issue);
      });
    }
    return lowerWithCurrentStyles(paragraph, options, locale, safeHelpers, false, issue);
  });
  if (lowered === null || lowered === undefined) {
    return { ok: false, issue: { name: issue.name, detail: issue.detail } };
  }
  return { ok: true, lowered: lowered };
}
