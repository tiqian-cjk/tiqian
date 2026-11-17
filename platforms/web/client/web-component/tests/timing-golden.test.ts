import { globalServices } from "@tiqian/core/src/services/global-services.js";
// Timing-anchor goldens for the web prose host refactor (ADR 0053 batch 0,
// decomposition report section 11). Every journey runs real module code under
// the shared fake clock (test-clock.ts) so dispatch order and record
// structure are deterministic. Wall-clock-derived numbers are deliberately
// not frozen: the element module's lazy imports do real I/O whose interleaving
// with the fake-clock pump varies per process, so frame counts and every
// duration derived from them vary too (timing-golden-host.ts normalizes them
// away at recording time). Golden updates go through
// TIQIAN_UPDATE_TIMING_GOLDEN=1; each diff is reviewed before the fixture is
// committed, mirroring the JVM LayoutDumpGoldenTest discipline.

import * as assert from "node:assert/strict";
import test from "node:test";
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import {
  preserveGlobals,
  restoreGlobals,
  installFakeClock,
  CLOCK_GLOBALS,
} from "./test-clock.js";
import {
  digest,
  faceEvidence,
  harness,
  manifestWithFaces,
} from "./browser-fonts-fixtures.js";
import {
  driveElementTimeline,
  ELEMENT_DRIVE_GLOBALS,
  FakeClock,
  FRAME_STEP_MS,
  TimingGoldenRecord,
} from "./timing-golden-host.js";
import { probe } from "./runtime-host.js";
import { workerLayoutRequestForRoot } from "@tiqian/core/src/engine/worker-request.js";
import { optionsFromJs } from "@tiqian/core/src/engine/lifecycle.js";
import { initializeGlobalServices } from "@tiqian/core/src/services/global-services.js";
import { CoordinationService } from "@tiqian/core/src/engine/coordination/coordination-service.js";
import type { createPrepareJob as CreatePrepareJob } from "@tiqian/core/src/engine/web-worker/worker-channel.js";
initializeGlobalServices();

const FIXTURE_PATH = fileURLToPath(new URL("./timing-golden.fixture.json", import.meta.url));
const GOLDEN_VERSION = 1;
const UPDATE_ENV = "TIQIAN_UPDATE_TIMING_GOLDEN";
const FRAME_TRACE_LIMIT = 600;
const SLOW_FRAME_STEP_MS = 60;
const SUSPEND_GAP_MS = 300;

// ---------------------------------------------------------------------------
// Golden store
// ---------------------------------------------------------------------------

function loadFixture() {
  try {
    const parsed = JSON.parse(readFileSync(FIXTURE_PATH, "utf8"));
    assert.equal(parsed.version, GOLDEN_VERSION, "fixture version");
    return parsed;
  } catch (error) {
    if ((error as Record<string, unknown>).code === "ENOENT") return { version: GOLDEN_VERSION, journeys: {} };
    throw error;
  }
}

function storeGolden(journeys: Record<string, unknown>) {
  const ordered: Record<string, unknown> = {};
  for (const id of Object.keys(journeys).sort()) ordered[id] = journeys[id];
  writeFileSync(
    FIXTURE_PATH,
    `${JSON.stringify({ version: GOLDEN_VERSION, journeys: ordered }, null, 2)}\n`,
  );
}

function firstDifferencePath(expected: unknown, actual: unknown, prefix = "$"): string | null {
  if (typeof expected !== typeof actual) return prefix;
  if (
    expected === null || actual === null ||
    typeof expected !== "object" || typeof actual !== "object"
  ) {
    return expected === actual ? null : prefix;
  }
  if (Array.isArray(expected) !== Array.isArray(actual)) return prefix;
  const expectedRecord = expected as Record<string, unknown>;
  const actualRecord = actual as Record<string, unknown>;
  const keys = new Set([...Object.keys(expectedRecord), ...Object.keys(actualRecord)]);
  for (const key of keys) {
    const path = `${prefix}.${key}`;
    if (!(key in expectedRecord) || !(key in actualRecord)) return path;
    const diff = firstDifferencePath(expectedRecord[key], actualRecord[key], path);
    if (diff !== null) return diff;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Element-journey projections (four record shapes from the shared drive)
// ---------------------------------------------------------------------------

function projectEventDispatch(full: TimingGoldenRecord) {
  // frameAdvanceCounts is intentionally excluded: the pump frame counts ride
  // the same lazy-import I/O interleaving (see timing-golden-host.ts), so
  // this journey freezes dispatch order and detail structure only. The
  // engineCalls stream is the successor observable of the retired internal
  // document events (ADR 0053 C1): the drive substitutes a recording engine
  // stub, and each host-to-engine call lands here in phase order.
  return {
    elementEvents: full.elementEvents,
    documentEvents: full.documentEvents,
    engineCalls: full.engineCalls,
  };
}

function projectDatasetFirstWrites(full: TimingGoldenRecord) {
  return {
    datasetWrites: full.datasetWrites,
    attributeWrites: full.attributeWrites,
  };
}

// Each verdict is derived from the recorded observables (events, dataset
// writes, paragraph state) so a behavior change moves the golden; nothing is
// hardcoded. Complementary branch names keep a suppressed dispatch or a
// missing write visible instead of silently absent.
function deriveTransitions(full: TimingGoldenRecord) {
  const elementEventsIn = (phase: string) => full.elementEvents.filter((e) => e.phase === phase);
  const has = (phase: string, type: string) => elementEventsIn(phase).some((e) => e.type === type);
  const docHas = (phase: string, type: string) =>
    full.documentEvents.some((e) => e.phase === phase && e.type === type);
  const engineHas = (phase: string, method: string) =>
    full.engineCalls.some((call) => call.phase === phase && call.method === method);
  const dsHas = (phase: string, key: string) =>
    full.datasetWrites.some((w) => w.phase === phase && w.key === key);
  const adopted = (phase: string) => full.paragraphStates[phase]?.firstChildNodeType === 1;
  const restored = (phase: string) => full.paragraphStates[phase]?.firstChildText === "中国";

  return [
    {
      phase: "s1-adopt",
      trigger: "connect",
      verdicts: [
        has("s1-adopt", "tiqian:ready") ? "ready-dispatched" : "ready-missing",
        adopted("s1") ? "paragraph-adopted" : "paragraph-not-adopted",
        dsHas("s1-adopt", "tiqianSnapshot") ? "dataset-snapshot-written" : "dataset-snapshot-missing",
      ],
    },
    {
      phase: "s2-resize",
      trigger: "width-change",
      verdicts: [
        has("s2-resize", "tiqian:relayout-ready")
          ? "relayout-event-dispatched"
          : "relayout-event-suppressed",
        restored("s2") ? "paragraph-restored" : "paragraph-not-restored",
        engineHas("s2-resize", "enhanceProgressively")
          ? "enhance-progressively-engine-called"
          : "enhance-progressively-engine-missing",
        dsHas("s2-resize", "tiqianSnapshotFontMiss")
          ? "snapshot-font-miss-recorded"
          : "snapshot-font-miss-missing",
      ],
    },
    {
      phase: "s3-midflight-disconnect",
      trigger: "midflight-disconnect",
      verdicts: [
        engineHas("s3-midflight-disconnect", "detach")
          ? "detach-engine-called"
          : "detach-engine-missing",
        elementEventsIn("s3-midflight-disconnect").length === 0
          ? "element-events-suppressed"
          : "element-events-present",
      ],
    },
    {
      phase: "s4-reconnect",
      trigger: "reconnect",
      verdicts: [
        engineHas("s4-reconnect", "destroy") ? "destroy-engine-called" : "destroy-engine-missing",
        has("s4-reconnect", "tiqian:ready") ? "ready-dispatched" : "ready-missing",
        adopted("s4") ? "paragraph-adopted" : "paragraph-not-adopted",
      ],
    },
  ];
}

// Token-transitions scope: state-machine verdicts derived from the dataset and
// event streams.
function projectTokenTransitions(full: TimingGoldenRecord) {
  return { transitions: deriveTransitions(full) };
}

// Cache-invalidation scope: the cancel paths that require an active
// Kotlin-runtime capture are unreachable in this no-runtime drive. Recorded
// here is the JS-reachable side only: geometry-change consequences (restore,
// observer teardown) and disconnect-driven release.
function projectCacheInvalidation(full: TimingGoldenRecord) {
  return {
    observerActivity: full.observerActivity,
    fetchCalls: full.fetchCalls,
    releaseVerdicts: {
      s2Restore: full.paragraphStates.s2?.firstChildText === "中国",
      s3Release: full.observerActivity.some((o) =>
        o.ops.some((op) => op.op === "disconnect")),
    },
  };
}

type JourneyProjector = (full: TimingGoldenRecord) => Record<string, unknown>;

const ELEMENT_JOURNEYS: Record<string, JourneyProjector> = {
  "event-dispatch": projectEventDispatch,
  "dataset-first-writes": projectDatasetFirstWrites,
  "token-transitions": projectTokenTransitions,
  "cache-invalidation": projectCacheInvalidation,
  "snapshot-font-contract-mismatch": projectDatasetFirstWrites,
};

// Each element journey runs the full S1-S4 drive in a pristine global
// environment and projects the shared record into its own frozen shape.
async function recordElementJourney(journeyKey: string) {
  const globals = preserveGlobals([...CLOCK_GLOBALS, ...ELEMENT_DRIVE_GLOBALS]);
  const clock = installFakeClock();
  try {
    const options = journeyKey === "snapshot-font-contract-mismatch"
      ? { fontFaceSrc: "url(\"/assets/mismatch-deadbeef.woff2\")" }
      : {};
    const full = await driveElementTimeline(clock, journeyKey, options);
    return ELEMENT_JOURNEYS[journeyKey](full);
  } finally {
    restoreGlobals(globals);
  }
}

// ---------------------------------------------------------------------------
// Journey: grant rounds (anchor class: GrantController vouchers per frame)
// ---------------------------------------------------------------------------

// The recording runtime wraps the slice protocol the coordinator drives. It
// answers from a pending-count map exactly like the fake runtime the
// coordinator suite uses, and records every voucher the coordinator hands
// out: root, job generation, Date-domain deadline, quota, the tier the grant
// addressed, the processed count returned, and the tier triple after the
// grant. The DeadlineGate terms are sampled at the quota boundary: the gate
// formula (quota reached OR Date-domain deadline passed) is part of the
// frozen contract even though the fake clock never trips the deadline inside
// a single frame. Every voucher also carries the admission class that issued it ("grant" for polled grants).
type ShouldStopFn = (n: number) => boolean;

interface SliceController {
  root: unknown;
  quota: number;
  admissionClass: string;
  generation: number;
  deadline: unknown;
  shouldStop: ShouldStopFn;
}

function recordingRuntime(pendingByRoot: Map<unknown, number[]>, grants: unknown[]) {
  return {
    hasJob: (root: unknown) => pendingByRoot.has(root),
    jobGeneration: (root: unknown) => (pendingByRoot.has(root) ? 1 : 0),
    pendingInTier: (root: unknown, tier: number) => (pendingByRoot.get(root) ?? [])[tier - 1],
    runSlice: (controller: SliceController, minTier: number) => {
      const tiers = pendingByRoot.get(controller.root) ?? [];
      const pendingBefore = [...tiers];
      let processed = 0;
      for (let tier = 1; tier <= minTier && processed < controller.quota; tier += 1) {
        while (tiers[tier - 1] > 0 && processed < controller.quota) {
          tiers[tier - 1] -= 1;
          processed += 1;
        }
      }
      // Conservation invariant of the voucher protocol: a slice moves items
      // from pending to processed and creates or drops nothing. The task-pool
      // unification slice must keep this true at every grant.
      const pendingBeforeSum = pendingBefore.reduce((sum, n) => sum + n, 0);
      const pendingAfterSum = tiers.reduce((sum, n) => sum + n, 0);
      assert.equal(
        pendingBeforeSum,
        processed + pendingAfterSum,
        "grant must conserve pending+processed",
      );
      grants.push({
        root: (controller.root as { name: string }).name,
        lane: controller.admissionClass,
        tier: minTier,
        generation: controller.generation,
        deadline: controller.deadline,
        quota: controller.quota,
        processed,
        pendingAfter: [...tiers],
        gateStopsAtQuota: controller.shouldStop(controller.quota),
        gateStopsPastQuota: controller.shouldStop(controller.quota + 1),
      });
      return processed;
    },
  };
}

// Two visible roots. Segment 1 anchors tier-ordered grants across roots;
// segment 2 anchors the adaptive quota on alpha (cold start, growth, ceiling,
// slow-frame halving, suspend-gap immunity, floor walk-down, recovery) while
// beta stays dry.
const GRANT_SCHEDULE = [
  [2, FRAME_STEP_MS],
  [3, FRAME_STEP_MS],
  [4, FRAME_STEP_MS],
  [5, FRAME_STEP_MS],
  [6, FRAME_STEP_MS],
  [7, FRAME_STEP_MS],
  [8, FRAME_STEP_MS],
  [8, FRAME_STEP_MS],
  [8, SLOW_FRAME_STEP_MS],
  [4, FRAME_STEP_MS],
  [5, FRAME_STEP_MS],
  [6, SUSPEND_GAP_MS],
  [6, SLOW_FRAME_STEP_MS],
  [3, SLOW_FRAME_STEP_MS],
  [1, SLOW_FRAME_STEP_MS],
  [1, SLOW_FRAME_STEP_MS],
  [1, FRAME_STEP_MS],
  [2, FRAME_STEP_MS],
];

type RegisterWorkerWithRuntimeFn = (
  session: number,
  element: HTMLElement,
  runtime: unknown,
) => void;

async function runGrantRoundsJourney(clock: FakeClock) {
  // The query string only busts the module cache so the journey gets a
  // pristine coordinator; the runtime shape is the element.js re-export of
  // the core class. Widening the specifier to string keeps tsc from trying
  // to resolve the query suffix as a file.
  const module = await import("../element.js?timing-golden=grants" as string) as {
    CoordinationService: typeof CoordinationService;
  };
  const Coordinator = module.CoordinationService;
  const coordinator = new Coordinator();
  const alpha = { name: "alpha" };
  const beta = { name: "beta" };
  const alphaSession = coordinator.register();
  const betaSession = coordinator.register();
  const pending = new Map([
    [alpha, [1, 0, 0]],
    [beta, [0, 2, 0]],
  ]);
  const grants: unknown[] = [];
  const runtime = recordingRuntime(pending, grants);
  // The third argument is a vestige of the pre-R10 wiring: registerWorker
  // takes (session, element) and grants flow through the coordinator's own
  // layoutJobPool, so the frozen golden records an empty grants stream on
  // purpose and the runtime is kept alive only for its pending map. The
  // method is bound because it reads private fields through this.
  const registerWorkerWithRuntime: RegisterWorkerWithRuntimeFn = probe<RegisterWorkerWithRuntimeFn>(coordinator.registerWorker.bind(coordinator));
  registerWorkerWithRuntime(alphaSession, probe<HTMLElement>(alpha), runtime);
  registerWorkerWithRuntime(betaSession, probe<HTMLElement>(beta), runtime);
  coordinator.setWorkerActive(alphaSession, true);
  coordinator.setWorkerActive(betaSession, true);

  // FrameTraceDiagnostics: opt in before the first frame so the ring records
  // one row per frame from the start.
  coordinator.traceConfig = { maxEntries: FRAME_TRACE_LIMIT };

  // Segment 1: tier-ordered grants across the two roots.
  coordinator.requestWorkerFrame(alphaSession);
  coordinator.requestWorkerFrame(betaSession);
  clock.advance(FRAME_STEP_MS);

  // Segment 2: adaptive quota schedule on alpha.
  for (const [alphaPending, stepMs] of GRANT_SCHEDULE) {
    pending.get(alpha)![0] = alphaPending;
    coordinator.requestWorkerFrame(alphaSession);
    clock.advance(stepMs);
  }

  return {
    grants,
    frameTrace: coordinator.frameTrace ?? [],
    finalPending: {
      alpha: pending.get(alpha),
      beta: pending.get(beta),
    },
  };
}

async function recordGrantRounds() {
  const globals = preserveGlobals(CLOCK_GLOBALS);
  const clock = installFakeClock();
  try {
    return await runGrantRoundsJourney(clock);
  } finally {
    restoreGlobals(globals);
  }
}

// ---------------------------------------------------------------------------
// Journey: worker messages (anchor class: init/layout/release order, bridge
// take/issue/release against the plan cache)
// ---------------------------------------------------------------------------

interface WorkerLayoutMessageRequest {
  text: string;
}

interface WorkerLayoutMessage {
  type: string;
  request?: WorkerLayoutMessageRequest;
  id: unknown;
}

// A Worker double that answers like layout-worker.js (canned plan keyed by the
// request text, error for the failure text) while recording every posted
// message in order. The reply rides a microtask, matching the real Worker's
// asynchronous postMessage.
function recordingWorker(messages: unknown[]) {
  return class RecordingWorker {
    listeners = new Map();

    addEventListener(type: string, listener: unknown) {
      this.listeners.set(type, listener);
    }

    postMessage(message: WorkerLayoutMessage) {
      messages.push(
        message.type === "layout"
          ? { type: message.type, text: message.request?.text }
          : { type: message.type },
      );
      queueMicrotask(() => this.listeners.get("message")?.({
        data: message.type === "layout"
          ? message.request?.text === "failure"
            ? { id: message.id, ok: false, error: "fixture replay miss" }
            : { id: message.id, ok: true, plan: { fixture: message.request?.text } }
          : { id: message.id, ok: true },
      }));
    }

    terminate() {}
  };
}

// The worker-messages journey attaches per-candidate computed values to the
// fake paragraph; the stub reads them back through this shape.
interface ComputedStyleSource {
  _computedValues?: Record<string, string>;
}

// Computed-style double for the worker-messages journey: zero padding and
// borders so the pure request builder measures the candidate's rect width,
// and empty getPropertyValue answers for the lowerer's style reads.
function journeyComputedStyle(values?: Record<string, string>): CSSStyleDeclaration {
  const base = {
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
  };
  const getPropertyValue = (name: string): string => {
    const key = String(name).toLowerCase();
    return Object.prototype.hasOwnProperty.call(values ?? {}, key)
      ? String(values?.[key] ?? "")
      : "";
  };
  const styleDeclarationObj: CSSStyleDeclaration = probe<CSSStyleDeclaration>({ ...base, getPropertyValue });
  return styleDeclarationObj;
}

// One root with three lowerable candidate paragraphs drives the full
// protocol: init then layout on the first prepare, layout-only on later
// prepares (the coordinator singleton survives module re-evaluation),
// plan-cache hits and misses through the bridge, the failed-request issue
// string, and release evicting the session-prefixed plans. R10: the prepare
// path builds requests through the pure workerLayoutRequestForRoot, so each
// candidate is a lowerable paragraph double (text-only children lower into
// a plain paragraph) and the take/issue ops reuse that candidate's
// serialized build; request text and geometry derive from the candidate.
type QuerySelectorAllElementsFn = () => Element[];

async function runWorkerMessagesJourney() {
  const bytes = new TextEncoder().encode("fixture-font-source");
  const state = harness(manifestWithFaces([[faceEvidence(digest(bytes))]]), { bytes });
  const handle = await state.loader.prepare(probe<HTMLElement>(state.root));

  const ROOT_SELECTOR = "tiqian-prose, [data-tiqian-root]";
  const lowerableParagraph = (text: string): Element => probe<Element>({
    tagName: "P",
    textContent: text,
    childNodes: [{ nodeType: 3, textContent: text }],
    getAttribute: () => null,
    setAttribute: () => {},
    removeAttribute: () => {},
    style: {
      setProperty: () => {},
      removeProperty: () => {},
      getPropertyValue: () => "",
      getPropertyPriority: () => "",
    },
    closest: (selector: string) => (selector === ROOT_SELECTOR ? state.root : null),
    querySelectorAll: () => [],
    querySelector: () => null,
    getBoundingClientRect: () => ({ width: 323, top: 0, bottom: 24 }),
    getClientRects: () => [],
    parentElement: null,
  });
  const candidates = {
    first: lowerableParagraph("first"),
    second: lowerableParagraph("second"),
    failure: lowerableParagraph("failure"),
  };
  let activeElement: Element = candidates.first;
  probe<{ querySelectorAll: QuerySelectorAllElementsFn }>(state.root).querySelectorAll = () => [activeElement];

  const prepareOptions = {
    paragraphSelector: ":is(p, li):not([data-tq-snapshot-key])",
    snapshotFontSession: {
      status: "conforming",
      sessionId: handle.id,
      detail: "test",
    },
  };
  const canonicalOptions = optionsFromJs(prepareOptions);
  const requestJson = () => {
    const built = workerLayoutRequestForRoot(probe<Element>(state.root), activeElement, canonicalOptions);
    return JSON.stringify({ ...built, semantics: [], renderInlineBoxes: [] });
  };

  const messages: unknown[] = [];
  const ops: unknown[] = [];
  const savedWorker = globalThis.Worker;
  const savedInnerHeight = globalThis.innerHeight;
  const savedBridge = globalServices().coordination.layoutWorker;
  const coordinatorKey = Symbol.for("@tiqian/web-component.layout-worker-coordinator.v1");
  const savedCoordinator = probe<Record<symbol, unknown>>(globalThis)[coordinatorKey];
  const savedComputedStyle = globalThis.getComputedStyle;
  const compactTake = (resultText: string | null) => {
    if (resultText === null) return null;
    const record = JSON.parse(resultText);
    return {
      plan: record.plan.fixture,
      semanticReplay: record.semanticReplay,
      semantics: record.semantics,
      inlineBoxes: record.inlineBoxes,
    };
  };

  try {
    delete probe<Record<symbol, unknown>>(globalThis)[coordinatorKey];
    delete probe<Record<string, unknown>>(globalServices().coordination).layoutWorker;
    globalThis.Worker = probe<typeof Worker>(recordingWorker(messages));
    globalThis.innerHeight = 800;
    globalThis.getComputedStyle = (target: unknown): CSSStyleDeclaration =>
      journeyComputedStyle((target as ComputedStyleSource | null | undefined)?._computedValues);

    // Same query-string cache-bust trick as the grants journey: a pristine
    // worker-channel module whose install step re-creates the bridge.
    const module = await import(
      "@tiqian/core/src/engine/web-worker/worker-channel.js?timing-golden=worker-messages" as string
    ) as { createPrepareJob: typeof CreatePrepareJob };
    const bridge = globalServices().coordination.layoutWorker!;
    const prepare = async () => {
      const job = await module.createPrepareJob(
        probe<HTMLElement>(state.root),
        handle,
        prepareOptions,
        () => true,
      );
      let prepared = 0;
      if (job) {
        while (!job.done) {
          job.step(() => false);
          await Promise.resolve();
        }
        prepared = await job.finished;
      }
      ops.push({ op: "prepare", text: (activeElement as { textContent: string }).textContent, prepared });
      return prepared;
    };
    ops.push({ op: "bridge", version: bridge.version, semanticReplayRevision: bridge.semanticReplayRevision });

    // First prepare initializes the session, then sends one layout message.
    await prepare();
    ops.push({ op: "take", text: "first", out: compactTake(bridge.take(activeElement, handle.id, requestJson())) });

    // Semantic-only changes replay the cached plan with the new semantics.
    const semanticChange = JSON.stringify({
      ...JSON.parse(requestJson()),
      semantics: [{ start: 0, end: 5, tagName: "a", attributes: [["href", "/latest"]] }],
      renderInlineBoxes: [{ start: 0, end: 5, inlineStart: 1, inlineEnd: 2 }],
    });
    ops.push({ op: "take-semantic", out: compactTake(bridge.take(activeElement, handle.id, semanticChange)) });

    // A measure change is a different plan key: miss.
    const builtMeasure = JSON.parse(requestJson()).maxWidthPx;
    const changedMeasure = JSON.stringify({ ...JSON.parse(requestJson()), maxWidthPx: builtMeasure - 1 });
    ops.push({ op: "take-miss", out: compactTake(bridge.take(activeElement, handle.id, changedMeasure)) });

    // A second prepare for a new text sends a layout message without a new init.
    activeElement = candidates.second;
    await prepare();
    ops.push({ op: "issue-clean", out: bridge.issue(activeElement, handle.id, requestJson()) });

    // A failed layout request reports nothing prepared; the issue string
    // survives in the plan cache for the runtime bridge to read.
    activeElement = candidates.failure;
    await prepare();
    ops.push({ op: "take-failed", out: compactTake(bridge.take(activeElement, handle.id, requestJson())) });
    ops.push({ op: "issue-failed", out: bridge.issue(activeElement, handle.id, requestJson()) });

    // Release evicts the session-prefixed plans and releases the worker
    // session; the previously cached plan no longer replays.
    ops.push({ op: "release", out: bridge.release(handle.id) });
    activeElement = candidates.first;
    ops.push({ op: "take-after-release", out: compactTake(bridge.take(activeElement, handle.id, requestJson())) });
    ops.push({ op: "release-again", out: bridge.release(handle.id) });

    return { messages, ops };
  } finally {
    if (savedWorker === undefined) delete (globalThis as Record<string, unknown>).Worker;
    else globalThis.Worker = savedWorker;
    if (savedInnerHeight === undefined) delete (globalThis as Record<string, unknown>).innerHeight;
    else (globalThis as Record<string, unknown>).innerHeight = savedInnerHeight;
    if (savedComputedStyle === undefined) delete (globalThis as Record<string, unknown>).getComputedStyle;
    else (globalThis as Record<string, unknown>).getComputedStyle = savedComputedStyle;
    if (savedBridge === undefined) {
      const coord = globalServices().coordination;
      delete probe<Record<string, unknown>>(coord).layoutWorker;
    } else {
      probe<Record<string, unknown>>(globalServices().coordination).layoutWorker = savedBridge;
    }
    if (savedCoordinator === undefined) delete probe<Record<symbol, unknown>>(globalThis)[coordinatorKey];
    else probe<Record<symbol, unknown>>(globalThis)[coordinatorKey] = savedCoordinator;
    state.loader.release(handle);
  }
}

async function recordWorkerMessages() {
  const globals = preserveGlobals(CLOCK_GLOBALS);
  const clock = installFakeClock();
  try {
    return await runWorkerMessagesJourney();
  } finally {
    restoreGlobals(globals);
  }
}

// ---------------------------------------------------------------------------
// Suite
// ---------------------------------------------------------------------------

type JourneyRunner = () => Promise<Record<string, unknown>>;

const JOURNEYS: Record<string, JourneyRunner> = {
  "grant-rounds": recordGrantRounds,
  "worker-messages": recordWorkerMessages,
  "event-dispatch": () => recordElementJourney("event-dispatch"),
  "dataset-first-writes": () => recordElementJourney("dataset-first-writes"),
  "token-transitions": () => recordElementJourney("token-transitions"),
  "cache-invalidation": () => recordElementJourney("cache-invalidation"),
  "snapshot-font-contract-mismatch": () => recordElementJourney("snapshot-font-contract-mismatch"),
};

test("timing goldens match the frozen fixture", async () => {
  const updating = process.env[UPDATE_ENV] === "1";
  const fixture = loadFixture();
  const journeys: Record<string, Record<string, unknown>> = {};
  let failed = false;
  for (const [id, run] of Object.entries(JOURNEYS)) {
    const recorded = await run();
    journeys[id] = recorded;
    if (updating) continue;
    const expected = fixture.journeys[id];
    if (expected === undefined) {
      console.error(`golden journey ${id} has no frozen record; rerun with ${UPDATE_ENV}=1`);
      failed = true;
      continue;
    }
    try {
      assert.deepStrictEqual(recorded, expected);
    } catch {
      const path = firstDifferencePath(expected, recorded);
      console.error(`golden journey ${id} diverges at ${path}`);
      console.error(`expected: ${JSON.stringify(expected)?.slice(0, 400)}`);
      console.error(`recorded: ${JSON.stringify(recorded)?.slice(0, 400)}`);
      failed = true;
    }
  }
  if (updating) {
    storeGolden(journeys);
    // Round-trip: the stored fixture must equal what was recorded.
    const stored = loadFixture();
    for (const [id, recorded] of Object.entries(journeys)) {
      assert.deepStrictEqual(stored.journeys[id], recorded);
    }
    return;
  }
  assert.equal(failed, false, "timing goldens diverged; review the diff before updating");
});