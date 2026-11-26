// Part-level coverage for the behavior the dissolved root-state.ts carried
// (core-neutral wave). The WeakMap registry (getState/setState/deleteState
// per root) no longer exists by design: one context per element, so where
// the old file asked "does this root carry runtime state" these tests
// observe context.contextState.runtimeEstablished. The preparedDomEnabled
// flag, the activeTsOptions view and the engineState identity cross-section
// were dissolved with it. Subjects: OptionsLedger engine-option resolution
// (bag first-parse vs canonical re-entry), DomWriteLayer.publishState
// attribute projection, EffectSync.strandedSourceParagraphs,
// ContextState.paragraphCandidates, and the TypographyManager capability
// and browser-fallback descriptors.

import assert from "node:assert/strict";
import test from "node:test";

import { createEnhanceContext } from "../src/engine/context/enhance-context.js";
import type { EnhancedElementContext } from "../src/engine/context/enhance-context.js";
import { activeSnapshotSessionDescriptor } from "../src/engine/enhance/snapshot-adoption.js";
import { initializeGlobalServices } from "../src/services/global-services.js";
import type { EnhanceOptions, ResolvedEnhanceOptions } from "../src/engine/lifecycle.js";
import type { TrackedParagraph } from "../src/engine/enhance/context-state.js";
import type { LoweredParagraph } from "../src/engine/lowered-paragraph.js";
initializeGlobalServices();


// Real lifecycle defaults resolved by withRootDefaults when the root inherits
// nothing.
const DEFAULT_CJK_FONT_FAMILY = '"MiSans VF", "PingFang SC", "Noto Sans CJK SC", sans-serif';
const DEFAULT_LATIN_FONT_FAMILY = '"InterVariable", "Inter", "MiSans VF", sans-serif';
const DEFAULT_MONOSPACE_FONT_FAMILY =
  '"JetBrains Mono Variable", "SFMono-Regular", Menlo, Consolas, "MiSans VF", monospace';
const DEFAULT_CJK_SERIF_FONT_FAMILY = '"MetroSungPlus-SC", "Songti SC", serif';
const DEFAULT_LATIN_SERIF_FONT_FAMILY = 'Georgia, "Times New Roman", serif';

interface SavedGlobal {
  name: string;
  own: boolean;
  value: unknown;
}

function preserveGlobals(names: string[]): SavedGlobal[] {
  return names.map((name) => ({
    name,
    own: Object.prototype.hasOwnProperty.call(globalThis, name),
    value: globalThis[name as keyof typeof globalThis],
  }));
}

function restoreGlobals(entries: SavedGlobal[]): void {
  for (const { name, own, value } of entries) {
    if (own) (globalThis as Record<string, unknown>)[name] = value;
    else delete (globalThis as Record<string, unknown>)[name];
  }
}

type ClosestFn = (selector: string) => FakeElement | null;

interface FakeElementOverrides {
  tagName?: string;
  parent?: FakeElement | null;
  children?: FakeElement[];
  textContent?: string;
  closestFn?: ClosestFn | null;
  querySelectorAllResult?: FakeElement[] | null;
  attributes?: Record<string, string>;
}

class FakeElement {
  tagName: string;
  parent: FakeElement | null;
  children: FakeElement[];
  textContent: string;
  closestFn: ClosestFn | null;
  querySelectorAllResult: FakeElement[] | null;
  attributes: Map<string, string>;
  setAttributeCalls: Array<[string, string]>;

  constructor(overrides: FakeElementOverrides = {}) {
    this.tagName = overrides.tagName ?? "P";
    this.parent = overrides.parent ?? null;
    this.children = overrides.children ?? [];
    this.textContent = overrides.textContent ?? "text";
    this.closestFn = overrides.closestFn ?? null;
    this.querySelectorAllResult = overrides.querySelectorAllResult ?? null;
    this.attributes = new Map(Object.entries(overrides.attributes ?? {}));
    this.setAttributeCalls = [];
    for (const child of this.children) child.parent = this;
  }
  getAttribute(name: string): string | null {
    return this.attributes.get(name) ?? null;
  }
  setAttribute(name: string, value: string): void {
    this.setAttributeCalls.push([name, String(value)]);
    this.attributes.set(name, String(value));
  }
  removeAttribute(name: string): void {
    this.attributes.delete(name);
  }
  closest(selector: string): FakeElement | null {
    if (this.closestFn) return this.closestFn(selector);
    return null;
  }
  contains(other: FakeElement | null): boolean {
    let node: FakeElement | null = other ?? null;
    while (node) {
      if (node === this) return true;
      node = node.parent;
    }
    return false;
  }
  querySelectorAll(_selector: string): FakeElement[] {
    if (this.querySelectorAllResult) return this.querySelectorAllResult;
    return this.children.slice();
  }
}

// Bridge alias so the local fake crosses into DOM-typed APIs with a single
// assertion (the intersection is assignable back to FakeElement).
type FakeElementAsElement = FakeElement & Element;

interface FakeComputedStyle {
  getPropertyValue(property: string): string;
}

type FakeGetComputedStyle = () => FakeComputedStyle;

type Producer<T> = () => T;

// withRootDefaults reads the root's computed font-family; an empty answer
// makes every family fall back to the built-in default stack.
function withComputedStyle<T>(fn: Producer<T>): T {
  const saved = preserveGlobals(["getComputedStyle"]);
  const fakeGetComputedStyle: FakeGetComputedStyle = () => ({
    getPropertyValue: (): string => "",
  });
  (globalThis as Record<string, unknown>).getComputedStyle = fakeGetComputedStyle;
  try {
    return fn();
  } finally {
    restoreGlobals(saved);
  }
}

// Paragraph records pushed in these tests only exercise `source`; lowered and
// lastMeasure stay null placeholders. The nullable widening keeps the real
// TrackedParagraph assignable, so the stub crosses into pushParagraph with a
// single assertion.
interface TrackedParagraphStub {
  source: Element;
  lowered: LoweredParagraph | null;
  lastMeasure: number | null;
}

test("1. resolveEngineOptions: bag -> optionsFromJs -> snapshot gate -> withRootDefaults; context parts start empty", () => {
  withComputedStyle(() => {
    const root = new FakeElement({
      attributes: { "data-tiqian-snapshot-layout-fallback": "stale" },
    }) as FakeElementAsElement;
    const context = createEnhanceContext(root);

    // Context construction leaves the fallback marker untouched and writes
    // no attributes of its own.
    assert.equal(root.getAttribute("data-tiqian-snapshot-layout-fallback"), "stale");
    assert.equal(
      root.setAttributeCalls.filter((call) => call[0] === "data-tiqian-snapshot-layout-fallback").length,
      0
    );
    assert.equal(context.element, root);
    assert.deepEqual(context.contextState.paragraphs, []);
    assert.deepEqual(context.diagnosis.issues, []);

    // fontSize bag: the snapshot gate routes through withoutSnapshotFontSession.
    const resolved = context.optionsLedger.resolveEngineOptions(root, { fontSize: 19 });
    assert.equal(resolved.fontSize, 19);
    assert.equal(resolved.snapshotFontSession, null);
    assert.equal(resolved.fontFamilies.cjk, DEFAULT_CJK_FONT_FAMILY);
    assert.equal(resolved.fontFamilies.latin, DEFAULT_LATIN_FONT_FAMILY);
    assert.equal(resolved.fontFamilies.monospace, DEFAULT_MONOSPACE_FONT_FAMILY);
    assert.equal(resolved.fontFamilies.cjkSerif, DEFAULT_CJK_SERIF_FONT_FAMILY);
    assert.equal(resolved.fontFamilies.latinSerif, DEFAULT_LATIN_SERIF_FONT_FAMILY);

    // Runtime establishment computes the dash capability evidence and builds
    // the browser fallback bridge (both dissolved from root-state onto the
    // typography part).
    context.typography.establishRuntime(root, resolved);
    assert.deepEqual(context.typography.cjkDashCapability, { status: "not-needed", detail: null });
    assert.ok(context.typography.browserFallback != null);
    assert.ok(context.typography.browserFallback.bridge);
    assert.equal(typeof context.typography.browserFallback.bridge.shape, "function");
    assert.equal(typeof context.typography.browserFallback.bridge.resolve, "function");

    // All-default bag: the snapshot gate passes straight through, so the
    // withoutSnapshotFontSession path is never taken.
    const allDefault = context.optionsLedger.resolveEngineOptions(root, {});
    assert.equal(allDefault.snapshotFontSession, null);

    // null bag also works.
    const nullBag = context.optionsLedger.resolveEngineOptions(root, {});
    assert.equal(nullBag.fontSize, null);
  });
});

test("2. resolveEngineOptionsFromCanonical skips optionsFromJs and the snapshot gate but runs withRootDefaults", () => {
  withComputedStyle(() => {
    const root = new FakeElement() as FakeElementAsElement;
    const context = createEnhanceContext(root);
    const canonical: EnhanceOptions = {
      fontFamilies: { cjk: "CJK", latin: "Latin", monospace: "Mono", cjkSerif: "Serif", latinSerif: "LatinSerif" },
      fontSize: 19,
      lineHeight: null,
      firstLineIndentIc: 0,
      emphasisDotGapEm: 0.1,
      strongAsEmphasisMarks: false,
      paragraphSelector: "p, li",
      cjkDashCapability: null,
      snapshotFontSession: { status: "conforming", sessionId: "canonical-session", detail: null },
      requireSnapshotLayoutWorker: false,
    };

    const resolved = context.optionsLedger.resolveEngineOptionsFromCanonical(root, canonical);

    assert.equal(context.element, root);
    // Explicit families pass through unchanged; the snapshot gate is
    // skipped, so the conforming session survives despite the fontSize.
    assert.equal(resolved.fontFamilies.cjk, "CJK");
    assert.equal(resolved.snapshotFontSession!.sessionId, "canonical-session");
    assert.deepEqual(context.contextState.paragraphs, []);
    assert.deepEqual(context.diagnosis.issues, []);

    context.typography.establishRuntime(root, resolved);
    assert.deepEqual(context.typography.cjkDashCapability, { status: "not-needed", detail: null });
  });
});

test("3. snapshot session descriptor: resolved from the canonical options, no fallback attribute", () => {
  withComputedStyle(() => {
    const root = new FakeElement() as FakeElementAsElement;
    const context = createEnhanceContext(root);
    const resolved = context.optionsLedger.resolveEngineOptions(root, {
      snapshotFontSession: { status: "conforming", sessionId: "sess-1", detail: null },
    });

    // The descriptor resolves the session id into the callback pair ffi takes
    // as call parameters; an unregistered id only fails at call time.
    const descriptor = activeSnapshotSessionDescriptor(resolved);
    assert.equal(typeof descriptor!.shape, "function");
    assert.equal(typeof descriptor!.resolve, "function");

    // The former disable toggle and its fallback attribute were dissolved;
    // construction must not write the fallback marker at all.
    assert.equal(root.getAttribute("data-tiqian-snapshot-layout-fallback"), null);
    assert.equal(
      root.setAttributeCalls.filter((call) => call[0] === "data-tiqian-snapshot-layout-fallback").length,
      0
    );
  });
});

test("4. context cross-section: live arrays, reference push paths", () => {
  withComputedStyle(() => {
    const root = new FakeElement() as FakeElementAsElement;
    const context = createEnhanceContext(root);
    const resolved = context.optionsLedger.resolveEngineOptions(root, {
      snapshotFontSession: { status: "conforming", sessionId: "sess-1", detail: null },
    });
    context.typography.establishRuntime(root, resolved);

    assert.ok(context.typography.browserFallback != null);
    assert.ok(context.typography.browserFallback.bridge);
    assert.equal(typeof context.typography.browserFallback.bridge.shape, "function");
    assert.equal(typeof context.typography.browserFallback.bridge.resolve, "function");

    // Capability issue records accumulate by reference on the diagnosis
    // manager's live array (the former engineState onIssue callback).
    const issue = { name: "MissingSharedRuntimeStyles" };
    context.diagnosis.issues.push(issue);
    assert.equal(context.diagnosis.issues.length, 1);
    assert.equal(context.diagnosis.issues[0], issue);

    // Tracked paragraphs accumulate through pushParagraph on the context
    // state's live array (the former onParagraphCommitted callback).
    const item: TrackedParagraphStub = { source: root, lowered: null, lastMeasure: null };
    context.contextState.pushParagraph(item as TrackedParagraph);
    assert.equal(context.contextState.paragraphs.length, 1);
    assert.equal(context.contextState.paragraphs[0], item);
  });
});

test("5. publishState: work branch, keepEmpty branch, delete branch, snapshot count participation", () => {
  withComputedStyle(() => {
    // Work branch: attributes written, the runtime-established flag replaces
    // the former WeakMap presence check, and the observable snapshot count
    // participates in the enhanced count.
    const rootWork = new FakeElement() as FakeElementAsElement;
    const contextWork = createEnhanceContext(rootWork);
    const workParagraph: TrackedParagraphStub = { source: rootWork, lowered: null, lastMeasure: null };
    contextWork.contextState.pushParagraph(workParagraph as TrackedParagraph);
    rootWork.setAttribute("data-tiqian-snapshot-count", "3");
    contextWork.domWriteLayer.publishState(
      contextWork.contextState.paragraphs.length,
      contextWork.diagnosis.issues.length
    );
    assert.equal(rootWork.getAttribute("data-tiqian-enhanced"), "true");
    assert.equal(rootWork.getAttribute("data-tiqian-enhanced-count"), "4");
    assert.equal(rootWork.getAttribute("data-tiqian-issue-count"), null);
    assert.equal(contextWork.contextState.runtimeEstablished, true);

    // keepEmpty: no work but the flag is retained and attributes still write.
    const rootKeep = new FakeElement() as FakeElementAsElement;
    const contextKeep = createEnhanceContext(rootKeep);
    contextKeep.domWriteLayer.publishState(0, 0, true);
    assert.equal(contextKeep.contextState.runtimeEstablished, true);
    assert.equal(rootKeep.getAttribute("data-tiqian-enhanced"), "true");
    assert.equal(rootKeep.getAttribute("data-tiqian-enhanced-count"), "0");
    assert.equal(rootKeep.getAttribute("data-tiqian-issue-count"), null);

    // delete branch: no work and not keepEmpty -> the flag drops and the
    // three attributes are removed.
    const rootDelete = new FakeElement({
      attributes: {
        "data-tiqian-enhanced": "true",
        "data-tiqian-enhanced-count": "2",
        "data-tiqian-issue-count": "1",
      },
    }) as FakeElementAsElement;
    const contextDelete = createEnhanceContext(rootDelete);
    contextDelete.contextState.setRuntimeEstablished(true);
    contextDelete.domWriteLayer.publishState(0, 0);
    assert.equal(contextDelete.contextState.runtimeEstablished, false);
    assert.equal(rootDelete.getAttribute("data-tiqian-enhanced"), null);
    assert.equal(rootDelete.getAttribute("data-tiqian-enhanced-count"), null);
    assert.equal(rootDelete.getAttribute("data-tiqian-issue-count"), null);

    // Issue count branch: issues present -> issue-count written.
    const rootIssue = new FakeElement() as FakeElementAsElement;
    const contextIssue = createEnhanceContext(rootIssue);
    contextIssue.diagnosis.issues.push({ name: "MissingSharedRuntimeStyles" });
    contextIssue.domWriteLayer.publishState(
      contextIssue.contextState.paragraphs.length,
      contextIssue.diagnosis.issues.length
    );
    assert.equal(rootIssue.getAttribute("data-tiqian-issue-count"), "1");
  });
});

test("6. strandedSourceParagraphs: empty paragraphs returns all candidates; rendered sources subtracted", () => {
  withComputedStyle(() => {
    const c0 = new FakeElement() as FakeElementAsElement;
    const c1 = new FakeElement();
    const c2 = new FakeElement() as FakeElementAsElement;
    const root = new FakeElement({ children: [c0, c1, c2] }) as FakeElementAsElement;
    const context = createEnhanceContext(root);
    context.contextState.setRuntimeOptions(context.optionsLedger.resolveEngineOptions(root, {}));

    assert.deepEqual(context.effectSync.strandedSourceParagraphs(), [c0, c1, c2]);

    const firstTracked: TrackedParagraphStub = { source: c0, lowered: null, lastMeasure: null };
    context.contextState.pushParagraph(firstTracked as TrackedParagraph);
    const secondTracked: TrackedParagraphStub = { source: c2, lowered: null, lastMeasure: null };
    context.contextState.pushParagraph(secondTracked as TrackedParagraph);
    assert.deepEqual(context.effectSync.strandedSourceParagraphs(), [c1]);
  });
});

test("7. paragraphCandidates: root-scope and real eligibility filtering", () => {
  const root = new FakeElement() as FakeElementAsElement;
  const context = createEnhanceContext(root);
  const innerEl = new FakeElement({ parent: root });
  const outsideEl = new FakeElement();
  // closest answers the root-scope owner for the root selector and stays null
  // for every other selector (including eligibility's skip-list ancestor
  // selector), so the real shouldTryParagraph predicate is exercised.
  const rootScopedClosest = (owner: FakeElement) => (selector: string): FakeElement | null =>
    selector === "tiqian-prose, [data-tiqian-root]" ? owner : null;
  // closest null -> owner absent, in scope, eligible.
  const p1 = new FakeElement({ parent: root });
  // owner lives outside the root -> in scope, eligible.
  const p2 = new FakeElement({ parent: root, closestFn: rootScopedClosest(outsideEl) });
  // owner is the root itself -> the root owns the paragraph, in scope.
  const p3 = new FakeElement({ parent: root, closestFn: rootScopedClosest(root) });
  // owner is a descendant inside the root -> out of scope even when eligible.
  const p4 = new FakeElement({ parent: root, closestFn: rootScopedClosest(innerEl) });
  // a plain in-scope paragraph is eligible.
  const p5 = new FakeElement({ parent: root });
  // data-tiqian-skip marks an in-scope paragraph ineligible.
  const p6 = new FakeElement({ parent: root, attributes: { "data-tiqian-skip": "" } });
  root.querySelectorAllResult = [p1, p2, p3, p4, p5, p6];

  const candidates = context.contextState.paragraphCandidates(root, "p, li");
  assert.deepEqual(candidates, [p1, p2, p3, p5]);
  // p4 is rejected by the root-scope gate (its scope owner is a nested
  // element inside the root); p6 by the real eligibility predicate
  // (data-tiqian-skip). p3 stays a candidate because its nearest scope
  // owner is the root being enhanced.
});
