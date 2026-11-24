import { globalServices, initializeGlobalServices } from "@tiqian/core/src/services/global-services.js";
import { SNAPSHOT_SCHEMA, LAYOUT_REVISION } from "@tiqian/core/snapshot-schema";
import { createEnhanceContext } from "@tiqian/core/src/engine/context/enhance-context.js";
import type { EnhancedElementContext } from "@tiqian/core/src/engine/context/enhance-context.js";
import type { ReplayMetricItem, ReplayShapeItem } from "@tiqian/core/src/measurement/replay-entry-codec.js";
import type { GrantController, TiqianLayoutWorkerInstance } from "@tiqian/core/src/engine/coordination/coordination-service.js";

export function probe<T>(value: unknown): T {
  return value as T;
}

// Type definitions for test environment
type FrameRequestCallback = (time: number) => void;
type TimeRemainingFn = () => number;

interface IdleCallbackArg {
  didTimeout: boolean;
  timeRemaining: TimeRemainingFn;
}

type IdleCallback = (arg: IdleCallbackArg) => number;
type IdleRequestCallback = (callback: IdleCallback) => number;

interface DOMRectJSON {
  x: number;
  y: number;
  top: number;
  left: number;
  right: number;
  bottom: number;
  width: number;
  height: number;
}

interface EventInitOptions {
  bubbles?: boolean;
  cancelable?: boolean;
  detail?: unknown;
}

interface ClipboardEventInitOptions extends EventInitOptions {
  clipboardData?: unknown;
}

interface StylePropertyView {
  columns?: string;
  display?: string;
  inlineSize?: string;
  width?: string;
  height?: string;
  paddingLeft?: string;
  paddingRight?: string;
}

type GetComputedStyleFn = (element: Element, pseudo?: string | null) => CSSStyleDeclaration;

interface GlobalWithGetComputedStyle {
  getComputedStyle?: GetComputedStyleFn;
}

interface GlobalWithDocument {
  document?: FakeDocument;
}

type NowFn = () => number;

interface PerformanceDouble {
  now: NowFn;
}

interface GlobalWithPerformance {
  performance: PerformanceDouble;
}

type GetSelectionFn = () => FakeSelection;

interface GlobalWithSelection {
  getSelection?: GetSelectionFn;
}

interface MultiColumnAncestor {
  ancestor: FakeElement;
  colWidth: number;
  colGap: number;
  colHeight: number;
}

interface HorizontalPadding {
  left: number;
  right: number;
}

export interface AttributeTupleEntry {
  name: string;
  value: string;
}

export type AttributeTuple = [string, string] & AttributeTupleEntry;

type VoidCallback = () => void;
type TimeCallback = (time: number) => void;
type TimeoutCallback = (callback: VoidCallback, delay?: number) => number;
type CancelIdleCallback = (id: number) => void;

type RequestFrameFn = (callback: FrameRequestCallback) => number;
type CancelFrameFn = (id: number) => void;
type ClearTimeoutFn = (id: number) => void;

interface TestAnimationFramesState {
  originalRequest: RequestFrameFn;
  originalCancel: CancelFrameFn;
  originalRequestIdle?: IdleRequestCallback;
  originalCancelIdle?: CancelIdleCallback;
  originalSetTimeout: TimeoutCallback;
  originalClearTimeout: ClearTimeoutFn;
  callbacks: Map<number, TimeCallback | VoidCallback>;
  nextId: number;
  cancelled: number;
  idleScheduled: number;
  idleBudget: number;
}

type ArrayItemFn = (index: number) => unknown;

interface ArrayWithItem {
  item?: ArrayItemFn;
}

type ContainsFn = (other: FakeNode) => boolean;

interface FakeNodeWithContains {
  contains: ContainsFn;
}

type MatchesFn = (selector: string) => boolean;

interface FakeNodeWithMatches {
  matches: MatchesFn;
}

type ReplaceChildrenFn = (...nodes: FakeNode[]) => void;
type ReplaceWithFn = (...nodes: FakeNode[]) => void;

interface FakeNodePrototypeMethods {
  replaceChildren: ReplaceChildrenFn;
  replaceWith: ReplaceWithFn;
}

interface PreparedLivePlanCell {
  rangeStart: number;
  rangeEnd: number;
  source: string;
  display: string;
  drawX: number;
  naturalWidth: number;
  leadingLayoutAdvance: number;
}

type NodeContainsFn = (node: FakeNode | null) => boolean;
interface NodeWithOptionalContains extends FakeNode {
  contains?: NodeContainsFn;
}

type ObserverCallback = (records: unknown[]) => void;

interface RuntimeServices {
  layoutJobPool: unknown;
}

export interface GrantControllerDouble {
  root: FakeElement;
  generation: number;
  deadline: number;
  quota: number;
  shouldStop(processed: number): boolean;
}

export interface SnapshotFontSessionFixtureOptions {
  failShaping?: boolean;
  failFamily?: string | null;
  failText?: string | null;
  varyFaceByText?: boolean;
  corruptShapeError?: string | null;
}

interface FixtureGlyph {
  id: number;
  advanceEm: number;
  xEm: number;
  yEm: number;
  boundsEm: number[];
}

interface LivePlanCell {
  rangeStart: number;
  rangeEnd: number;
  source: string;
  display: string;
  drawX: number;
  drawY: number;
  width: number;
  height: number;
  ascender: number;
  descender: number;
  isEngineBreak: boolean;
  isSpace: boolean;
  line: number;
  script: string;
  style: number;
}

export interface MountOptions {
  sharedStylesReady?: boolean;
}

// Read/write view of data-* attributes exposed through HostElement.dataset.
interface DatasetView {
  [key: string]: string | undefined;
}

// An element carrying the ad-hoc namespaceURI the SVG path stamps on.
interface NamespacedElement extends FakeElement {
  namespaceURI: string | null;
}

// The getComputedStyle double this host installs on globalThis.
type GlobalGetComputedStyle = (element: Element, pseudo?: string | null) => CSSStyleDeclaration;

// Fake host environment for driving Kotlin/JS runtime under Node.js test runner.
// Node does not provide rAF or DOM; the fake clock and DOM doubles below provide
// stable and synchronous execution for raw-DOM backup relayout and destruction tests.

import assert from "node:assert/strict";
import {
  FakeDocument,
  FakeElement,
  type FakeElementClassList,
  FakeFragment,
  FakeInlineStyle,
  FakeNode,
  FakeText,
  fixtureComputedStyle,
} from "./snapshot-dom-fixtures.js";
import {
  enhance,
  enhanceProgressively,
  enhanceProgressivelyFromCanonical,
  relayout,
} from "@tiqian/core/src/engine/progressive-drivers.js";
import { destroyRoot, detachRoot, optionsFromJs } from "@tiqian/core/src/engine/lifecycle.js";
import { probeRootContentDrift, reconcileRoot } from "@tiqian/core/src/engine/content-reconcile.js";
import { workerLayoutRequestForRoot } from "@tiqian/core/src/engine/worker-request.js";

export class FakeDOMRect {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
  readonly top: number;
  readonly left: number;
  readonly right: number;
  readonly bottom: number;

  constructor(x = 0, y = 0, width = 0, height = 0) {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
    this.top = y;
    this.left = x;
    this.right = x + width;
    this.bottom = y + height;
  }

  toJSON(): DOMRectJSON {
    return {
      x: this.x,
      y: this.y,
      top: this.top,
      left: this.left,
      right: this.right,
      bottom: this.bottom,
      width: this.width,
      height: this.height,
    };
  }
}

export class FakeEvent {
  readonly type: string;
  readonly bubbles: boolean;
  readonly cancelable: boolean;
  defaultPrevented: boolean;
  detail: unknown;
  target: FakeNode | null;
  currentTarget: FakeNode | null;

  constructor(type: string, init: EventInitOptions = {}) {
    this.type = type;
    this.bubbles = init.bubbles ?? false;
    this.cancelable = init.cancelable ?? false;
    this.defaultPrevented = false;
    this.detail = init.detail ?? null;
    this.target = null;
    this.currentTarget = null;
  }

  preventDefault(): void {
    if (this.cancelable) this.defaultPrevented = true;
  }
}

export class FakeCustomEvent extends FakeEvent {
  constructor(type: string, init: EventInitOptions = {}) {
    super(type, init);
    this.detail = init.detail ?? null;
  }
}

export class FakeClipboardEvent extends FakeEvent {
  readonly clipboardData: unknown;

  constructor(type: string, init: ClipboardEventInitOptions = {}) {
    super(type, init);
    this.clipboardData = init.clipboardData ?? null;
  }
}

export class FakeDataTransfer {
  readonly _data: Record<string, string>;

  constructor() {
    this._data = {};
  }

  setData(type: string, value: string): void {
    this._data[type] = String(value);
  }

  getData(type: string): string {
    return this._data[type] ?? "";
  }
}

export class FakeSelection {
  _ranges: unknown[];

  constructor() {
    this._ranges = [];
  }

  get rangeCount(): number {
    return this._ranges.length;
  }

  get isCollapsed(): boolean {
    if (this._ranges.length === 0) return true;
    const r = this._ranges[0] as { startContainer: unknown; endContainer: unknown; startOffset: number; endOffset: number };
    return r.startContainer === r.endContainer && r.startOffset === r.endOffset;
  }

  getRangeAt(index: number): unknown | null {
    return this._ranges[index] ?? null;
  }

  removeAllRanges(): void {
    this._ranges = [];
  }

  addRange(range: unknown): void {
    this._ranges.push(range);
  }

  toString(): string {
    if (this._ranges.length === 0) return "";
    return this._ranges.map((r) => String(r)).join("");
  }
}

function splitSelectorList(selector: string): string[] {
  const parts: string[] = [];
  let curr = "";
  let parenDepth = 0;
  let bracketDepth = 0;
  let quote: string | null = null;
  for (let i = 0; i < selector.length; i++) {
    const ch = selector[i];
    if (quote) {
      if (ch === quote) quote = null;
      curr += ch;
    } else if (ch === '"' || ch === "'") {
      quote = ch;
      curr += ch;
    } else if (ch === "(") {
      parenDepth++;
      curr += ch;
    } else if (ch === ")") {
      if (parenDepth > 0) parenDepth--;
      curr += ch;
    } else if (ch === "[") {
      bracketDepth++;
      curr += ch;
    } else if (ch === "]") {
      if (bracketDepth > 0) bracketDepth--;
      curr += ch;
    } else if (ch === "," && parenDepth === 0 && bracketDepth === 0) {
      if (curr.trim()) parts.push(curr.trim());
      curr = "";
    } else {
      curr += ch;
    }
  }
  if (curr.trim()) parts.push(curr.trim());
  return parts;
}

function splitByWhitespace(selector: string): string[] {
  const parts: string[] = [];
  let curr = "";
  let parenDepth = 0;
  let bracketDepth = 0;
  let quote: string | null = null;
  for (let i = 0; i < selector.length; i++) {
    const ch = selector[i];
    if (quote) {
      if (ch === quote) quote = null;
      curr += ch;
    } else if (ch === '"' || ch === "'") {
      quote = ch;
      curr += ch;
    } else if (ch === "(") {
      parenDepth++;
      curr += ch;
    } else if (ch === ")") {
      if (parenDepth > 0) parenDepth--;
      curr += ch;
    } else if (ch === "[") {
      bracketDepth++;
      curr += ch;
    } else if (ch === "]") {
      if (bracketDepth > 0) bracketDepth--;
      curr += ch;
    } else if (/\s/.test(ch) && parenDepth === 0 && bracketDepth === 0) {
      if (curr) parts.push(curr);
      curr = "";
    } else {
      curr += ch;
    }
  }
  if (curr) parts.push(curr);
  return parts;
}

function splitByCombinator(selector: string, combinator: string): string[] {
  const parts: string[] = [];
  let curr = "";
  let parenDepth = 0;
  let bracketDepth = 0;
  let quote: string | null = null;
  for (let i = 0; i < selector.length; i++) {
    const ch = selector[i];
    if (quote) {
      if (ch === quote) quote = null;
      curr += ch;
    } else if (ch === '"' || ch === "'") {
      quote = ch;
      curr += ch;
    } else if (ch === "(") {
      parenDepth++;
      curr += ch;
    } else if (ch === ")") {
      if (parenDepth > 0) parenDepth--;
      curr += ch;
    } else if (ch === "[") {
      bracketDepth++;
      curr += ch;
    } else if (ch === "]") {
      if (bracketDepth > 0) bracketDepth--;
      curr += ch;
    } else if (ch === combinator && parenDepth === 0 && bracketDepth === 0) {
      if (curr.trim()) parts.push(curr.trim());
      curr = "";
    } else {
      curr += ch;
    }
  }
  if (curr.trim()) parts.push(curr.trim());
  return parts;
}

function matchesHostSelector(element: FakeElement, selector: string, scopeElement: FakeElement | null = null): boolean {
  if (!element || element.nodeType !== 1) return false;
  if (selector === "*") return true;
  const parts = splitSelectorList(selector);
  if (parts.length > 1) {
    return parts.some((p) => matchesHostSelector(element, p, scopeElement));
  }

  if (selector === ":scope") {
    return element === scopeElement;
  }

  if (selector.includes(">")) {
    const segments = splitByCombinator(selector, ">");
    if (segments.length > 1) {
      let curr: FakeElement | null = element;
      for (let i = segments.length - 1; i >= 0; i--) {
        if (!curr || curr.nodeType !== 1) return false;
        const seg = segments[i];
        if (seg === ":scope") {
          if (curr !== scopeElement) return false;
        } else if (!matchesCompound(curr, seg)) {
          return false;
        }
        curr = curr.parentElement;
      }
      return true;
    }
  }

  const spaceTokens = splitByWhitespace(selector);
  if (spaceTokens.length > 1) {
    const targetSelector = spaceTokens[spaceTokens.length - 1];
    if (!matchesCompound(element, targetSelector)) return false;
    let ancestor = element.parentElement;
    let tokenIndex = spaceTokens.length - 2;
    while (ancestor && tokenIndex >= 0) {
      if (spaceTokens[tokenIndex] === ":scope") {
        if (ancestor !== scopeElement) return false;
        tokenIndex -= 1;
      } else if (matchesCompound(ancestor, spaceTokens[tokenIndex])) {
        tokenIndex -= 1;
      }
      ancestor = ancestor.parentElement;
    }
    return tokenIndex < 0;
  }

  return matchesCompound(element, selector);
}

function matchesCompound(element: FakeElement, selector: string): boolean {
  if (!element || element.nodeType !== 1) return false;
  if (selector === "*") return true;

  if (selector.startsWith(":is(") && selector.endsWith(")")) {
    const inside = selector.slice(4, -1);
    const subSelectors = splitSelectorList(inside);
    return subSelectors.some((sub) => matchesHostSelector(element, sub));
  }

  let s = selector.trim();
  const tagMatch = /^([a-zA-Z0-9_-]+)/.exec(s);
  if (tagMatch) {
    if (element.tagName !== tagMatch[1].toUpperCase()) return false;
    s = s.slice(tagMatch[0].length);
  } else if (s.startsWith("*")) {
    s = s.slice(1);
  }

  while (s.length > 0) {
    if (s.startsWith(":not(")) {
      let depth = 0;
      let endIdx = -1;
      for (let i = 4; i < s.length; i++) {
        if (s[i] === "(") depth++;
        else if (s[i] === ")") {
          depth--;
          if (depth === 0) {
            endIdx = i;
            break;
          }
        }
      }
      if (endIdx < 0) return false;
      const negated = s.slice(5, endIdx).trim();
      if (matchesHostSelector(element, negated)) return false;
      s = s.slice(endIdx + 1);
    } else if (s.startsWith(":is(")) {
      let depth = 0;
      let endIdx = -1;
      for (let i = 3; i < s.length; i++) {
        if (s[i] === "(") depth++;
        else if (s[i] === ")") {
          depth--;
          if (depth === 0) {
            endIdx = i;
            break;
          }
        }
      }
      if (endIdx < 0) return false;
      const inside = s.slice(4, endIdx).trim();
      const subSelectors = splitSelectorList(inside);
      if (!subSelectors.some((sub) => matchesHostSelector(element, sub))) return false;
      s = s.slice(endIdx + 1);
    } else if (s.startsWith("#")) {
      const idMatch = /^#([a-zA-Z0-9_-]+)/.exec(s);
      if (!idMatch) return false;
      if (element.getAttribute("id") !== idMatch[1]) return false;
      s = s.slice(idMatch[0].length);
    } else if (s.startsWith(".")) {
      const classMatch = /^\.([a-zA-Z0-9_-]+)/.exec(s);
      if (!classMatch) return false;
      const classes = (element.getAttribute("class") || "").trim().split(/\s+/);
      if (!classes.includes(classMatch[1])) return false;
      s = s.slice(classMatch[0].length);
    } else if (s.startsWith("[")) {
      const attrMatch = /^\[([a-zA-Z0-9_-]+)(?:([~|^$*]?=)(?:"([^"]*)"|'([^']*)'|([^\]]+)))?\]/.exec(s);
      if (!attrMatch) return false;
      const [, attrName, op, dblVal, sglVal, rawVal] = attrMatch;
      if (!element.hasAttribute(attrName)) return false;
      const expectedVal = dblVal ?? sglVal ?? rawVal;
      if (op && expectedVal != null) {
        const actualVal = element.getAttribute(attrName);
        if (actualVal == null) return false;
        if (op === "=" && actualVal !== expectedVal) return false;
        if (op === "~=" && !actualVal.split(/\s+/).includes(expectedVal)) return false;
        if (op === "|=" && actualVal !== expectedVal && !actualVal.startsWith(expectedVal + "-")) return false;
        if (op === "^=" && !actualVal.startsWith(expectedVal)) return false;
        if (op === "$=" && !actualVal.endsWith(expectedVal)) return false;
        if (op === "*=" && !actualVal.includes(expectedVal)) return false;
      }
      s = s.slice(attrMatch[0].length);
    } else {
      return false;
    }
  }

  return true;
}

// Browsers expand padding/margin shorthands into longhands in the CSSOM.
// The fake host parses declarations on demand, so longhand queries must
// resolve through a present shorthand with the standard 1-4 value box
// rules; expansion happens in declaration order so a later longhand still
// overrides an earlier shorthand and vice versa, as in the cascade.
const BOX_SHORTHANDS = new Map<string, string[]>([
  ["padding", ["padding-top", "padding-right", "padding-bottom", "padding-left"]],
  ["margin", ["margin-top", "margin-right", "margin-bottom", "margin-left"]],
]);

function expandBoxShorthand(prop: string, value: string): Array<[string, string]> | null {
  const sides = BOX_SHORTHANDS.get(prop);
  if (!sides) return null;
  const parts = String(value).trim().split(/\s+/);
  if (parts.length < 1 || parts.length > 4 || parts.some((part) => !part)) return null;
  const top = parts[0];
  const right = parts.length > 1 ? parts[1] : top;
  const bottom = parts.length > 2 ? parts[2] : top;
  const left = parts.length > 3 ? parts[3] : right;
  return [
    [sides[0], top],
    [sides[1], right],
    [sides[2], bottom],
    [sides[3], left],
  ];
}

function parseStyleDeclarations(text: string, map: Map<string, string>, priorities: Map<string, string>): void {
  map.clear();
  priorities.clear();
  if (!text) return;
  const cleaned = String(text).replace(/\/\*[\s\S]*?\*\//g, "");
  const decls = cleaned.split(";");
  for (const decl of decls) {
    const idx = decl.indexOf(":");
    if (idx > 0) {
      const k = decl.slice(0, idx).trim().toLowerCase();
      let v = decl.slice(idx + 1).trim();
      if (!k || !v) continue;
      let priority = "";
      const importantMatch = /\s*!\s*important\s*$/i.exec(v);
      if (importantMatch) {
        priority = "important";
        v = v.slice(0, importantMatch.index).trim();
      }
      map.set(k, v);
      if (priority) {
        priorities.set(k, priority);
      }
      const expanded = expandBoxShorthand(k, v);
      if (expanded) {
        for (const [long, longValue] of expanded) {
          map.set(long, longValue);
          if (priority) {
            priorities.set(long, priority);
          }
        }
      }
    }
  }
}

// Browsers keep the style attribute verbatim across setAttribute and mirror
// it into the declaration lazily; the attribute string is only rewritten
// (normalized) after a declaration-side mutation, which merges over the
// attribute content. The fake follows the same shape so engine-written
// style strings round-trip byte-identical until code mutates .style.
const STYLE_ATTR_STALE = Symbol("styleAttrStale");

interface StaleStyleMarker {
  [STYLE_ATTR_STALE]?: VoidCallback;
}

function createStyleObject(element: FakeElement): CSSStyleDeclaration {
  const map = new Map<string, string>();
  const priorities = new Map<string, string>();
  let syncedFromAttr = false;
  const ensureSynced = (): void => {
    if (syncedFromAttr) return;
    syncedFromAttr = true;
    const attr = element?.attributes?.get?.("style");
    if (typeof attr === "string" && attr) {
      parseStyleDeclarations(attr, map, priorities);
    }
  };
  return probe<CSSStyleDeclaration>(new Proxy({}, {
    get(target: Record<string | symbol, unknown>, prop: string | symbol): unknown {
      if (prop === STYLE_ATTR_STALE) {
        return () => { syncedFromAttr = false; };
      }
      if (prop === "setProperty") {
        return (name: string, value: string | null, priority: string = "") => {
          ensureSynced();
          const kebab = String(name).trim().toLowerCase();
          if (value == null || value === "") {
            map.delete(kebab);
            priorities.delete(kebab);
          } else {
            map.set(kebab, String(value));
            if (priority && String(priority).toLowerCase() === "important") {
              priorities.set(kebab, "important");
            } else if (priority) {
              priorities.set(kebab, String(priority));
            } else {
              priorities.delete(kebab);
            }
          }
          updateStyleAttr();
        };
      }
      if (prop === "getPropertyValue") {
        return (name: string) => {
          ensureSynced();
          const kebab = String(name).trim().toLowerCase();
          return map.get(kebab) ?? "";
        };
      }
      if (prop === "getPropertyPriority") {
        return (name: string) => {
          ensureSynced();
          const kebab = String(name).trim().toLowerCase();
          return priorities.get(kebab) ?? "";
        };
      }
      if (prop === "removeProperty") {
        return (name: string) => {
          ensureSynced();
          const kebab = String(name).trim().toLowerCase();
          const old = map.get(kebab) ?? "";
          map.delete(kebab);
          priorities.delete(kebab);
          updateStyleAttr();
          return old;
        };
      }
      if (prop === "length") {
        ensureSynced();
        return map.size;
      }
      if (prop === "item") {
        return (index: number) => {
          ensureSynced();
          return Array.from(map.keys())[index] ?? "";
        };
      }
      if (prop === "cssText") {
        ensureSynced();
        return Array.from(map.entries()).map(([k, v]) => {
          const prio = priorities.get(k);
          return prio ? `${k}: ${v} !${prio}` : `${k}: ${v}`;
        }).join("; ");
      }
      if (typeof prop === "symbol" && prop === Symbol.iterator) {
        return function* (): IterableIterator<string> {
          ensureSynced();
          yield* map.keys();
        };
      }
      if (typeof prop === "string" && /^\d+$/.test(prop)) {
        const idx = Number(prop);
        ensureSynced();
        return Array.from(map.keys())[idx] ?? undefined;
      }
      if (typeof prop === "string") {
        const kebab = prop.replace(/[A-Z]/g, (m) => `-${m.toLowerCase()}`);
        ensureSynced();
        return map.get(kebab) ?? map.get(prop) ?? "";
      }
      return Reflect.get(target, prop);
    },
    set(_target: Record<string | symbol, unknown>, prop: string | symbol, value: unknown): boolean {
      if (prop === "cssText") {
        parseStyleDeclarations(String(value), map, priorities);
        updateStyleAttr();
        return true;
      }
      if (typeof prop === "string") {
        ensureSynced();
        const kebab = prop.replace(/[A-Z]/g, (m) => `-${m.toLowerCase()}`);
        if (value == null || value === "") {
          map.delete(kebab);
          map.delete(prop);
          priorities.delete(kebab);
          priorities.delete(prop);
        } else {
          map.set(kebab, String(value));
        }
        updateStyleAttr();
        return true;
      }
      return Reflect.set(_target, prop, value);
    },
    has(_target: Record<string | symbol, unknown>, prop: string | symbol): boolean {
      if (typeof prop === "string") {
        const kebab = prop.replace(/[A-Z]/g, (m) => `-${m.toLowerCase()}`);
        return map.has(kebab) || map.has(prop) || prop in _target;
      }
      return Reflect.has(_target, prop);
    },
  }));

  function updateStyleAttr(): void {
    syncedFromAttr = true;
    if (map.size === 0) {
      element.attributes.delete("style");
    } else {
      const text = Array.from(map.entries()).map(([k, v]) => {
        const prio = priorities.get(k);
        return prio ? `${k}: ${v} !${prio}` : `${k}: ${v}`;
      }).join("; ");
      element.attributes.set("style", text);
    }
  }
}

interface RuleDeclaration {
  value: string;
  important: boolean;
}

interface ParsedStylesheetRule {
  selector: string;
  specificity: number[];
  index: number;
  declarations: Map<string, RuleDeclaration>;
}

interface ParsedPseudoRule {
  selector: string;
  pseudo: string;
  specificity: number[];
  index: number;
  declarations: Map<string, RuleDeclaration>;
}

interface BestRuleMatch<R = ParsedStylesheetRule> {
  rule: R;
  decl: RuleDeclaration;
}

interface SpecificityRule {
  specificity: number[];
  index: number;
}

const stylesheetRules = new Map<string, Map<string, string>>();
const parsedStylesheetRules: ParsedStylesheetRule[] = [];
const parsedPseudoRules: ParsedPseudoRule[] = [];

function parseDeclarationBlock(declBlock: string): Map<string, RuleDeclaration> {
  const map = new Map<string, RuleDeclaration>();
  const decls = declBlock.split(";");
  for (const decl of decls) {
    const colonIdx = decl.indexOf(":");
    if (colonIdx > 0) {
      const prop = decl.slice(0, colonIdx).trim().toLowerCase();
      let val = decl.slice(colonIdx + 1).trim();
      if (!prop || !val) continue;
      let important = false;
      const importantMatch = /\s*!\s*important\s*$/i.exec(val);
      if (importantMatch) {
        important = true;
        val = val.slice(0, importantMatch.index).trim();
      }
      map.set(prop, { value: val, important });
      if (prop === "padding-inline-start" && !map.has("padding-left")) {
        map.set("padding-left", { value: val, important });
      }
      if (prop === "margin-inline") {
        if (!map.has("margin-left")) map.set("margin-left", { value: val, important });
        if (!map.has("margin-right")) map.set("margin-right", { value: val, important });
      }
      const expanded = expandBoxShorthand(prop, val);
      if (expanded) {
        for (const [long, longValue] of expanded) {
          map.set(long, { value: longValue, important });
        }
      }
    }
  }
  return map;
}

function computeSpecificity(selector: string): number[] {
  let a = 0;
  let b = 0;
  let c = 0;
  const tokens = splitByWhitespace(selector);
  for (const token of tokens) {
    if (!token || token === ">" || token === "+" || token === "~" || token === "*") continue;
    let s = token;
    const tagMatch = /^([a-zA-Z0-9_-]+)/.exec(s);
    if (tagMatch) {
      c++;
      s = s.slice(tagMatch[0].length);
    }
    while (s.length > 0) {
      if (s.startsWith("#")) {
        const idMatch = /^#([a-zA-Z0-9_-]+)/.exec(s);
        if (idMatch) {
          a++;
          s = s.slice(idMatch[0].length);
        } else {
          s = s.slice(1);
        }
      } else if (s.startsWith(".")) {
        const classMatch = /^\.([a-zA-Z0-9_-]+)/.exec(s);
        if (classMatch) {
          b++;
          s = s.slice(classMatch[0].length);
        } else {
          s = s.slice(1);
        }
      } else if (s.startsWith("[")) {
        const attrEnd = s.indexOf("]");
        if (attrEnd >= 0) {
          b++;
          s = s.slice(attrEnd + 1);
        } else {
          s = s.slice(1);
        }
      } else if (s.startsWith(":not(")) {
        let depth = 0;
        let endIdx = -1;
        for (let i = 4; i < s.length; i++) {
          if (s[i] === "(") depth++;
          else if (s[i] === ")") {
            depth--;
            if (depth === 0) {
              endIdx = i;
              break;
            }
          }
        }
        if (endIdx >= 0) {
          const inner = s.slice(5, endIdx).trim();
          const innerSpec = computeSpecificity(inner);
          a += innerSpec[0];
          b += innerSpec[1];
          c += innerSpec[2];
          s = s.slice(endIdx + 1);
        } else {
          s = s.slice(5);
        }
      } else if (s.startsWith(":")) {
        const pseudoMatch = /^:([a-zA-Z0-9_-]+)/.exec(s);
        if (pseudoMatch) {
          b++;
          s = s.slice(pseudoMatch[0].length);
        } else {
          s = s.slice(1);
        }
      } else {
        s = s.slice(1);
      }
    }
  }
  return [a, b, c];
}

function compareSpecificity(spec1: number[], spec2: number[], index1: number, index2: number): number {
  for (let i = 0; i < 3; i++) {
    if (spec1[i] !== spec2[i]) return spec1[i] - spec2[i];
  }
  return index1 - index2;
}

function collectStylesheetRules(cssText: string): void {
  if (!cssText) return;
  const cleaned = String(cssText).replace(/\/\*[\s\S]*?\*\//g, "");
  const ruleRegex = /([^{}]+)\{([^}]+)\}/g;
  let match: RegExpExecArray | null;
  while ((match = ruleRegex.exec(cleaned)) !== null) {
    const rawSelectors = match[1].trim();
    const declBlock = match[2];
    const selectors = splitSelectorList(rawSelectors);
    const declsMap = parseDeclarationBlock(declBlock);
    for (const sel of selectors) {
      const trimmedSel = sel.trim();
      if (!trimmedSel) continue;
      const pseudoMatch = /::?(before|after)$/.exec(trimmedSel);
      if (pseudoMatch) {
        const baseSelector = trimmedSel.slice(0, pseudoMatch.index).trim();
        const pseudoKey = ":" + pseudoMatch[1];
        if (baseSelector) {
          parsedPseudoRules.push({
            selector: baseSelector,
            pseudo: pseudoKey,
            specificity: computeSpecificity(baseSelector),
            index: parsedPseudoRules.length,
            declarations: declsMap,
          });
        }
        continue;
      }
      const spec = computeSpecificity(trimmedSel);
      const ruleIndex = parsedStylesheetRules.length;
      parsedStylesheetRules.push({
        selector: trimmedSel,
        specificity: spec,
        index: ruleIndex,
        declarations: declsMap,
      });
      const tagMatch = /^[a-zA-Z0-9_-]+$/.exec(trimmedSel);
      if (tagMatch) {
        const tag = trimmedSel.toUpperCase();
        let tagRules = stylesheetRules.get(tag);
        if (!tagRules) {
          tagRules = new Map();
          stylesheetRules.set(tag, tagRules);
        }
        for (const [p, d] of declsMap) {
          tagRules.set(p, d.value);
        }
      }
    }
  }
}

function getStyleAttrProperty(element: FakeElement | null, name: string): string {
  const styleAttr = element?.attributes?.get?.("style") ?? (typeof element?.getAttribute === "function" ? element.getAttribute("style") : null);
  if (!styleAttr || typeof styleAttr !== "string") return "";
  const kebab = name.toLowerCase();
  // Last matching declaration wins: a longhand after a shorthand must
  // override the shorthand's derived value, so every decl updates the
  // result and the scan runs to the end.
  let result = "";
  const decls = styleAttr.split(";");
  for (const decl of decls) {
    const idx = decl.indexOf(":");
    if (idx > 0) {
      const k = decl.slice(0, idx).trim().toLowerCase();
      const v = decl.slice(idx + 1).trim();
      if (!k || !v) continue;
      if (k === kebab) {
        result = v;
        continue;
      }
      if (k === "padding-inline-start" && kebab === "padding-left") {
        result = v;
        continue;
      }
      if (k === "margin-inline" && (kebab === "margin-left" || kebab === "margin-right")) {
        result = v;
        continue;
      }
      const expanded = expandBoxShorthand(k, v);
      if (expanded) {
        for (const [long, longValue] of expanded) {
          if (long === kebab) {
            result = longValue;
            break;
          }
        }
      }
    }
  }
  return result;
}

function getStylesheetProperty(element: FakeElement, kebab: string): string {
  let bestImportant: BestRuleMatch<ParsedStylesheetRule> | null = null;
  let bestNormal: BestRuleMatch<ParsedStylesheetRule> | null = null;

  for (const rule of parsedStylesheetRules) {
    if (rule.declarations.has(kebab) || rule.declarations.has("all")) {
      if (matchesHostSelector(element, rule.selector)) {
        // A rule's explicit declaration for the property wins over its own
        // `all` shorthand; `all: unset` then only clears what the rule does
        // not set explicitly, mirroring declaration order inside a block.
        const decl = rule.declarations.has(kebab)
          ? rule.declarations.get(kebab)!
          : allShorthandDecl(rule);
        if (!decl) continue;
        if (decl.important) {
          if (!bestImportant || compareSpecificity(rule.specificity, bestImportant.rule.specificity, rule.index, bestImportant.rule.index) >= 0) {
            bestImportant = { rule, decl };
          }
        } else {
          if (!bestNormal || compareSpecificity(rule.specificity, bestNormal.rule.specificity, rule.index, bestNormal.rule.index) >= 0) {
            bestNormal = { rule, decl };
          }
        }
      }
    }
  }

  if (bestImportant) return bestImportant.decl.value;
  if (bestNormal) return bestNormal.decl.value;
  return "";
}

// The `all` shorthand competes for every property. Only the CSS-wide reset
// keywords make sense on it in host stylesheets; other values (e.g. a font
// shorthand) do not expand per-property here and are ignored.
function allShorthandDecl(rule: ParsedStylesheetRule): RuleDeclaration | null {
  const decl = rule.declarations.get("all");
  if (!decl) return null;
  const value = String(decl.value).trim().toLowerCase();
  if (value !== "unset" && value !== "initial" && value !== "inherit" && value !== "revert") {
    return null;
  }
  return { ...decl, value: `__all_${value}__` };
}

function isAllResetValue(value: string): boolean {
  return typeof value === "string" && /^__all_(unset|initial|inherit|revert)__$/.test(value);
}

function allResetKeyword(value: string): string | null {
  const m = /^__all_(unset|initial|inherit|revert)__$/.exec(value);
  return m ? m[1] : null;
}

function getPseudoStylesheetProperty(element: FakeElement, kebab: string, pseudoKey: string): string {
  let bestImportant: BestRuleMatch<ParsedPseudoRule> | null = null;
  let bestNormal: BestRuleMatch<ParsedPseudoRule> | null = null;

  for (const rule of parsedPseudoRules) {
    if (rule.pseudo === pseudoKey && rule.declarations.has(kebab)) {
      if (matchesHostSelector(element, rule.selector)) {
        const decl = rule.declarations.get(kebab)!;
        if (decl.important) {
          if (!bestImportant || compareSpecificity(rule.specificity, bestImportant.rule.specificity, rule.index, bestImportant.rule.index) >= 0) {
            bestImportant = { rule, decl };
          }
        } else {
          if (!bestNormal || compareSpecificity(rule.specificity, bestNormal.rule.specificity, rule.index, bestNormal.rule.index) >= 0) {
            bestNormal = { rule, decl };
          }
        }
      }
    }
  }

  if (bestImportant) return bestImportant.decl.value;
  if (bestNormal) return bestNormal.decl.value;
  return "";
}

// The prepared renderer emits its geometry and run declarations
// (--tq-line-height, letter-spacing, margin-right, ...) into a per-root
// scoped value-style stylesheet (<style data-tq-prepared-value-styles> in
// document.head) at enhance time, which postdates the static stylesheet
// parse. Match those rules lazily here so computed style, inline-advance
// accounting, and box geometry observe the same declarations a browser
// applies. Declarations are product-emitted with !important, so a matching
// rule wins the host cascade.
function getPreparedValueStyleProperty(element: FakeElement, kebab: string): string {
  if (!element || element.nodeType !== 1) return "";
  const doc = element.ownerDocument ?? probe<GlobalWithDocument>(globalThis).document;
  if (!doc) return "";
  let bestImportant: BestRuleMatch<SpecificityRule> | null = null;
  let bestNormal: BestRuleMatch<SpecificityRule> | null = null;
  let ruleIndex = 0;
  for (const parent of [doc.head, doc.body, doc.documentElement].filter(Boolean)) {
    for (const node of parent.childNodes ?? []) {
      if (!node || node.nodeType !== 1 || (node as FakeElement).tagName !== "STYLE") continue;
      if (typeof (node as FakeElement).hasAttribute === "function" &&
          !(node as FakeElement).hasAttribute("data-tq-prepared-value-styles")) continue;
      const cleaned = String(node.textContent ?? "").replace(/\/\*[\s\S]*?\*\//g, "");
      for (const match of cleaned.matchAll(/([^{}]+)\{([^}]+)\}/g)) {
        const declarations = parseDeclarationBlock(match[2]);
        if (!declarations.has(kebab)) continue;
        for (const selector of splitSelectorList(match[1])) {
          const trimmed = selector.trim();
          if (!trimmed || !matchesHostSelector(element, trimmed)) continue;
          const rule = { specificity: computeSpecificity(trimmed), index: ruleIndex++ };
          const decl = declarations.get(kebab)!;
          if (decl.important) {
            if (!bestImportant || compareSpecificity(rule.specificity, bestImportant.rule.specificity, rule.index, bestImportant.rule.index) >= 0) {
              bestImportant = { rule, decl };
            }
          } else {
            if (!bestNormal || compareSpecificity(rule.specificity, bestNormal.rule.specificity, rule.index, bestNormal.rule.index) >= 0) {
              bestNormal = { rule, decl };
            }
          }
        }
      }
    }
  }
  if (bestImportant) return bestImportant.decl.value;
  if (bestNormal) return bestNormal.decl.value;
  return "";
}

function resolveElementPropertyRaw(element: FakeElement, property: string, base: Record<string, unknown> = {}): string {
  if (!element || element.nodeType !== 1) return "";

  if (property.startsWith("--")) {
    for (let curr: FakeElement | null = element; curr; curr = curr.parentElement) {
      const prepared = getPreparedValueStyleProperty(curr, property);
      if (prepared !== "") return prepared;
      const v = curr.style?.getPropertyValue?.(property);
      if (v !== undefined && v !== "") return v;
      const attrV = getStyleAttrProperty(curr, property);
      if (attrV !== "") return attrV;
    }
    return "";
  }

  const kebab = property.toLowerCase();

  // 1. Element inline style Proxy map
  const inline = element.style?.getPropertyValue?.(kebab);
  if (inline !== undefined && inline !== "") return inline;

  // 2. Element style attribute string
  const attrVal = getStyleAttrProperty(element, kebab);
  if (attrVal !== "") return attrVal;

  // 2b. Per-root prepared value-style stylesheet (product !important rules).
  const preparedVal = getPreparedValueStyleProperty(element, kebab);
  if (preparedVal !== "") return preparedVal;

  // 3. Stylesheet rules (extended specificity-based rules)
  const sheetVal = getStylesheetProperty(element, kebab);
  if (isAllResetValue(sheetVal)) {
    // `all: unset` wins the cascade for this property: inherited properties
    // keep flowing from the ancestor chain, everything else resets to its
    // initial value (reported as the empty string here).
    const keyword = allResetKeyword(sheetVal);
    const inheritable = INHERITED_PROPERTIES.includes(kebab) || keyword === "inherit";
    if (inheritable && element.parentElement && element.parentElement.nodeType === 1) {
      const parentVal = resolveElementPropertyRaw(element.parentElement, kebab, base);
      if (parentVal !== "") return parentVal;
    }
    return "";
  }
  if (sheetVal !== "") return sheetVal;

  // 3b. Fallback tag rule if any
  const tagRule = stylesheetRules.get(element.tagName)?.get(kebab);
  if (tagRule !== undefined && tagRule !== "") return tagRule;

  // 4. Inherited properties
  if (INHERITED_PROPERTIES.includes(kebab) && element.parentElement && element.parentElement.nodeType === 1) {
    const parentVal = resolveElementPropertyRaw(element.parentElement, kebab, base);
    if (parentVal !== "") return parentVal;
  }

  return "";
}

const INHERITED_PROPERTIES = [
  "font-size", "font-weight", "font-family", "font-style",
  "line-height", "letter-spacing", "word-spacing", "color", "direction",
  "font-feature-settings", "white-space",
];

// Substitutes var(--custom[, fallback]) references against the element's
// custom-property chain before a computed value leaves the resolver, the
// same replacement a real engine performs at computed-value time.
function substituteCssVars(value: string, element: FakeElement, depth = 0): string {
  if (typeof value !== "string" || !value.includes("var(") || depth > 4) return value;
  return value.replace(
    /var\(\s*(--[A-Za-z0-9_-]+)\s*(?:,\s*([^()]*?))?\s*\)/g,
    (_match, name, fallback) => {
      const resolved = resolveElementPropertyRaw(element, name);
      if (resolved !== "") return resolved;
      return fallback !== undefined ? fallback.trim() : "";
    },
  );
}

// The currentColor keyword computes against the element's color chain; a
// browser reports the resolved used value for properties like fill/stroke.
function resolveCurrentColorKeyword(value: string, element: FakeElement, property: string): string {
  if (typeof value !== "string" || value.trim() !== "currentColor") return value;
  if (property.toLowerCase() === "color") {
    return element?.parentElement
      ? resolveElementPropertyRaw(element.parentElement, "color")
      : value;
  }
  const color = resolveElementPropertyRaw(element, "color");
  return color !== "" ? color : value;
}

function resolveElementProperty(element: FakeElement, property: string, base: Record<string, unknown> = {}): string {
  return resolveCurrentColorKeyword(
    substituteCssVars(resolveElementPropertyRaw(element, property, base), element),
    element,
    property,
  );
}

function getHorizontalPadding(element: FakeElement): HorizontalPadding {
  if (!element || element.nodeType !== 1) return { left: 0, right: 0 };
  const cs = probe<GlobalWithGetComputedStyle>(globalThis).getComputedStyle?.(probe<Element>(element));
  if (cs) {
    const pl = cs.getPropertyValue("padding-left") || cs.getPropertyValue("padding-inline-start");
    const pr = cs.getPropertyValue("padding-right") || cs.getPropertyValue("padding-inline-end");
    if (pl || pr) {
      return { left: Number.parseFloat(pl) || 0, right: Number.parseFloat(pr) || 0 };
    }
    const p = cs.getPropertyValue("padding");
    if (p) {
      const parts = String(p).trim().split(/\s+/);
      if (parts.length === 1) {
        const v = Number.parseFloat(parts[0]) || 0;
        return { left: v, right: v };
      }
      if (parts.length >= 2) {
        const v = Number.parseFloat(parts[1]) || 0;
        return { left: v, right: v };
      }
    }
  } else if (element.style) {
    const pl = (element.style.getPropertyValue?.("padding-left") || probe<StylePropertyView>(element.style).paddingLeft) ?? "";
    const pr = (element.style.getPropertyValue?.("padding-right") || probe<StylePropertyView>(element.style).paddingRight) ?? "";
    if (pl || pr) {
      return { left: Number.parseFloat(pl) || 0, right: Number.parseFloat(pr) || 0 };
    }
  }
  return { left: 0, right: 0 };
}

function getElementExplicitWidth(element: FakeElement): number | null {
  if (!element || element.nodeType !== 1) return null;
  const inlineSize = element.style?.getPropertyValue?.("inline-size") ||
    probe<StylePropertyView>(element.style).inlineSize ||
    (element.hasAttribute("data-tq-spacing-carrier") ? preparedValueStyleProperty(element, "inline-size") : "");
  if (inlineSize) {
    const parsed = Number.parseFloat(inlineSize);
    if (!Number.isNaN(parsed) && parsed > 0) return parsed;
  }
  const styleWidth = element.style?.getPropertyValue?.("width") || probe<StylePropertyView>(element.style).width;
  if (styleWidth) {
    const parsed = Number.parseFloat(styleWidth);
    if (!Number.isNaN(parsed) && parsed > 0) return parsed;
  }
  const attrStyle = element.getAttribute?.("style");
  if (attrStyle) {
    const match = /(?:^|;)\s*width\s*:\s*(\d+(?:\.\d+)?)px/i.exec(attrStyle);
    if (match) {
      const parsed = Number.parseFloat(match[1]);
      if (!Number.isNaN(parsed) && parsed > 0) return parsed;
    }
  }
  if (element.width) return element.width;
  if (element.tagName === "IMG" || element.tagName === "SVG") {
    const attrW = element.getAttribute?.("width") ?? element.width;
    if (attrW != null) {
      const parsed = Number.parseFloat(String(attrW));
      if (!Number.isNaN(parsed) && parsed > 0) return parsed;
    }
  }
  return null;
}

function readExplicitHeight(element: FakeElement): number | null {
  if (!element || element.nodeType !== 1) return null;
  const styleHeight = element.style?.getPropertyValue?.("height") || probe<StylePropertyView>(element.style).height;
  if (styleHeight) {
    const parsed = Number.parseFloat(styleHeight);
    if (!Number.isNaN(parsed) && parsed > 0) return parsed;
  }
  const attrStyle = element.getAttribute?.("style");
  if (attrStyle) {
    const match = /(?:^|;)\s*height\s*:\s*(\d+(?:\.\d+)?)px/i.exec(attrStyle);
    if (match) {
      const parsed = Number.parseFloat(match[1]);
      if (!Number.isNaN(parsed) && parsed > 0) return parsed;
    }
  }
  if (element.tagName === "IMG" || element.tagName === "SVG") {
    const attrH = element.getAttribute?.("height") ?? element.height;
    if (attrH != null) {
      const parsed = Number.parseFloat(String(attrH));
      if (!Number.isNaN(parsed) && parsed > 0) return parsed;
    }
  }
  return null;
}

function getBlockWidth(element: FakeElement): number {
  const selfExplicit = getElementExplicitWidth(element);
  if (selfExplicit != null) {
    const cs = probe<GlobalWithGetComputedStyle>(globalThis).getComputedStyle?.(probe<Element>(element));
    const boxSizing = cs?.getPropertyValue?.("box-sizing") || "content-box";
    if (boxSizing === "border-box") {
      return selfExplicit;
    }
    const selfPad = getHorizontalPadding(element);
    return selfExplicit + selfPad.left + selfPad.right;
  }

  let explicitWidth = 360;
  let widthAncestor: FakeElement | null = null;
  for (let curr = element.parentElement; curr; curr = curr.parentElement) {
    const ew = getElementExplicitWidth(curr);
    if (ew != null) {
      explicitWidth = ew;
      widthAncestor = curr;
      break;
    }
  }

  let available = explicitWidth;
  if (widthAncestor) {
    for (let curr = element.parentElement; curr; curr = curr.parentElement) {
      const pad = getHorizontalPadding(curr);
      available -= (pad.left + pad.right);
      if (curr === widthAncestor) break;
    }
  }

  return Math.max(0, available);
}

function findMultiColumnAncestor(element: FakeElement): MultiColumnAncestor | null {
  for (let curr = element.parentElement; curr; curr = curr.parentElement) {
    const styleAttr = curr.getAttribute?.("style") || "";
    const inlineCol = curr.style?.getPropertyValue?.("columns") || probe<StylePropertyView>(curr.style).columns;
    const combined = `${styleAttr}; columns: ${inlineCol || ""}`;
    const colMatch = /columns\s*:\s*(\d+(?:\.\d+)?)px(?:\s+auto)?/i.exec(combined);
    if (colMatch) {
      const colWidth = Number.parseFloat(colMatch[1]);
      let colGap = 0;
      const gapMatch = /column-gap\s*:\s*(\d+(?:\.\d+)?)px/i.exec(combined) ||
        curr.style?.getPropertyValue?.("column-gap");
      if (gapMatch) {
        colGap = typeof gapMatch === "string" ? cssPx(gapMatch) : Number.parseFloat(gapMatch[1]);
      }
      let colHeight = 120;
      const heightMatch = /height\s*:\s*(\d+(?:\.\d+)?)px/i.exec(combined) ||
        curr.style?.getPropertyValue?.("height");
      if (heightMatch) {
        colHeight = typeof heightMatch === "string" ? cssPx(heightMatch) : Number.parseFloat(heightMatch[1]);
      }
      return {
        ancestor: curr,
        colWidth,
        colGap,
        colHeight,
      };
    }
  }
  return null;
}

function findContentSizedAncestor(element: FakeElement): FakeElement | null {
  for (let curr: FakeElement | null = element; curr; curr = curr.parentElement) {
    const display = curr.style?.getPropertyValue?.("display") || probe<StylePropertyView>(curr.style).display || "";
    if (["inline-block", "inline-flex", "inline-grid", "flex", "grid"].includes(display) || curr.tagName === "FIGURE") {
      return curr;
    }
  }
  return null;
}

export function cssPx(value: string | number): number {
  return Number.parseFloat(String(value).replace(/px$/, "")) || 0;
}

function inlineContentAdvance(node: FakeNode): number {
  if (node.nodeType === 3) {
    const data = ((node as FakeNode & { data?: string }).data ?? "").replace(/[\u200B\uFEFF]/g, "");
    if (data.length === 0) return 0;
    const baseFontSize = node.parentElement ? blockFontSizePx(node.parentElement) : 18;
    const letterSpacing = computedLetterSpacingPx(node.parentElement);
    let advance = 0;
    for (const ch of data) {
      advance += fakeCharNaturalAdvance(ch, baseFontSize) + letterSpacing;
    }
    return advance;
  }
  if (node.nodeType !== 1) return 0;
  const element = node as FakeElement;
  if (NON_RENDERED_TAGS.has(element.tagName)) return 0;
  const computed = (globalThis as Record<string, unknown>).getComputedStyle as GlobalGetComputedStyle | undefined;
  const cs = computed?.(element as FakeElement & Element);
  const margin = (side: string): number => {
    const raw = cs?.getPropertyValue?.(side) ?? "0";
    const parsed = Number.parseFloat(raw);
    return Number.isNaN(parsed) ? 0 : parsed;
  };
  const explicit = getElementExplicitWidth(element);
  if (explicit != null) return margin("margin-left") + explicit + margin("margin-right");
  const pad = getHorizontalPadding(element);
  let inner = 0;
  for (const child of element.childNodes) inner += inlineContentAdvance(child);
  const beforeAdvance = pseudoContentAdvance(element, "::before");
  const afterAdvance = pseudoContentAdvance(element, "::after");
  return margin("margin-left") + pad.left + beforeAdvance + inner + afterAdvance + pad.right + margin("margin-right");
}

function pseudoContentAdvance(element: FakeElement, pseudo: string): number {
  if (!element || element.nodeType !== 1) return 0;
  const computed = (globalThis as Record<string, unknown>).getComputedStyle as GlobalGetComputedStyle | undefined;
  const cs = computed?.(element as FakeElement & Element, pseudo);
  if (!cs) return 0;
  const display = cs.getPropertyValue?.("display") ?? "";
  if (display === "none") return 0;
  const position = cs.getPropertyValue?.("position") ?? "";
  if (position === "absolute" || position === "fixed") return 0;
  let content = cs.getPropertyValue?.("content") ?? "";
  content = content.trim();
  if (!content || content === "none" || content === "normal") return 0;
  if ((content.startsWith('"') && content.endsWith('"')) || (content.startsWith("'") && content.endsWith("'"))) {
    content = content.slice(1, -1);
  }
  if (!content) return 0;
  const fontSize = cssPx(cs.getPropertyValue?.("font-size")) || 18;
  const letterSpacing = computedLetterSpacingPx(element);
  return content.length * (fontSize + letterSpacing);
}

// Left edge of a node within its block container's content box, by walking
// preceding inline siblings and ancestor paddings.
function inlineStartOffset(node: FakeNode): number {
  const parent = node.parentNode;
  if (!parent || parent.nodeType !== 1) return 0;
  const parentElement = parent as FakeElement;
  const isInline = INLINE_FLOW_TAGS.has(parentElement.tagName);
  const computed = (globalThis as Record<string, unknown>).getComputedStyle as GlobalGetComputedStyle | undefined;
  const cs = computed?.(parentElement as FakeElement & Element);
  const margin = (side: string): number => {
    const raw = cs?.getPropertyValue?.(side) ?? "0";
    const parsed = Number.parseFloat(raw);
    return Number.isNaN(parsed) ? 0 : parsed;
  };
  let offset = getHorizontalPadding(parentElement).left + pseudoContentAdvance(parentElement, "::before");
  for (const sibling of parent.childNodes) {
    if (sibling === node) break;
    offset += inlineContentAdvance(sibling);
  }
  return (isInline ? inlineStartOffset(parentElement) + margin("margin-left") : 0) + offset;
}

function* attributeTuples(map: Map<string, string>): Generator<AttributeTuple> {
  for (const [k, v] of Map.prototype.entries.call(map) as IterableIterator<[string, string]>) {
    const tuple: [string, string] = [k, v];
    yield Object.assign(tuple, { name: k, value: v });
  }
}

export class FakeAttributesMap extends Map<string, string> {
  // A DOM attribute list yields tuples that carry name and value beside the
  // pair; the Map signature is what every consumer here reads, so the richer
  // iterator is cast to it and the extra properties stay a run-time detail.
  override [Symbol.iterator](): MapIterator<[string, string]> {
    return attributeTuples(this) as unknown as MapIterator<[string, string]>;
  }

  override entries(): MapIterator<[string, string]> {
    return this[Symbol.iterator]();
  }
}

interface HostElementPrivate {
  _clientWidth?: number;
  _clientHeight?: number;
  listeners: Map<string, Set<unknown>>;
}

export class HostElement extends FakeElement {
  declare _clientWidth?: number;
  declare _clientHeight?: number;
  readonly listeners: Map<string, Set<unknown>>;

  constructor(tagName: string) {
    super(tagName);
    this.attributes = new FakeAttributesMap();
    this.ownerDocument = probe<GlobalWithDocument>(globalThis).document ?? null;
    this.style = createStyleObject(this) as CSSStyleDeclaration & FakeInlineStyle;
    this.listeners = new Map();
  }

  get firstElementChild(): HostElement | null {
    return (this.childNodes.find((n) => n.nodeType === 1) as HostElement | null) ?? null;
  }

  get lastElementChild(): HostElement | null {
    return (this.childNodes.filter((n) => n.nodeType === 1).pop() as HostElement | null) ?? null;
  }

  get children(): HostElement[] {
    return this.childNodes.filter((n): n is HostElement => n.nodeType === 1);
  }

  get clientWidth(): number {
    return this._clientWidth ?? this.getBoundingClientRect().width;
  }

  set clientWidth(v: number) {
    this._clientWidth = Number(v);
  }

  get clientHeight(): number {
    return this._clientHeight ?? this.getBoundingClientRect().height;
  }

  set clientHeight(v: number) {
    this._clientHeight = Number(v);
  }

  get scrollWidth(): number {
    const pad = getHorizontalPadding(this);
    const widest = widestInlineSegment(this);
    return widest > 0 ? widest + pad.left + pad.right
      : (this._clientWidth ?? this.getBoundingClientRect().width);
  }

  override get dataset(): DatasetView {
    const self: FakeElement = this;
    return new Proxy(self as FakeElement & DatasetView, {
      get(target: FakeElement & DatasetView, prop: string | symbol): unknown {
        if (typeof prop !== "string") return undefined;
        const attrName = "data-" + prop.replace(/([A-Z])/g, "-$1").toLowerCase();
        return target.getAttribute(attrName) ?? undefined;
      },
      set(target: FakeElement & DatasetView, prop: string | symbol, value: unknown): boolean {
        if (typeof prop !== "string") return false;
        const attrName = "data-" + prop.replace(/([A-Z])/g, "-$1").toLowerCase();
        target.setAttribute(attrName, String(value));
        return true;
      },
      deleteProperty(target: FakeElement & DatasetView, prop: string | symbol): boolean {
        if (typeof prop !== "string") return false;
        const attrName = "data-" + prop.replace(/([A-Z])/g, "-$1").toLowerCase();
        target.removeAttribute(attrName);
        return true;
      },
      has(target: FakeElement & DatasetView, prop: string | symbol): boolean {
        if (typeof prop !== "string") return false;
        const attrName = "data-" + prop.replace(/([A-Z])/g, "-$1").toLowerCase();
        return target.hasAttribute(attrName);
      },
    });
  }

  override set dataset(value: Record<string, string | undefined>) {
    if (value && typeof value === "object") {
      for (const [k, v] of Object.entries(value)) {
        this.dataset[k] = v;
      }
    }
  }

  get className(): string {
    return this.getAttribute("class") || "";
  }

  set className(value: string) {
    if (value == null || value === "") {
      this.removeAttribute("class");
    } else {
      this.setAttribute("class", String(value));
    }
  }

  get classList(): FakeElementClassList {
    const getClasses = () => (this.getAttribute("class") || "").trim().split(/\s+/).filter(Boolean);
    return {
      contains: (cls: string) => getClasses().includes(cls),
      add: (...cls: string[]) => {
        const set = new Set(getClasses());
        for (const c of cls) set.add(c);
        this.setAttribute("class", Array.from(set).join(" "));
      },
      remove: (...cls: string[]) => {
        const set = new Set(getClasses());
        for (const c of cls) set.delete(c);
        this.setAttribute("class", Array.from(set).join(" "));
      },
    };
  }

  override setAttribute(name: string, value: string): void {
    super.setAttribute(name, value);
    if (name === "style") {
      // Wholesale attribute write: keep the string verbatim and mark the
      // declaration mirror stale; the next .style access reparses it.
      probe<StaleStyleMarker>(this.style)[STYLE_ATTR_STALE]?.();
    }
  }

  override removeAttribute(name: string): void {
    super.removeAttribute(name);
    if (name === "style") {
      this.style.cssText = "";
    }
  }

  addEventListener(type: string, listener: unknown): void {
    if (!this.listeners.has(type)) {
      this.listeners.set(type, new Set());
    }
    this.listeners.get(type)!.add(listener);
  }

  removeEventListener(type: string, listener: unknown): void {
    this.listeners.get(type)?.delete(listener);
  }

  dispatchEvent(event: FakeEvent): boolean {
    event.target = this;
    let curr: FakeElement | null = this;
    while (curr) {
      event.currentTarget = curr;
      const he = curr as HostElement;
      const set = he.listeners?.get(event.type);
      if (set) {
        for (const listener of Array.from(set)) {
          (listener as (event: FakeEvent) => void)(event);
        }
      }
      if (!event.bubbles) break;
      curr = curr.parentElement;
    }
    if (event.bubbles && this.ownerDocument) {
      event.currentTarget = probe<FakeNode>(this.ownerDocument);
      const he = probe<HostElement>(this.ownerDocument);
      const docSet = he.listeners?.get(event.type);
      if (docSet) {
        for (const listener of Array.from(docSet)) {
          (listener as (event: FakeEvent) => void)(event);
        }
      }
    }
    return !event.defaultPrevented;
  }

  matches(selector: string): boolean {
    return matchesHostSelector(this, selector);
  }

  override closest(selector: string): FakeElement | null {
    let node: FakeElement | null = this;
    while (node) {
      if (node.nodeType === 1 && matchesHostSelector(node, selector)) return node;
      node = node.parentElement;
    }
    return null;
  }

  replaceChildren(...nodes: FakeNode[]): void {
    while (this.firstChild) this.removeChild(this.firstChild);
    for (const node of nodes) this.appendChild(node);
  }

  override insertBefore(newNode: FakeNode, referenceNode: FakeNode | null): FakeNode {
    if (!referenceNode) return this.appendChild(newNode);
    if (newNode.nodeType === 11) {
      while (newNode.firstChild) this.insertBefore(newNode.firstChild, referenceNode);
      return newNode;
    }
    if (newNode.parentNode) newNode.parentNode.removeChild(newNode);
    const index = this.childNodes.indexOf(referenceNode);
    if (index < 0) throw new Error("NotFoundError");
    this.childNodes.splice(index, 0, newNode);
    newNode.parentNode = this;
    newNode.parentElement = this.nodeType === 1 ? (this as FakeElement) : null;
    return newNode;
  }

  override replaceChild(newChild: FakeNode, oldChild: FakeNode): FakeNode {
    this.insertBefore(newChild, oldChild);
    return this.removeChild(oldChild);
  }

  override getBoundingClientRect(): DOMRect {
    const self: FakeElement = this;
    let w = this.width;
    if (!w) {
      const inlineSize = this.style?.getPropertyValue?.("inline-size") || probe<StylePropertyView>(this.style).inlineSize;
      if (inlineSize) {
        const parsed = Number.parseFloat(inlineSize);
        if (!Number.isNaN(parsed) && parsed > 0) {
          w = parsed;
        }
      }
    }
    if (!w) {
      const explicit = getElementExplicitWidth(self);
      if (explicit != null) w = explicit;
    }
    if (!w) {
      const multiCol = findMultiColumnAncestor(self);
      if (multiCol) {
        w = getBlockWidth(multiCol.ancestor);
      }
    }
    if (!w) {
      const isInline = [
        "STRONG", "SPAN", "EM", "A", "B", "I", "U", "MARK", "SMALL",
        "SUB", "SUP", "CODE", "KBD", "SAMP", "VAR", "TIME", "DATA",
        "RUBY", "RT", "RP", "BDI", "BDO", "ABBR", "Q", "CITE", "DEL", "SPOILER",
      ].includes(this.tagName);
      if (isInline) {
        const pad = getHorizontalPadding(self);
        let inner = 0;
        for (const child of this.childNodes) {
          inner += inlineContentAdvance(child);
        }
        const beforeAdv = pseudoContentAdvance(self, "::before");
        const afterAdv = pseudoContentAdvance(self, "::after");
        w = pad.left + beforeAdv + inner + afterAdv + pad.right;
      } else {
        const isContentSized = Boolean(findContentSizedAncestor(self));

        if (isContentSized) {
          const pad = getHorizontalPadding(self);
          const textLen = (this.textContent || "").length;
          let availableWidth = 360;
          for (let curr = this.parentElement; curr; curr = curr.parentElement) {
            if (curr.tagName === "FIGURE") {
              for (const child of curr.childNodes) {
                if (child.nodeType === 1) {
                  const ew = getElementExplicitWidth(child as FakeElement);
                  if (ew != null && ew > 0) {
                    availableWidth = ew;
                    break;
                  }
                }
              }
            }
            const sw = curr.style?.getPropertyValue?.("width") || probe<StylePropertyView>(curr.style).width;
            if (sw) {
              const p = Number.parseFloat(sw);
              if (!Number.isNaN(p) && p > 0) {
                availableWidth = p;
                break;
              }
            }
          }
          if (textLen === 0) {
            w = 0;
          } else {
            const cs = probe<GlobalWithGetComputedStyle>(globalThis).getComputedStyle?.(probe<Element>(this));
            const fontSize = (cs ? cssPx(cs.getPropertyValue("font-size")) : 18) || 18;
            w = Math.min(availableWidth, pad.left + textLen * fontSize + pad.right);
          }
        } else {
          w = getBlockWidth(self);
        }
      }
    }
    if (w == null || (w === 0 && (this.textContent || "").length > 0)) w = 360;
    const explicitHeight = readExplicitHeight(self);
    const cs = probe<GlobalWithGetComputedStyle>(globalThis).getComputedStyle?.(probe<Element>(this));
    const marginLeft = cs ? cssPx(cs.getPropertyValue("margin-left")) : 0;
    const isInline = [
      "STRONG", "SPAN", "EM", "A", "B", "I", "U", "MARK", "SMALL",
      "SUB", "SUP", "CODE", "KBD", "SAMP", "VAR", "TIME", "DATA",
      "RUBY", "RT", "RP", "BDI", "BDO", "ABBR", "Q", "CITE", "DEL", "SPOILER",
    ].includes(this.tagName);
    const left = isInline ? (inlineStartOffset(self) + marginLeft) : (this.left || 0);
    return new FakeDOMRect(left, this.top ?? 0, w, explicitHeight != null ? explicitHeight : (this.height || 30));
  }

  override getClientRects(): DOMRect[] {
    const self: FakeElement = this;
    const multiCol = findMultiColumnAncestor(self);
    if (multiCol) {
      const W = multiCol.colWidth;
      const G = multiCol.colGap;
      const H = multiCol.colHeight;
      const cs = probe<GlobalWithGetComputedStyle>(globalThis).getComputedStyle?.(probe<Element>(this));
      const fontSize = (cs ? cssPx(cs.getPropertyValue("font-size")) : 18) || 18;
      const lineHeight = (cs ? cssPx(cs.getPropertyValue("line-height")) : 30) || 30;
      const linesPerCol = Math.max(1, Math.floor(H / lineHeight));
      const charsPerLine = Math.max(1, Math.floor(W / fontSize));
      const capacityPerCol = linesPerCol * charsPerLine;
      const totalChars = (this.textContent || "").length;
      const numCols = Math.max(1, Math.ceil(totalChars / capacityPerCol));
      const rects: DOMRect[] = [];
      for (let i = 0; i < numCols; i++) {
        rects.push(new FakeDOMRect(i * (W + G), 0, W, H));
      }
      return rects;
    }
    return [this.getBoundingClientRect()];
  }

  get innerHTML(): string {
    return this.childNodes.map((child) => serializeNode(child)).join("");
  }

  set innerHTML(value: string) {
    while (this.firstChild) this.removeChild(this.firstChild);
    if (value) {
      for (const node of parseHtmlNodes(value, this.ownerDocument)) {
        this.appendChild(node);
      }
    }
  }

  override querySelectorAll(selector: string): FakeElement[] {
    const result: FakeElement[] = [];
    const visit = (node: FakeNode): void => {
      for (const child of node.childNodes) {
        if (child.nodeType === 1 && matchesHostSelector(child as FakeElement, selector, this)) {
          result.push(child as FakeElement);
        }
        visit(child);
      }
    };
    visit(this);
    return result;
  }

  override querySelector(selector: string): FakeElement | null {
    return this.querySelectorAll(selector)[0] ?? null;
  }

  override cloneNode(deep: boolean = false): FakeElement {
    const clone = new HostElement(this.tagName);
    clone.ownerDocument = this.ownerDocument;
    clone.attributes = new FakeAttributesMap(this.attributes);
    clone.style.cssText = this.style.cssText;
    if (deep) {
      for (const child of this.childNodes) {
        clone.appendChild(child.cloneNode(true));
      }
    }
    return clone as FakeElement;
  }
}

function serializeNode(node: FakeNode): string {
  if (node.nodeType === 3) {
    return (node as FakeText).value ?? node.textContent ?? "";
  }
  if (node.nodeType === 1) {
    const element = node as FakeElement;
    const tag = element.tagName.toLowerCase();
    let attrs = "";
    if (element.attributes) {
      for (const [k, v] of element.attributes) {
        attrs += ` ${k}="${v}"`;
      }
    }
    const isVoid = ["br", "hr", "img", "input", "link", "meta"].includes(tag);
    if (isVoid) {
      return `<${tag}${attrs}>`;
    }
    const inner = (element.childNodes || []).map(serializeNode).join("");
    return `<${tag}${attrs}>${inner}</${tag}>`;
  }
  if (node.nodeType === 11) {
    return (node.childNodes || []).map(serializeNode).join("");
  }
  return "";
}

function parseHtmlNodes(html: string, doc: FakeDocument | null = defaultParserDocument()): FakeNode[] {
  const tagRegex = /<\/?([a-zA-Z0-9-]+)((?:\s+[a-zA-Z0-9_-]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))?)*)\s*\/?>|([^<]+)/gs;
  const attrRegex = /([a-zA-Z0-9_-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;

  const root = new HostElement("div");
  if (doc) root.ownerDocument = doc;
  const stack: HostElement[] = [root];

  let match: RegExpExecArray | null;
  while ((match = tagRegex.exec(html)) !== null) {
    const [full, tagName, attrStr, text] = match;
    if (text !== undefined) {
      if (text.length > 0) {
        const parent = stack[stack.length - 1];
        if (parent?.tagName === "STYLE") {
          collectStylesheetRules(text);
        }
        const textNode = new FakeText(text);
        parent.appendChild(textNode);
      }
    } else if (full.startsWith("</")) {
      const closingTag = (tagName || "").toLowerCase();
      if (!["br", "hr", "img", "input", "link", "meta"].includes(closingTag)) {
        if (stack.length > 1) {
          stack.pop();
        }
      }
    } else {
      const el = new HostElement(tagName ?? "div");
      if (doc) el.ownerDocument = doc;
      if (attrStr) {
        let attrMatch: RegExpExecArray | null;
        while ((attrMatch = attrRegex.exec(attrStr)) !== null) {
          const attrName = attrMatch[1];
          const attrVal = decodeHtmlEntities(attrMatch[2] ?? attrMatch[3] ?? attrMatch[4] ?? "");
          el.setAttribute(attrName, attrVal);
        }
      }
      stack[stack.length - 1].appendChild(el);
      const isSelfClosing = full.endsWith("/>") || ["br", "hr", "img", "input"].includes((tagName || "").toLowerCase());
      if (!isSelfClosing) {
        stack.push(el);
      }
    }
  }

  return Array.from(root.childNodes);
}

function defaultParserDocument(): FakeDocument | null {
  return ((globalThis as Record<string, unknown>).document as FakeDocument | undefined) ?? null;
}

// Widest inline run between engine line markers in a block container.
// Line breaks surface both as BR (data-tq-engine-break) and as empty
// SPAN.tq-line markers, and inside sliced inline elements they sit below
// the direct children, so the walk recurses and resets the running segment
// at either marker kind while mirroring inlineContentAdvance's chrome
// model (margins, padding, pseudo advances) for the elements it crosses.
function widestInlineSegment(container: FakeElement): number {
  let max = 0;
  let current = 0;
  const marginOf = (element: FakeElement, side: string): number => {
    const computed = (globalThis as Record<string, unknown>).getComputedStyle as GlobalGetComputedStyle | undefined;
    const parsed = Number.parseFloat(computed?.(element as FakeElement & Element)?.getPropertyValue?.(side) ?? "0");
    return Number.isNaN(parsed) ? 0 : parsed;
  };
  const visit = (node: FakeNode): void => {
    if (node.nodeType === 3) {
      current += inlineContentAdvance(node);
      return;
    }
    if (node.nodeType !== 1) return;
    const element = node as FakeElement;
    if (NON_RENDERED_TAGS.has(element.tagName)) return;
    if (element.tagName === "BR") {
      max = Math.max(max, current);
      current = 0;
      return;
    }
    const isLineMarker = Boolean(element.classList?.contains("tq-line"));
    if (isLineMarker) {
      max = Math.max(max, current);
      current = 0;
      return;
    }
    const explicit = getElementExplicitWidth(element);
    if (explicit != null) {
      current += marginOf(element, "margin-left") + explicit + marginOf(element, "margin-right");
      return;
    }
    const pad = getHorizontalPadding(element);
    current += marginOf(element, "margin-left") + pad.left + pseudoContentAdvance(element, "::before");
    for (const child of element.childNodes) visit(child);
    current += pseudoContentAdvance(element, "::after") + pad.right + marginOf(element, "margin-right");
  };
  for (const child of container.childNodes) visit(child);
  return Math.max(max, current);
}

// ---- Runtime host exports ----

export async function drainMicrotasks(times = 6): Promise<void> {
  for (let i = 0; i < times; i += 1) {
    await new Promise((resolve) => setImmediate(resolve));
  }
}

// Extend FakeText with data property.
Object.defineProperty(FakeText.prototype, "data", {
  get() { return this.value; },
  set(v) { this.value = String(v); },
  configurable: true,
});

export function parseHtmlFragment(html: string, doc: FakeDocument | null = defaultParserDocument()): FakeElement {
  const nodes = parseHtmlNodes(html, doc);
  if (nodes.length === 1 && nodes[0].nodeType === 1) {
    return nodes[0] as FakeElement;
  }
  const root = new HostElement("div");
  if (doc) root.ownerDocument = doc;
  for (const node of nodes) {
    root.appendChild(node);
  }
  return root;
}

function decodeHtmlEntities(str: string): string {
  if (!str || typeof str !== "string") return str;
  return str
    .replace(/&#(\d+);/g, (_match, num) => String.fromCharCode(Number(num)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_match, hex) => String.fromCharCode(Number.parseInt(hex, 16)))
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&");
}

const PUNCT_OPENING_FULLWIDTH = new Set<string>("（〔【《〈「『｛".split(""));
const PUNCT_CLOSING_FULLWIDTH = new Set<string>("）〕】》〉」』".split(""));
const PUNCT_PAUSE_OR_STOP_FULLWIDTH = new Set<string>("、。，．：；！？".split(""));
const PUNCT_HALFWIDTH_CELL = new Set<string>("｢｣｡､".split(""));

interface FakeCharMetrics {
  advance: number;
  inkLeft: number;
  inkRight: number;
}

function fakeCanvasCharMetrics(ch: string, fontSize: number): FakeCharMetrics | null {
  const em = fontSize;
  // Ink windows mirror the measured Noto Sans CJK SC bounds so the trim
  // arithmetic picks the same body frame side the real browser layout does.
  if (PUNCT_OPENING_FULLWIDTH.has(ch)) {
    return { advance: em, inkLeft: em * 0.66, inkRight: em * 0.95 };
  }
  if (PUNCT_CLOSING_FULLWIDTH.has(ch)) {
    return { advance: em, inkLeft: em * 0.05, inkRight: em * 0.35 };
  }
  if (PUNCT_PAUSE_OR_STOP_FULLWIDTH.has(ch)) {
    return { advance: em, inkLeft: em * 0.06, inkRight: em * 0.32 };
  }
  if (PUNCT_HALFWIDTH_CELL.has(ch)) {
    // Halfwidth corner marks and halfwidth ideographic pauses shape at half
    // advance; the engine re-seats the glyph inside a synthesized full-width
    // cell (UnderwidthPunctuationFullWidthBoxPlacement).
    return { advance: em * 0.5, inkLeft: em * 0.04, inkRight: em * 0.34 };
  }
  if (ch === "·") {
    return { advance: em, inkLeft: em * 0.42, inkRight: em * 0.58 };
  }
  if (ch === "“" || ch === "”" || ch === "‘" || ch === "’") {
    return { advance: em * 0.45, inkLeft: 0, inkRight: em * 0.45 };
  }
  return null;
}

// Natural advance of one character under the same metric table, shared by
// the canvas shaper and the DOM-side advance model so the engine's
// letter-spacing residuals replay to the declared widths.
function fakeCharNaturalAdvance(ch: string, fontSize: number): number {
  const m = fakeCanvasCharMetrics(ch, fontSize);
  return m ? m.advance : fontSize;
}

interface FakeTextMetrics {
  width: number;
  actualBoundingBoxLeft: number;
  // Unmeasured multi-char strings never assign inkRight in the .mjs host, so
  // the field can legitimately be undefined there.
  actualBoundingBoxRight: number | undefined;
  actualBoundingBoxAscent: number;
  actualBoundingBoxDescent: number;
  fontBoundingBoxAscent: number;
  fontBoundingBoxDescent: number;
  ideographicBaseline: number;
  alphabeticBaseline: number;
}

export class FakeCanvasRenderingContext2D {
  font = "";
  direction = "ltr";
  textAlign = "start";
  textBaseline = "alphabetic";

  setTransform(): void {}
  resetTransform(): void {}
  save(): void {}
  restore(): void {}
  scale(): void {}
  translate(): void {}
  rotate(): void {}
  transform(): void {}
  fillText(): void {}
  strokeText(): void {}
  beginPath(): void {}
  closePath(): void {}
  moveTo(): void {}
  lineTo(): void {}
  arc(): void {}
  fill(): void {}
  stroke(): void {}
  clearRect(): void {}
  fillRect(): void {}
  strokeRect(): void {}
  createImageData(): Record<string, unknown> {
    return {};
  }
  getImageData(): Record<string, unknown> {
    return { data: new Uint8ClampedArray(4) };
  }
  putImageData(): void {}

  measureText(text: string): FakeTextMetrics {
    const s = String(text ?? "");
    const match = /(\d+(?:\.\d+)?)px\b/.exec(this.font || "");
    const fontSize = match ? Number.parseFloat(match[1]) : 18;
    const ascent = fontSize * (16 / 18);
    const descent = fontSize * (4 / 18);
    const chars = Array.from(s);
    let width: number | undefined;
    let inkLeft = 0;
    let inkRight: number | undefined;
    if (chars.length === 1) {
      const m = fakeCanvasCharMetrics(chars[0], fontSize);
      if (m) {
        width = m.advance;
        inkLeft = -m.inkLeft;
        inkRight = m.inkRight;
      }
    }
    if (width == null) {
      width = s.length * fontSize;
      inkRight = width;
    }
    return {
      width,
      actualBoundingBoxLeft: inkLeft,
      actualBoundingBoxRight: inkRight,
      actualBoundingBoxAscent: ascent,
      actualBoundingBoxDescent: descent,
      fontBoundingBoxAscent: ascent,
      fontBoundingBoxDescent: descent,
      ideographicBaseline: -ascent,
      alphabeticBaseline: -ascent,
    };
  }
}

export class FakeHTMLCanvasElement extends HostElement {
  readonly ctx2d: FakeCanvasRenderingContext2D;

  constructor() {
    super("canvas");
    this.ctx2d = new FakeCanvasRenderingContext2D();
  }

  getContext(type: string): FakeCanvasRenderingContext2D | null {
    return type === "2d" ? this.ctx2d : null;
  }
}

function createFakeCanvas(): FakeHTMLCanvasElement {
  return new FakeHTMLCanvasElement();
}

let originalGlobals: Record<string, unknown> | null = null;

export function installTestAnimationFrames(): void {
  if ((globalThis as Record<string, unknown>).__TiqianTestAnimationFrames) return;
  const tqInstallFrameState = {
    originalRequest: (globalThis as Record<string, unknown>).requestAnimationFrame,
    originalCancel: (globalThis as Record<string, unknown>).cancelAnimationFrame,
    originalRequestIdle: (globalThis as Record<string, unknown>).requestIdleCallback,
    originalCancelIdle: (globalThis as Record<string, unknown>).cancelIdleCallback,
    originalSetTimeout: (globalThis as Record<string, unknown>).setTimeout,
    originalClearTimeout: (globalThis as Record<string, unknown>).clearTimeout,
    callbacks: new Map<number, TimeCallback | VoidCallback>(),
    nextId: 1,
    cancelled: 0,
    idleScheduled: 0,
    idleBudget: 50,
  };
  (globalThis as Record<string, unknown>).__TiqianTestAnimationFrames = tqInstallFrameState;
  (globalThis as Record<string, unknown>).requestAnimationFrame = (callback: FrameRequestCallback): number => {
    const tqFrameId = tqInstallFrameState.nextId++;
    tqInstallFrameState.callbacks.set(tqFrameId, callback);
    return tqFrameId;
  };
  (globalThis as Record<string, unknown>).cancelAnimationFrame = (tqFrameId: number): void => {
    if (tqInstallFrameState.callbacks.delete(tqFrameId)) tqInstallFrameState.cancelled += 1;
  };
  (globalThis as Record<string, unknown>).requestIdleCallback = (callback: IdleCallback): number => {
    const tqIdleId = tqInstallFrameState.nextId++;
    tqInstallFrameState.idleScheduled += 1;
    tqInstallFrameState.callbacks.set(tqIdleId, () => callback({
      didTimeout: false,
      timeRemaining: () => tqInstallFrameState.idleBudget,
    }));
    return tqIdleId;
  };
  (globalThis as Record<string, unknown>).cancelIdleCallback = (tqIdleId: number): void => {
    if (tqInstallFrameState.callbacks.delete(tqIdleId)) tqInstallFrameState.cancelled += 1;
  };
  (globalThis as Record<string, unknown>).setTimeout = (callback: VoidCallback): number => {
    const tqTimerId = tqInstallFrameState.nextId++;
    tqInstallFrameState.callbacks.set(tqTimerId, callback);
    return tqTimerId;
  };
  (globalThis as Record<string, unknown>).clearTimeout = (tqTimerId: number): void => {
    if (tqInstallFrameState.callbacks.delete(tqTimerId)) tqInstallFrameState.cancelled += 1;
  };
  if (globalThis.window) {
    globalThis.window.requestAnimationFrame = globalThis.requestAnimationFrame;
    globalThis.window.cancelAnimationFrame = globalThis.cancelAnimationFrame;
    globalThis.window.requestIdleCallback = globalThis.requestIdleCallback;
    globalThis.window.cancelIdleCallback = globalThis.cancelIdleCallback;
    globalThis.window.setTimeout = globalThis.setTimeout;
    globalThis.window.clearTimeout = globalThis.clearTimeout;
  }
}

export function flushOneTestAnimationFrame(): number {
  const tqFlushOneState = probe<TestAnimationFramesState | undefined>((globalThis as Record<string, unknown>).__TiqianTestAnimationFrames);
  if (!tqFlushOneState) return 0;
  const tqFlushOneCallbacks = [...tqFlushOneState.callbacks.values()];
  tqFlushOneState.callbacks.clear();
  const perf = probe<GlobalWithPerformance>(globalThis).performance;
  for (const tqFlushOneCallback of tqFlushOneCallbacks) (tqFlushOneCallback as TimeCallback)(perf.now());
  return tqFlushOneCallbacks.length;
}

export function flushAllTestAnimationFrames(): number {
  const tqFlushAllState = probe<TestAnimationFramesState | undefined>((globalThis as Record<string, unknown>).__TiqianTestAnimationFrames);
  if (!tqFlushAllState) return 0;
  let tqFlushAllSlices = 0;
  const perf = probe<GlobalWithPerformance>(globalThis).performance;
  while (tqFlushAllState.callbacks.size > 0) {
    if (tqFlushAllSlices++ > 1000) throw new Error("animation frame test queue did not settle");
    const tqFlushAllCallbacks = [...tqFlushAllState.callbacks.values()];
    tqFlushAllState.callbacks.clear();
    for (const tqFlushAllCallback of tqFlushAllCallbacks) (tqFlushAllCallback as TimeCallback)(perf.now());
  }
  return tqFlushAllSlices;
}

export function pendingTestAnimationFrameCount(): number {
  const state = probe<TestAnimationFramesState | undefined>((globalThis as Record<string, unknown>).__TiqianTestAnimationFrames);
  return state ? state.callbacks.size : 0;
}

export function cancelledTestAnimationFrameCount(): number {
  const state = probe<TestAnimationFramesState | undefined>((globalThis as Record<string, unknown>).__TiqianTestAnimationFrames);
  return state ? state.cancelled : 0;
}

export function restoreTestAnimationFrames(): void {
  const tqRestoreFrameState = (globalThis as Record<string, unknown>).__TiqianTestAnimationFrames;
  if (!tqRestoreFrameState) return;
  const state = tqRestoreFrameState as TestAnimationFramesState;
  (globalThis as Record<string, unknown>).requestAnimationFrame = state.originalRequest;
  (globalThis as Record<string, unknown>).cancelAnimationFrame = state.originalCancel;
  if (state.originalRequestIdle === undefined) {
    delete (globalThis as Record<string, unknown>).requestIdleCallback;
  } else {
    (globalThis as Record<string, unknown>).requestIdleCallback = state.originalRequestIdle;
  }
  if (state.originalCancelIdle === undefined) {
    delete (globalThis as Record<string, unknown>).cancelIdleCallback;
  } else {
    (globalThis as Record<string, unknown>).cancelIdleCallback = state.originalCancelIdle;
  }
  (globalThis as Record<string, unknown>).setTimeout = state.originalSetTimeout;
  (globalThis as Record<string, unknown>).clearTimeout = state.originalClearTimeout;
  if (globalThis.window) {
    globalThis.window.requestAnimationFrame = globalThis.requestAnimationFrame;
    globalThis.window.cancelAnimationFrame = globalThis.cancelAnimationFrame;
    globalThis.window.requestIdleCallback = globalThis.requestIdleCallback;
    globalThis.window.cancelIdleCallback = globalThis.cancelIdleCallback;
    globalThis.window.setTimeout = globalThis.setTimeout;
    globalThis.window.clearTimeout = globalThis.clearTimeout;
  }
  delete (globalThis as Record<string, unknown>).__TiqianTestAnimationFrames;
}

// Ensure Array.prototype.item exists for NodeList compatibility with Kotlin/JS DOM.
if (!probe<ArrayWithItem>(Array.prototype).item) {
  Object.defineProperty(Array.prototype, "item", {
    value: function (this: unknown[], index: number) {
      return this[index] ?? null;
    },
    configurable: true,
    writable: true,
  });
}

probe<FakeNodeWithContains>(FakeNode.prototype).contains = function contains(this: FakeNode, other: FakeNode): boolean {
  for (let node: FakeNode | null = other; node; node = node.parentNode) {
    if (node === this) return true;
  }
  return false;
};

FakeNode.prototype.querySelectorAll = function (selector: string): FakeElement[] {
  const result: FakeElement[] = [];
  const visit = (node: FakeNode): void => {
    for (const child of node.childNodes) {
      if (child instanceof FakeElement && matchesHostSelector(child, selector, this as FakeElement)) {
        result.push(child);
      }
      visit(child);
    }
  };
  visit(this);
  return result;
};

FakeNode.prototype.querySelector = function (selector: string): FakeElement | null {
  return this.querySelectorAll(selector)[0] ?? null;
};

probe<FakeNodeWithMatches>(FakeNode.prototype).matches = function matches(this: FakeNode, selector: string): boolean {
  return matchesHostSelector(this as FakeElement, selector);
};

export class HostNode extends FakeNode {
  contains(other: FakeNode): boolean {
    for (let node: FakeNode | null = other; node; node = node.parentNode) {
      if (node === this) return true;
    }
    return false;
  }
}
const HostNodeStatics = probe<Record<string, number>>(HostNode);
HostNodeStatics.TEXT_NODE = 3;
HostNodeStatics.ELEMENT_NODE = 1;
HostNodeStatics.DOCUMENT_FRAGMENT_NODE = 11;

// Constructor statics are enrichment the fixtures class never declares.
const FakeNodeStatics = probe<Record<string, number>>(FakeNode);
FakeNodeStatics.TEXT_NODE = 3;
FakeNodeStatics.ELEMENT_NODE = 1;
FakeNodeStatics.DOCUMENT_FRAGMENT_NODE = 11;

Object.defineProperty(FakeNode.prototype, "nextSibling", {
  get() {
    if (!this.parentNode) return null;
    const siblings = this.parentNode.childNodes;
    const index = siblings.indexOf(this);
    if (index < 0 || index + 1 >= siblings.length) return null;
    return siblings[index + 1];
  },
  configurable: true,
});

Object.defineProperty(FakeNode.prototype, "previousSibling", {
  get() {
    if (!this.parentNode) return null;
    const siblings = this.parentNode.childNodes;
    const index = siblings.indexOf(this);
    if (index <= 0) return null;
    return siblings[index - 1];
  },
  configurable: true,
});

Object.defineProperty(FakeNode.prototype, "nextElementSibling", {
  get() {
    if (!this.parentNode) return null;
    const siblings = this.parentNode.childNodes;
    const index = siblings.indexOf(this);
    for (let scan = index + 1; scan < siblings.length; scan += 1) {
      if (siblings[scan].nodeType === 1) return siblings[scan];
    }
    return null;
  },
  configurable: true,
});

Object.defineProperty(FakeNode.prototype, "lastChild", {
  get() {
    return this.childNodes[this.childNodes.length - 1] ?? null;
  },
  configurable: true,
});

Object.defineProperty(FakeNode.prototype, "isConnected", {
  get() {
    let curr: FakeNode | null = this;
    const doc = (globalThis as Record<string, unknown>).document as FakeNode | undefined;
    while (curr) {
      if (curr._isConnected !== undefined) return curr._isConnected;
      if (curr.nodeType === 9 || (doc && curr === doc)) return true;
      curr = curr.parentNode;
    }
    return false;
  },
  set(value: boolean) {
    this._isConnected = value;
  },
  configurable: true,
});

FakeNode.prototype.appendChild = function appendChild(node: FakeNode): FakeNode {
  if (node.nodeType === 11) {
    while (node.firstChild) {
      const child = node.firstChild;
      node.childNodes.shift();
      this.childNodes.push(child);
      child.parentNode = this;
      child.parentElement = this.nodeType === 1 ? (this as FakeElement) : null;
    }
    return node;
  }
  if (node.parentNode) node.parentNode.removeChild(node);
  this.childNodes.push(node);
  node.parentNode = this;
  node.parentElement = this.nodeType === 1 ? (this as FakeElement) : null;
  return node;
};

FakeNode.prototype.removeChild = function removeChild(node: FakeNode): FakeNode {
  const index = this.childNodes.indexOf(node);
  if (index < 0) throw new Error("NotFoundError");
  this.childNodes.splice(index, 1);
  node.parentNode = null;
  node.parentElement = null;
  return node;
};

FakeNode.prototype.insertBefore = function insertBefore(newNode: FakeNode, referenceNode: FakeNode | null): FakeNode {
  if (!referenceNode) return this.appendChild(newNode);
  if (newNode.nodeType === 11) {
    while (newNode.firstChild) this.insertBefore(newNode.firstChild, referenceNode);
    return newNode;
  }
  if (newNode.parentNode) newNode.parentNode.removeChild(newNode);
  const index = this.childNodes.indexOf(referenceNode);
  if (index < 0) throw new Error("NotFoundError");
  this.childNodes.splice(index, 0, newNode);
  newNode.parentNode = this;
  newNode.parentElement = this.nodeType === 1 ? (this as FakeElement) : null;
  return newNode;
};

FakeNode.prototype.replaceChild = function replaceChild(newChild: FakeNode, oldChild: FakeNode): FakeNode {
  this.insertBefore(newChild, oldChild);
  return this.removeChild(oldChild);
};

// replaceChildren/replaceWith are enrichment the fixtures never declare, so
// the installs go through the same seam the runtime defines them on.
const FakeNodePrototype = probe<FakeNodePrototypeMethods>(FakeNode.prototype);

FakeNodePrototype.replaceChildren = function replaceChildren(this: FakeNode, ...nodes: FakeNode[]): void {
  while (this.firstChild) {
    const child = this.firstChild;
    this.childNodes.shift();
    child.parentNode = null;
    child.parentElement = null;
  }
  for (const node of nodes) {
    if (node.nodeType === 11) {
      while (node.firstChild) {
        const child = node.firstChild;
        node.childNodes.shift();
        this.childNodes.push(child);
        child.parentNode = this;
        child.parentElement = this.nodeType === 1 ? (this as FakeElement) : null;
      }
    } else {
      if (node.parentNode) node.parentNode.removeChild(node);
      this.childNodes.push(node);
      node.parentNode = this;
      node.parentElement = this.nodeType === 1 ? (this as FakeElement) : null;
    }
  }
};

FakeNodePrototype.replaceWith = function replaceWith(this: FakeNode, ...nodes: FakeNode[]): void {
  if (!this.parentNode) return;
  const parent = this.parentNode;
  for (const node of nodes) {
    parent.insertBefore(node, this);
  }
  parent.removeChild(this);
};

const NON_RENDERED_TAGS = new Set(["HEAD", "STYLE", "SCRIPT", "META", "LINK", "TITLE", "NOSCRIPT"]);

const INLINE_FLOW_TAGS = new Set([
  "STRONG", "SPAN", "EM", "A", "B", "I", "U", "MARK", "SMALL",
  "SUB", "SUP", "CODE", "KBD", "SAMP", "VAR", "TIME", "DATA",
  "RUBY", "RT", "RP", "BDI", "BDO", "ABBR", "Q", "CITE", "DEL", "SPOILER",
]);

function blockFontSizePx(element: FakeElement): number {
  let node: FakeElement | null = element;
  while (node && node.nodeType === 1) {
    if (!INLINE_FLOW_TAGS.has(node.tagName)) {
      const computed = (globalThis as Record<string, unknown>).getComputedStyle as GlobalGetComputedStyle | undefined;
      return cssPx(computed?.(node as FakeElement & Element)?.getPropertyValue("font-size") ?? "") || 18;
    }
    node = node.parentElement;
  }
  return 18;
}

function computedLetterSpacingPx(element: FakeElement | null): number {
  if (!element || element.nodeType !== 1) return 0;
  const computed = (globalThis as Record<string, unknown>).getComputedStyle as GlobalGetComputedStyle | undefined;
  const raw = computed?.(element as FakeElement & Element)?.getPropertyValue("letter-spacing") ?? "";
  const match = /^(-?\d+(?:\.\d+)?)px/.exec(String(raw).trim());
  return match ? Number.parseFloat(match[1]) : 0;
}

export class FakeRange {
  startContainer: FakeNode | null;
  startOffset: number;
  endContainer: FakeNode | null;
  endOffset: number;

  constructor() {
    this.startContainer = null;
    this.startOffset = 0;
    this.endContainer = null;
    this.endOffset = 0;
  }

  setStart(node: FakeNode | null, offset: number): void {
    this.startContainer = node;
    this.startOffset = offset;
  }

  setEnd(node: FakeNode | null, offset: number): void {
    this.endContainer = node;
    this.endOffset = offset;
  }

  selectNodeContents(node: FakeNode): void {
    this.startContainer = node;
    this.startOffset = 0;
    this.endContainer = node;
    if (node?.nodeType === 1) {
      this.endOffset = node.childNodes.length;
    } else {
      this.endOffset = (
        (node as (FakeNode & { data?: string }) | undefined)?.data ??
        (node as FakeText | undefined)?.value ??
        node?.textContent ?? ""
      ).length;
    }
  }

  selectNode(node: FakeNode): void {
    const parent = node?.parentNode ?? node?.parentElement ?? null;
    this.startContainer = parent;
    this.endContainer = parent;
    if (parent) {
      const idx = parent.childNodes.indexOf(node);
      this.startOffset = idx >= 0 ? idx : 0;
      this.endOffset = idx >= 0 ? idx + 1 : 0;
    } else {
      this.startOffset = 0;
      this.endOffset = 0;
    }
  }

  get commonAncestorContainer(): FakeNode | null {
    return this.startContainer;
  }

  intersectsNode(node: FakeNode): boolean {
    if (!node) return false;
    if (node === this.startContainer || node === this.endContainer) return true;
    const startContainer = this.startContainer as NodeWithOptionalContains | null;
    const nodeWithContains = node as NodeWithOptionalContains;
    if (startContainer?.contains?.(node) || nodeWithContains.contains?.(startContainer)) return true;
    return false;
  }

  cloneContents(): FakeFragment {
    const fragment = new FakeFragment();
    if (!this.startContainer) return fragment;
    if (this.startContainer === this.endContainer) {
      if (this.startContainer.nodeType === 1) {
        const slice = this.startContainer.childNodes.slice(this.startOffset, this.endOffset);
        for (const child of slice) {
          fragment.appendChild(child.cloneNode(true));
        }
      } else if (this.startContainer.nodeType === 3) {
        const container = this.startContainer as FakeNode & { data?: string };
        const full = container.data ?? (container as FakeText).value ?? container.textContent ?? "";
        const start = this.startOffset ?? 0;
        const end = this.endOffset ?? full.length;
        fragment.appendChild(new FakeText(full.slice(start, end)));
      }
    } else {
      fragment.appendChild(new FakeText(this.toString()));
    }
    return fragment;
  }

  toString(): string {
    if (!this.startContainer) return "";
    if (this.startContainer === this.endContainer) {
      if (this.startContainer.nodeType === 3) {
        const container = this.startContainer as FakeNode & { data?: string };
        const full = container.data ?? (container as FakeText).value ?? container.textContent ?? "";
        const start = this.startOffset ?? 0;
        const end = this.endOffset ?? full.length;
        return full.slice(start, end);
      }
      if (this.startContainer.nodeType === 1) {
        return this.startContainer.childNodes
          .slice(this.startOffset, this.endOffset)
          .map((n) => n.textContent ?? "")
          .join("");
      }
    }
    return this.startContainer.textContent ?? "";
  }

  getBoundingClientRect(): FakeDOMRect {
    let left = 0;
    let width = 0;
    if (this.startContainer) {
      if (this.startContainer.nodeType === 3) {
        const container = this.startContainer as FakeNode & { data?: string };
        const full = container.data ?? (container as FakeText).value ?? container.textContent ?? "";
        const start = this.startOffset ?? 0;
        const end = this.endOffset ?? full.length;
        const anchorElement = this.startContainer.parentElement;
        const baseFontSize = anchorElement ? blockFontSizePx(anchorElement) : 18;
        const letterSpacing = computedLetterSpacingPx(anchorElement);
        const charAdvance = (ch: string) => fakeCharNaturalAdvance(ch, baseFontSize) + letterSpacing;
        const chars = Array.from(full);
        left = inlineStartOffset(this.startContainer as FakeElement);
        for (let i = 0; i < Math.min(start, chars.length); i += 1) {
          left += charAdvance(chars[i]);
        }
        width = 0;
        for (let i = start; i < Math.min(end, chars.length); i += 1) {
          width += charAdvance(chars[i]);
        }
      } else {
        const container = this.startContainer as FakeElement;
        const children = container.childNodes ?? [];
        const start = Math.min(this.startOffset ?? 0, children.length);
        const end = Math.min(this.endOffset ?? children.length, children.length);
        left = inlineStartOffset(container);
        for (let i = 0; i < start; i += 1) {
          left += inlineContentAdvance(children[i]);
        }
        width = 0;
        for (let i = start; i < end; i += 1) {
          width += inlineContentAdvance(children[i]);
        }
      }
    }
    return new FakeDOMRect(left, 0, width, 30);
  }

  getClientRects(): DOMRect[] {
    return [this.getBoundingClientRect()];
  }
}

let cachedDocument: FakeDocument | null = null;

// The double builds body/head/documentElement through its own createElement
// after the literal exists (the methods close over `doc`), so the literal type
// carries the three roots as optional and the return assertion narrows them
// once assigned. The .mjs double has the same undefined window.
type DocumentDoubleInit = Omit<FakeDocument, "body" | "head" | "documentElement"> & {
  body?: FakeElement;
  head?: FakeElement;
  documentElement?: FakeElement;
};

function createDocumentDouble(): FakeDocument {
  if (cachedDocument) return cachedDocument;
  const listeners = new Map<string, Set<unknown>>();
  const doc: DocumentDoubleInit = {
    nodeType: 9,
    childNodes: [],
    parentNode: null,
    parentElement: null,
    ownerDocument: null,
    isConnected: true,
    baseURI: "https://example.test/post/",
    styleSheets: [],
    elements: new Map<string, unknown>(),
    listeners,
    get defaultView() {
      return globalThis.window ?? globalThis;
    },
    fonts: {
      load: async () => [{}],
      check: () => true,
      addEventListener() {},
      removeEventListener() {},
      ready: Promise.resolve(),
    },
    createElement(tagName: string): FakeElement {
      if (String(tagName).toLowerCase() === "canvas") {
        const canvas = createFakeCanvas();
        canvas.ownerDocument = doc as DocumentDoubleInit & FakeDocument;
        return canvas as FakeElement;
      }
      const el = new HostElement(tagName);
      el.ownerDocument = doc as DocumentDoubleInit & FakeDocument;
      return el as FakeElement;
    },
    createElementNS(ns: string | null, tagName: string): FakeElement {
      const el = doc.createElement(String(tagName).replace(/^svg:/i, ""));
      (el as NamespacedElement).namespaceURI = ns ?? null;
      return el;
    },
    createTextNode(data: string): FakeText {
      return new FakeText(data);
    },
    createDocumentFragment(): FakeFragment {
      return new FakeFragment();
    },
    createRange(): FakeRange {
      return new FakeRange();
    },
    getElementById(id: string): FakeElement | null {
      return doc.body?.querySelector(`#${id}`) ?? null;
    },
    querySelector(selector: string): FakeElement | null {
      return doc.body?.querySelector(selector) ?? null;
    },
    querySelectorAll(selector: string): FakeElement[] {
      return doc.body?.querySelectorAll(selector) ?? [];
    },
    addEventListener(type: string, listener: unknown): void {
      if (!listeners.has(type)) {
        listeners.set(type, new Set());
      }
      listeners.get(type)!.add(listener);
    },
    removeEventListener(type: string, listener: unknown): void {
      listeners.get(type)?.delete(listener);
    },
    dispatchEvent(event: FakeEvent): boolean {
      event.target = doc as DocumentDoubleInit & FakeNode;
      event.currentTarget = doc as DocumentDoubleInit & FakeNode;
      const set = listeners.get(event.type);
      if (set) {
        for (const listener of Array.from(set)) {
          (listener as (event: FakeEvent) => void)(event);
        }
      }
      return !event.defaultPrevented;
    },
    getSelection(): FakeSelection {
      return ((globalThis as Record<string, unknown>).getSelection as () => FakeSelection)();
    },
    contains(other: FakeNode): boolean {
      for (let node: FakeNode | null = other; node; node = node.parentNode) {
        if (node === (doc as DocumentDoubleInit & FakeNode) || node === doc.documentElement || node === doc.body) return true;
      }
      return false;
    },
  };
  const body = doc.createElement("body");
  const head = doc.createElement("head");
  const documentElement = doc.createElement("html");
  doc.body = body;
  doc.head = head;
  doc.documentElement = documentElement;
  documentElement.appendChild(head);
  documentElement.appendChild(body);
  documentElement.parentNode = doc as DocumentDoubleInit & FakeNode;
  cachedDocument = doc as DocumentDoubleInit & FakeDocument;
  return cachedDocument;
}

let currentSelection: FakeSelection | null = null;

export function buildWorld(): void {
  if (!originalGlobals) {
    originalGlobals = {
      document: (globalThis as Record<string, unknown>).document,
      Element: (globalThis as Record<string, unknown>).Element,
      HTMLElement: (globalThis as Record<string, unknown>).HTMLElement,
      HTMLCanvasElement: (globalThis as Record<string, unknown>).HTMLCanvasElement,
      CanvasRenderingContext2D: (globalThis as Record<string, unknown>).CanvasRenderingContext2D,
      Node: (globalThis as Record<string, unknown>).Node,
      Range: (globalThis as Record<string, unknown>).Range,
      DocumentFragment: (globalThis as Record<string, unknown>).DocumentFragment,
      Text: (globalThis as Record<string, unknown>).Text,
      getComputedStyle: (globalThis as Record<string, unknown>).getComputedStyle,
      MutationObserver: (globalThis as Record<string, unknown>).MutationObserver,
      ResizeObserver: (globalThis as Record<string, unknown>).ResizeObserver,
      IntersectionObserver: (globalThis as Record<string, unknown>).IntersectionObserver,
      CustomEvent: (globalThis as Record<string, unknown>).CustomEvent,
      Event: (globalThis as Record<string, unknown>).Event,
      ClipboardEvent: (globalThis as Record<string, unknown>).ClipboardEvent,
      DataTransfer: (globalThis as Record<string, unknown>).DataTransfer,
      getSelection: (globalThis as Record<string, unknown>).getSelection,
      DOMRect: (globalThis as Record<string, unknown>).DOMRect,
      window: (globalThis as Record<string, unknown>).window,
      fetch: (globalThis as Record<string, unknown>).fetch,
      requestAnimationFrame: (globalThis as Record<string, unknown>).requestAnimationFrame,
      cancelAnimationFrame: (globalThis as Record<string, unknown>).cancelAnimationFrame,
      requestIdleCallback: (globalThis as Record<string, unknown>).requestIdleCallback,
      cancelIdleCallback: (globalThis as Record<string, unknown>).cancelIdleCallback,
      setTimeout: (globalThis as Record<string, unknown>).setTimeout,
      clearTimeout: (globalThis as Record<string, unknown>).clearTimeout,
    };
  }

  currentSelection = new FakeSelection();
  (globalThis as Record<string, unknown>).Node = FakeNode;
  (globalThis as Record<string, unknown>).Element = HostElement;
  (globalThis as Record<string, unknown>).HTMLElement = HostElement;
  (globalThis as Record<string, unknown>).HTMLCanvasElement = FakeHTMLCanvasElement;
  (globalThis as Record<string, unknown>).CanvasRenderingContext2D = FakeCanvasRenderingContext2D;
  (globalThis as Record<string, unknown>).Range = FakeRange;
  (globalThis as Record<string, unknown>).DocumentFragment = FakeFragment;
  (globalThis as Record<string, unknown>).Text = FakeText;
  (globalThis as Record<string, unknown>).CustomEvent = FakeCustomEvent;
  (globalThis as Record<string, unknown>).Event = FakeEvent;
  (globalThis as Record<string, unknown>).ClipboardEvent = FakeClipboardEvent;
  (globalThis as Record<string, unknown>).DataTransfer = FakeDataTransfer;
  (globalThis as Record<string, unknown>).getSelection = () => currentSelection;
  (globalThis as Record<string, unknown>).DOMRect = FakeDOMRect;
  (globalThis as Record<string, unknown>).document = createDocumentDouble();
  (globalThis as Record<string, unknown>).window = globalThis;
  ((globalThis as Record<string, unknown>).window as Window).getSelection = (): Selection | null =>
    currentSelection as (FakeSelection & Selection) | null;

  (globalThis as Record<string, unknown>).getComputedStyle = (element: FakeElement, pseudo: string | null) => {
    const isInlineTag = [
      "STRONG", "SPAN", "EM", "A", "B", "I", "U", "MARK", "SMALL",
      "SUB", "SUP", "CODE", "KBD", "SAMP", "VAR", "TIME", "DATA",
      "RUBY", "RT", "RP", "BDI", "BDO", "ABBR", "Q", "CITE", "SPOILER", "DEL",
    ].includes(element?.tagName);
    const overrides: Record<string, string> = isInlineTag ? { display: "inline" } : {};
    const base = fixtureComputedStyle(element, pseudo, overrides);

    const pseudoKey = pseudo ? ":" + String(pseudo).trim().replace(/^:+/, "") : null;
    const pseudoInheritable = [
      "font-size", "font-weight", "font-style", "font-family",
      "line-height", "letter-spacing", "color", "white-space",
    ];

    const getProp = (name: string): string => {
      const kebab = name.replace(/[A-Z]/g, (m) => `-${m.toLowerCase()}`);
      if (pseudoKey) {
        const pseudoVal = getPseudoStylesheetProperty(element, kebab, pseudoKey);
        if (pseudoVal !== "") return pseudoVal;
        if (pseudoInheritable.includes(kebab)) {
          const inherited = resolveElementProperty(element, kebab, base);
          if (inherited !== undefined && inherited !== "") return inherited;
        }
        const camel = kebab.replace(/-([a-z])/g, (_, c) => c.toUpperCase());
        return base[kebab] ?? base[camel] ?? base[name] ?? (kebab === "float" ? (base.cssFloat ?? "none") : "");
      }
      const val = resolveElementProperty(element, kebab, base);
      if (val !== undefined && val !== "") return val;
      const camel = kebab.replace(/-([a-z])/g, (_, c) => c.toUpperCase());
      return base[kebab] ?? base[camel] ?? base[name] ?? (kebab === "float" ? (base.cssFloat ?? "none") : "");
    };

    return new Proxy(base, {
      get(target: Record<string, string>, prop: string | symbol) {
        if (prop === "getPropertyValue") {
          return (name: string) => getProp(name);
        }
        if (typeof prop === "string") {
          const val = getProp(prop);
          if (val !== "") return val;
        }
        return Reflect.get(target, prop);
      },
    });
  };

  (globalThis as Record<string, unknown>).MutationObserver = class {
    constructor(callback: ObserverCallback) { this.callback = callback; }
    callback: ObserverCallback;
    observe() {}
    disconnect() {}
    takeRecords() { return []; }
  };

  (globalThis as Record<string, unknown>).ResizeObserver = class {
    constructor(callback: ObserverCallback) { this.callback = callback; }
    callback: ObserverCallback;
    observe() {}
    unobserve() {}
    disconnect() {}
  };

  (globalThis as Record<string, unknown>).IntersectionObserver = class {
    constructor(callback: ObserverCallback) { this.callback = callback; }
    callback: ObserverCallback;
    observe() {}
    unobserve() {}
    disconnect() {}
  };

  (globalThis as Record<string, unknown>).fetch = async () => ({ ok: false });

  if (typeof (globalThis as Record<string, unknown>).addEventListener !== "function") {
    const windowListeners = new Map<string, Set<unknown>>();
    (globalThis as Record<string, unknown>).addEventListener = (type: string, listener: unknown) => {
      if (!windowListeners.has(type)) windowListeners.set(type, new Set());
      windowListeners.get(type)!.add(listener);
    };
    (globalThis as Record<string, unknown>).removeEventListener = (type: string, listener: unknown) => {
      windowListeners.get(type)?.delete(listener);
    };
    (globalThis as Record<string, unknown>).dispatchEvent = (event: FakeEvent) => {
      event.target ??= probe<FakeNode>(globalThis);
      event.currentTarget = probe<FakeNode>(globalThis);
      const set = windowListeners.get(event.type);
      if (set) {
        for (const listener of Array.from(set)) (listener as (event: FakeEvent) => void)(event);
      }
      return !event.defaultPrevented;
    };
  }
  (globalThis as Record<string, unknown>).innerHeight = 768;
  const gtdoc = (globalThis as Record<string, unknown>).document as FakeDocument | undefined;
  if (gtdoc?.documentElement) {
    const root = gtdoc.documentElement as FakeElement & HostElement;
    root.clientWidth = 1024;
    root.clientHeight = 768;
  }

  installTestAnimationFrames();
}

export function cleanupWorld(): void {
  stylesheetRules.clear();
  parsedStylesheetRules.length = 0;
  parsedPseudoRules.length = 0;
  if (currentSelection) {
    currentSelection.removeAllRanges();
  }
  const gtdoc = probe<GlobalWithDocument>(globalThis).document;
  if (gtdoc?.body) {
    while (gtdoc.body.firstChild) {
      gtdoc.body.removeChild(gtdoc.body.firstChild);
    }
  }
}

export function setElementRect(element: FakeElement, top: number, width: number): void {
  element.getBoundingClientRect = () => new FakeDOMRect(0, top, width, 30);
}

export function relayoutEventIsStale(event: FakeEvent): boolean {
  return Boolean(event?.detail && (event.detail as Record<string, unknown>).stale === true);
}

export function eventDetailInt(event: FakeEvent, name: string): number {
  return Number(event?.detail && (event.detail as Record<string, unknown>)[name]);
}

let runtimeServices: RuntimeServices | null = null;
const contextsByRoot = new WeakMap<FakeElement, EnhancedElementContext>();

export function contextForRoot(root: FakeElement): EnhancedElementContext {
  let context = contextsByRoot.get(root);
  if (!context) {
    context = createEnhanceContext(root as FakeElement & Element);
    contextsByRoot.set(root, context);
  }
  return context;
}

function requireRuntimeServices(): RuntimeServices {
  if (!runtimeServices) throw new Error("host runtime not loaded; call loadHostRuntime() first");
  return runtimeServices;
}

export function dispatchRelayout(root: FakeElement): void {
  requireRuntimeServices();
  relayout(contextForRoot(root), root as FakeElement & Element);
}

export function probeContentDrift(root: FakeElement): unknown {
  requireRuntimeServices();
  return probeRootContentDrift(contextForRoot(root), root as FakeElement & Element);
}

export function reconcileContent(root: FakeElement, paragraphs: unknown[] = []): unknown {
  requireRuntimeServices();
  return reconcileRoot(contextForRoot(root), root as FakeElement & HTMLElement, paragraphs as unknown[] & Element[]);
}

export function detachViaChannel(root: FakeElement): void {
  requireRuntimeServices();
  detachRoot(contextForRoot(root), root as FakeElement & HTMLElement);
}

export function testGrantController(root: FakeElement, generation: number, deadlineMs: number, quota: number): GrantControllerDouble {
  return {
    root,
    generation,
    deadline: deadlineMs,
    quota,
    shouldStop(processed: number) {
      return processed >= quota || Date.now() >= deadlineMs;
    },
  };
}

export function installSnapshotFontSessionFixture(options: SnapshotFontSessionFixtureOptions = {}): void {
  const { failShaping = false, failFamily = null, failText = null, varyFaceByText = false, corruptShapeError = null } = options;
  (globalThis as Record<string, unknown>).__TiqianSnapshotFixtureActive = true;
  (globalThis as Record<string, unknown>).__TiqianSnapshotFontShapeCount = 0;
  (globalThis as Record<string, unknown>).__TiqianSnapshotFontFallbackCount = 0;

  function shapeFailure(displayText: string, serializedFamilies: string): boolean {
    return Boolean(
      failShaping ||
        (failFamily !== null && String(serializedFamilies).includes(failFamily)) ||
        (failText !== null && String(displayText).includes(failText)),
    );
  }

  class FixtureShapeTable extends Map<string, ReplayShapeItem> {
    override get(key: string): ReplayShapeItem {
      if (corruptShapeError) throw new Error(corruptShapeError);
      const [displayText, serializedFamilies] = JSON.parse(key) as [string, string];
      if (shapeFailure(displayText, serializedFamilies)) {
        (globalThis as Record<string, unknown>).__TiqianSnapshotFontFallbackCount = ((globalThis as Record<string, unknown>).__TiqianSnapshotFontFallbackCount as number) + 1;
        throw new Error("NoSnapshotFontFace:test");
      }
      (globalThis as Record<string, unknown>).__TiqianSnapshotFontShapeCount = ((globalThis as Record<string, unknown>).__TiqianSnapshotFontShapeCount as number) + 1;
      const glyphs: FixtureGlyph[] = [];
      let glyphIndex = 0;
      for (const _point of displayText) {
        glyphs.push({
          id: 100 + glyphIndex,
          advanceEm: 1,
          xEm: glyphIndex,
          yEm: 0,
          boundsEm: [0, -0.88, 1, 0.12],
        });
        glyphIndex++;
      }
      const parsedKey: unknown = JSON.parse(key);
      const role = Array.isArray(parsedKey) ? String(parsedKey[5]) : "";
      const features = role === "LatinText" && /[‘’“”]/u.test(displayText)
        ? ["pwid", "palt"]
        : [];
      return {
        key,
        result: {
          glyphs,
          advanceEm: glyphs.length,
          features,
          faceId: varyFaceByText ? `Fixture CJK:${displayText}` : "Fixture CJK",
          fontInstanceId: "fixture:0:default",
          script: "Hani",
          unsafeBreakCount: 0,
        },
      };
    }
  }

  class FixtureMetricTable extends Map<string, ReplayMetricItem> {
    override get(key: string): ReplayMetricItem {
      const [serializedFamilies] = JSON.parse(key) as [string];
      if (failShaping || (failFamily && String(serializedFamilies).includes(failFamily))) {
        (globalThis as Record<string, unknown>).__TiqianSnapshotFontFallbackCount = ((globalThis as Record<string, unknown>).__TiqianSnapshotFontFallbackCount as number) + 1;
        throw new Error("NoSnapshotFontFace:test");
      }
      return { key, valuesEm: [1, 0.25, 0, 0.88, 0.12] };
    }
  }

  globalServices().coordination.fonts.replayRegistry.sessions.set(
    "fixture-snapshot-session",
    { shapes: new FixtureShapeTable(), metrics: new FixtureMetricTable(), probe: null },
  );
}

export function clearSnapshotFontSessionFixture(): void {
  globalServices().coordination.fonts.replayRegistry.sessions.delete("fixture-snapshot-session");
  delete (globalThis as Record<string, unknown>).__TiqianSnapshotFixtureActive;
  delete globalServices().coordination.layoutWorker;
  delete (globalThis as Record<string, unknown>).__TiqianSnapshotFontShapeCount;
  delete (globalThis as Record<string, unknown>).__TiqianSnapshotFontFallbackCount;
}

export function snapshotFontShapeCount(): number {
  return ((globalThis as Record<string, unknown>).__TiqianSnapshotFontShapeCount as number) || 0;
}

export function snapshotFontFallbackCount(): number {
  return ((globalThis as Record<string, unknown>).__TiqianSnapshotFontFallbackCount as number) || 0;
}

export function installPreparedWorkerIssue(detail: unknown): void {
  // The .mjs stub never carries version/semanticReplayRevision/release; the
  // assertion keeps the installed shape identical to the frozen host.
  globalServices().coordination.layoutWorker = probe<TiqianLayoutWorkerInstance>({
    take: () => null,
    issue: () => detail as string | null,
  });
}

// One semantic entry of a serialized live-plan worker request.
interface LivePlanSemantic {
  start: number;
  end: number;
  tagName: string;
  sourceIndex: number;
  order: number;
}

// The entry shape emitted after ordering: `order` is consumed by the sort.
interface LivePlanSemanticEntry {
  start: number;
  end: number;
  tagName: string;
  sourceIndex: number;
}

export function installPreparedWorkerLivePlan(): void {
  globalServices().coordination.layoutWorker = probe<TiqianLayoutWorkerInstance>({
    take(_element: unknown, _sessionKey: string, requestText: string): string {
      const request = JSON.parse(requestText) as Record<string, unknown>;
      const semantics: LivePlanSemanticEntry[] = Array.from(
        (request.semantics || []) as Record<string, unknown>[],
        function (this: void, semantic: Record<string, unknown>, sourceIndex: number): LivePlanSemantic {
          return {
            start: semantic.start as number,
            end: semantic.end as number,
            tagName: semantic.tagName as string,
            sourceIndex: Number.isSafeInteger(semantic.sourceIndex)
              ? semantic.sourceIndex as number
              : sourceIndex,
            order: Number.isSafeInteger(semantic.order) ? semantic.order as number : sourceIndex,
          };
        },
      ).sort(function (left: LivePlanSemantic, right: LivePlanSemantic) {
        return left.start - right.start || right.end - left.end || left.order - right.order;
      }).map(function (semantic: LivePlanSemantic): LivePlanSemanticEntry {
        return {
          start: semantic.start,
          end: semantic.end,
          tagName: semantic.tagName,
          sourceIndex: semantic.sourceIndex,
        };
      });
      const text = String(request.text || "");
      const charWidth = Number(request.fontSizePx) || 18;
      const lineHeight = Number(request.lineHeightPx) || 30;
      const indent = (Number(request.firstLineIndentIc) || 0) * charWidth;
      const inlineGeometry: Record<string, number> = {};
      for (const record of String(request.inlineObjects || "").split("\u001e")) {
        if (!record) continue;
        const fields = record.split("\u001d");
        inlineGeometry[fields[0] + "-" + fields[1]] = Number(fields[2]) || charWidth;
      }
      const cells: PreparedLivePlanCell[] = [];
      let drawX = indent;
      let index = 0;
      while (index < text.length) {
        const code = text.codePointAt(index);
        const size = code && code >= 0x10000 ? 2 : 1;
        const key = index + "-" + (index + size);
        const naturalWidth = inlineGeometry[key] != null ? inlineGeometry[key] : charWidth;
        cells.push({
          rangeStart: index,
          rangeEnd: index + size,
          source: text.slice(index, index + size),
          display: text.slice(index, index + size),
          drawX: drawX,
          naturalWidth: naturalWidth,
          leadingLayoutAdvance: 0,
        });
        drawX += naturalWidth;
        index += size;
      }
      const plan = {
        schema: SNAPSHOT_SCHEMA,
        layoutRevision: LAYOUT_REVISION,
        height: lineHeight,
        lines: cells.length
          ? [{
              rangeStart: 0,
              rangeEnd: text.length,
              endReason: "ParagraphEnd",
              indent: indent,
              visualWidth: drawX - indent,
              hyphenAdvance: 0,
              top: 0,
              bottom: lineHeight,
              baseline: lineHeight - 6,
              cells: cells,
            }]
          : [],
      };
      return JSON.stringify({
        plan: plan,
        semanticReplay: "live-source",
        semantics,
        inlineBoxes: request.renderInlineBoxes || [],
      });
    },
    issue: () => null,
  });
}

export const enginePunctuationFeatureStyle = `
        <style>
          [data-tq-rendered="true"] {
            font-feature-settings: "halt" 0, "chws" 0, "palt" 0 !important;
          }
          [data-tq-rendered="true"] span[data-tq-open-type-features="pwid,palt"] {
            font-feature-settings: "halt" 0, "chws" 0, "palt" 1 !important;
          }
        </style>
    `;

export function assertEnginePunctuationFeatureLock(element: FakeElement, proportionalQuote = false): void {
  const features = computedStyleValue(element, "font-feature-settings");
  assert.ok(/["']halt["']\s+0/.test(features), features);
  assert.ok(/["']chws["']\s+0/.test(features), features);
  const palt = /["']palt["'](?:\s+(-?\d+))?/.exec(features);
  assert.ok(palt, features);
  const paltValue = palt[1] === undefined ? "1" : palt[1];
  assert.equal(proportionalQuote ? "1" : "0", paltValue, features);
}

export const PROGRESSIVE_TIER_COUNT = 3;

export function attachWorker(root: FakeElement): void {
  tiqianWeb().workerAttach(root as FakeElement & Element);
}

export function grantWorkerSlice(root: FakeElement, deadlineMs = 0): number {
  const controller = testGrantController(
    root,
    tiqianWeb().workerJobGeneration(root as FakeElement & Element),
    deadlineMs,
    Number.MAX_SAFE_INTEGER,
  );
  return tiqianWeb().workerRunSlice(controller, PROGRESSIVE_TIER_COUNT);
}

export function runWorkerJobToCompletion(root: FakeElement, deadlineMs = 0): number {
  let slices = 0;
  while (tiqianWeb().workerHasJob(root as FakeElement & Element)) {
    grantWorkerSlice(root, deadlineMs);
    slices += 1;
    if (slices > 1000) throw new Error("attached worker job did not settle");
  }
  return slices;
}

export function grantUnboundedSlice(root: FakeElement, minTier: number): number {
  const controller = testGrantController(
    root,
    tiqianWeb().workerJobGeneration(root as FakeElement & Element),
    Infinity,
    Number.MAX_SAFE_INTEGER,
  );
  return tiqianWeb().workerRunSlice(controller, minTier);
}

export function renderedLineSignature(paragraph: FakeElement): string {
  return Array.from(paragraph.querySelectorAll(".tq-line"))
    .map((line) => [
      (line as FakeElement).dataset.tqLineRange,
      (line as FakeElement).dataset.tqLineWidth,
      (line as FakeElement).dataset.tqLineEnd,
    ].join("\u001f"))
    .join("\u001e");
}

export function dispatchTestProgressiveScroll(): void {
  ((globalThis as Record<string, unknown>).window as Window | undefined)?.dispatchEvent?.(new FakeEvent("scroll") as FakeEvent & Event);
}

export function testOptions(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return { fontSize: 18, lineHeight: 30, ...overrides };
}

export function elementFragmentWidths(element: FakeElement): number[] {
  return Array.from(element.getClientRects()).filter((rect) => rect.width > 0).map((rect) => rect.width);
}

export function snapshotWorkerRequestMaxWidth(root: FakeElement, paragraph: FakeElement): number {
  const request = workerLayoutRequestForRoot(root as FakeElement & Element, paragraph as FakeElement & Element, optionsFromJs({
    snapshotFontSession: {
      status: "conforming",
      sessionId: "fixture-grid-session",
      detail: "test",
    },
  }));
  if (!request) throw new Error("worker layout request unavailable for snapshot fixture");
  return request.maxWidthPx;
}

export function snapshotTestOptions(): Record<string, unknown> {
  return {
    paragraphSelector: "p[data-tq-snapshot-key]",
    snapshotFontSession: {
      status: "conforming",
      sessionId: "fixture-snapshot-session",
      detail: "test",
    },
  };
}

let runtimePromise: Promise<unknown> | undefined;


// Typed accessors for the doubles this host installs on globalThis; call
// sites never property-access an unknown-typed global directly.
type GlobalDataTransferCtor = new () => FakeDataTransfer;
type GlobalClipboardEventCtor = new (type: string, init: ClipboardEventInitOptions) => FakeClipboardEvent;

function globalDataTransfer(): FakeDataTransfer {
  return new ((globalThis as Record<string, unknown>).DataTransfer as GlobalDataTransferCtor)();
}

function globalClipboardEvent(type: string, init: ClipboardEventInitOptions): FakeClipboardEvent {
  return new ((globalThis as Record<string, unknown>).ClipboardEvent as GlobalClipboardEventCtor)(type, init);
}

function globalGetSelection(): FakeSelection | null {
  const getSelection = (globalThis as Record<string, unknown>).getSelection as (() => FakeSelection) | undefined;
  return getSelection?.() ?? null;
}

function globalCreateRange(): FakeRange | null {
  const doc = (globalThis as Record<string, unknown>).document as FakeDocument | undefined;
  return doc?.createRange?.() as FakeRange | null;
}

// The TiqianWeb bridge this host installs on globalThis; call sites reach it
// through tiqianWeb() so none of them property-access an unknown-typed global.
export interface TiqianWebBridge {
  install(): void;
  enhance(root: Element, options?: unknown): number;
  enhanceProgressively(root: Element, options?: unknown): void;
  destroy(root: Element): void;
  detach(root: Element): void;
  relayout(root: Element): void;
  refresh(root: Element, progressively?: boolean): Element | HTMLElement;
  cancelLayoutWork(root: Element): void;
  probeContentDrift(root: Element): unknown;
  reconcileContent(root: Element, paragraphs: unknown[]): unknown;
  workerLayoutRequest(root: Element, paragraph: Element, options: unknown): string | null;
  workerAttach(root: Element): void;
  workerDetach(root: Element): void;
  workerHasJob(root: Element): boolean;
  workerJobGeneration(root: Element): number;
  workerRunSlice(controller: unknown, minTier: number): number;
  workerPendingInTier(root: Element, tier: number): number;
  workerParagraphCount(root: Element): number;
  workerParagraphAt(root: Element, index: number): Element | null;
  workerSetParagraphTier(root: Element, index: number, tier: number): void;
}

function tiqianWeb(): TiqianWebBridge {
  return (globalThis as Record<string, unknown>).TiqianWeb as TiqianWebBridge;
}

export async function loadHostRuntime(): Promise<TiqianWebBridge> {
  buildWorld();
  initializeGlobalServices();
  runtimePromise ??= Promise.resolve().then(() => {
    const layoutJobPool = globalServices().coordination.layoutJobPool;
    runtimeServices = { layoutJobPool };

    const bridge = {
      install() {
        if (globalThis.document) globalServices().clipboard.install(globalThis.document);
      },
      enhance(root: Element, options: unknown) {
        return enhance(contextForRoot(root as Element & FakeElement), root, (options ?? null) as Record<string, unknown> | null, false);
      },
      enhanceProgressively(root: Element, options: unknown) {
        enhanceProgressively(contextForRoot(root as Element & FakeElement), root, (options ?? null) as Record<string, unknown> | null);
      },
      destroy(root: Element) {
        destroyRoot(contextForRoot(root as Element & FakeElement), root as Element & HTMLElement);
      },
      detach(root: Element) {
        detachRoot(contextForRoot(root as Element & FakeElement), root as Element & HTMLElement);
      },
      relayout(root: Element) {
        relayout(contextForRoot(root as Element & FakeElement), root);
      },
      refresh(root: Element, progressively = true) {
        const context = contextForRoot(root as Element & FakeElement);
        const canonicalOptions = context.contextState.runtimeOptions;
        if (context.contextState.runtimeEstablished && canonicalOptions) {
          if (progressively) {
            enhanceProgressivelyFromCanonical(context, root, canonicalOptions);
          } else {
            enhance(context, root, canonicalOptions, true);
          }
        }
        return root ?? ((globalThis as Record<string, unknown>).document as Document).body;
      },
      cancelLayoutWork(root: Element) {
        layoutJobPool.cancelJob(root);
      },
      probeContentDrift(root: Element) {
        return probeRootContentDrift(contextForRoot(root as Element & FakeElement), root);
      },
      reconcileContent(root: Element, paragraphs: unknown[]) {
        return reconcileRoot(
          contextForRoot(root as Element & FakeElement),
          root as Element & HTMLElement,
          paragraphs as unknown[] & Element[],
        );
      },
      workerLayoutRequest(root: Element, paragraph: Element, options: unknown) {
        const request = workerLayoutRequestForRoot(root, paragraph, optionsFromJs((options ?? {}) as Record<string, unknown>));
        return request ? JSON.stringify(request) : null;
      },
      workerAttach: (root: Element) => layoutJobPool.attach(root),
      workerDetach: (root: Element) => layoutJobPool.detach(root),
      workerHasJob: (root: Element) => layoutJobPool.hasJob(root),
      workerJobGeneration: (root: Element) => layoutJobPool.jobGeneration(root),
      workerRunSlice: (controller: unknown, minTier: number) => layoutJobPool.runSlice(controller as GrantController, minTier),
      workerPendingInTier: (root: Element, tier: number) => layoutJobPool.pendingInTier(root, tier),
      workerParagraphCount: (root: Element) => layoutJobPool.paragraphCount(root),
      workerParagraphAt: (root: Element, index: number) => layoutJobPool.paragraphAt(root, index),
      workerSetParagraphTier: (root: Element, index: number, tier: number) => layoutJobPool.setParagraphTier(root, index, tier),
    };
    (globalThis as Record<string, unknown>).TiqianWeb = bridge;
    return bridge;
  });
  return runtimePromise as Promise<TiqianWebBridge>;
}

export function computedStyleValue(element: FakeElement, property: string): string {
  const computed = (globalThis as Record<string, unknown>).getComputedStyle as GlobalGetComputedStyle;
  return computed(element as FakeElement & Element).getPropertyValue(property);
}

export function nativeInnerText(element: FakeElement): string {
  return element.innerText;
}

export function emptyRenderedLineCount(paragraph: FakeElement): number {
  return Array.from(paragraph.querySelectorAll(".tq-line"))
    .filter((line) => (line as FakeElement).dataset.tqLineEmpty === "true")
    .length;
}

export function elementWidth(element: FakeElement): number {
  return element.getBoundingClientRect().width;
}

export function preparedValueStyleProperty(element: FakeElement, property: string): string {
  const classes = new Set(
    String(element.getAttribute("class") ?? "").split(/\s+/u).filter(Boolean),
  );
  if (classes.size === 0) return "";
  const doc = element.ownerDocument ?? (globalThis as Record<string, unknown>).document as FakeDocument;
  const parents = [doc.head, doc.body, doc.documentElement].filter(Boolean);
  let resolved = "";
  for (const parent of parents) {
    for (const style of parent.childNodes ?? []) {
      if (!(style instanceof FakeElement) || style.tagName !== "STYLE") continue;
      for (const rule of String(style.textContent ?? "").matchAll(/\.([A-Za-z0-9_-]+)\{([^}]*)\}/gu)) {
        if (!classes.has(rule[1])) continue;
        for (const declaration of rule[2].split(";")) {
          const colon = declaration.indexOf(":");
          if (colon < 0) continue;
          if (declaration.slice(0, colon).trim() === property) {
            resolved = declaration.slice(colon + 1).replace(/!important\s*$/u, "").trim();
          }
        }
      }
    }
  }
  return resolved;
}

export function copySelection(element: FakeElement): string {
  const selection = globalGetSelection();
  const range = globalCreateRange();
  if (!selection || !range) throw new Error("clipboard doubles not installed");
  range.selectNodeContents(element);
  selection.removeAllRanges();
  selection.addRange(range);
  const clipboardData = globalDataTransfer();
  const event = globalClipboardEvent("copy", {
    bubbles: true,
    cancelable: true,
    clipboardData,
  });
  (element as FakeElement & HostElement).dispatchEvent(event);
  const text = clipboardData.getData("text/plain") || selection.toString();
  selection.removeAllRanges();
  return text;
}

export function copiedData(element: FakeElement, type: string): string {
  const selection = globalGetSelection();
  const range = globalCreateRange();
  if (!selection || !range) throw new Error("clipboard doubles not installed");
  range.selectNodeContents(element);
  selection.removeAllRanges();
  selection.addRange(range);
  const clipboardData = globalDataTransfer();
  (element as FakeElement & HostElement).dispatchEvent(
    globalClipboardEvent("copy", {
      bubbles: true,
      cancelable: true,
      clipboardData,
    }),
  );
  const value = clipboardData.getData(type);
  selection.removeAllRanges();
  return value;
}

export function copiedNodeData(node: FakeNode, type: string): string {
  const selection = globalGetSelection();
  const range = globalCreateRange();
  if (!selection || !range) throw new Error("clipboard doubles not installed");
  range.selectNode(node);
  selection.removeAllRanges();
  selection.addRange(range);
  const clipboardData = globalDataTransfer();
  ((node as FakeElement).parentElement as (FakeElement & HostElement) | null)?.dispatchEvent(
    globalClipboardEvent("copy", {
      bubbles: true,
      cancelable: true,
      clipboardData,
    }),
  );
  const value = clipboardData.getData(type);
  selection.removeAllRanges();
  return value;
}

export function copyWasIntercepted(element: FakeElement): boolean {
  const selection = globalGetSelection();
  const range = globalCreateRange();
  if (!selection || !range) throw new Error("clipboard doubles not installed");
  range.selectNodeContents(element);
  selection.removeAllRanges();
  selection.addRange(range);
  const event = globalClipboardEvent("copy", {
    bubbles: true,
    cancelable: true,
    clipboardData: globalDataTransfer(),
  });
  (element as FakeElement & HostElement).dispatchEvent(event);
  selection.removeAllRanges();
  return event.defaultPrevented;
}

export const copySelectionWasIntercepted = copyWasIntercepted;

export function clearSelection(): void {
  const selection = probe<GlobalWithSelection>(globalThis).getSelection?.();
  if (selection) selection.removeAllRanges();
}

const mounted: HostElement[] = [];

export function mount(html: string, { sharedStylesReady = true }: MountOptions = {}): HostElement {
  buildWorld();
  const wrapper = new HostElement("div");
  wrapper.ownerDocument = (globalThis as Record<string, unknown>).document as FakeDocument;
  wrapper.innerHTML = html;
  const root = wrapper.firstElementChild;
  if (!root) throw new Error("mount: markup has no root element");
  if (sharedStylesReady) {
    root.style.setProperty("--tq-styles-ready", "1");
  }
  ((globalThis as Record<string, unknown>).document as FakeDocument).body.appendChild(root);
  mounted.push(root);
  return root;
}

export async function cleanupMounted(): Promise<void> {
  const bridge = tiqianWeb();
  for (const root of mounted) {
    try {
      bridge?.destroy?.(probe<Element>(root));
    } catch {}
    try {
      bridge?.workerDetach?.(probe<Element>(root));
    } catch {}
    root.parentNode?.removeChild?.(root);
  }
  mounted.length = 0;
  clearSnapshotFontSessionFixture();
  restoreTestAnimationFrames();
  cleanupWorld();
}

export function computedPseudoContent(element: FakeElement, pseudo: string): string {
  const computed = (globalThis as Record<string, unknown>).getComputedStyle as GlobalGetComputedStyle;
  const content = computed(element as FakeElement & Element, pseudo).getPropertyValue("content").trim();
  if ((content.startsWith('"') && content.endsWith('"')) ||
      (content.startsWith("'") && content.endsWith("'"))) {
    return content.slice(1, -1);
  }
  return content;
}

export function directTextContent(paragraph: FakeElement): string {
  return Array.from(paragraph.childNodes)
    .filter((node) => node.nodeType === 3)
    .map((node) => (node as FakeNode & { data?: string }).data)
    .join("");
}

export function selectionCoversElement(container: FakeElement, target: FakeElement): boolean {
  const range = globalCreateRange();
  if (!range) throw new Error("clipboard doubles not installed");
  range.selectNodeContents(container);
  const selected = range.getBoundingClientRect();
  const expected = target.getBoundingClientRect();
  return selected.left <= expected.left + 0.1 && selected.right >= expected.right - 0.1;
}
