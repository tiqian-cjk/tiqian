// Fake host and S1-S4 element timeline shared by the element-driven
// timing-golden journeys (timing-golden.test.ts, decomposition report
// section 11) and the declared-face wake drive (element.test.ts, ADR 0053
// E2). The drive runs the real element.js module against a hand-grafted
// fake DOM under the shared fake clock (test-clock.ts) and records the
// JS-observable anchors: element and document event dispatches, dataset and
// attribute writes, ResizeObserver lifecycles, fetches, and per-phase
// paragraph state.
//
// Freeze boundary: frame counts and clock-derived durations are not stable
// across processes. element.js lazily imports its collaborators, those
// imports perform real I/O, and the interleaving between that I/O and the
// fake-clock pump varies per run; the number of frames an adoption chain
// needs therefore varies, and every duration the code computes from clock
// readings varies with it. The recorders below normalize those numbers away
// (durations dropped from event details, duration dataset values nulled) so
// the golden freezes structure: dispatch order, write order, keys, phases,
// and derived verdicts.
//
// ADR 0053 C1 removed the internal document-level event channel, and the R10
// core-neutral refactor dissolved the engine facade the former recording stub
// impersonated. The recording layer keeps the baseline recording CONTRACT, not
// the dead baseline mechanism:
//
//   * engineCalls stays empty. After R10 the old recording doubles were never
//     wired to anything (the drivers no longer receive an engine facade), so
//     the frozen fixture records [] for every journey and the token-transitions
//     verdicts freeze the "-engine-missing" vocabulary. The fixture is the
//     contract; the drive must reproduce it exactly.
//   * elementEvents records the completion detail at the PRE-FUNNEL point.
//     Baseline semantics: the fake dispatchEvent snapshotted event.detail
//     before invoking the single registered listener, and the session's ready
//     funnel ran as that listener — so the fixture freezes the detail the
//     driver dispatched, before the funnel's snapshot-count adjustment. The
//     core-neutral event flip moved the funnel ahead of the DOM dispatch
//     (eventChannel.notify runs the funnel, then synthesizes the CustomEvent),
//     so the equivalent pre-funnel observation point is the channel's
//     notify/dispatch entry: the drive wraps the captured context's
//     eventChannel.notify and eventChannel.dispatch and records the detail
//     they receive, then forwards. Events dispatched on the element from
//     outside the channel (test drives) carry no INTERNAL_DISPATCH_MARKER and
//     are recorded by the element.dispatchEvent override, exactly like the
//     baseline recorded every dispatch.
//
// Context capture: the element builds its context in a native private field
// (#context = createEnhanceContext(this)), unreachable from the drive. The
// single interception point is the Object.defineProperties(context, {...})
// call that publishes the context parts at the end of createEnhanceContext; a
// scoped Object.defineProperties wrapper, armed only around
// `new TiqianProseElement()`, matches that descriptor map and captures the
// context object. teardown() restores every wrapper so sibling journeys in the
// same process (worker messages, grant rounds) keep pristine services.

import {
  FakeDocument,
  FakeElement,
  FakeEvent,
  FakeFragment,
  FakeNode,
  FakeText,
  asElement,
  asFakeElement,
  asFakeNode,
  canonicalFixtureNode,
  fixtureComputedStyle,
  sha256,
  styleDeclaration,
} from "./snapshot-dom-fixtures.js";
import { FONT_REPLAY_REVISION, stableStringify } from "@tiqian/core/snapshot-schema.js";
import { writeBinaryTable } from "@tiqian/core/table-binary-encode";
import { INTERNAL_DISPATCH_MARKER } from "@tiqian/core/src/engine/enhance/event-channel.js";

import { probe } from "./runtime-host.js";

let activeEnginePhase = "";

const CONTEXT_DESCRIPTOR_MARKERS = ["contextState", "optionsLedger", "typography", "domWriteLayer"];

type ConstructFn<T> = () => T;
type FlushPendingFn = () => void;
type TeardownFn = () => void;
type RestoreFn = () => void;
type EventChannelSend = (kind: string, detail: unknown) => unknown;
type EventChannelWrapper = (original: EventChannelSend) => EventChannelSend;
type LifecycleCallback = () => void;
type FakeDispatchEvent = (event: FakeEvent) => boolean;

interface RecordingEngine {
  captureContextDuring<T>(construct: ConstructFn<T>): T;
  flushPending: FlushPendingFn;
  teardown: TeardownFn;
}

function installRecordingEngine(record: TimingGoldenRecord, initialPhase: string): RecordingEngine {
  activeEnginePhase = initialPhase;

  const restores: RestoreFn[] = [];
  const recordEvent = (type: string, detail: unknown): void => {
    record.elementEvents.push({
      phase: activeEnginePhase,
      type,
      detail: stableDetail(detail as Record<string, unknown>),
    });
  };

  // ---- Context part-method shims (installed once the context is captured) -
  const wrapCapturedContext = (context: Record<string, unknown>): void => {
    const wrapPart = (partName: string, key: string, wrapper: EventChannelWrapper): void => {
      const part = context[partName] as Record<string, unknown> | undefined;
      if (!part) return;
      const original = part[key] as EventChannelSend | undefined;
      if (typeof original !== "function") return;
      part[key] = wrapper(original);
      restores.push(() => { part[key] = original; });
    };
    // The pre-funnel recording point: notify runs the completion funnel after
    // the wrapper records the driver's detail; dispatch (the progressive error
    // events) is non-funnel and recorded the same way for a single recording
    // surface. Both wrappers forward the receiver: the channel methods read
    // their own state through this.
    wrapPart("eventChannel", "notify", (original) => function (this: unknown, kind: string, detail: unknown) {
      recordEvent(kind, detail);
      return original.call(this, kind, detail);
    });
    wrapPart("eventChannel", "dispatch", (original) => function (this: unknown, kind: string, detail: unknown) {
      recordEvent(kind, detail);
      return original.call(this, kind, detail);
    });
  };

  // ---- Context capture -----------------------------------------------------
  // createEnhanceContext publishes the parts with one Object.defineProperties
  // call; a scoped wrapper armed only around element construction matches the
  // descriptor map and captures the context. The private #context field that
  // holds it is otherwise unreachable.
  const realDefineProperties = Object.defineProperties;
  const captureContextDuring = <T>(construct: ConstructFn<T>): T => {
    let captured: Record<string, unknown> | null = null;
    const definePropertiesShim: typeof Object.defineProperties = function <TargetType>(target: TargetType, properties: PropertyDescriptorMap & ThisType<unknown>): TargetType {
      const result = realDefineProperties.call(Object, probe<Record<string, unknown>>(target), properties);
      if (captured === null && properties &&
          CONTEXT_DESCRIPTOR_MARKERS.every((key) =>
            Object.prototype.hasOwnProperty.call(properties, key))) {
        captured = probe<Record<string, unknown>>(target);
      }
      return probe<TargetType>(result);
    };
    Object.defineProperties = definePropertiesShim;
    try {
      return construct();
    } finally {
      Object.defineProperties = realDefineProperties;
      if (captured) wrapCapturedContext(captured);
    }
  };

  return {
    captureContextDuring,
    // Baseline phase-boundary hook; the empty engineCalls contract needs no
    // flushing, but the journeys keep the call for the frozen drive shape.
    flushPending() {},
    teardown() {
      for (let i = restores.length - 1; i >= 0; i -= 1) restores[i]();
      activeEnginePhase = "";
    },
  };
}

export const FRAME_STEP_MS = 16;

// Globals the drive replaces beyond the fake clock's own set; the journey
// wrapper preserves them so every journey starts from a pristine host.
export const ELEMENT_DRIVE_GLOBALS = [
  "document", "HTMLElement", "customElements", "getComputedStyle",
  "MutationObserver", "window", "CustomEvent", "ResizeObserver",
  "TiqianWeb", "fetch", "IntersectionObserver",
];

const typography = {
  fontFamilies: ["Fixture CJK"],
  fontSizePx: 18,
  lineHeightPx: 27,
  locale: "zh-Hans",
  fontWeight: 400,
  italic: false,
  firstLineIndentIc: 0,
  lineLengthGridEnabled: true,
  letterSpacingPx: 0,
  fontFeatureSettings: "normal",
  fontVariationSettings: "normal",
  fontVariantNumeric: "normal",
};
const probeFeatures: string[] = [];
const probeEvidence = {
  text: "中国",
  advancePx: 36,
  fontSizePx: 18,
  fontWeight: 400,
  italic: false,
  script: "Hani",
  language: "zh-Hans",
  features: probeFeatures,
};
const weightRange: [number, number] = [400, 400];
const emptyAxes: Record<string, unknown> = {};
const evidence = {
  family: "Fixture CJK",
  style: "normal",
  weight: weightRange,
  unicodeRange: "U+4E00-9FFF",
  publicUrl: "/assets/fixture-deadbeef.woff2",
  sourceSha256: "a".repeat(64),
  sfntSha256: "b".repeat(64),
  faceIndex: 0,
  sourceOrder: 0,
  axes: emptyAxes,
  localNames: ["Fixture CJK", "FixtureCJK"],
  coverageText: "中国",
};

interface WorldBuildResult {
  documentObject: FakeDocument;
  tableBytesByUrl: Map<string, Uint8Array>;
  fetchCalls: string[];
}

function buildWorld(): WorldBuildResult {
  const tableBytesByUrl = new Map<string, Uint8Array>();
  const fetchCalls: string[] = [];
  const bodyEl = new FakeElement("body");
  const headEl = new FakeElement("head");
  const docEl = new FakeElement("html");
  const emptyFonts: unknown[] = [{}];
  const rawDoc = {
    baseURI: "https://example.test/post/",
    elements: new Map(),
    styleSheets: [],
    listeners: new Map(),
    fonts: {
      load: async () => emptyFonts,
      addEventListener() {},
      removeEventListener() {},
    },
    createDocumentFragment: () => new FakeFragment(),
    createElement(tagName: string) {
      const element = new FakeElement(tagName);
      element.ownerDocument = documentObject;
      element._fixtureProbeWidth = 36;
      return element;
    },
    createRange() {
      let selectedNode: FakeNode | null = null;
      return {
        selectNodeContents(node: FakeNode) { selectedNode = node; },
        getBoundingClientRect() { return { width: 36 }; },
      };
    },
    getElementById(id: string) { return (documentObject.elements.get(id) as FakeElement | undefined) ?? null; },
    querySelector() { return null; },
    querySelectorAll() { return []; },
    addEventListener() {},
    removeEventListener() {},
    dispatchEvent(event: FakeEvent) {
      const listener = documentObject.listeners.get(event.type);
      if (listener) probe<(event: FakeEvent) => void>(listener)(event);
      return true;
    },
    body: bodyEl,
    head: headEl,
    documentElement: docEl,
  };
  const documentObject: FakeDocument = probe<FakeDocument>(rawDoc);
  bodyEl.ownerDocument = documentObject;
  headEl.ownerDocument = documentObject;
  docEl.ownerDocument = documentObject;
  docEl.width = 1200;
  docEl.height = 800;
  docEl.clientWidth = 1200;
  docEl.clientHeight = 800;

  const realFetch = globalThis.fetch;
  (globalThis as { fetch: typeof globalThis.fetch }).fetch = async function (url: string | URL, init?: RequestInit) {
    fetchCalls.push(String(url));
    const bytes = tableBytesByUrl.get(String(url));
    if (bytes != null) return probe<Response>({ ok: true, arrayBuffer: async () => bytes });
    return realFetch.call(globalThis, url, init);
  } as typeof globalThis.fetch;

  return { documentObject, tableBytesByUrl, fetchCalls };
}

interface BuildSnapshotOptions {
  fontFaceFamily?: string;
  fontFaceSrc?: string;
}

interface BuildSnapshotResult {
  root: FakeElement;
  paragraph: FakeElement;
  originalText: FakeText;
}

function buildSnapshot(
  world: WorldBuildResult,
  options: BuildSnapshotOptions = {}
): BuildSnapshotResult {
  const { documentObject, tableBytesByUrl } = world;
  const { fontFaceFamily = "\"Fixture CJK\"", fontFaceSrc = "url(\"/assets/fixture-deadbeef.woff2\")" } = options;
  const root = documentObject.createElement("tiqian-prose");
  root.setAttribute("snapshot-ref", "tq-page");
  const paragraph = documentObject.createElement("p");
  paragraph.setAttribute("data-tq-snapshot-key", "p-1");
  paragraph.width = 360;
  paragraph.height = 27;
  paragraph.innerText = "中国";
  const originalText = new FakeText("中国");
  paragraph.appendChild(originalText);
  root.appendChild(paragraph);

  const template = documentObject.createElement("template");
  probe<{ content: FakeFragment }>(template).content = new FakeFragment();
  const entry = documentObject.createElement("div");
  entry.setAttribute("data-tq-entry", "p-1");
  const marker = documentObject.createElement("span");
  marker.setAttribute("data-tq-geometry", "true");
  marker.setAttribute("data-tq-line-flow-width", "36");
  marker.setAttribute("data-tq-line-width", "36");
  marker.setAttribute("data-tq-line-top", "0");
  marker.setAttribute("data-tq-line-bottom", "27");
  marker.setAttribute("data-tq-line-baseline", "20");
  marker.setAttribute("data-tq-paragraph-height", "27");
  marker.left = 0;
  marker.top = 0;
  marker.height = 27;
  const rendered = documentObject.createElement("span");
  rendered.setAttribute("data-tq-advance", "36");
  rendered.setAttribute("data-tq-geometry", "true");
  rendered.setAttribute("data-tq-shaping-boundary", "current-segment");
  rendered.setAttribute("data-tq-x", "0");
  rendered.width = 36;
  rendered.left = 0;
  rendered.textContent = "中国";
  const sentinel = documentObject.createElement("span");
  sentinel.setAttribute("data-tq-geometry", "true");
  sentinel.setAttribute("data-tq-line-end-sentinel", "0");
  sentinel.left = 36;
  sentinel.top = 20;
  entry.append(marker, rendered, sentinel);

  const tableBytes = writeBinaryTable({
    replayStrings: [],
    metrics: [],
    probes: [probeEvidence],
    typographies: [{
      sha256: sha256(stableStringify(typography)),
      value: typography,
    }],
    faces: [{
      ...Object.fromEntries(Object.entries(evidence).filter(([key]) =>
        key !== "coverageText")),
    }],
    valueStyles: [],
    fontPreloads: ["/assets/fixture-deadbeef.woff2"],
    revisions: { backendRevision: "tiqian-shared-harfbuzz-v5", harfbuzzVersion: "fixture" },
  });
  const tableUrl = "https://tables.test/timing-golden-1.tiqtbl";
  tableBytesByUrl.set(tableUrl, tableBytes);
  root.setAttribute("tq-tables", tableUrl);
  const manifest = {
    schema: 2,
    tables: { snapshot: sha256(tableBytes) },
    layoutRevision: "tiqian-layout-v2",
    renderRevision: "prebroken-dom-v17",
    fontSourcePolicy: "host-compatible-stylesheet-v1",
    renderFontFamilies: ["Fixture CJK"],
    paragraphSelector: "p[data-tq-snapshot-key]",
    fontReplay: { revision: FONT_REPLAY_REVISION, encoding: "shared-strings-v1", shapes: [] },
    entries: [{
      key: "p-1",
      sourceSha256: sha256("中国"),
      typographyRef: 0,
      maxWidthPx: 360,
      fontFaceEvidence: [{ faceRef: 0, coverageText: "中国", probeRef: 0 }],
      renderArtifactSha256: sha256(stableStringify(entry.childNodes.map(canonicalFixtureNode))),
    }],
  };
  const script = documentObject.createElement("script");
  script.setAttribute("data-tq-snapshot-manifest", "");
  script.textContent = JSON.stringify(manifest);
  probe<{ content: FakeFragment }>(template).content.append(script, entry);
  documentObject.elements.set("tq-page", template);

  const fontFaceStyle = styleDeclaration({
    "font-family": fontFaceFamily,
    "font-style": "normal",
    "font-weight": "400",
    "font-display": "block",
    "unicode-range": "U+4E00-9FFF",
    src: fontFaceSrc,
  });
  const sheet = { href: "https://example.test/fonts.css" };
  documentObject.styleSheets.push({
    href: sheet.href,
    cssRules: [{ type: 5, style: fontFaceStyle, parentStyleSheet: sheet }],
  });
  return { root, paragraph, originalText };
}

// Event-detail keys whose values are frame-derived durations (see the freeze
// boundary note at the top of this file); dropped before the detail is frozen.
const FRAME_DERIVED_DETAIL_KEYS = new Set(["durationMs", "maxSliceMs"]);

// Stable JSON-safe view of an event detail: numbers, booleans, strings only,
// minus the frame-derived duration keys.
function stableDetail(detail: Record<string, unknown> | undefined): Record<string, string | number | boolean> {
  const out: Record<string, string | number | boolean> = {};
  for (const [key, value] of Object.entries(detail ?? {})) {
    if (FRAME_DERIVED_DETAIL_KEYS.has(key)) continue;
    if (typeof value === "number" && Number.isFinite(value)) out[key] = value;
    else if (typeof value === "boolean") out[key] = value;
    else if (typeof value === "string") out[key] = value;
  }
  return out;
}

interface CustomEventInitLike {
  detail?: unknown;
  bubbles?: boolean;
  composed?: boolean;
}

class FakeCustomEventClass {
  readonly type: string;
  readonly detail: unknown;
  readonly bubbles: boolean | undefined;
  readonly composed: boolean | undefined;

  constructor(type: string, init: CustomEventInitLike = {}) {
    this.type = type;
    this.detail = init.detail;
    this.bubbles = init.bubbles;
    this.composed = init.composed;
  }
}

// Registry of ResizeObserver instances for the cache-invalidation projection.
// The class is module-level because element.js grabs it from globalThis; the
// registry is reset at each drive start so a journey records only its own
// observer activity.
let nextObserverId = 0;
interface ObserverContentRect {
  width: number;
  height: number;
}
interface ObserverEntry {
  target: Element;
  contentRect: ObserverContentRect;
}
type ObserverCallback = (entries: ObserverEntry[]) => void;
interface ObserverLogEntry {
  op: string;
  target?: Element;
}
interface ObserverInstanceHolder {
  id: number;
  callback: ObserverCallback;
  log: ObserverLogEntry[];
  observed: Set<Element>;
}

const observerInstances: ObserverInstanceHolder[] = [];

class FakeResizeObserver {
  readonly id: number;
  readonly callback: ObserverCallback;
  readonly log: ObserverLogEntry[];
  readonly observed: Set<Element>;

  constructor(callback: ObserverCallback) {
    this.id = ++nextObserverId;
    this.callback = callback;
    this.log = [];
    this.observed = new Set();
    observerInstances.push(this);
  }
  observe(target: Element): void {
    this.log.push({ op: "observe", target });
    this.observed.add(target);
    const rect = asFakeElement(target).getBoundingClientRect();
    queueMicrotask(() => this.callback([{
      target,
      contentRect: { width: rect.width, height: rect.height },
    }]));
  }
  unobserve(target: Element): void {
    this.log.push({ op: "unobserve", target });
    this.observed.delete(target);
  }
  disconnect(): void {
    this.log.push({ op: "disconnect" });
    this.observed.clear();
  }
}

type SetPhaseFn = (phase: string) => void;
type PumpPredicateFn = () => boolean;
type PumpUntilFn = (predicate: PumpPredicateFn, cap?: number) => Promise<number>;
type PumpQuiescentFn = (cap?: number) => Promise<number>;
type WidthObserverFn = () => ObserverInstanceHolder | null;
type ParagraphStateFn = () => Record<string, unknown>;

interface ElementDriveResult {
  world: WorldBuildResult;
  record: TimingGoldenRecord;
  element: Element;
  paragraph: FakeElement;
  setPhase: SetPhaseFn;
  pumpUntil: PumpUntilFn;
  pumpQuiescent: PumpQuiescentFn;
  widthObserver: WidthObserverFn;
  paragraphState: ParagraphStateFn;
  engineTeardown: RecordingEngine;
}

type CustomElementsDefineFn = () => void;
type CustomElementsGetFn = () => undefined;

interface FakeCustomElementsRegistry {
  define: CustomElementsDefineFn;
  get: CustomElementsGetFn;
}

type GetComputedStyleFn = (element: Element, pseudo: string | null) => CSSStyleDeclaration;
type RequestAnimationFrameFn = (callback: FrameRequestCallback) => number;
type CancelAnimationFrameFn = (id: number) => void;
type FakeWindowEventListener = () => void;

interface FakeWindowLike {
  addEventListener: FakeWindowEventListener;
  removeEventListener: FakeWindowEventListener;
  innerHeight: number;
  getComputedStyle: GetComputedStyleFn;
}

// Drive the full S1-S4 element timeline and return the complete record:
// S1 connect + initial snapshot adoption, S2 width shrink past the snapshot
// table's only width, S3 mid-flight disconnect while the adoption chain is
// suspended, S4 reconnect at the original width.
// Shared element-drive setup: builds the fake world, grafts the real element
// onto the fixture root, installs every recorder, warms the lazy imports,
// and runs the S1 connect through "tiqian:ready". The timing-golden S1-S4
// journey and the declared-face wake drive both start from this state, so
// recorder semantics and the pump stay identical between them.
async function startElementDrive(
  clock: FakeClock,
  journeyKey: string,
  options: Record<string, unknown> = {}
): Promise<ElementDriveResult> {
  nextObserverId = 0;
  observerInstances.length = 0;

  const world = buildWorld();
  const { root, paragraph } = buildSnapshot(world, options);
  const record: TimingGoldenRecord = {
    engineCalls: [],
    elementEvents: [],
    documentEvents: [],
    datasetWrites: [],
    attributeWrites: [],
    fetchCalls: [],
    observerActivity: [],
    frameAdvanceCounts: {},
    paragraphStates: {},
  };
  let currentPhase = "s1-adopt";
  const engineTeardown = installRecordingEngine(record, currentPhase);

  class FakeHostElementClass extends FakeElement {
    constructor() { super("tiqian-prose"); }
  }
  probe<{ HTMLElement: typeof FakeElement }>(globalThis).HTMLElement = FakeHostElementClass;
  probe<{ Node: typeof FakeNode }>(globalThis).Node = FakeNode;
  probe<{ customElements: FakeCustomElementsRegistry }>(globalThis).customElements = { define() {}, get() { return undefined; } };
  probe<{ document: FakeDocument }>(globalThis).document = world.documentObject;
  let hostElement: Element | null = null;
  probe<{ getComputedStyle: GetComputedStyleFn }>(globalThis).getComputedStyle = (element: Element, pseudo: string | null) => {
    const values = fixtureComputedStyle(asFakeElement(element), pseudo,
      element === hostElement ? { "--tq-styles-ready": "1" } : {});
    const styleObj: CSSStyleDeclaration = probe<CSSStyleDeclaration>({ ...values, getPropertyValue: (name: string) => values[name] ?? "" });
    return styleObj;
  };
  probe<{ MutationObserver: typeof MutationObserver }>(globalThis).MutationObserver = probe<typeof MutationObserver>(class {
    observe() {}
    disconnect() {}
    takeRecords() { return []; }
  });
  probe<{ CustomEvent: typeof FakeCustomEventClass }>(globalThis).CustomEvent = FakeCustomEventClass;
  probe<{ ResizeObserver: typeof FakeResizeObserver }>(globalThis).ResizeObserver = FakeResizeObserver;
  probe<{ window: FakeWindowLike }>(globalThis).window = {
    addEventListener() {},
    removeEventListener() {},
    innerHeight: 800,
    getComputedStyle: (element: Element, pseudo: string | null) => probe<{ getComputedStyle: GetComputedStyleFn }>(globalThis).getComputedStyle(element, pseudo),
  };
  delete (globalThis as Record<string, unknown>).TiqianWeb;
  delete (globalThis as Record<string, unknown>).IntersectionObserver;

  // rAF accounting wrapper so we can detect frame-loop quiescence.
  const origRaf = probe<{ requestAnimationFrame: RequestAnimationFrameFn }>(globalThis).requestAnimationFrame;
  const origCancel = probe<{ cancelAnimationFrame: CancelAnimationFrameFn }>(globalThis).cancelAnimationFrame;
  const activeFrames = new Set<number>();
  probe<{ requestAnimationFrame: RequestAnimationFrameFn }>(globalThis).requestAnimationFrame = (callback: FrameRequestCallback) => {
    const id = origRaf((now: number) => {
      activeFrames.delete(id);
      callback(now);
    });
    activeFrames.add(id);
    return id;
  };
  probe<{ cancelAnimationFrame: CancelAnimationFrameFn }>(globalThis).cancelAnimationFrame = (id: number) => {
    activeFrames.delete(id);
    origCancel(id);
  };

  // The query string busts the module cache per journey: under the fake clock
  // a Date.now()-based string would be identical across journeys and the
  // second drive would silently reuse the first drive's module state.
  const module = await import(`../element.js?timing-golden=${journeyKey}`);
  // Capture the privately-held enhance context as it is published during
  // construction, then run the drive against the real context + shared pool.
  const element = engineTeardown.captureContextDuring(() => new module.TiqianProseElement()) as Element;
  hostElement = element;
  asFakeElement(element).attributes = root.attributes;
  asFakeElement(element).childNodes = root.childNodes;
  asFakeElement(element).ownerDocument = world.documentObject;
  asFakeNode(probe<Node>(paragraph)).parentNode = asFakeNode(element);
  asFakeElement(probe<Element>(paragraph)).parentElement = asFakeElement(element);
  asFakeElement(element).width = 360;
  asFakeElement(element).height = 27;
  probe<FakeElement & { isConnected?: boolean }>(asFakeElement(element)).isConnected = true;

  // Comma-aware querySelectorAll on the instance: the single-selector path
  // keeps FakeElement semantics, the multi-selector path walks the graft.
  const singleQuerySelectorAll = FakeElement.prototype.querySelectorAll;
  asFakeElement(element).querySelectorAll = (selector: string) => {
    const parts = String(selector).split(",").map((part) => part.trim());
    if (parts.length === 1) return singleQuerySelectorAll.call(asFakeNode(probe<Node>(element)), selector);
    const out: FakeElement[] = [];
    const visit = (node: FakeNode): void => {
      for (const child of node.childNodes) {
        if (child.nodeType === 1) {
          for (const part of parts) {
            if ((child as FakeElement).closest && (child as FakeElement).closest(part) === child) { out.push(child as FakeElement); break; }
          }
        }
        visit(child);
      }
    };
    visit(asFakeNode(element));
    return out;
  };

  const listeners = new Map<string, (event: FakeEvent) => void>();
  type FakeEventListener = (event: FakeEvent) => void;
  type FakeDispatchEvent = (event: FakeEvent) => boolean;
  type AddEventListenerFn = (name: string, listener: FakeEventListener) => void;
  type RemoveEventListenerFn = (name: string, listener: FakeEventListener) => void;

  interface FakeElementWithEvents extends FakeElement {
    addEventListener: AddEventListenerFn;
    removeEventListener: RemoveEventListenerFn;
    dispatchEvent: FakeDispatchEvent;
  }
  const el = probe<FakeElementWithEvents>(asFakeElement(element));
  el.addEventListener = (name: string, listener: FakeEventListener) => { listeners.set(name, listener); };
  el.removeEventListener = (name: string, listener: FakeEventListener) => {
    if (listeners.get(name) === listener) listeners.delete(name);
  };
  el.dispatchEvent = (event: FakeEvent) => {
    // Channel-originated completions carry the internal dispatch marker and are
    // recorded at the pre-funnel notify/dispatch point; record only the
    // externally dispatched events here, like the baseline recorded every
    // dispatch that reached the element.
    if (!probe<Record<string, unknown>>(event)[probe<string>(INTERNAL_DISPATCH_MARKER)]) {
      record.elementEvents.push({
        phase: currentPhase,
        type: event.type,
        detail: stableDetail(event.detail as Record<string, unknown>),
      });
    }
    listeners.get(event.type)?.(event);
    return true;
  };

  const realDocDispatch = world.documentObject.dispatchEvent.bind(world.documentObject);
  world.documentObject.dispatchEvent = (event: FakeEvent) => {
    record.documentEvents.push({ phase: currentPhase, type: event.type });
    return realDocDispatch(event);
  };

  const datasetTarget: Record<string, unknown> = {};
  const datasetWrites = record.datasetWrites;
  asFakeElement(element).dataset = new Proxy(datasetTarget, {
    set(_target: Record<string, unknown>, key: string, value: unknown): boolean {
      if (String(key).startsWith("tiqian")) {
        // Duration-valued dataset keys share the frame-count instability;
        // keep the write itself (key, order) and drop the number.
        const stableValue = String(key).endsWith("Ms") ? null : String(value);
        datasetWrites.push({ phase: currentPhase, op: "set", key: String(key), value: stableValue });
      }
      return Reflect.set(datasetTarget, key, value);
    },
    deleteProperty(_target: Record<string, unknown>, key: string): boolean {
      if (String(key).startsWith("tiqian")) {
        datasetWrites.push({ phase: currentPhase, op: "delete", key: String(key) });
      }
      return Reflect.deleteProperty(datasetTarget, key);
    },
  }) as Record<string, string>;

  const realSetAttribute = FakeElement.prototype.setAttribute;
  const realRemoveAttribute = FakeElement.prototype.removeAttribute;
  asFakeElement(element).setAttribute = (name: string, value: string) => {
    if (String(name).startsWith("data-tiqian-") || String(name).startsWith("data-tq-")) {
      record.attributeWrites.push({ phase: currentPhase, name: String(name), value: String(value) });
    }
    return realSetAttribute.call(asFakeNode(element), name, value);
  };
  asFakeElement(element).removeAttribute = (name: string) => {
    if (String(name).startsWith("data-tiqian-") || String(name).startsWith("data-tq-")) {
      record.attributeWrites.push({ phase: currentPhase, name: String(name), value: null });
    }
    return realRemoveAttribute.call(asFakeNode(element), name);
  };

  const paragraphState = () => ({
    rendered: paragraph.getAttribute("data-tq-rendered"),
    canonicalSource: paragraph.getAttribute("data-tq-canonical-source"),
    canonicalPlain: paragraph.getAttribute("data-tq-canonical-plain"),
    firstChildNodeType: paragraph.firstChild?.nodeType ?? null,
    firstChildText: paragraph.firstChild?.textContent ?? null,
  });

  const nextTick = async (): Promise<void> => new Promise<void>((resolve) => {
    setImmediate(resolve);
  });

  // The pump cap only guards against a hung drive; frame counts are excluded
  // from every golden projection, and node:test runs sibling files in
  // parallel, so a lazy-import compile can easily need more loop turns than
  // sixty setImmediate yields while the process is under load. A cap of a
  // few thousand turns keeps the hang guard without starving the import.
  const pumpUntil = async (predicate: PumpPredicateFn, cap = 2000): Promise<number> => {
    let frames = 0;
    while (frames < cap) {
      await nextTick();
      clock.advance(FRAME_STEP_MS);
      frames += 1;
      if (predicate()) break;
    }
    return frames;
  };

  const pumpQuiescent = async (cap = 2000): Promise<number> => {
    let frames = 0;
    let quietStreak = 0;
    while (frames < cap) {
      await nextTick();
      clock.advance(FRAME_STEP_MS);
      frames += 1;
      quietStreak = activeFrames.size === 0 ? quietStreak + 1 : 0;
      if (quietStreak >= 2) break;
    }
    return frames;
  };

  const widthObserver = () => {
    for (let i = observerInstances.length - 1; i >= 0; i -= 1) {
      if (observerInstances[i].observed.has(element)) return observerInstances[i];
    }
    return null;
  };

  // ---- S1: connect + initial snapshot adoption ----
  // Warm the dynamic imports element.js performs (worker-channel.js and the
  // browser-fonts module, both on the snapshot-session path) before the drive
  // starts. Cold, their disk reads race the fake-clock pump under parallel
  // test load and shift observer creation order per run; warm, the cache hits
  // keep the S1 tail deterministic. The warm imports run inside the journey's
  // fake-clock window, so any module top-level captures see the same doubles.
  await import("@tiqian/core/src/engine/web-worker/worker-channel.js");
  await import("@tiqian/core/src/measurement/browser-fonts.js");
  probe<FakeElement & { connectedCallback: LifecycleCallback }>(asFakeElement(element)).connectedCallback();
  record.frameAdvanceCounts.s1 = await pumpUntil(
    () => record.elementEvents.some((e) => e.type === "tiqian:ready" && e.phase === "s1-adopt"),
  );
  record.paragraphStates.s1 = paragraphState();

  const setPhase = (phase: string) => {
    engineTeardown.flushPending?.();
    currentPhase = phase;
    activeEnginePhase = phase;
  };

  return {
    world,
    record,
    element,
    paragraph,
    setPhase,
    pumpUntil,
    pumpQuiescent,
    widthObserver,
    paragraphState,
    engineTeardown,
  };
}

export interface TimingEngineCall {
  phase: string;
  method: string;
}

export interface TimingElementEvent {
  phase: string;
  type: string;
  detail: Record<string, string | number | boolean>;
}

export interface TimingDocumentEvent {
  phase: string;
  type: string;
}

export interface TimingDatasetWrite {
  phase: string;
  op: string;
  key: string;
  value?: string | null;
}

export interface TimingAttributeWrite {
  phase: string;
  name: string;
  value: string | null;
}

export interface TimingObserverOp {
  op: string;
  target: string;
}

export interface TimingObserverActivity {
  id: number;
  ops: TimingObserverOp[];
}

export interface TimingGoldenRecord {
  readonly engineCalls: TimingEngineCall[];
  readonly elementEvents: TimingElementEvent[];
  readonly documentEvents: TimingDocumentEvent[];
  readonly datasetWrites: TimingDatasetWrite[];
  readonly attributeWrites: TimingAttributeWrite[];
  readonly fetchCalls: string[];
  readonly observerActivity: TimingObserverActivity[];
  readonly frameAdvanceCounts: Record<string, number>;
  readonly paragraphStates: Record<string, Record<string, unknown>>;
  readonly declaredWake?: Record<string, unknown>;
}

export interface FakeClock {
  pendingTimerCount(): number;
  advance(ms: number): void;
}

export async function driveElementTimeline(
  clock: FakeClock,
  journeyKey: string,
  options: Record<string, unknown> = {}
): Promise<TimingGoldenRecord> {
  const drive = await startElementDrive(clock, journeyKey, options);
  const {
    record, element, paragraph, setPhase,
    pumpUntil, pumpQuiescent, widthObserver, paragraphState,
  } = drive;

  // ---- S2: width shrink to 340, RO delivery, commit pass ----
  setPhase("s2-resize");
  asFakeElement(element).width = 340;
  paragraph.width = 340;
  const observer = widthObserver();
  if (observer) {
    observer.callback([
      { target: element, contentRect: { width: 340, height: 27 } },
      { target: asElement(paragraph), contentRect: { width: 340, height: 27 } },
    ]);
  }
  record.frameAdvanceCounts.s2 = await pumpQuiescent();
  record.paragraphStates.s2 = paragraphState();

  // ---- S3: width 320, freeze the clock, disconnect ----
  setPhase("s3-midflight-disconnect");
  asFakeElement(element).width = 320;
  paragraph.width = 320;
  const observer3 = widthObserver();
  if (observer3) {
    observer3.callback([
      { target: element, contentRect: { width: 320, height: 27 } },
      { target: asElement(paragraph), contentRect: { width: 320, height: 27 } },
    ]);
  }
  await new Promise<void>((resolve) => { setImmediate(resolve); });
  probe<FakeElement & { isConnected?: boolean }>(asFakeElement(element)).isConnected = false;
  probe<FakeElement & { disconnectedCallback: LifecycleCallback }>(asFakeElement(element)).disconnectedCallback();
  await new Promise<void>((resolve) => { setImmediate(resolve); });
  record.frameAdvanceCounts.s3 = await pumpQuiescent();
  record.paragraphStates.s3 = paragraphState();

  // ---- S4: reconnect at max width ----
  setPhase("s4-reconnect");
  asFakeElement(element).width = 360;
  paragraph.width = 360;
  probe<FakeElement & { isConnected?: boolean }>(asFakeElement(element)).isConnected = true;
  probe<FakeElement & { connectedCallback: LifecycleCallback }>(asFakeElement(element)).connectedCallback();
  record.frameAdvanceCounts.s4 = await pumpUntil(
    () => record.elementEvents.some((e) => e.type === "tiqian:ready" && e.phase === "s4-reconnect"),
  );
  if (!record.elementEvents.some((e) => e.type === "tiqian:ready" && e.phase === "s4-reconnect")) {
    record.frameAdvanceCounts.s4 = await pumpQuiescent();
  }
  record.paragraphStates.s4 = paragraphState();

  // Observer activity projection (targets serialized by identity kind).
  const mappedObserverActivity: TimingObserverActivity[] = observerInstances.map((instance) => ({
    id: instance.id,
    ops: instance.log.map((entry) => ({
      op: entry.op,
      target: entry.target != null && entry.target === element ? "root" : entry.target === asElement(paragraph) ? "paragraph" : "other",
    })),
  }));
  probe<{ observerActivity: TimingObserverActivity[] }>(record).observerActivity = mappedObserverActivity;

  probe<{ fetchCalls: string[] }>(record).fetchCalls = drive.world.fetchCalls;
  drive.engineTeardown.teardown();

  return record;
}

// Declared-face wake drive (ADR 0053 E2): the real element settles through
// S1, then DeclaredFaceEvidence registrations wake it. The engine stub
// records every revalidate the wakes produce, so the assertions read the
// element's own forced-check path end to end: registry notify, source
// subscription, scheduleTypographyCheck(true) through rAF dedup, snapshot
// invalidation, and the enhance dispatch that follows. Declared sheets
// never enter the CSSOM the signature reads, so the wake must force past
// the signature comparison; a wake that only scheduled an unforced check
// would leave the phase with no engine calls at all.
export async function driveDeclaredFaceWakeTimeline(
  clock: FakeClock,
  journeyKey: string
): Promise<TimingGoldenRecord> {
  const drive = await startElementDrive(clock, journeyKey);
  const { record, element, setPhase, pumpQuiescent } = drive;

  const revalidateCallsIn = (phase: string) =>
    record.engineCalls.filter((call) => call.phase === phase);

  // Executed-check observable: every typography-check signature read walks
  // root "p, li". Counting those queries per phase shows whether a wake
  // reached a scheduled check even when the refresh decision dedups against
  // in-flight work and produces no engine call.
  const paragraphQueriesByPhase = new Map<string, number>();
  const realQuerySelectorAll = asFakeElement(element).querySelectorAll;
  let queryPhase = "pre-wake";
  asFakeElement(element).querySelectorAll = (selector: string) => {
    if (String(selector).includes("p") && String(selector).includes("li")) {
      paragraphQueriesByPhase.set(queryPhase, (paragraphQueriesByPhase.get(queryPhase) ?? 0) + 1);
    }
    return realQuerySelectorAll.call(element, selector);
  };

  const { declareTiqianFontFaces } = await import(
    "@tiqian/core/src/sampler/snapshot/declared-faces.js"
  );

  const setWakePhase = (phase: string) => {
    setPhase(phase);
    queryPhase = phase;
  };

  // ---- W1: two same-tick declarations merge into one revalidate ----
  setWakePhase("w1-declared-merge");
  const unregisterA = declareTiqianFontFaces(
    "@font-face { font-family: Declared Wake A; src: url('wake-a.woff2'); }",
    { baseUrl: "https://declared.test/wake-a.css" },
  );
  const unregisterB = declareTiqianFontFaces(
    "@font-face { font-family: Declared Wake B; src: url('wake-b.woff2'); }",
    { baseUrl: "https://declared.test/wake-b.css" },
  );
  record.frameAdvanceCounts.w1 = await pumpQuiescent();
  probe<{ declaredWake?: Record<string, unknown> }>(record).declaredWake = { w1RevalidateCalls: revalidateCallsIn("w1-declared-merge").length };

  // ---- W2: a later declaration revalidates again ----
  // The W1 wake opened a layout job; typography observation pauses until the
  // work finishes. The stub engine never runs the job to completion, so
  // deliver the completion event the real runtime dispatches on the root.
  // The ready listener accepts it (#acceptLayoutCompletion was armed by the
  // W1 dispatch), finishes the layout work and re-observes. W2's declare
  // then meets an idle, observed root, exactly like a later declaration in
  // production.
  setWakePhase("w2-job-complete");
  probe<FakeElement & { dispatchEvent: FakeDispatchEvent }>(asFakeElement(element)).dispatchEvent(probe<FakeEvent>(new FakeCustomEventClass("tiqian:relayout-ready", {
    bubbles: true,
    composed: true,
    detail: { enhancedCount: 1, issueCount: 0 },
  })));
  record.frameAdvanceCounts.w2JobComplete = await pumpQuiescent();

  setWakePhase("w2-declared-later");
  const unregisterC = declareTiqianFontFaces(
    "@font-face { font-family: Declared Wake C; src: url('wake-c.woff2'); }",
    { baseUrl: "https://declared.test/wake-c.css" },
  );
  record.frameAdvanceCounts.w2 = await pumpQuiescent();
  (record.declaredWake as Record<string, unknown>).w2RevalidateCalls = revalidateCallsIn("w2-declared-later").length;

  // ---- W3: a disabled element unsubscribes and stops waking ----
  setWakePhase("w3-disabled");
  asFakeElement(element).setAttribute("disabled", "");
  type AttributeChangedCallbackFn = (name: string, oldValue: string | null, newValue: string) => void;
  probe<FakeElement & { attributeChangedCallback: AttributeChangedCallbackFn }>(asFakeElement(element)).attributeChangedCallback("disabled", null, "");
  await pumpQuiescent();
  // Disabling itself reaches the engine (destroy, detach); snapshot the
  // record length after that settles so only wake-driven calls count.
  const engineCallsAtStop = record.engineCalls.length;
  const unregisterD = declareTiqianFontFaces(
    "@font-face { font-family: Declared Wake D; src: url('wake-d.woff2'); }",
    { baseUrl: "https://declared.test/wake-d.css" },
  );
  record.frameAdvanceCounts.w3 = await pumpQuiescent();
  (record.declaredWake as Record<string, unknown>).w3RevalidateCalls = record.engineCalls.length - engineCallsAtStop;
  (record.declaredWake as Record<string, unknown>).paragraphQueries = Object.fromEntries(paragraphQueriesByPhase);

  unregisterA();
  unregisterB();
  unregisterC();
  unregisterD();
  probe<FakeElement & { isConnected?: boolean }>(asFakeElement(element)).isConnected = false;
  probe<FakeElement & { disconnectedCallback: LifecycleCallback }>(asFakeElement(element)).disconnectedCallback();
  await new Promise<void>((resolve) => { setImmediate(resolve); });

  probe<{ fetchCalls: string[] }>(record).fetchCalls = drive.world.fetchCalls;
  drive.engineTeardown.teardown();

  return record;
}