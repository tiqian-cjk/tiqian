import assert from "node:assert/strict";
import test from "node:test";

import { globalServices, initializeGlobalServices } from "../src/services/global-services.js";
import { processParagraph } from "../src/engine/process-paragraph.js";
import { lowerMarkdown } from "../src/engine/markdown-lowering.js";
import { createEnhanceContext } from "../src/engine/context/enhance-context.js";
import { optionsFromJs } from "../src/engine/lifecycle.js";
import { effectiveLineMeasure } from "../src/engine/responsive-measure.js";
import { LAYOUT_REVISION, SNAPSHOT_SCHEMA } from "../src/sampler/snapshot/snapshot-schema.js";
import { installThrowingFontBackend } from "./fixture-font-backend.js";
import { FakeElement, FakeFragment, FakeNode, FakeText, asElement, asFakeElement, asNodeConstructor } from "./snapshot-dom-fixtures.js";
import type { EnhancedElementContext } from "../src/engine/context/enhance-context.js";
import type { TiqianLayoutWorkerInstance } from "../src/engine/coordination/coordination-service.js";
import type { ReplayProbe, ReplayRegistry } from "../src/measurement/browser-font-replay.js";
import { classifyRole as classifyFontRole, classifyRoles as classifyFontRoles } from "../src/engine/engine-access/font-role.js";
initializeGlobalServices();

// The pipeline runs for real: eligibility, markdown lowering, the lifecycle
// helpers, the worker request serializer, the prepared-metadata builders, the
// direct prepare step and both commit functions (including the real
// prepared-DOM renderer). The unit under test receives the per-element
// EnhancedElementContext; its contextState.paragraphs and diagnosis.issues
// live arrays are the commit/issue observation points, and the raw-DOM
// record it carries is the observation point for begin/take/commit/restore.
// The fake world supplies the document (fragment factory, style head,
// lowering probes, canvas for the browser-fallback bridge) and the Node
// prototype the raw-DOM commit forwarding captures.

interface SavedGlobal {
  name: string;
  own: boolean;
  value: unknown;
}

interface ComputedStyleValues {
  [key: string]: string;
}

// Canvas double for the browser-fallback bridge: measureText answers one
// fontSize advance per code point parsed out of the current font shorthand,
// and the TextMetrics fields carry the fixture box proportions, so the real
// canvas shaper and metrics resolver produce a complete layout envelope.
interface CanvasBox {
  width: number;
  height: number;
}

interface ScriptedTextMetrics {
  width: number;
  actualBoundingBoxLeft: number;
  actualBoundingBoxAscent: number;
  actualBoundingBoxRight: number;
  actualBoundingBoxDescent: number;
  fontBoundingBoxAscent: number;
  fontBoundingBoxDescent: number;
  ideographicBaseline: number;
}

type MeasureTextFn = (text: string) => ScriptedTextMetrics;

interface ScriptedImageData {
  data: Uint8ClampedArray;
}

type GetImageDataFn = (sx: number, sy: number, sw: number, sh: number) => ScriptedImageData;

interface CanvasContext {
  font: string;
  canvas: CanvasBox;
  measureText: MeasureTextFn;
  setTransform: VoidFunction;
  clearRect: VoidFunction;
  fillText: VoidFunction;
  getImageData: GetImageDataFn;
}

type CanvasContextGetter = () => CanvasContext;

interface FakeCanvasElement extends CanvasBox {
  getContext: CanvasContextGetter;
}

// The fake document supplies the fragment factory the raw-DOM takeover uses,
// a style-carrying head for the prepared-value style state, lowering probes
// whose baseline answers probeBottom, an inert Range for the inline-edge
// measurement, a body the canvas shaper's hidden-DOM probe attaches to, and
// a canvas whose 2d context is the scripted double above.
type EmptyClientRectsFn = () => [];

interface FakeRange {
  selectNodeContents: VoidFunction;
  getClientRects: EmptyClientRectsFn;
}

type CreateElementFn = (tagName: string) => FakeElement | FakeCanvasElement;
type CreateDocumentFragmentFn = () => FakeFragment;
type CreateRangeFn = () => FakeRange;

interface FakeDocument {
  createElement: CreateElementFn;
  createDocumentFragment: CreateDocumentFragmentFn;
  createRange: CreateRangeFn;
  head: FakeElement;
  body: FakeElement;
}

interface MakeParagraphOptions {
  width?: number;
  attributes?: Record<string, string>;
  childNodes?: Array<FakeText | FakeElement>;
}

interface WorkerTakeCall {
  element: FakeElement;
  sessionKey: string;
  request: string;
}

interface WithEnvOverrides {
  document?: FakeDocument;
  layoutWorker?: TiqianLayoutWorkerInstance;
}

type WithEnvAction<T> = () => T;

interface SeedContextOptions {
  canonical?: boolean;
}

// The computed-style double reads and the fixture builders write the
// override bag through this carrier intersection, so the fixture's own
// FakeElement declaration stays untouched.
interface ComputedValuesCarrier {
  _computedValues?: ComputedStyleValues;
}

type FakeElementWithComputedValues = FakeElement & ComputedValuesCarrier;

function readComputedValues(element: FakeElement): ComputedStyleValues | undefined {
  return (element as FakeElementWithComputedValues)._computedValues;
}

function writeComputedValues(element: FakeElement, values: ComputedStyleValues): void {
  (element as FakeElementWithComputedValues)._computedValues = values;
}

// The snapshot-session registry slot keeps a non-exported record shape, so
// the test derives it from the exported registry type instead of
// redeclaring it.
type ReplaySessionRecord = NonNullable<ReturnType<ReplayRegistry["sessions"]["get"]>>;
type ReplayTable = Map<string, unknown>;
type ReplayTableLookup = Pick<ReplayTable, "get">;

interface ReplaySessionStub {
  shapes: ReplayTable;
  metrics: ReplayTable;
  probe: ReplayProbe | null;
}

function saveGlobals(names: string[]): SavedGlobal[] {
  return names.map((name) => ({
    name,
    own: Object.prototype.hasOwnProperty.call(globalThis, name),
    value: globalThis[name as keyof typeof globalThis],
  }));
}

function restoreGlobals(entries: SavedGlobal[]): void {
  for (const { name, own, value } of entries) {
    if (own) Object.defineProperty(globalThis, name, { value, writable: true, configurable: true });
    else delete (globalThis as Record<string, unknown>)[name];
  }
}

// Computed style double: property accessors feed elementContentWidth and the
// opaque-inline-object geometry probe; getPropertyValue feeds the lowerer and
// the inline edge measurements.
function computedStyle(values: ComputedStyleValues = {}): CSSStyleDeclaration {
  const props: ComputedStyleValues = {
    paddingLeft: "0px",
    paddingRight: "0px",
    borderLeftWidth: "0px",
    borderRightWidth: "0px",
    position: "static",
    transform: "none",
    float: "none",
    marginLeft: "0px",
    marginRight: "0px",
    marginTop: "0px",
    marginBottom: "0px",
    "line-height": "33px",
    "font-family": "Fixture CJK",
    ...values,
  };
  const style: Partial<CSSStyleDeclaration> = {};
  for (const key of Object.keys(props)) (style as Record<string, unknown>)[key] = props[key];
  style.getPropertyValue = (name: string): string => {
    const key = String(name).toLowerCase();
    return Object.prototype.hasOwnProperty.call(props, key)
      ? String(props[key])
      : "";
  };
  return style as CSSStyleDeclaration;
}

function scriptedCanvasContext(): CanvasContext {
  const context: CanvasContext = {
    font: "16px sans-serif",
    canvas: { width: 0, height: 0 },
    measureText(text: string) {
      const match = /(\d+(?:\.\d+)?)px/.exec(String(context.font));
      const fontSize = match ? Number(match[1]) : 16;
      const width = Array.from(String(text)).length * fontSize;
      return {
        width,
        actualBoundingBoxLeft: 0,
        actualBoundingBoxAscent: fontSize * 0.88,
        actualBoundingBoxRight: width,
        actualBoundingBoxDescent: fontSize * 0.12,
        fontBoundingBoxAscent: fontSize * 0.88,
        fontBoundingBoxDescent: fontSize * 0.12,
        ideographicBaseline: -fontSize * 0.12,
      };
    },
    setTransform() {},
    clearRect() {},
    fillText() {},
    getImageData: (_sx: number, _sy: number, sw: number, sh: number) => ({ data: new Uint8ClampedArray(Math.max(sw, 0) * Math.max(sh, 0) * 4) }),
  };
  return context;
}

function makeFakeDocument(probeBottom: number = 0): FakeDocument {
  const documentObject: FakeDocument = {
    createElement: (tagName: string): FakeElement | FakeCanvasElement => {
      if (String(tagName || "").toLowerCase() === "canvas") {
        return {
          width: 0,
          height: 0,
          getContext: (): CanvasContext => scriptedCanvasContext(),
        };
      }
      const probe = new FakeElement(tagName || "span");
      probe.top = probeBottom;
      return probe;
    },
    createDocumentFragment: (): FakeFragment => new FakeFragment(),
    createRange: (): FakeRange => ({
      selectNodeContents() {},
      getClientRects: (): [] => [],
    }),
    head: new FakeElement("head"),
    body: new FakeElement("body"),
  };
  return documentObject;
}

// Runs fn with the environment globals the real pipeline reads.
function withEnv<T>(fn: WithEnvAction<T>, overrides: WithEnvOverrides = {}): T {
  const saved = saveGlobals([
    "getComputedStyle",
    "document",
    "Node",
  ]);
  const savedTiqianLayoutWorkerInstance = globalServices().coordination.layoutWorker;
  try {
    Object.defineProperty(globalThis, "document", { value: overrides.document ?? makeFakeDocument(), writable: true, configurable: true });
    Object.defineProperty(globalThis, "Node", { value: asNodeConstructor(FakeNode), writable: true, configurable: true });
    if (overrides.layoutWorker !== undefined) {
      globalServices().coordination.layoutWorker = overrides.layoutWorker;
    }
    Object.defineProperty(globalThis, "getComputedStyle", {
      value: (target: Element, _pseudo?: string | null): CSSStyleDeclaration => {
        const values = target ? readComputedValues(asFakeElement(target)) : undefined;
        return values ? computedStyle(values) : computedStyle();
      },
      writable: true,
      configurable: true,
    });
    return fn();
  } finally {
    globalServices().coordination.layoutWorker = savedTiqianLayoutWorkerInstance;
    restoreGlobals(saved);
  }
}

// The snapshot-session descriptor is derived inside the pipeline from the
// runtime options' snapshotFontSession id through the coordination replay
// registry; tests seed that registry slot directly. An empty table makes the
// session's callbacks report MissingServerShapingReplay, which the exact
// path treats as a font capability failure and retries through the browser
// fallback bridge.
function registerReplaySession(sessionId: string, record: ReplaySessionStub): VoidFunction {
  const registry = globalServices().coordination.fonts.replayRegistry;
  registry.sessions.set(sessionId, record as ReplaySessionRecord);
  return (): void => { registry.sessions.delete(sessionId); };
}

function registerEmptyReplaySession(sessionId: string): VoidFunction {
  return registerReplaySession(sessionId, { shapes: new Map(), metrics: new Map(), probe: null });
}

// Standard core-neutral seeding: one EnhancedElementContext for the element,
// resolved engine options on the context state, and an established runtime
// for the browser-fallback descriptor, exactly the driver order. The ledger
// resolver applies the snapshot gate (configured typography lowers the
// snapshot font session), so tests that need configured typography AND a
// conforming session together enter through the canonical re-entry verb,
// which skips the gate.
function seedContext(paragraph: FakeElement, optionsBag: Record<string, unknown>, { canonical = false }: SeedContextOptions = {}): EnhancedElementContext {
  const element = asElement(paragraph);
  const context = createEnhanceContext(element);
  const resolved = canonical
    ? context.optionsLedger.resolveEngineOptionsFromCanonical(element, optionsFromJs(optionsBag))
    : context.optionsLedger.resolveEngineOptions(element, optionsBag);
  context.contextState.setRuntimeOptions(resolved);
  context.typography.establishRuntime(element, resolved);
  return context;
}

// Paragraph host element on the fixture fake-DOM base: a measurable P whose
// children survive the raw-DOM takeover and whose innerHTML carries the
// renderer output.
function makeParagraphElement(options: MakeParagraphOptions = {}): FakeElement {
  const element = new FakeElement("p");
  element.width = options.width ?? 320;
  element.ownerDocument = globalThis.document;
  for (const [name, value] of Object.entries(options.attributes ?? {})) {
    element.setAttribute(name, value);
  }
  for (const child of options.childNodes ?? [new FakeText("hello world")]) {
    element.appendChild(child);
  }
  return element;
}

// A latin STRONG with strongAsEmphasisMarks lowers into a sourceSpan carrying
// a non-null cjkStrongBaseWeight and no Emphasis decoration.
function strongChild(text: string): FakeElement {
  const element = new FakeElement("strong");
  element.appendChild(new FakeText(text));
  writeComputedValues(element, { display: "inline", "font-weight": "normal" });
  return element;
}

test("strong emphasis classifies contextual marks against the complete paragraph", () => {
  withEnv(() => {
    const children = [strongChild("A"), strongChild("——"), strongChild("B")];
    for (const child of children) {
      writeComputedValues(child, { display: "inline", "font-weight": "700" });
    }
    const paragraph = makeParagraphElement({
      childNodes: children,
    });
    const result = lowerMarkdown(
      asElement(paragraph),
      { strongAsEmphasisMarks: true, locale: "zh-Hans" },
      { classifyRole: classifyFontRole, classifyRoles: classifyFontRoles },
    );

    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.lowered.text, "A——B");
    assert.deepEqual(result.lowered.decorations, []);
    assert.deepEqual(
      result.lowered.spans.map(function (span) { return [span.start, span.end, span.style.fontWeight]; }),
      [[0, 1, 700], [1, 3, 700], [3, 4, 700]],
    );
  });
});

// A block-level child fails lowering with UnsupportedInlineFormattingContext.
function blockChild(tagName: string, text: string): FakeElement {
  const element = new FakeElement(tagName);
  element.appendChild(new FakeText(text));
  writeComputedValues(element, { display: "block" });
  return element;
}

// A static inline object child: the geometry probe measures it against the
// fake document's probe baseline.
function inlineObjectSpan(width: number, height: number): FakeElement {
  const element = new FakeElement("span");
  element.setAttribute("data-tiqian-static-inline-object", "");
  element.appendChild(new FakeText("obj"));
  element.width = width;
  element.height = height;
  element.top = 10;
  writeComputedValues(element, { display: "inline-block" });
  return element;
}

// The minimal schema-conforming worker plan: the renderer accepts it and
// renders no lines, so the worker commit path runs without line geometry.
const EMPTY_PLAN_JSON = JSON.stringify({
  schema: SNAPSHOT_SCHEMA,
  layoutRevision: LAYOUT_REVISION,
  height: 0,
  lines: [],
});

test("1. Direct happy path: lowering ok, rawDom record captures the original shell, prepare ready, commit success", () => {
  withEnv(() => {
    const paragraph = makeParagraphElement({
      attributes: {
        style: "color: blue;",
        "data-tq-rendered": "false",
        "data-tq-host-inline-size": "300px",
      },
    });
    paragraph.style.setProperty("position", "relative");
    paragraph.style.setProperty("inline-size", "300px");
    paragraph.style.setProperty("font-size", "19px");

    const context = seedContext(paragraph, { fontSize: 19 });

    processParagraph(context, asElement(paragraph));

    // The raw-DOM record captured the original shell values begin received.
    const record = context.rawDomParagraphs.get(asElement(paragraph));
    assert.ok(record);
    assert.equal(record.originalRenderedAttribute, "false");
    assert.equal(record.originalStyleAttribute, "color: blue;");
    assert.equal(record.originalHostInlineSizeAttribute, "300px");
    assert.equal(record.originalPosition, "relative");
    assert.equal(record.originalInlineSize, "300px");
    assert.equal(record.originalFontSize, "19px");
    // Take moved the original children into the backup fragment and commit
    // published it; the host now carries the rendered replay.
    assert.ok(record.originalContent);
    assert.ok(record.fragment);
    assert.equal(record.originalContent!.textContent, "hello world");
    assert.ok(paragraph.textContent!.includes("hello world"));

    assert.equal(paragraph.getAttribute("data-tq-rendered"), "true");
    assert.equal(paragraph.getAttribute("data-tq-runtime-render-font"), "true");

    assert.equal(context.contextState.paragraphs.length, 1);
    const item = context.contextState.paragraphs[0];
    assert.equal(item.source, paragraph);
    // The real direct commit records the effective line measure, not a canned
    // 300.
    assert.equal(item.lastMeasure, effectiveLineMeasure(320, 19));
    assert.equal(context.diagnosis.issues.length, 0);
  });
});

test("2. Worker happy path: worker request built, layout worker take returns a plan, worker commit commits it", () => {
  const takeCalls: WorkerTakeCall[] = [];
  const layoutWorker: TiqianLayoutWorkerInstance = {
    version: 1,
    semanticReplayRevision: 1,
    take: (element: Element | null | undefined, sessionKey: string, requestText: string): string | null => {
      takeCalls.push({ element: asFakeElement(element!), sessionKey, request: requestText });
      return JSON.stringify({ plan: EMPTY_PLAN_JSON });
    },
    issue: (): string | null => null,
    release: (_sessionKey?: string): boolean => true,
  };
  withEnv(() => {
    const objSpan = inlineObjectSpan(42, 20);
    // Children: latin strong (sourceSpan with cjkStrongBaseWeight), a space,
    // then the opaque inline object (domInlineObject). No Emphasis
    // decoration, so the paragraph stays Worker-eligible.
    const paragraph = makeParagraphElement({
      childNodes: [strongChild("hello"), new FakeText(" "), objSpan],
    });
    writeComputedValues(paragraph, { "font-weight": "normal" });

    // Configured typography and the conforming session coexist through the
    // canonical re-entry verb, which skips the snapshot gate.
    const context = seedContext(paragraph, {
      fontSize: 19,
      strongAsEmphasisMarks: true,
      snapshotFontSession: { status: "conforming", sessionId: "session-1" },
    }, { canonical: true });

    processParagraph(context, asElement(paragraph));

    // The worker request was built from the lowered paragraph and sent with
    // the conforming session key; the opaque inline object lowers to the
    // object replacement character.
    assert.equal(takeCalls.length, 1);
    assert.equal(takeCalls[0].element, paragraph);
    assert.equal(takeCalls[0].sessionKey, "session-1");
    assert.equal(JSON.parse(takeCalls[0].request).text, "hello \ufffc");

    // The worker commit set the prepared-dom and canonical attributes and
    // cached the effective line measure.
    assert.equal(paragraph.getAttribute("data-tq-snapshot-prepared-dom"), "true");
    assert.equal(paragraph.getAttribute("data-tq-canonical-source"), "true");
    assert.equal(paragraph.getAttribute("lang"), "zh-Hans");

    assert.equal(context.contextState.paragraphs.length, 1);
    assert.equal(context.contextState.paragraphs[0].lastMeasure, effectiveLineMeasure(320, 19));
    assert.equal(context.diagnosis.issues.length, 0);
  }, { layoutWorker, document: makeFakeDocument(30) });
});

test("3. Lowering throw -> DomLoweringFailure reported, nothing after it runs (rawDom never registered)", () => {
  const throwError = new Error("lowering syntax error");
  withEnv(() => {
    const paragraph = makeParagraphElement();
    const context = seedContext(paragraph, { fontSize: 19 });
    // Seeding resolved its options through the normal computed style; the
    // lowering probe is the first consumer that must see the throw.
    globalThis.getComputedStyle = (): CSSStyleDeclaration => {
      throw throwError;
    };
    processParagraph(context, asElement(paragraph));

    assert.equal(context.rawDomParagraphs.has(asElement(paragraph)), false);
    assert.equal(context.diagnosis.issues.length, 1);
    assert.equal(context.diagnosis.issues[0].name, "DomLoweringFailure");
    assert.equal(context.diagnosis.issues[0].detail, "lowering syntax error");
    assert.equal(context.diagnosis.issues[0].element, paragraph);
    assert.equal(context.diagnosis.issues[0].reportToConsole, true);
    // The lifecycle marker was written onto the paragraph element.
    assert.equal(paragraph.getAttribute("data-tiqian-capability-issue"), "DomLoweringFailure");
  });
});

test("4. Lowering ok false with an issue -> that issue reported", () => {
  withEnv(() => {
    const paragraph = makeParagraphElement({
      childNodes: [blockChild("div", "blocked")],
    });
    const context = seedContext(paragraph, { fontSize: 19 });
    processParagraph(context, asElement(paragraph));

    assert.equal(context.rawDomParagraphs.has(asElement(paragraph)), false);
    assert.equal(context.diagnosis.issues.length, 1);
    assert.equal(context.diagnosis.issues[0].name, "UnsupportedInlineFormattingContext");
    assert.equal(context.diagnosis.issues[0].detail, "div:block");
    assert.equal(context.diagnosis.issues[0].element, paragraph);
    assert.equal(context.diagnosis.issues[0].reportToConsole, true);
    // The lifecycle marker was written onto the paragraph element.
    assert.equal(paragraph.getAttribute("data-tiqian-capability-issue"), "UnsupportedInlineFormattingContext");
  });
});

test("6. Snapshot worker gate: requireSnapshotLayoutWorker true, plan null, rich fallback not applicable -> style attribute restored, SnapshotLayoutWorkerPlanUnavailable", () => {
  const layoutWorker: TiqianLayoutWorkerInstance = {
    version: 1,
    semanticReplayRevision: 1,
    take: (): null => null,
    issue: (): string => "No worker available in this context",
    release: (_sessionKey?: string): boolean => true,
  };
  withEnv(() => {
    const paragraph = makeParagraphElement({
      attributes: { style: "margin: 10px;" },
    });
    const context = seedContext(paragraph, {
      requireSnapshotLayoutWorker: true,
      snapshotFontSession: { status: "conforming", sessionId: "session-1" },
    });
    processParagraph(context, asElement(paragraph));

    assert.equal(paragraph.getAttribute("style"), "margin: 10px;");
    // Begin recorded the shell but the gate tripped before the takeover.
    const record = context.rawDomParagraphs.get(asElement(paragraph));
    assert.ok(record);
    assert.equal(record.originalContent, null);
    assert.equal(context.diagnosis.issues.length, 1);
    assert.equal(context.diagnosis.issues[0].name, "SnapshotLayoutWorkerPlanUnavailable");
    assert.equal(context.diagnosis.issues[0].detail, "No worker available in this context");
    assert.equal(context.diagnosis.issues[0].element, paragraph);
    assert.equal(context.diagnosis.issues[0].reportToConsole, true);
    // The lifecycle marker was written onto the paragraph element.
    assert.equal(paragraph.getAttribute("data-tiqian-capability-issue"), "SnapshotLayoutWorkerPlanUnavailable");
  }, { layoutWorker });
});

test("7. canUseRichBrowserFallback: rich lowered plus a capability-failure worker issue -> gate NOT taken, processing continues", () => {
  const layoutWorker: TiqianLayoutWorkerInstance = {
    version: 1,
    semanticReplayRevision: 1,
    take: (): null => null,
    issue: (): string => "MissingServerShapingReplay for CodeFont",
    release: (_sessionKey?: string): boolean => true,
  };
  // The registered replay session stays empty, so the exact snapshot-session
  // layout misses its shaping supply and retries through the browser
  // fallback bridge.
  const unregister = registerEmptyReplaySession("session-1");
  try {
    withEnv(() => {
      // The opaque inline object makes the lowered paragraph rich without
      // adding live semantic sources, so the direct commit stays on the
      // inline-object branch.
      const paragraph = makeParagraphElement({
        childNodes: [new FakeText("hello "), inlineObjectSpan(42, 20)],
      });
      const context = seedContext(paragraph, {
        requireSnapshotLayoutWorker: true,
        snapshotFontSession: { status: "conforming", sessionId: "session-1" },
      });

      processParagraph(context, asElement(paragraph));

      // The rich fallback bypassed the worker gate: the takeover ran and the
      // direct path committed.
      const record = context.rawDomParagraphs.get(asElement(paragraph));
      assert.ok(record);
      assert.ok(record.originalContent);
      assert.equal(context.contextState.paragraphs.length, 1);
      assert.equal(context.diagnosis.issues.length, 0);
    }, { layoutWorker, document: makeFakeDocument(30) });
  } finally {
    unregister();
  }
});

test("9. Dispatch throw -> WebEnhancementFailure, rawDom restored", () => {
  const backend = installThrowingFontBackend(new Error("unexpected engine crash"));
  // The throwing backend answers the registered session's shaping lookups,
  // so the snapshot-session descriptor derived from the runtime options
  // throws exactly like the old injected session did.
  const shapesStub: ReplayTableLookup = { get: () => { backend.shape({} as never); return 0 as never; } };
  const metricsStub: ReplayTableLookup = { get: () => { backend.resolve({} as never); return 0 as never; } };
  const unregister = registerReplaySession("session-throw", {
    shapes: shapesStub as ReplayTable,
    metrics: metricsStub as ReplayTable,
    probe: null,
  });
  try {
    withEnv(() => {
      const paragraph = makeParagraphElement();
      const context = seedContext(paragraph, {
        fontSize: 19,
        snapshotFontSession: { status: "conforming", sessionId: "session-throw" },
      }, { canonical: true });

      processParagraph(context, asElement(paragraph));

      // The restore returned the original children and shell to the host.
      assert.equal(paragraph.textContent, "hello world");
      assert.equal(paragraph.getAttribute("data-tq-rendered"), null);
      assert.equal(context.contextState.paragraphs.length, 0);
      assert.equal(context.diagnosis.issues.length, 1);
      assert.equal(context.diagnosis.issues[0].name, "WebEnhancementFailure");
      assert.equal(context.diagnosis.issues[0].detail, "unexpected engine crash");
      // The lifecycle marker was written onto the paragraph element.
      assert.equal(paragraph.getAttribute("data-tiqian-capability-issue"), "WebEnhancementFailure");
    });
  } finally {
    backend.uninstall();
    unregister();
  }
});

test("10. preparedDomEnabled gate dissolved (2026-08-27 core-neutral wave): without a snapshotFontSession option the worker channel is skipped and the direct path commits", () => {
  const takeCalls: WorkerTakeCall[] = [];
  const layoutWorker: TiqianLayoutWorkerInstance = {
    version: 1,
    semanticReplayRevision: 1,
    take: (element: Element | null | undefined, sessionKey: string, requestText: string): null => {
      takeCalls.push({ element: asFakeElement(element!), sessionKey, request: requestText });
      return null;
    },
    issue: (): null => null,
    release: (_sessionKey?: string): boolean => true,
  };
  withEnv(() => {
    const paragraph = makeParagraphElement();
    const context = seedContext(paragraph, { fontSize: 19 });

    processParagraph(context, asElement(paragraph));

    // The preparedDomEnabled flag was dissolved: the snapshotFontSession
    // option's presence alone gates the worker channel. Runtime options
    // without one never reach an installed worker, and the direct path
    // commits.
    assert.equal(takeCalls.length, 0);
    assert.equal(context.contextState.paragraphs.length, 1);
    assert.equal(context.diagnosis.issues.length, 0);
  }, { layoutWorker });
});

test("11. absent layout worker channel reads as no reusable plan and the direct path proceeds", () => {
  // The registered replay session stays empty, so after the absent worker
  // channel reads as no plan the snapshot-session layout misses its shaping
  // supply and completes through the browser fallback retry.
  const unregister = registerEmptyReplaySession("session-1");
  try {
    withEnv(() => {
      const paragraph = makeParagraphElement();
      const context = seedContext(paragraph, {
        fontSize: 19,
        snapshotFontSession: { status: "conforming", sessionId: "session-1" },
      }, { canonical: true });

      processParagraph(context, asElement(paragraph));

      // No layout worker channel is installed, so the direct path ran the
      // real prepare and commit.
      assert.ok(!globalServices().coordination.layoutWorker);
      assert.equal(context.contextState.paragraphs.length, 1);
      assert.equal(context.diagnosis.issues.length, 0);
    });
  } finally {
    unregister();
  }
});
