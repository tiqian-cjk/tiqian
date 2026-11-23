// Frame budget, task pool, and grants for attached roots (ADR 0053 batch 1;
// decomposition report section 7). Extracted verbatim from element.js.
// Replaces the former TiqianLayoutCoordinator (one object, one name).
//
// RootSessionKey: every registration structure is keyed by a monotonic root
// session id allocated by register(); the service never keys bookkeeping by
// a component instance. The one element value a worker slot keeps is a
// functional value — the grant rounds need it for viewport anchoring and as
// the root argument of the slot's layout job pool (ruling 3 keeps the
// element in the registerWorker signature).
import {
  captureViewportAnchor,
  compensateViewportAnchor,
  releaseNativeScrollAnchoring,
} from "./viewport-anchor.js";
import type { ViewportAnchor } from "./viewport-anchor.js";
import type { FontCoordinationState } from "./fonts.js";
import { createReplayRegistry } from "./fonts.js";
import type { MeasurementCoordinationState } from "./measurement.js";
import type { TraceConfig } from "../lifecycle.js";
import type { LayoutJobPool } from "../layout-job-pool.js";
import { createLayoutJobPool } from "../layout-job-pool.js";
import type {
  PageWorkerCoordinator,
  PlanRecord,
  PendingRequest,
  WorkerLayoutRequestBody,
  WorkerPlanLookup,
  WorkerResponseEnvelope,
} from "../web-worker/worker-channel.js";

export type LayoutWorkerTakeFn = (
  element: Element | null | undefined,
  sessionKey: string,
  requestText: string,
) => string | null;

export type LayoutWorkerIssueFn = (
  element: Element | null | undefined,
  sessionKey: string,
  requestText: string,
) => string | null;

export type LayoutWorkerReleaseFn = (sessionKey?: string) => boolean;

export interface TiqianLayoutWorkerInstance {
  readonly version: number;
  readonly semanticReplayRevision: number;
  lookup?(sessionKey: string, request: WorkerLayoutRequestBody): WorkerPlanLookup;
  take: LayoutWorkerTakeFn;
  issue: LayoutWorkerIssueFn;
  release: LayoutWorkerReleaseFn;
}

export type RootSessionId = number;
export type FrameTaskCallback = (now: number) => void;
export type GrantStopPredicate = (processedCount: number) => boolean;
export type ShouldYieldPredicate = () => boolean;
export type PrepareFinishedCallback = (job: PrepareJob) => void;
export type PrepareStepFn = (shouldYield: ShouldYieldPredicate) => number;
export type PrepareResolveFn = (count: number) => void;
export type SpentReporter = (consumedMs: number) => void;
export type FrameTraceRow = [number, number, number, number, number, number, number, number];

export interface CoordinatorTask {
  callback: FrameTaskCallback;
  session: RootSessionId | null;
  deferCount: number;
}

export interface DeferredTaskBucket {
  dueAt: number;
  tasks: Map<FrameTaskCallback, CoordinatorTask>;
}

export interface CoordinatorEntry {
  inViewport: boolean;
  area?: number;
  inlineSize?: number;
  visibleArea?: number;
  intersectionRatio?: number;
}

export interface CoordinatorUpdateOptions {
  inViewport?: boolean;
  area?: number;
  inlineSize?: number;
  visibleArea?: number;
  intersectionRatio?: number;
}

export interface GrantController {
  admissionClass: "grant" | "prepaint" | string;
  root: HTMLElement;
  generation: number;
  deadline: number;
  quota: number;
  shouldStop: GrantStopPredicate;
}

export interface CoordinatorWorkerSlot {
  session: RootSessionId;
  // WeakSlotElement: the slot must not be the reason a detached root object
  // stays reachable. Removed iframes and abandoned hosts do not reliably fire
  // disconnectedCallback, so the frame scan drops a slot whose target has
  // been collected (spec wc-s6 scope 5: no cleanup path may depend on that
  // callback).
  elementRef: WeakRef<HTMLElement>;
  active: boolean;
  pendingByTier: [number, number, number] | number[];
  generation: number;
  deferredUntil: number;
  deferCount: number;
  lastGrantFrame: number;
  quota: number;
}

export interface PrepareJob {
  readonly done: boolean;
  onFinished: PrepareFinishedCallback | null;
  finished: Promise<number>;
  step: PrepareStepFn;
}

export interface PrepareMember {
  job: PrepareJob;
  resolve: PrepareResolveFn | null;
}

export interface MainSliceAdmission {
  admissionClass: string;
  deadline: number;
  spent: SpentReporter;
}

// OffscreenDebounceGate window: an off-screen element's frame task waits this
// long after its last request before it runs. 200ms covers a full fast-drag
// sweep, and a paused off-screen element still gets its final layout soon
// after the window.
const OFFSCREEN_DEBOUNCE_MS = 200;

// GrantQuotaComplementsDeadline: a grant deadline truncates to whole
// milliseconds on the coarse clock, so a sub-millisecond remainder could
// admit many cheap paragraphs in one grant. The quota caps a grant by
// paragraph count.
//
// AdaptiveGrantQuota: the quota is per root and moves with measured frame
// cost. A commit's real bill lands after the slice returns: style, layout,
// and accessibility work for the committed paragraphs settle natively in the
// same task, so the deadline bounds only the JS part. The frame delta after
// a committing frame measures the whole bill one frame late. A slow frame
// (delta above the cadence by GRANT_QUOTA_SLOW_FRAME_RATIO) halves that
// root's quota, a healthy frame (delta under the cadence by
// GRANT_QUOTA_HEALTHY_FRAME_RATIO) raises it by one. Only roots that
// committed in the previous frame are judged, so one heavy root converges to
// small batches while its neighbours keep their headroom. Deltas outside
// [GRANT_QUOTA_MIN_FRAME_DELTA, GRANT_QUOTA_MAX_FRAME_DELTA] judge nobody:
// those gaps come from suspended tabs, not from layout work.
const WORKER_GRANT_QUOTA_MAX = 8;
const WORKER_GRANT_QUOTA_START = 2;
const WORKER_GRANT_QUOTA_FLOOR = 1;
const GRANT_QUOTA_SLOW_FRAME_RATIO = 1.5;
const GRANT_QUOTA_HEALTHY_FRAME_RATIO = 1.1;
const GRANT_QUOTA_MIN_FRAME_DELTA = 4.0;
const GRANT_QUOTA_MAX_FRAME_DELTA = 150.0;

// PrePaintResponsiveCommit allowance window: immediate grants issued from
// ResizeObserver callbacks share one allowance per rendering update. Two
// deliveries further apart than this cannot belong to the same update, so
// the allowance resets. 8ms sits between one 120Hz frame and one 60Hz frame.
const IMMEDIATE_GRANT_WINDOW_MS = 8;

// WorkerPolledScheduling: the coordinator owns every layout slice of an
// attached root. Each slot caches liveness plus the three tier counters the
// Kotlin facade reports, so a polled frame allocates nothing beyond the one
// scan it already runs; slot objects live from attach to disconnect.
function sumPendingUpTo(slot: CoordinatorWorkerSlot, tier: number): number {
  let total = 0;
  for (let t = 0; t < tier; t++) total += slot.pendingByTier[t];
  return total;
}

export class CoordinationService {
  layoutWorker?: TiqianLayoutWorkerInstance;
  traceConfig?: TraceConfig;
  frameTrace?: FrameTraceRow[];
  readonly layoutJobPool: LayoutJobPool = createLayoutJobPool();
  // PageWorkerCoordinator: the Kotlin-era page bridge registry consolidated
  // from worker-channel.ts module scope (S5-bc). The Symbol.for sharing
  // pattern is preserved through globalServices, which itself uses Symbol.for.
  channel: PageWorkerCoordinator = {
    plans: new Map(),
    worker: null,
    nextRequestId: 1,
    pending: new Map(),
    initializedSessions: new Set(),
  };
  #entries: Map<RootSessionId, CoordinatorEntry> = new Map();
  #nextRootSessionId: RootSessionId = 1;
  // FontCoordinationState and MeasurementCoordinationState: page-wide
  // font/measurement singletons the absorbed loader modules consult (see
  // fonts.ts / measurement.ts for why each is page-level single).
  readonly fonts: FontCoordinationState = {
    snapshotFontFallbackPromise: undefined,
    declaredFacesEntries: new Map(),
    declaredFacesChangeListeners: new Set(),
    browserFontLoader: undefined,
    replayRegistry: createReplayRegistry(),
  };
  readonly measurement: MeasurementCoordinationState = {
    measurementCache: new Map(),
    degenerateInkBoundsByFont: {},
    canvasAdvanceParityByFont: {},
    fontLoadInvalidationInstalled: false,
  };
  // OffscreenDebounceGate: when an element is outside the viewport, its frame
  // tasks wait in this deferred queue. Each repeated request while the element
  // stays off-screen pushes the task's due time further out, so a fast drag
  // keeps postponing layout work for elements the user cannot see. One
  // shared timer moves due tasks back into the normal frame loop, where the
  // anti-starvation aging rules still apply. When an element returns to the
  // viewport, its pending task is promoted immediately, so visible content
  // never waits out the debounce.
  #deferred: Map<RootSessionId, DeferredTaskBucket> = new Map();
  #deferredTimer: ReturnType<typeof setTimeout> | number = 0;
  #workerSlots: CoordinatorWorkerSlot[] = [];
  #prepareMembers: Map<RootSessionId, PrepareMember> = new Map();
  #workerWakeTimer: ReturnType<typeof setTimeout> | number = 0;
  #frameCounter: number = 0;

  register(): RootSessionId {
    const session = this.#nextRootSessionId;
    this.#nextRootSessionId += 1;
    this.#entries.set(session, { inViewport: true });
    return session;
  }

  unregister(session: RootSessionId): void {
    if (!session) return;
    this.#dropDeferred(session);
    this.#removeWorkerSlot(session);
    this.#cancelPrepare(session);
    this.#entries.delete(session);
  }

  update(session: RootSessionId, { inViewport, area, inlineSize, visibleArea, intersectionRatio }: CoordinatorUpdateOptions): void {
    if (!session) return;
    let entry = this.#entries.get(session);
    if (!entry) {
      entry = {
        inViewport: inViewport ?? true,
        area: area ?? 0,
        inlineSize: inlineSize ?? 0,
        visibleArea: visibleArea ?? 0,
        intersectionRatio: intersectionRatio ?? 1.0,
      };
      this.#entries.set(session, entry);
    }
    const wasInViewport = entry.inViewport;
    if (inViewport !== undefined) entry.inViewport = inViewport;
    if (area !== undefined) entry.area = area;
    if (inlineSize !== undefined) entry.inlineSize = inlineSize;
    if (visibleArea !== undefined) entry.visibleArea = visibleArea;
    if (intersectionRatio !== undefined) entry.intersectionRatio = intersectionRatio;
    if (inViewport === true && !wasInViewport) {
      this.#promoteDeferred(session);
    }
  }

  #dropDeferred(session: RootSessionId): void {
    if (!this.#deferred.delete(session)) return;
    if (this.#deferred.size === 0 && this.#deferredTimer) {
      clearTimeout(this.#deferredTimer);
      this.#deferredTimer = 0;
    }
  }

  #promoteDeferred(session: RootSessionId): void {
    const bucket = this.#deferred.get(session);
    if (!bucket) return;
    this.#deferred.delete(session);
    if (this.#deferred.size === 0 && this.#deferredTimer) {
      clearTimeout(this.#deferredTimer);
      this.#deferredTimer = 0;
    }
    for (const task of bucket.tasks.values()) {
      this.#callbacks.set(task.callback, task);
    }
    if (!this.#rafId) {
      this.#rafId = requestAnimationFrame(this.#runFrameLoop);
    }
  }

  #flushDeferred = (): void => {
    this.#deferredTimer = 0;
    const now = Date.now();
    let nextDueAt = Infinity;
    const deferredBuckets = Array.from(this.#deferred.entries());
    for (let i = 0; i < deferredBuckets.length; i++) {
      const session = deferredBuckets[i][0];
      const bucket = deferredBuckets[i][1];
      if (bucket.dueAt <= now) {
        this.#deferred.delete(session);
        for (const task of bucket.tasks.values()) {
          this.#callbacks.set(task.callback, task);
        }
      } else {
        nextDueAt = Math.min(nextDueAt, bucket.dueAt);
      }
    }
    if (this.#callbacks.size > 0 && !this.#rafId) {
      this.#rafId = requestAnimationFrame(this.#runFrameLoop);
    }
    if (this.#deferred.size > 0) {
      this.#deferredTimer = setTimeout(this.#flushDeferred, Math.max(0, nextDueAt - Date.now()));
    }
  };

  #callbacks: Map<FrameTaskCallback, CoordinatorTask> = new Map();
  #rafId: number = 0;
  #budgetMs: number = 6.0;
  #lastFrameTimestamp: number = 0;
  #hasFrameTimestamp: boolean = false;
  #measuredFrameInterval: number = 16.67;
  #immediateWindowStart: number = -Infinity;
  #immediateSpentMs: number = 0;

  #runFrameLoop = (now: number): void => {
    this.#rafId = 0;
    this.#frameCounter += 1;

    // RefreshAnchoredFrameBudget: the frame budget follows the measured
    // display cadence only. The previous event-driven regulator shrank the
    // budget on long frames and kept a shared EMA of slice durations, so one
    // slow first slice could close the grant gate for every root until the
    // idle-frame escape kicked in. Scheduling pressure now expresses itself
    // by itself: a late frame starts late and the absolute deadline simply
    // covers less work.
    let frameDelta = 0;
    // The explicit flag keeps the first delta at zero even when a host or
    // test clock starts at exactly zero, so frame two gets a real verdict.
    if (this.#hasFrameTimestamp) {
      frameDelta = now - this.#lastFrameTimestamp;
      if (frameDelta > 4.0 && frameDelta < 150.0) {
        if (frameDelta < this.#measuredFrameInterval * 1.1) {
          this.#measuredFrameInterval = 0.9 * this.#measuredFrameInterval + 0.1 * frameDelta;
        }
      }
    }
    this.#lastFrameTimestamp = now;
    this.#hasFrameTimestamp = true;
    this.#budgetMs = Math.min(6.0, Math.max(2.5, this.#measuredFrameInterval * 0.4));
    this.#applyGrantQuotaFeedback(frameDelta);

    const allTasks = Array.from(this.#callbacks.values());
    this.#callbacks.clear();

    // Human-centric visual prominence ordering with Anti-Starvation aging:
    // 1. inViewport + high intersection ratio + large visible area first;
    // 2. Add deferCount aging boost so tasks that have waited multiple frames bubble up.
    if (allTasks.length > 1) {
      allTasks.sort((a, b) => {
        const entryA = a.session !== null ? this.#entries.get(a.session) : undefined;
        const entryB = b.session !== null ? this.#entries.get(b.session) : undefined;

        const inViewA = entryA?.inViewport ? 1 : 0;
        const inViewB = entryB?.inViewport ? 1 : 0;

        const visibleScoreA = entryA
          ? ((entryA.visibleArea || entryA.area || 0) * (1.0 + (entryA.intersectionRatio || 0)) + (entryA.inlineSize || 0))
          : 0;
        const visibleScoreB = entryB
          ? ((entryB.visibleArea || entryB.area || 0) * (1.0 + (entryB.intersectionRatio || 0)) + (entryB.inlineSize || 0))
          : 0;

        // VisibleClassBeforeScore, same as the worker comparator: the
        // off-screen `visibleArea || area` fallback can exceed any additive
        // in-viewport bonus, so visibility is a strict class comparison and
        // score plus anti-starvation aging order only within a class.
        if (inViewA !== inViewB) return inViewB - inViewA;
        const priorityA = visibleScoreA + (a.deferCount || 0) * 50000;
        const priorityB = visibleScoreB + (b.deferCount || 0) * 50000;

        return priorityB - priorityA;
      });
    }

    // ClockTierDiscipline: budget deadlines read performance.now. The rAF
    // timestamp marks the frame start and lags behind callback execution in
    // a long frame, so a budget window started from it can already be
    // expired. Worker grants pass the remaining milliseconds as a duration,
    // so the runtime measures them on its own Date.now timeline and the two
    // clocks never mix. Coarse counters such as debounce due times and duration
    // statistics run on Date.now; millisecond resolution is enough there.
    const startTime = performance.now();
    let executedCount = 0;

    for (let i = 0; i < allTasks.length; i++) {
      const task = allTasks[i];
      const elapsed = performance.now() - startTime;

      // Yield once the budget is spent. The first task always runs; a
      // prediction of the next task's cost was removed with the slice EMA.
      if (executedCount > 0 && elapsed >= this.#budgetMs) {
        for (let j = i; j < allTasks.length; j++) {
          const deferredTask = allTasks[j];
          deferredTask.deferCount = (deferredTask.deferCount || 0) + 1;
          this.#callbacks.set(deferredTask.callback, deferredTask);
        }
        this.#rafId = requestAnimationFrame(this.#runFrameLoop);
        break;
      }

      try {
        task.callback(now);
        executedCount++;
      } catch (e) {
        console.error("Tiqian frame task error", e);
      }
    }

    // Worker grants share the same frame budget the task loop just used;
    // a dispatch task that started a job in this frame sees its first slice
    // granted in the same frame.
    const workerGrants = this.#pollWorkers(startTime, executedCount);
    this.#pollPrepare(startTime);

    this.#retainWorkerFrame();

    this.#traceFrame(now, executedCount, workerGrants);

    if (this.#callbacks.size > 0 && !this.#rafId) {
      this.#rafId = requestAnimationFrame(this.#runFrameLoop);
    }
  };

  // FrameTraceDiagnostics: opt-in scheduling evidence for stalls. A page that
  // sets globalThis.__tqTrace (with { maxEntries }) before the first enhance
  // gets one compact row per frame in globalThis.__tqFrameTrace; without the
  // opt-in the cost is one property read per frame.
  // The last column is the pre-paint admission's ledger in the shared admission window.
  #traceFrame(now: number, executedCount: number, workerGrants: number): void {
    const trace = this.traceConfig;
    if (!trace) return;
    const ring = this.frameTrace ?? (this.frameTrace = []);
    let activeSlots = 0;
    let totalPending = 0;
    for (let i = 0; i < this.#workerSlots.length; i++) {
      const slot = this.#workerSlots[i];
      if (!slot.active) continue;
      activeSlots += 1;
      totalPending += slot.pendingByTier[0] + slot.pendingByTier[1] + slot.pendingByTier[2];
    }
    ring.push([
      Math.round(now), Math.round(this.#budgetMs * 10) / 10,
      executedCount, workerGrants,
      activeSlots, totalPending, this.#callbacks.size,
      Math.round(this.#immediateSpentMs * 10) / 10,
    ]);
    const maxEntries = trace.maxEntries ?? 600;
    if (ring.length > maxEntries) ring.splice(0, ring.length - maxEntries);
  }

  // MainSliceAdmissionWindow: the pre-paint admission class runs on the
  // main thread outside the frame loop. It draws from a rolling allowance per
  // rendering update; the ceiling follows the same numbers the frame loop
  // uses (frame budget, half the measured frame interval). The admission
  // reports what it spent through the returned voucher.
  #admitMainSlice(admissionClass: string): MainSliceAdmission | null {
    const now = performance.now();
    if (now - this.#immediateWindowStart > IMMEDIATE_GRANT_WINDOW_MS) {
      this.#immediateWindowStart = now;
      this.#immediateSpentMs = 0;
    }
    const ceiling = Math.max(this.#budgetMs, this.#measuredFrameInterval * 0.5);
    const allowance = ceiling - this.#immediateSpentMs;
    if (allowance <= 0) return null;
    return {
      admissionClass,
      deadline: Date.now() + allowance,
      spent: (consumedMs: number) => { this.#immediateSpentMs += consumedMs; },
    };
  }

  // AdaptiveGrantQuota feedback pass: the constant block above holds the
  // full contract. This runs before any task or grant of the new frame, so
  // the quota a grant reads already carries the previous frame's verdict.
  // The verdict is per slot but the frame delta is shared: native follow-up
  // cost cannot be split by root, so every root that committed in the slow
  // frame is judged. An innocent neighbour recovers its headroom at one
  // quota step per frame.
  #applyGrantQuotaFeedback(frameDelta: number): void {
    if (frameDelta <= GRANT_QUOTA_MIN_FRAME_DELTA) return;
    if (frameDelta >= GRANT_QUOTA_MAX_FRAME_DELTA) return;
    const slowFrame = frameDelta > this.#measuredFrameInterval * GRANT_QUOTA_SLOW_FRAME_RATIO;
    const healthyFrame = !slowFrame &&
      frameDelta < this.#measuredFrameInterval * GRANT_QUOTA_HEALTHY_FRAME_RATIO;
    if (!slowFrame && !healthyFrame) return;
    const committingFrame = this.#frameCounter - 1;
    for (let i = 0; i < this.#workerSlots.length; i++) {
      const slot = this.#workerSlots[i];
      if (slot.lastGrantFrame !== committingFrame) continue;
      if (slowFrame) {
        slot.quota = Math.max(WORKER_GRANT_QUOTA_FLOOR, Math.floor(slot.quota / 2));
      } else {
        slot.quota = Math.min(WORKER_GRANT_QUOTA_MAX, slot.quota + 1);
      }
    }
  }

  requestFrame(callback: FrameTaskCallback, session: RootSessionId | null = null): void {
    const existing = this.#callbacks.get(callback);
    const task: CoordinatorTask = {
      callback,
      session,
      deferCount: existing ? existing.deferCount : 0,
    };
    const entry = session !== null ? this.#entries.get(session) : undefined;
    if (session !== null && entry && !entry.inViewport) {
      // OffscreenRequestQueue: one element can have several distinct
      // callbacks pending while off screen (initial enhance plus responsive
      // commits). Keep every callback per element; a single slot would let
      // the newest request silently drop the older ones.
      let bucket = this.#deferred.get(session);
      if (!bucket) {
        bucket = { dueAt: 0, tasks: new Map() };
        this.#deferred.set(session, bucket);
      }
      const pending = bucket.tasks.get(callback);
      task.deferCount = Math.max(task.deferCount, pending ? pending.deferCount : 0);
      bucket.tasks.set(callback, task);
      bucket.dueAt = Date.now() + OFFSCREEN_DEBOUNCE_MS;
      if (!this.#deferredTimer) {
        this.#deferredTimer = setTimeout(this.#flushDeferred, OFFSCREEN_DEBOUNCE_MS);
      }
      return;
    }
    this.#callbacks.set(callback, task);
    if (this.#rafId) return;
    this.#rafId = requestAnimationFrame(this.#runFrameLoop);
  }

  cancelFrame(callback: FrameTaskCallback): void {
    this.#callbacks.delete(callback);
    const deferredBuckets = Array.from(this.#deferred.entries());
    for (let i = 0; i < deferredBuckets.length; i++) {
      const session = deferredBuckets[i][0];
      const bucket = deferredBuckets[i][1];
      bucket.tasks.delete(callback);
      if (bucket.tasks.size === 0) this.#dropDeferred(session);
    }
    if (this.#callbacks.size === 0 && this.#rafId) {
      cancelAnimationFrame(this.#rafId);
      this.#rafId = 0;
    }
  }

  // FrameBoundaryYield: one-shot continuation at the next frame start that
  // deliberately bypasses the frame loop. The direct-SSR background proof uses
  // it only to reach the frame boundary before handing its continuation to
  // background-priority scheduler work; running it as a budgeted frame task
  // would contend with layout work it is meant to yield to. This keeps every
  // native frame call inside the coordination service (ruling R5).
  requestFrameBoundary(callback: FrameTaskCallback): number {
    return requestAnimationFrame(callback);
  }

  registerWorker(session: RootSessionId, element: HTMLElement): void {
    for (let i = 0; i < this.#workerSlots.length; i++) {
      if (this.#workerSlots[i].session === session) {
        this.#workerSlots[i].elementRef = new WeakRef(element);
        return;
      }
    }
    this.#workerSlots.push({
      session,
      elementRef: new WeakRef(element),
      active: false,
      pendingByTier: [0, 0, 0],
      generation: 0,
      deferredUntil: 0,
      deferCount: 0,
      lastGrantFrame: -1,
      quota: WORKER_GRANT_QUOTA_START,
    });
  }

  // PrePaintResponsiveCommit: a width-only relayout dispatched from inside a
  // ResizeObserver callback still runs before the browser paints the resized
  // frame, so draining the job's in-viewport tier here removes the one
  // painted frame in which stale lines overflow the narrowed container. The
  // grant copies the polled-grant contract (job generation, per-root quota,
  // deadline in the Date.now domain) and draws from a shared per-update
  // allowance; once it is spent, later callers wait for the polled frame
  // loop. Remaining tiers stay with it.
  grantImmediate(session: RootSessionId): boolean {
    const slot = this.#findWorkerSlot(session);
    if (!slot || typeof this.layoutJobPool?.runSlice !== "function") return false;
    const element = slot.elementRef.deref();
    if (!element) return false;
    if (!this.layoutJobPool.hasJob(element)) return false;
    const admission = this.#admitMainSlice("prepaint");
    if (!admission) return false;
    const sliceStart = performance.now();
    const generation = this.layoutJobPool.jobGeneration(element);
    const quota = slot.quota;
    let processed = 0;
    const viewportAnchor = captureViewportAnchor(element);
    try {
      // Drain the in-viewport tier like a polled grant round: one slice per
      // quota batch until the tier is empty or the allowance is spent, so a
      // root whose visible paragraph count exceeds the adaptive quota still
      // commits atomically before this frame paints.
      while (Date.now() < admission.deadline) {
        const sliceProcessed = this.layoutJobPool.runSlice({
          admissionClass: "prepaint",
          root: element,
          generation,
          deadline: admission.deadline,
          quota,
          shouldStop(processedCount: number): boolean {
            return processedCount >= quota || Date.now() >= admission.deadline;
          },
        }, 1);
        processed += sliceProcessed;
        if (sliceProcessed === 0) break;
        if (this.layoutJobPool.pendingInTier(element, 1) === 0) break;
      }
    } finally {
      admission.spent(performance.now() - sliceStart);
    }
    if (processed > 0) {
      compensateViewportAnchor(element, viewportAnchor);
      slot.deferCount = 0;
      slot.lastGrantFrame = this.#frameCounter;
    }
    slot.active = this.layoutJobPool.hasJob(element);
    if (!slot.active) releaseNativeScrollAnchoring(element);
    slot.pendingByTier[0] = this.layoutJobPool.pendingInTier(element, 1);
    slot.pendingByTier[1] = this.layoutJobPool.pendingInTier(element, 2);
    slot.pendingByTier[2] = this.layoutJobPool.pendingInTier(element, 3);
    return processed > 0;
  }

  // PrepareLaneInFrameLoop: preparation slices used to run in their own
  // loop outside this pool. A job registered here advances inside the frame
  // loop after tasks and grants, under the same startTime deadline, one
  // candidate guaranteed per frame. Worker replies re-arm the loop through
  // the job's onFinished; the returned promise resolves with the stored-plan
  // count once the job finishes. A second registration for the same root
  // session resolves the previous promise and replaces the member.
  runPrepare(session: RootSessionId, job: PrepareJob): Promise<number> {
    const existing = this.#prepareMembers.get(session);
    if (existing) existing.resolve!(0);
    let resolve: PrepareResolveFn | null = null;
    const promise = new Promise<number>((r) => { resolve = r; });
    this.#prepareMembers.set(session, { job, resolve });
    job.onFinished = (finishedJob: PrepareJob): void => {
      if (finishedJob.done) {
        const member = this.#prepareMembers.get(session);
        if (member && member.job === finishedJob) this.#prepareMembers.delete(session);
        finishedJob.finished.then(resolve!);
      } else if (!this.#rafId) {
        this.#rafId = requestAnimationFrame(this.#runFrameLoop);
      }
    };
    if (!this.#rafId) this.#rafId = requestAnimationFrame(this.#runFrameLoop);
    return promise;
  }

  #removeWorkerSlot(session: RootSessionId): void {
    const slots = this.#workerSlots;
    for (let i = 0; i < slots.length; i++) {
      if (slots[i].session !== session) continue;
      slots[i] = slots[slots.length - 1];
      slots.pop();
      break;
    }
    if (slots.length === 0 && this.#workerWakeTimer) {
      clearTimeout(this.#workerWakeTimer);
      this.#workerWakeTimer = 0;
    }
  }

  #cancelPrepare(session: RootSessionId): void {
    const member = this.#prepareMembers.get(session);
    if (!member) return;
    this.#prepareMembers.delete(session);
    member.resolve!(0);
  }

  setWorkerActive(session: RootSessionId, active: boolean): void {
    const slot = this.#findWorkerSlot(session);
    if (!slot) return;
    slot.active = active;
    if (active && !this.#rafId) {
      this.#rafId = requestAnimationFrame(this.#runFrameLoop);
    }
  }

  // OffscreenWorkerDebounce: an off-screen root with pending layout work is
  // granted nothing until this trailing window expires. Width changes while
  // the root stays off-screen keep pushing the due time out, so a fast drag
  // lays out only the final width.
  refreshWorkerDeferred(session: RootSessionId): void {
    const slot = this.#findWorkerSlot(session);
    if (slot) slot.deferredUntil = Date.now() + OFFSCREEN_DEBOUNCE_MS;
  }

  clearWorkerDeferred(session: RootSessionId): void {
    const slot = this.#findWorkerSlot(session);
    if (!slot) return;
    slot.deferredUntil = 0;
    if (!this.#rafId) {
      this.#rafId = requestAnimationFrame(this.#runFrameLoop);
    }
  }

  requestWorkerFrame(_session: RootSessionId): void {
    if (!this.#rafId) {
      this.#rafId = requestAnimationFrame(this.#runFrameLoop);
    }
  }

  #findWorkerSlot(session: RootSessionId): CoordinatorWorkerSlot | null {
    for (let i = 0; i < this.#workerSlots.length; i++) {
      if (this.#workerSlots[i].session === session) return this.#workerSlots[i];
    }
    return null;
  }

  #compareWorkerSlots = (a: CoordinatorWorkerSlot, b: CoordinatorWorkerSlot): number => {
    const entryA = this.#entries.get(a.session);
    const entryB = this.#entries.get(b.session);
    const inViewA = entryA?.inViewport ? 1 : 0;
    const inViewB = entryB?.inViewport ? 1 : 0;
    const visibleScoreA = entryA
      ? ((entryA.visibleArea || entryA.area || 0) * (1.0 + (entryA.intersectionRatio || 0)) +
        (entryA.inlineSize || 0))
      : 0;
    const visibleScoreB = entryB
      ? ((entryB.visibleArea || entryB.area || 0) * (1.0 + (entryB.intersectionRatio || 0)) +
        (entryB.inlineSize || 0))
      : 0;
    // VisibleClassBeforeScore: pollWorkers derives visibleCount from the
    // sorted prefix, so the in-viewport class must strictly precede the
    // off-screen class no matter how large any score term grows — an
    // additive bonus cannot guarantee that, because `visibleArea || area`
    // falls back to the element's FULL area for off-screen entries. Aging
    // stays capped for the same reason and orders only within a class.
    if (inViewA !== inViewB) return inViewB - inViewA;
    const priorityA = visibleScoreA + Math.min(a.deferCount * 50000, 900000);
    const priorityB = visibleScoreB + Math.min(b.deferCount * 50000, 900000);
    return priorityB - priorityA;
  };

  #pollWorkers(startTime: number, executedCount: number): number {
    const slots = this.#workerSlots;
    if (slots.length === 0) return 0;
    const deadline = startTime + this.#budgetMs;
    // GrantClockConversion: the frame deadline lives in the performance.now()
    // domain while the runtime's stop closure reads the coarse Date.now()
    // clock. Reading both clocks once per poll yields this frame's offset;
    // each grant converts its deadline by adding it, so both sides of a
    // grant share one anchor and the runtime holds no clock arithmetic.
    const grantDeadline = deadline + (Date.now() - performance.now());
    // One scan per frame: liveness, job generation, and the three tier
    // counters per attached root. Grants re-read only the tier they drained.
    for (let i = 0; i < slots.length; i++) {
      const slot = slots[i];
      const element = slot.elementRef.deref();
      if (!element) {
        // WeakSlotElement: the root object was collected without a
        // disconnectedCallback, so the slot retires here instead of waiting
        // for an unregister that will never arrive.
        this.#removeWorkerSlot(slot.session);
        i -= 1;
        continue;
      }
      if (this.layoutJobPool.hasJob(element)) {
        slot.active = true;
        slot.generation = this.layoutJobPool.jobGeneration(element);
        slot.pendingByTier[0] = this.layoutJobPool.pendingInTier(element, 1);
        slot.pendingByTier[1] = this.layoutJobPool.pendingInTier(element, 2);
        slot.pendingByTier[2] = this.layoutJobPool.pendingInTier(element, 3);
      } else {
        slot.active = false;
        slot.generation = 0;
        slot.pendingByTier[0] = 0;
        slot.pendingByTier[1] = 0;
        slot.pendingByTier[2] = 0;
        // NativeAnchoringHandover: the job is over; hand the scroller back to
        // the browser's own anchoring until the next slice commits.
        releaseNativeScrollAnchoring(element);
      }
    }
    slots.sort(this.#compareWorkerSlots);
    let visibleCount = 0;
    while (visibleCount < slots.length && this.#entries.get(slots[visibleCount].session)?.inViewport) {
      visibleCount += 1;
    }
    let grants = 0;
    let workDone = executedCount;
    const grantSlot = (slot: CoordinatorWorkerSlot, tier: number): boolean => {
      const element = slot.elementRef.deref();
      if (!element) return false;
      // SliceCommitAnchorCompensation: every slice this grant runs happens in
      // this same task, so one capture/compensate pair around the drain sees
      // the pure layout displacement of all its commits.
      let viewportAnchor: ViewportAnchor | null = null;
      let anchorCaptured = false;
      let grantProcessed = 0;
      const finish = (result: boolean): boolean => {
        if (grantProcessed > 0) compensateViewportAnchor(element, viewportAnchor);
        return result;
      };
      while (sumPendingUpTo(slot, tier) > 0) {
        const now = performance.now();
        // DeadlineGate: grants stop once the frame budget is spent. A frame
        // that produced no work at all still grants once, so a job whose
        // every slice outlasts the budget keeps making progress.
        const guaranteeForwardProgress = workDone === 0;
        if (!guaranteeForwardProgress && now >= deadline) {
          return finish(false);
        }
        // GrantController: one controller per grant. It carries value-copied
        // stop terms for this recipient alone: the root, the job generation
        // this grant addresses, the Date.now()-domain deadline, and the
        // paragraph quota. The closure captures only those numbers, never
        // coordinator state, so the runtime can reach no other root through
        // a grant. The loop asks shouldStop after each paragraph and obeys.
        const quota = slot.quota;
        if (!anchorCaptured) {
          anchorCaptured = true;
          viewportAnchor = captureViewportAnchor(element);
        }
        const processed = this.layoutJobPool.runSlice({
          admissionClass: "grant",
          root: element,
          generation: slot.generation,
          deadline: grantDeadline,
          quota,
          shouldStop(processedCount: number): boolean {
            return processedCount >= quota || Date.now() >= grantDeadline;
          },
        }, tier);
        if (processed > 0) {
          grants += 1;
          workDone += 1;
          grantProcessed += processed;
          slot.deferCount = 0;
          slot.lastGrantFrame = this.#frameCounter;
        }
        // A tier-N grant may drain leftover lower-tier items, so every grant
        // refreshes all three counters.
        slot.pendingByTier[0] = this.layoutJobPool.pendingInTier(element, 1);
        slot.pendingByTier[1] = this.layoutJobPool.pendingInTier(element, 2);
        slot.pendingByTier[2] = this.layoutJobPool.pendingInTier(element, 3);
        if (processed === 0) return finish(true);
      }
      return finish(true);
    };
    // TierOrderedGrants: tiers drain in order across roots. Every visible
    // root finishes tier 1, its in-viewport paragraphs, before any root
    // starts tier 2; tier 3 comes last. Off-screen roots join only after
    // their debounce expires, behind every visible tier.
    for (let tier = 1; tier <= 3; tier++) {
      for (let i = 0; i < visibleCount; i++) {
        if (slots[i].active && !grantSlot(slots[i], tier)) return grants;
      }
    }
    const nowMs = Date.now();
    for (let i = visibleCount; i < slots.length; i++) {
      const slot = slots[i];
      if (!slot.active || !(slot.deferredUntil > 0) || slot.deferredUntil > nowMs) continue;
      for (let tier = 1; tier <= 3; tier++) {
        if (!grantSlot(slot, tier)) return grants;
      }
    }
    return grants;
  }

  #pollPrepare(startTime: number): void {
    if (this.#prepareMembers.size === 0) return;
    for (const [session, member] of this.#prepareMembers) {
      const job = member.job;
      if (job.done) continue;
      job.step(() => performance.now() - startTime >= this.#budgetMs);
      // A step can finish the job itself (cancellation finishes without a
      // reply); retire the member here so the root's await resumes and
      // the retained frame loop has one less reason to stay armed.
      if (job.done) {
        this.#prepareMembers.delete(session);
        job.finished.then(member.resolve);
      }
    }
  }

  #retainWorkerFrame(): void {
    let keepFrames = false;
    // Keep the frame loop alive while prepare members are incomplete;
    // idle frames waiting for Worker replies have almost zero cost.
    if (this.#prepareMembers.size > 0) keepFrames = true;
    const slots = this.#workerSlots;
    const now = Date.now();
    let nextWakeAt = Infinity;
    for (let i = 0; i < slots.length; i++) {
      const slot = slots[i];
      if (!slot.active) {
        // deferCount otherwise resets only on a successful grant, so a slot
        // whose job is gone would keep its aging boost forever.
        slot.deferCount = 0;
        continue;
      }
      const total = slot.pendingByTier[0] + slot.pendingByTier[1] + slot.pendingByTier[2];
      if (total === 0) {
        slot.deferCount = 0;
        continue;
      }
      if (this.#entries.get(slot.session)?.inViewport) {
        keepFrames = true;
      } else if (!slot.deferredUntil) {
        // First frame this off-screen root has pending work: the debounce
        // window starts now and the first grant follows its expiry.
        slot.deferredUntil = now + OFFSCREEN_DEBOUNCE_MS;
        if (slot.lastGrantFrame !== this.#frameCounter) slot.deferCount += 1;
        nextWakeAt = Math.min(nextWakeAt, slot.deferredUntil);
      } else if (slot.deferredUntil <= now) {
        keepFrames = true;
      } else {
        if (slot.lastGrantFrame !== this.#frameCounter) slot.deferCount += 1;
        nextWakeAt = Math.min(nextWakeAt, slot.deferredUntil);
      }
    }
    if (keepFrames && !this.#rafId) {
      this.#rafId = requestAnimationFrame(this.#runFrameLoop);
    }
    if (nextWakeAt < Infinity && !this.#workerWakeTimer) {
      this.#workerWakeTimer = setTimeout(
        this.#flushWorkerWake,
        Math.max(0, nextWakeAt - Date.now()),
      );
    }
  }

  #flushWorkerWake = (): void => {
    this.#workerWakeTimer = 0;
    if (!this.#rafId) {
      this.#rafId = requestAnimationFrame(this.#runFrameLoop);
    }
  };
}
