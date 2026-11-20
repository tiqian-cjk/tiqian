// Prepared-DOM value-style rendering (ADR 0053 batch 6). Moved verbatim
// from the package root; root paths remain as compatibility re-export shims.
//
// The lowering itself (string markup, evidence overlays, the prepared paragraph
// artifact) is generated from Haxe into the @tiqian/shared package. This module keeps
// what the generated layer cannot hold: plan wire parsing and validation,
// semantic normalization, live-source and inline-object DOM swaps, the
// value-style registry, and the typed-to-wire artifact serialization.

import {
  LAYOUT_REVISION,
  RENDER_REVISION,
  SNAPSHOT_SCHEMA,
} from "./snapshot-schema.js";
import {
  normalizeLiveSemantics,
  normalizeSnapshotSemantics,
} from "./snapshot-source.js";
import type {
  LiveSemanticSpan,
  SnapshotSemanticSpan,
} from "./snapshot-source.js";
import type { PlanCell, PlanEmphasisRange, PlanLine } from "@tiqian/ffi/engine-gen/org/tiqian/protocol/Plan.js";
import { EvidenceDecorationKind } from "@tiqian/shared/org/tiqian/shared/prepared_dom/EvidenceDecorationKind";
import { PreparedArtifact } from "@tiqian/shared/org/tiqian/shared/prepared_dom/PreparedArtifact";
import { PreparedDom as GeneratedPreparedDom } from "@tiqian/shared/org/tiqian/shared/prepared_dom/PreparedDom";
import type { AttributeEntry as GeneratedAttributeEntry } from "@tiqian/shared/org/tiqian/shared/prepared_dom/AttributeEntry";
import type { BopomofoZone as GeneratedBopomofoZone } from "@tiqian/shared/org/tiqian/shared/prepared_dom/BopomofoZone";
import type { EvidenceDecorationSegment as GeneratedEvidenceDecorationSegment } from "@tiqian/shared/org/tiqian/shared/prepared_dom/EvidenceDecorationSegment";
import type { EvidenceEmphasisDot as GeneratedEvidenceEmphasisDot } from "@tiqian/shared/org/tiqian/shared/prepared_dom/EvidenceEmphasisDot";
import type { MarkupArtifact as GeneratedMarkupArtifact } from "@tiqian/shared/org/tiqian/shared/prepared_dom/MarkupArtifact";
import type { PreparedArtifactOptions as GeneratedPreparedArtifactOptions } from "@tiqian/shared/org/tiqian/shared/prepared_dom/PreparedArtifactOptions";
import type { PreparedArtifactResult as GeneratedPreparedArtifactResult } from "@tiqian/shared/org/tiqian/shared/prepared_dom/PreparedArtifactResult";
import type { PreparedPlan as GeneratedPreparedPlan } from "@tiqian/shared/org/tiqian/shared/prepared_dom/PreparedPlan";
import type { PreparedPlanCell as GeneratedPreparedPlanCell } from "@tiqian/shared/org/tiqian/shared/prepared_dom/PreparedPlanCell";
import type { PreparedPlanLine as GeneratedPreparedPlanLine } from "@tiqian/shared/org/tiqian/shared/prepared_dom/PreparedPlanLine";
import type { PreparedRenderTextSpan as GeneratedPreparedRenderTextSpan } from "@tiqian/shared/org/tiqian/shared/prepared_dom/PreparedRenderTextSpan";
import type { PreparedSemanticSpan as GeneratedPreparedSemanticSpan } from "@tiqian/shared/org/tiqian/shared/prepared_dom/PreparedSemanticSpan";
import type { RubyAnnotation as GeneratedRubyAnnotation } from "@tiqian/shared/org/tiqian/shared/prepared_dom/RubyAnnotation";
import type { StyleDelta as GeneratedStyleDelta } from "@tiqian/shared/org/tiqian/shared/prepared_dom/StyleDelta";
import type { EnhancedElementContext } from "../../engine/context/enhance-context.js";

// --- Internal types ---

/** Wire artifact node shape produced by the lowering and serialized here. */
export type PreparedWireArtifact =
  | readonly [string, string]
  | readonly [string, readonly (readonly [string, string])[], readonly PreparedWireArtifact[]];

/** Ruby decision on the plan wire; numeric fields are Number()-mapped. */
interface RubyAnnotation {
  fontSize: number;
  ascent?: number | null;
  fontFamilies?: string[];
  text: string;
  fontWeight?: number | null;
  centerX: number;
  baselineY: number;
}

/** One bopomofo glyph placement on the plan wire. */
interface BopomofoPlacement {
  text: string;
  role: string;
  left: number;
  top: number;
  width: number;
  height: number;
}

/** Bopomofo zone on the plan wire. */
interface BopomofoZone {
  text: string;
  fontWeight: number;
  fontFamilies?: string[];
  placements?: BopomofoPlacement[];
}

/** Interlinear decoration segment on the plan wire. */
interface EvidenceDecorationSegment {
  left: number;
  top: number;
  right: number;
  kind: string;
}

/** Emphasis dot on the plan wire. */
interface EvidenceEmphasisDot {
  clusterRangeStart: number;
  anchorX: number;
  anchorY: number;
  dotDiameter: number;
}


/** Style owner key: either a host Element or the snapshot sentinel marker. */
type StyleOwner = Element | typeof SNAPSHOT_STYLE_OWNER;

/** Style delta from the prepared layout plan cell. */
interface StyleDelta {
  fontSize?: number;
  fontWeight?: number;
  italic?: boolean;
}

/** Inline edge entry from the prepared layout plan. */
interface InlineEdgeEntry {
  offset: number;
  inlineStart?: number;
  inlineEnd?: number;
}

/** QuerySelectorAll function signature. */
type QuerySelectorAllFn = (sel: string) => NodeListOf<Element>;

/** Host element shape for renderPreparedParagraphInto. */
interface PreparedParagraphHost extends Element {
  innerHTML: string;
  querySelectorAll: QuerySelectorAllFn;
}

/** Bridge candidate shape for revision probing. */
interface BridgeCandidateShape {
  version?: unknown;
  semanticReplayRevision?: unknown;
}

/** Style class mapper callback. */
type StyleClassForFn = (declaration: string) => string;

/** Semantic range received from either snapshot or live-source replay. */
interface SnapshotSemanticOption {
  start: number;
  end: number;
  sourceIndex?: number;
  tagName: string;
  attributes?: readonly (readonly [string, string])[];
  order?: number;
}

/** Emphasis dot color resolver callback. */
type EmphasisDotColorFn = (offset: number) => string | null;

/** Overlay options carried by the options bag (wire shape). */
interface EvidenceOverlayOptions {
  emphasisDotColor?: EmphasisDotColorFn | null;
}

/** Prepared style scope state held per root element. */
export interface PreparedStyleState {
  root: Element;
  scope: string;
  styleElement: HTMLStyleElement;
  originalScope: string | null;
  declarations: string[];
  indexes: Map<string, number>;
  owners: Map<StyleOwner, Set<number>>;
  dirty: boolean;
}

export {};


/** Spacing classification for a prepared run. */
interface PreparedSpacingResult {
  kind: string;
  px: number;
}

/** Cell properties read from snapshot JSON and the generated runtime plan. */
interface PreparedLayoutPlanCell {
  rangeStart: number;
  rangeEnd: number;
  source: string;
  display: string;
  drawX: number;
  naturalWidth: number;
  shapingBoundary?: boolean;
  openTypeFeatures?: string[];
  style?: StyleDelta | null;
  styleDelta?: PlanCell["styleDelta"];
  latin?: boolean;
  dashStrategy?: string | null;
  shapingLanguage?: string | null;
  resolvedFace?: string | null;
  glyphIds?: string | null;
  shapingEvidence?: string | null;
  punctuationInkFloor?: number | null;
  punctuationBodyWidth?: number | null;
  renderFontFamily?: string | null;
  inlineObject?: number | null;
  advance?: number | null;
  leadingLayoutAdvance?: number;
}

/** Line properties read from snapshot JSON and the generated runtime plan. */
interface PreparedLayoutPlanLine {
  cells: PreparedLayoutPlanCell[];
  top: number;
  bottom: number;
  baseline: number;
  indent: number;
  visualWidth: number;
  hyphenAdvance: number;
  endReason: string | PlanLine["endReason"];
  rangeStart: number;
  rangeEnd: number;
}

/** Ruby annotation with plan-specific base range. */
interface PlanRubyAnnotation extends RubyAnnotation {
  baseRangeEnd: number;
}

/** Bopomofo zone with plan-specific base range. */
interface PlanBopomofoZone extends BopomofoZone {
  baseRangeEnd: number;
}

/** The plan properties consumed by the prepared DOM renderer. */
interface PreparedLayoutPlan {
  schema: number;
  layoutRevision: string;
  height: number;
  lines: PreparedLayoutPlanLine[];
  emphasisRanges?: ([number, number] | PlanEmphasisRange)[];
  rubyDecisions?: PlanRubyAnnotation[];
  bopomofoDecisions?: PlanBopomofoZone[];
  inlineEdges?: InlineEdgeEntry[];
  decorationSegments?: EvidenceDecorationSegment[];
  emphasisDots?: EvidenceEmphasisDot[];
  fontSize?: number;
  overlayWidth?: number;
}

/** Options bag for renderPreparedParagraphArtifact and renderPreparedParagraphInto. */
interface PreparedParagraphRenderOptions {
  styleClassFor?: StyleClassForFn | null;
  semanticReplay?: string;
  sourceText?: string;
  semantics?: readonly SnapshotSemanticOption[];
  liveSemanticElements?: Element[];
  renderTextSpans?: RenderTextSpanEntry[];
  cjkStrongSemantics?: CjkStrongSemanticEntry[];
  inlineBoxes?: InlineBoxEntry[];
  emphasisDotColor?: EmphasisDotColorFn | null;
  inlineObjects?: InlineObjectOptionEntry[];
  evidenceOverlay?: EvidenceOverlayOptions;
}

/** Return value of renderPreparedParagraphArtifact. */
interface PreparedParagraphArtifactResult {
  readonly html: string;
  readonly artifact: PreparedWireArtifact[];
  readonly liveSemanticCount: number;
  readonly inlineObjectCount: number;
  readonly markerCount: number;
}

/** Return value of renderPreparedParagraphInto. */
interface PreparedParagraphIntoResult {
  readonly html: string;
  readonly markers: Element[];
}

/** Run object built during prepared paragraph rendering. */
interface PreparedRun {
  rangeStart: number;
  rangeEnd: number;
  source: string;
  display: string;
  drawX: number;
  naturalWidth: number;
  shapingBoundary: boolean;
  openTypeFeatures?: string[];
  renderFontFamilies: string[];
  trailingGap: number;
  spacing: PreparedSpacingResult;
  semanticPath: (SnapshotSemanticSpan | LiveSemanticSpan)[];
  styleDelta: StyleDelta | null;
  italicEffect: boolean;
  dashStrategy: string | null;
  shapingLanguage: string | null;
  resolvedFace: string | null;
  glyphIds: string | null;
  shapingEvidence: string | null;
  punctuationInkFloor: number | null;
  punctuationBodyWidth: number | null;
  evidenceRenderFontFamily: string | null;
  inlineObjectAdvance: number | null;
  bopomofoAdvanceWidth: number;
  styleSignature: string;
  punctuationSignature: string;
  semanticSignature?: string;
}

/** Inline box entry from plan or options. */
interface InlineBoxEntry {
  start: number;
  end: number;
  inlineStartPx: number;
  inlineEndPx: number;
}

/** Render text span entry from options. */
interface RenderTextSpanEntry {
  start: number;
  end: number;
  fontFamilies: string[];
}

/** CJK strong emphasis entry. */
interface CjkStrongSemanticEntry {
  start: number;
  end: number;
  weight: number;
}

/** Inline object entry from options. */
interface InlineObjectOptionEntry {
  start: number;
  end: number;
  element?: Element;
  marginRight?: number;
}

// --- Single-sourced constants (generated from Haxe) ---

const DEFAULT_LOCALE = GeneratedPreparedDom.DEFAULT_LOCALE;
const LINE_MARKER_SELECTOR = GeneratedPreparedDom.LINE_MARKER_SELECTOR;
const ROOT_SELECTOR = GeneratedPreparedDom.ROOT_SELECTOR;
const VALUE_STYLE_SCOPE_ATTRIBUTE = GeneratedPreparedDom.VALUE_STYLE_SCOPE_ATTRIBUTE;
const VALUE_STYLE_ELEMENT_ATTRIBUTE = GeneratedPreparedDom.VALUE_STYLE_ELEMENT_ATTRIBUTE;
const LIVE_SEMANTIC_INDEX_ATTRIBUTE = GeneratedPreparedDom.LIVE_SEMANTIC_INDEX_ATTRIBUTE;
const SNAPSHOT_STYLE_OWNER = GeneratedPreparedDom.SNAPSHOT_STYLE_OWNER;

function preparedPlan(value: string | PreparedLayoutPlan): PreparedLayoutPlan {
  return typeof value === "string" ? JSON.parse(value) : value;
}

function preparedLocale(value: string | Record<string, unknown>): string {
  if (typeof value === "string") return value;
  return String(value?.locale ?? DEFAULT_LOCALE);
}

// RuntimeValueStyleContentAddressing: runtime lowering must mint the same
// class name for the same declaration in every session, so a fresh one-shot
// enhance over a root reproduces the coordinated DOM byte for byte even
// though the coordinated registry still holds declarations from earlier
// widths. The snapshot namespace (tqv-) stays index based because frozen
// snapshot tables persist those indexes across builds. Two independent
// FNV-1a hashes make the name a pure function of the declaration string with
// collision odds far below any realistic declaration count, so no probe or
// registry state participates in naming.
function runtimeValueStyleKey(declaration: string) {
  let a = 0x811c9dc5;
  let b = 0x01000193;
  for (let i = 0; i < declaration.length; i++) {
    const code = declaration.charCodeAt(i);
    a ^= code;
    a = Math.imul(a, 0x01000193);
    b ^= code + i;
    b = Math.imul(b, 0x811c9dc5);
  }
  a >>>= 0;
  b >>>= 0;
  return `${a.toString(36)}${b.toString(36)}`;
}

function runtimeValueStyleClass(key: string): string {
  return GeneratedPreparedDom.runtimeValueStyleClass(key);
}

function createPreparedStyleState(root: Element, context: EnhancedElementContext) {
  const documentObject = root?.ownerDocument ?? globalThis.document;
  const parent = documentObject?.head ?? documentObject?.documentElement ?? documentObject?.body;
  if (!documentObject?.createElement || !parent?.appendChild || !root?.setAttribute) return null;
  const styleElement = documentObject.createElement("style");
  const scope = context.scope;
  styleElement.setAttribute(VALUE_STYLE_ELEMENT_ATTRIBUTE, scope);
  const originalScope = root.getAttribute(VALUE_STYLE_SCOPE_ATTRIBUTE);
  root.setAttribute(VALUE_STYLE_SCOPE_ATTRIBUTE, scope);
  parent.appendChild(styleElement);
  const state = {
    root,
    scope,
    styleElement,
    originalScope,
    declarations: [],
    indexes: new Map(),
    owners: new Map(),
    dirty: false,
  };
  context.preparedStyle = state;
  return state;
}

function preparedStyleState(root: Element, context: EnhancedElementContext) {
  if (context.preparedStyle) return context.preparedStyle;
  return createPreparedStyleState(root, context);
}

function registerPreparedValueStyle(state: PreparedStyleState, declaration: string) {
  const existing = state.indexes.get(declaration);
  if (existing != null) return existing;
  const index = state.declarations.length;
  state.declarations.push(declaration);
  state.indexes.set(declaration, index);
  state.dirty = true;
  return index;
}

// Preserve existing CSS rules across paragraph commits to avoid invalidating
// every previously rendered paragraph when only new declarations are added.
const syncedPreparedRules = new WeakMap<PreparedStyleState, string[]>();

function syncPreparedValueStyles(state: PreparedStyleState) {
  if (!state.dirty) return;
  const rootScope = `[${VALUE_STYLE_SCOPE_ATTRIBUTE}="${state.scope}"]`;
  const snapshotValuesActive = state.owners.has(SNAPSHOT_STYLE_OWNER);
  const runtimeValuesActive = Array.from(state.owners.keys()).some((owner) =>
    owner !== SNAPSHOT_STYLE_OWNER);
  const rules = state.declarations.flatMap((declaration: string, index: number) => {
    // PreparedValueNamespaceIsolation: build-time snapshot CSS remains live in
    // the document so it can restore exact first-paint nodes. Runtime lowering
    // must use a distinct class namespace; otherwise the same compact index can
    // combine unrelated important properties (for example snapshot
    // letter-spacing plus runtime margin-right) even when the scoped runtime
    // rule has higher specificity.
    const snapshotRule = snapshotValuesActive
      ? `${rootScope} [data-tq-rendered="true"] .${GeneratedPreparedDom.snapshotValueStyleClass(index)}{${declaration}}`
      : "";
    const runtimeRule = runtimeValuesActive
      ? `${rootScope}[${VALUE_STYLE_SCOPE_ATTRIBUTE}] [data-tq-rendered="true"] .${runtimeValueStyleClass(runtimeValueStyleKey(declaration))}{${declaration}}`
      : "";
    return [snapshotRule, runtimeRule].filter(Boolean);
  });

  // Owner changes may remove a namespace; replace only the differing suffix.
  // Detached/non-browser style elements retain the text-based fallback.
  const sheet = state.styleElement.sheet;
  const previous = syncedPreparedRules.get(state) ?? [];
  if (sheet) {
    let shared = 0;
    while (shared < previous.length && previous[shared] === rules[shared]) shared++;
    while (sheet.cssRules.length > shared) sheet.deleteRule(shared);
    for (let index = shared; index < rules.length; index++) sheet.insertRule(rules[index], index);
  } else {
    state.styleElement.textContent = rules.join("");
  }
  syncedPreparedRules.set(state, rules);
  state.dirty = false;
}

function removePreparedStyleState(state: PreparedStyleState, context: EnhancedElementContext) {
  context.preparedStyle = null;
  state.styleElement.remove?.();
  if (state.styleElement.parentNode) state.styleElement.parentNode.removeChild(state.styleElement);
  if (state.originalScope == null) state.root.removeAttribute(VALUE_STYLE_SCOPE_ATTRIBUTE);
  else state.root.setAttribute(VALUE_STYLE_SCOPE_ATTRIBUTE, state.originalScope);
}

/** Installs the compact snapshot's dynamic declarations before DOM adoption. */
export function installPreparedValueStyles(root: Element, context: EnhancedElementContext, declarations: string[], renderFontFamilies: string[] = []) {
  if (!Array.isArray(declarations)) throw new Error("InvalidPreparedValueStyles");
  if (!Array.isArray(renderFontFamilies) || renderFontFamilies.some((family) =>
    typeof family !== "string" || !family.trim())) throw new Error("InvalidPreparedRenderFontFamilies");
  releasePreparedValueStyleRoot(root, context);
  if (declarations.length === 0) return false;
  const state = preparedStyleState(root, context);
  if (!state) throw new Error("PreparedValueStyleHostUnavailable");
  try {
    const indexes = declarations.map((declaration, expectedIndex) => {
      if (typeof declaration !== "string" || !declaration) {
        throw new Error("InvalidPreparedValueStyleDeclaration");
      }
      const index = registerPreparedValueStyle(state, declaration);
      if (index !== expectedIndex) throw new Error("DuplicatePreparedValueStyleDeclaration");
      return index;
    });
    state.owners.set(SNAPSHOT_STYLE_OWNER, new Set(indexes));
    syncPreparedValueStyles(state);
    return true;
  } catch (error) {
    removePreparedStyleState(state, context);
    throw error;
  }
}

export function releasePreparedParagraphStyles(host: Element, context: EnhancedElementContext) {
  const state = context.preparedStyle;
  if (!state) return false;
  state.owners.delete(host);
  if (state.owners.size === 0) removePreparedStyleState(state, context);
  return true;
}

export function releasePreparedValueStyleRoot(root: Element, context: EnhancedElementContext) {
  const state = context.preparedStyle;
  if (!state) return false;
  removePreparedStyleState(state, context);
  return true;
}

export function releasePreparedStyleState(state: PreparedStyleState, context: EnhancedElementContext): void {
  removePreparedStyleState(state, context);
}

// --- Wire mapping into the generated lowering ---

function toTypedStyleDelta(style: StyleDelta | PlanCell["styleDelta"] | undefined): GeneratedStyleDelta | null {
  if (style == null) return null;
  return {
    fontSize: style.fontSize == null ? null : Number(style.fontSize),
    fontWeight: style.fontWeight == null ? null : Number(style.fontWeight),
    italic: style.italic == null ? null : style.italic === true,
  };
}

function toTypedCell(cell: PreparedLayoutPlanCell): GeneratedPreparedPlanCell {
  // PlanJson writes the generated styleDelta under the key style.
  const style = cell.style ?? cell.styleDelta ?? null;
  return {
    rangeStart: Number(cell.rangeStart),
    rangeEnd: Number(cell.rangeEnd),
    source: String(cell.source),
    display: String(cell.display),
    drawX: Number(cell.drawX),
    naturalWidth: Number(cell.naturalWidth),
    leadingLayoutAdvance: Number(cell.leadingLayoutAdvance),
    advance: cell.advance == null ? null : Number(cell.advance),
    shapingBoundary: cell.shapingBoundary === true,
    openTypeFeatures: cell.openTypeFeatures == null ? null : Array.from(cell.openTypeFeatures, String),
    style: toTypedStyleDelta(style),
    styleSignature: JSON.stringify(style),
    punctuationSignature: JSON.stringify([
      cell.punctuationInkFloor ?? null,
      cell.punctuationBodyWidth ?? null,
    ]),
    latin: cell.latin === true,
    dashStrategy: cell.dashStrategy ?? null,
    shapingLanguage: cell.shapingLanguage ?? null,
    resolvedFace: cell.resolvedFace ?? null,
    glyphIds: cell.glyphIds ?? null,
    shapingEvidence: cell.shapingEvidence ?? null,
    punctuationInkFloor: cell.punctuationInkFloor ?? null,
    punctuationBodyWidth: cell.punctuationBodyWidth ?? null,
    renderFontFamily: cell.renderFontFamily ?? null,
    inlineObject: cell.inlineObject ?? null,
  };
}

function toTypedLine(line: PreparedLayoutPlanLine): GeneratedPreparedPlanLine {
  // The generated enum carries the same reason name in its kind field.
  const reason = line.endReason;
  return {
    cells: line.cells.map(toTypedCell),
    top: Number(line.top),
    bottom: Number(line.bottom),
    baseline: Number(line.baseline),
    indent: Number(line.indent),
    visualWidth: Number(line.visualWidth),
    hyphenAdvance: Number(line.hyphenAdvance),
    endReason: typeof reason === "object" && reason != null ? reason.kind : String(reason),
    rangeStart: Number(line.rangeStart),
    rangeEnd: Number(line.rangeEnd),
  };
}

function toTypedDecorationSegment(segment: EvidenceDecorationSegment): GeneratedEvidenceDecorationSegment {
  const kind = String(segment.kind);
  if (kind === "ProperNoun") {
    return {
      left: Number(segment.left),
      top: Number(segment.top),
      right: Number(segment.right),
      kind: EvidenceDecorationKind.ProperNoun,
    };
  }
  if (kind === "BookTitle") {
    return {
      left: Number(segment.left),
      top: Number(segment.top),
      right: Number(segment.right),
      kind: EvidenceDecorationKind.BookTitle,
    };
  }
  throw new Error("UnsupportedPreparedDecorationSegment:" + kind);
}

function toTypedEmphasisDot(dot: EvidenceEmphasisDot): GeneratedEvidenceEmphasisDot {
  return {
    clusterRangeStart: Number(dot.clusterRangeStart),
    anchorX: Number(dot.anchorX),
    anchorY: Number(dot.anchorY),
    dotDiameter: Number(dot.dotDiameter),
  };
}

function toTypedRuby(ruby: PlanRubyAnnotation): GeneratedRubyAnnotation {
  return {
    fontSize: Number(ruby.fontSize),
    ascent: Number(ruby.ascent),
    fontFamilies: Array.from(ruby.fontFamilies ?? [], String),
    text: String(ruby.text),
    fontWeight: Number(ruby.fontWeight),
    centerX: Number(ruby.centerX),
    baselineY: Number(ruby.baselineY),
  };
}

function toTypedBopomofoZone(zone: PlanBopomofoZone): GeneratedBopomofoZone {
  const placements = Array.from(zone.placements ?? [], (placement) => ({
    text: String(placement.text),
    role: String(placement.role),
    left: Number(placement.left),
    top: Number(placement.top),
    width: Number(placement.width),
    height: Number(placement.height),
  }));
  return {
    text: String(zone.text),
    fontWeight: Number(zone.fontWeight),
    fontFamilies: Array.from(zone.fontFamilies ?? [], String),
    placements,
  };
}

function toTypedPlan(plan: PreparedLayoutPlan): GeneratedPreparedPlan {
  const rubyDecisions = Array.from(plan.rubyDecisions ?? [], (ruby) => {
    const typed = toTypedRuby(ruby);
    return {
      fontSize: typed.fontSize,
      ascent: typed.ascent,
      fontFamilies: typed.fontFamilies,
      text: typed.text,
      fontWeight: typed.fontWeight,
      centerX: typed.centerX,
      baselineY: typed.baselineY,
      baseRangeEnd: Number(ruby.baseRangeEnd),
    };
  });
  const bopomofoDecisions = Array.from(plan.bopomofoDecisions ?? [], (zone) => {
    const typed = toTypedBopomofoZone(zone);
    return {
      text: typed.text,
      fontWeight: typed.fontWeight,
      fontFamilies: typed.fontFamilies,
      placements: typed.placements,
      baseRangeEnd: Number(zone.baseRangeEnd),
    };
  });
  return {
    height: Number(plan.height),
    lines: plan.lines.map(toTypedLine),
    emphasisRanges: Array.from(plan.emphasisRanges ?? [], (range) =>
      Array.isArray(range) ? { start: Number(range[0]), end: Number(range[1]) } : range),
    rubyDecisions,
    bopomofoDecisions,
    inlineEdges: Array.from(plan.inlineEdges ?? [], (edge) => ({
      offset: Number(edge.offset),
      inlineStart: edge.inlineStart == null ? null : Number(edge.inlineStart),
      inlineEnd: edge.inlineEnd == null ? null : Number(edge.inlineEnd),
    })),
    decorationSegments: plan.decorationSegments == null
      ? null
      : Array.from(plan.decorationSegments, toTypedDecorationSegment),
    emphasisDots: plan.emphasisDots == null
      ? null
      : Array.from(plan.emphasisDots, toTypedEmphasisDot),
    fontSize: Number(plan.fontSize),
    overlayWidth: Number(plan.overlayWidth),
  };
}

function toTypedAttribute(entry: readonly [string, string]): GeneratedAttributeEntry {
  return { name: String(entry[0]), value: String(entry[1]) };
}

function toTypedSemantics(
  semantics: readonly (SnapshotSemanticSpan | LiveSemanticSpan)[],
): GeneratedPreparedSemanticSpan[] {
  return semantics.map((span, index) => ({
    index,
    start: Number(span.start),
    end: Number(span.end),
    tagName: String(span.tagName),
    sourceIndex: "sourceIndex" in span ? Number(span.sourceIndex) : 0,
    attributes: "attributes" in span
      ? Array.from(span.attributes, toTypedAttribute)
      : [],
    signature: JSON.stringify(span),
  }));
}

function toTypedRenderTextSpans(
  spans: readonly RenderTextSpanEntry[],
): GeneratedPreparedRenderTextSpan[] {
  return Array.from(spans, (span) => {
    const fontFamilies = Array.from(span.fontFamilies, String);
    return {
      start: Number(span.start),
      end: Number(span.end),
      fontFamilies,
      signature: JSON.stringify(fontFamilies),
    };
  });
}

/** Serializes one typed markup artifact back to the nested wire arrays. */
function artifactToWire(artifact: GeneratedMarkupArtifact): PreparedWireArtifact {
  if (artifact.kind === "Text") {
    return ["#", artifact.text] as const;
  }
  const entries = artifact.entries.map((entry) => [entry.name, entry.value] as const);
  return [
    artifact.tag,
    entries,
    artifact.children.map(artifactToWire),
  ] as const;
}

/**
 * Lowers the canonical prepared-layout wire format to the sparse DOM wire used
 * by both build-time snapshots and browser runtime rendering.
 */
export function renderPreparedParagraphArtifact(
  planOrJson: string | PreparedLayoutPlan,
  typographyOrLocale: string | Record<string, unknown> = DEFAULT_LOCALE,
  options: PreparedParagraphRenderOptions = {},
): PreparedParagraphArtifactResult {
  const plan = preparedPlan(planOrJson);
  const locale = preparedLocale(typographyOrLocale);
  const styleClassFor = typeof options.styleClassFor === "function" ? options.styleClassFor : null;
  if (plan?.schema !== SNAPSHOT_SCHEMA || plan?.layoutRevision !== LAYOUT_REVISION) {
    throw new Error("UnsupportedPreparedLayoutRevision");
  }
  const paragraphHeight = Number(plan.height);
  if (!Number.isFinite(paragraphHeight) || paragraphHeight < 0 || !Array.isArray(plan.lines)) {
    throw new Error("InvalidPreparedParagraphGeometry");
  }
  const sourceText = plan.lines.flatMap((line) => line.cells).map((cell) => cell.source).join("");
  const semanticReplay = options.semanticReplay ?? "snapshot-safe";
  if (semanticReplay !== "snapshot-safe" && semanticReplay !== "live-source") {
    throw new Error("UnsupportedPreparedSemanticReplay:" + semanticReplay);
  }
  const liveSource = semanticReplay === "live-source";
  const liveSemanticElements = Array.from(options.liveSemanticElements ?? []);
  const liveSemantics = liveSource
    ? normalizeLiveSemantics(options.sourceText ?? sourceText, options.semantics ?? [])
    : null;
  const semantics = liveSemantics ??
    normalizeSnapshotSemantics(options.sourceText ?? sourceText, options.semantics ?? []);
  if (liveSemantics) {
    const seenSourceIndices = new Set<number>();
    for (const semantic of liveSemantics) {
      const sourceElement = liveSemanticElements[semantic.sourceIndex];
      if (!sourceElement || typeof sourceElement.cloneNode !== "function" ||
          String(sourceElement.tagName ?? "").toLowerCase() !== semantic.tagName) {
        throw new Error(
          "LiveSemanticSourceMismatch:" + semantic.sourceIndex + ":" + semantic.tagName,
        );
      }
      if (seenSourceIndices.has(semantic.sourceIndex)) {
        throw new Error("DuplicateLiveSemanticSource:" + semantic.sourceIndex);
      }
      seenSourceIndices.add(semantic.sourceIndex);
    }
  }
  const renderTextSpans = Array.from(options.renderTextSpans ?? [], (span) => {
    const start = Number(span?.start);
    const end = Number(span?.end);
    const fontFamilies = Array.from(span?.fontFamilies ?? [], String)
      .map((family) => family.trim())
      .filter(Boolean);
    if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || end <= start ||
        end > (options.sourceText ?? sourceText).length || fontFamilies.length === 0) {
      throw new Error("InvalidPreparedRenderTextSpan");
    }
    return { start, end, fontFamilies };
  });
  const cjkStrongSemantics = Array.from(options.cjkStrongSemantics ?? []);
  const emphasisDotColorFn = typeof options.emphasisDotColor === "function"
    ? options.emphasisDotColor
    : null;
  // The generated option records carry function-valued fields whose nullability
  // is emitted on the return type rather than the function pointer (see the
  // boring TS emitter note), so the null case needs the documented cast.
  const typedOptions = {
    styleClassFor: styleClassFor == null
      ? null
      : { resolve: (declaration: string): string => styleClassFor(declaration) },
    liveSource,
    semantics: toTypedSemantics(semantics),
    renderTextSpans: toTypedRenderTextSpans(renderTextSpans),
    cjkStrongSemantics: Array.from(cjkStrongSemantics, (entry) => ({
      start: Number(entry.start),
      end: Number(entry.end),
      weight: Number(entry.weight),
    })),
    inlineBoxes: Array.from(options.inlineBoxes ?? [], (box) => ({
      start: Number(box.start),
      end: Number(box.end),
      inlineStartPx: Number(box.inlineStartPx),
      inlineEndPx: Number(box.inlineEndPx),
    })),
    emphasisDotColor: emphasisDotColorFn == null
      ? null
      : {
          resolve: (offset: number): string => {
            const color = emphasisDotColorFn(offset);
            return color == null ? "" : String(color);
          },
        },
  };
  let lowered: GeneratedPreparedArtifactResult;
  try {
    lowered = PreparedArtifact.renderPreparedParagraphArtifact(toTypedPlan(plan), locale, typedOptions);
  } catch (error) {
    // D3: the generated core throws its enum-carrying exception; the API keeps
    // the plain Error contract callers already handle.
    throw error instanceof Error ? new Error(error.message) : error;
  }
  return Object.freeze({
    html: lowered.html,
    artifact: lowered.artifact.map(artifactToWire),
    liveSemanticCount: lowered.liveSemanticCount,
    inlineObjectCount: lowered.inlineObjectCount,
    markerCount: lowered.markerCount,
  });
}

export function renderPreparedParagraph(planOrJson: string | PreparedLayoutPlan, typographyOrLocale: string | Record<string, unknown> = DEFAULT_LOCALE) {
  return renderPreparedParagraphArtifact(planOrJson, typographyOrLocale).html;
}

/**
 * LiveSourceSemanticReplay: replace inert placeholder spans with shallow clones
 * of the current source elements. Host attributes and CSS behavior never pass
 * through snapshot HTML, while Worker-owned geometry stays intact.
 */
function restoreLiveSemanticElements(
  host: Element,
  sourceElements: Element[],
  expectedCount: number,
  semantics: readonly SnapshotSemanticOption[] = [],
  cjkStrongSemantics: CjkStrongSemanticEntry[] = [],
) {
  if (expectedCount === 0) return;
  const placeholders = Array.from(host.querySelectorAll(`[${LIVE_SEMANTIC_INDEX_ATTRIBUTE}]`));
  if (placeholders.length !== expectedCount) {
    throw new Error(
      `LiveSemanticMarkerCountMismatch:expected=${expectedCount};actual=${placeholders.length}`,
    );
  }
  const seen = new Set();
  const cjkStrongList = Array.from(cjkStrongSemantics ?? []);
  const cjkBySourceIndex = new Map();
  if (cjkStrongList.length > 0) {
    for (const semantic of semantics) {
      const match = cjkStrongList.find(
        (entry) => Number(entry?.start) === semantic.start && Number(entry?.end) === semantic.end,
      );
      if (match != null) {
        const sourceIndex = Number.isSafeInteger(Number(semantic.sourceIndex))
          ? Number(semantic.sourceIndex)
          : semantics.indexOf(semantic);
        cjkBySourceIndex.set(sourceIndex, match);
      }
    }
  }
  for (const placeholder of placeholders) {
    const sourceIndex = Number(placeholder.getAttribute(LIVE_SEMANTIC_INDEX_ATTRIBUTE));
    const source = sourceElements[sourceIndex];
    if (!Number.isSafeInteger(sourceIndex) || seen.has(sourceIndex) ||
        !source || typeof source.cloneNode !== "function") {
      throw new Error(`LiveSemanticSourceUnavailable:${sourceIndex}`);
    }
    seen.add(sourceIndex);
    const clone = source.cloneNode(false) as HTMLElement;
    clone.setAttribute("data-tq-source-semantic", "true");
    const cjkStrong = cjkBySourceIndex.get(sourceIndex);
    if (cjkStrong != null) {
      clone.setAttribute("data-tq-cjk-emphasis", "true");
      clone.style.setProperty("font-weight", String(cjkStrong.weight), "important");
    }
    while (placeholder.firstChild) clone.appendChild(placeholder.firstChild);
    placeholder.replaceWith(clone);
  }
}

/**
 * InlineObjectCloneSwap (ADR 0053 B7.3): replace pending placeholders with
 * deep clones of the caller's live inline elements, mirroring the renderer's
 * appendInlineObject: data-tq-inline-object="true", data-tq-object-range, and
 * margin-right = marginRight + trailingGap applied as important only in the
 * trailing-margin branch. Elements cannot ride the Worker plan, so the caller
 * supplies them per range, exactly as it supplies liveSemanticElements.
 */
function swapInlineObjectClones(host: Element, inlineObjects: InlineObjectOptionEntry[]) {
  const placeholders = Array.from(host.querySelectorAll('[data-tq-inline-object="pending"]'));
  if (placeholders.length === 0) return 0;
  const byRange = new Map();
  for (const entry of inlineObjects) {
    const key = `${Number(entry.start)}-${Number(entry.end)}`;
    if (byRange.has(key)) throw new Error(`ConflictingInlineObjectRange:${key}`);
    byRange.set(key, entry);
  }
  for (const placeholder of placeholders) {
    const key = placeholder.getAttribute("data-tq-object-range");
    const entry = byRange.get(key);
    if (!entry || !entry.element || typeof entry.element.cloneNode !== "function") {
      throw new Error(`InlineObjectSourceUnavailable:${key}`);
    }
    const clone = entry.element.cloneNode(true);
    clone.setAttribute("data-tq-inline-object", "true");
    clone.setAttribute("data-tq-object-range", key);
    const trailingMargin = placeholder.getAttribute("data-tq-object-trailing-margin");
    if (trailingMargin != null) {
      const margin = Number(entry.marginRight ?? 0) + Number(trailingMargin);
      clone.style.setProperty("margin-right", `${margin}px`, "important");
    }
    placeholder.replaceWith(clone);
  }
  return placeholders.length;
}

/**
 * Replays the canonical markup in a browser host. `innerHTML` deliberately uses
 * the browser HTML parser, matching the DOM produced when the same string is
 * delivered inside an SSR snapshot template.
 */
export function renderPreparedParagraphInto(
  host: PreparedParagraphHost,
  planOrJson: string | PreparedLayoutPlan,
  typographyOrLocale: string | Record<string, unknown> = DEFAULT_LOCALE,
  options: PreparedParagraphRenderOptions = {},
  context: EnhancedElementContext,
): PreparedParagraphIntoResult {
  if (host == null || !("innerHTML" in Object(host)) || typeof host.querySelectorAll !== "function") {
    throw new Error("InvalidPreparedParagraphHost");
  }
  const root = host.closest?.(ROOT_SELECTOR) ?? host;
  const state = preparedStyleState(root, context);
  const usedStyles = new Set<number>();
  const emphasisDotColor = options.emphasisDotColor ?? (
    options.semantics && options.liveSemanticElements && typeof globalThis.getComputedStyle === "function"
      ? (offset) => {
          if (!Number.isFinite(offset)) return null;
          let maxOrder = -Infinity;
          let selected = null;
          for (const semantic of options.semantics!) {
            const start = Number(semantic.start);
            const end = Number(semantic.end);
            if (offset >= start && offset < end) {
              const order = Number(semantic.order ?? 0);
              if (order > maxOrder) {
                maxOrder = order;
                selected = semantic;
              }
            }
          }
          if (selected?.sourceIndex == null) return null;
          const element = options.liveSemanticElements![selected.sourceIndex];
          if (!element) return null;
          try {
            const color = globalThis.getComputedStyle(element)?.color;
            return typeof color === "string" && color.trim().length > 0 ? color.trim() : null;
          } catch {
            return null;
          }
        }
      : null
  );
  let lowered;
  try {
    lowered = renderPreparedParagraphArtifact(planOrJson, typographyOrLocale, {
      ...options,
      emphasisDotColor,
      styleClassFor: state
        ? (declaration: string) => {
          const index = registerPreparedValueStyle(state, declaration);
          usedStyles.add(index);
          return runtimeValueStyleClass(runtimeValueStyleKey(declaration));
        }
        : null,
    });
  } catch (error) {
    if (state?.owners.size === 0) removePreparedStyleState(state, context);
    throw error;
  }
  if (state) {
    state.owners.set(host, usedStyles);
    state.dirty = true;
    syncPreparedValueStyles(state);
  }
  host.innerHTML = lowered.html;
  if (lowered.liveSemanticCount > 0) {
    restoreLiveSemanticElements(
      host,
      Array.from(options.liveSemanticElements ?? []),
      lowered.liveSemanticCount,
      options.semantics,
      Array.from(options.cjkStrongSemantics ?? []),
    );
  }
  const swappedInlineObjects = swapInlineObjectClones(
    host,
    Array.from(options.inlineObjects ?? []),
  );
  const markers = Array.from(host.querySelectorAll(LINE_MARKER_SELECTOR));
  if (markers.length !== lowered.markerCount) {
    throw new Error(
      `PreparedDomMarkerCountMismatch:expected=${lowered.markerCount};actual=${markers.length}`,
    );
  }
  return Object.freeze({
    html: lowered.liveSemanticCount > 0 || swappedInlineObjects > 0
      ? host.innerHTML
      : lowered.html,
    markers,
  });
}


export const version = 1;
export const semanticReplayRevision = 1;
