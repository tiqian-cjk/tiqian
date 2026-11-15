import { globalServices } from "../../services/global-services.js";
// Main-thread worker channel (ADR 0053 batch 5; decomposition report
// section 9). Moved verbatim from the package root; layout-worker.js
// stays at the root, so the Worker URL gains three parent levels.
import { browserFontSessionWorkerContract } from "../../measurement/browser-fonts.js";
import type {
  BrowserFontSessionHandle,
  BrowserFontSessionWorkerContract,
} from "../../measurement/browser-fonts.js";
import { workerLayoutRequestForRoot } from "../worker-request.js";
import { optionsFromJs } from "../lifecycle.js";
import {
  normalizeLiveSemantics,
  normalizeSnapshotSemantics,
  SnapshotSemanticError,
} from "../../sampler/snapshot/snapshot-source.js";
import type {
  LiveSemanticSpan,
  SnapshotSemanticSpan,
} from "../../sampler/snapshot/snapshot-source.js";
import { LAYOUT_REQUEST_FIELDS } from "./assembly-record-fields.js";
import type {
  PrepareFinishedCallback,
  PrepareJob,
  PrepareResolveFn,
  PrepareStepFn,
  ShouldYieldPredicate,
} from "../coordination/coordination-service.js";
import type { ProbeMeasure } from "../../measurement/replay-probe.js";

export interface WorkerInitEnvelope {
  id?: number;
  type: "init";
  sessionKey: string;
  manifestText?: string;
  tablesBytes?: Uint8Array | null;
  probeBootstrap?: boolean;
  measureAdapter?: ProbeMeasure | null;
}

export interface WorkerReleaseEnvelope {
  id?: number;
  type: "release";
  sessionKey: string;
}

export interface WorkerLayoutEnvelope {
  id?: number;
  type: "layout";
  sessionKey: string;
  request: WorkerLayoutRequestBody;
}

export type WorkerRequestEnvelope =
  | WorkerInitEnvelope
  | WorkerReleaseEnvelope
  | WorkerLayoutEnvelope;

export interface WorkerSuccessEnvelope {
  id?: number;
  ok: true;
  plan?: string;
}

export interface WorkerErrorEnvelope {
  id?: number;
  ok: false;
  error: string;
}

export type WorkerResponseEnvelope =
  | WorkerSuccessEnvelope
  | WorkerErrorEnvelope;

import type { WorkerLayoutRequest, TextSpanWire, InlineBoxWire, LineBreakSpanWire, InlineObjectWire, SemanticSpanWire, RenderInlineBoxWire } from "@tiqian/ffi";

export interface WorkerLayoutSemanticSpan {
  start?: unknown;
  end?: unknown;
  order?: unknown;
  tagName?: unknown;
  attributes?: unknown;
  sourceIndex?: unknown;
  [key: string]: unknown;
}

export interface WorkerLayoutRequestBody extends WorkerLayoutRequest {
  // Additional fields specific to the worker channel
  renderEvidence: boolean;
  semantics: SemanticSpanWire[];
  renderInlineBoxes: RenderInlineBoxWire[];
  sourceTag: string;
  [key: string]: unknown;
}

export interface PlanRecord {
  plan?: string;
  issue?: string;
}

export type PendingResolveFn = (value: WorkerResponseEnvelope) => void;
export type PendingRejectFn = (reason: Error) => void;

export interface PendingRequest {
  resolve: PendingResolveFn;
  reject: PendingRejectFn;
}

export interface PageWorkerCoordinator {
  plans: Map<string, PlanRecord>;
  worker: Worker | null;
  nextRequestId: number;
  pending: Map<number, PendingRequest>;
  initializedSessions: Set<string>;
}

export type SemanticReplayMode = "snapshot-safe" | "live-source";

export interface SemanticReplaySuccess {
  mode: SemanticReplayMode;
  semantics: readonly SnapshotSemanticSpan[] | readonly LiveSemanticSpan[];
  issue?: undefined;
}

export interface SemanticReplayFailure {
  mode?: undefined;
  semantics?: undefined;
  issue: string;
}

export type SemanticReplayResult = SemanticReplaySuccess | SemanticReplayFailure;

export interface PrepareJobOptions {
  paragraphSelector?: string;
  [key: string]: unknown;
}

export type IsCurrentPredicate = () => boolean;

export interface InternalPrepareCandidate {
  element: HTMLElement;
  index: number;
  distance: number;
}

export interface InternalPrepareJob {
  readonly done: boolean;
  onFinished: PrepareFinishedCallback | null;
  finished: Promise<number> | null;
  step: PrepareStepFn;
  finishedResolve?: PrepareResolveFn;
}

const ROOT_SELECTOR = "tiqian-prose, [data-tiqian-root]";
const DEFAULT_RUNTIME_PARAGRAPH_SELECTOR = "p, li";
const BRIDGE_VERSION = 1;
const SEMANTIC_REPLAY_REVISION = 1;
const LIVE_SOURCE_SEMANTIC_CODES: Set<string> = new Set([
  "UnsupportedSnapshotSemanticAttribute",
  "UnsupportedSnapshotSemanticTag",
  "UnsafeSnapshotSemanticHref",
]);
// PageWorkerCoordinator: client routers, dev HMR and duplicated package chunks
// may evaluate this module more than once in the same document. Kotlin reaches
// the worker through one page-global bridge, so every module instance must use
// the same plans, pending requests and session ownership as that bridge.
// S5-bc: the coordinator singleton moved into globalServices().coordination.channel;
// this accessor replaces the former Symbol.for module-scope singleton.
function coord(): PageWorkerCoordinator {
  return globalServices().coordination.channel;
}

function ensureWorker(): Worker {
  const c = coord();
  if (c.worker) return c.worker;
  if (typeof Worker !== "function") throw new Error("LayoutWorkerUnavailable");
  c.worker = new Worker(new URL("../layout-worker.ts", import.meta.url), {
    type: "module",
  });
  c.worker.addEventListener("message", (event: MessageEvent<WorkerResponseEnvelope>) => {
    const message = event.data;
    const request = c.pending.get(message?.id!);
    if (!request) return;
    c.pending.delete(message.id!);
    if (message.ok) request.resolve(message);
    else request.reject(new Error(message.error || "LayoutWorkerFailed"));
  });
  c.worker.addEventListener("error", (event: ErrorEvent) => {
    const error = event.error ?? new Error(event.message || "LayoutWorkerFailed");
    for (const request of c.pending.values()) request.reject(error);
    c.pending.clear();
    c.initializedSessions.clear();
    c.worker?.terminate();
    c.worker = null;
  });
  return c.worker;
}

function send(message: WorkerRequestEnvelope): Promise<WorkerResponseEnvelope> {
  const target = ensureWorker();
  const c = coord();
  const id = c.nextRequestId++;
  const result = new Promise<WorkerResponseEnvelope>((resolve, reject) => c.pending.set(id, { resolve, reject }));
  target.postMessage({ ...message, id });
  return result;
}

async function ensureSession(contract: BrowserFontSessionWorkerContract): Promise<void> {
  const c = coord();
  if (c.initializedSessions.has(contract.sessionKey)) return;
  await send({ type: "init", ...contract });
  c.initializedSessions.add(contract.sessionKey);
}


function distanceFromViewport(element: Element): number {
  const rect = element.getBoundingClientRect();
  const height = globalThis.innerHeight || document.documentElement.clientHeight || 0;
  if (rect.bottom >= 0 && rect.top <= height) return 0;
  return rect.bottom < 0 ? -rect.bottom : rect.top - height;
}

function layoutRequestKey(request: WorkerLayoutRequestBody | null | undefined): string {
  return JSON.stringify(LAYOUT_REQUEST_FIELDS.map((field) => request?.[field] ?? null));
}

function preparedPlanKey(sessionKey: string, request: WorkerLayoutRequestBody | null | undefined): string {
  return `${sessionKey}\u0000${layoutRequestKey(request)}`;
}

function parsedLayoutRequest(requestText: string): WorkerLayoutRequestBody | null {
  try {
    return JSON.parse(requestText) as WorkerLayoutRequestBody;
  } catch {
    return null;
  }
}


function errorDetail(error: unknown): string {
  return String(error instanceof Error ? error.message : error).slice(0, 1_000);
}

/**
 * WorkerPlanReplayEligibility: layout identity deliberately excludes DOM
 * semantics. Resolve replay eligibility from the current request every time,
 * without storing a semantic miss in the shared layout-plan cache.
 */
function semanticReplay(request: WorkerLayoutRequestBody): SemanticReplayResult {
  try {
    return {
      mode: "snapshot-safe",
      semantics: normalizeSnapshotSemantics(request.text, request.semantics),
    };
  } catch (error) {
    if (!(error instanceof SnapshotSemanticError) ||
        !LIVE_SOURCE_SEMANTIC_CODES.has(error.code)) {
      return { issue: errorDetail(error) };
    }
    try {
      return {
        mode: "live-source",
        semantics: normalizeLiveSemantics(request.text, request.semantics),
      };
    } catch (liveError) {
      return { issue: errorDetail(liveError) };
    }
  }
}

function installBridge(): void {
  const installedVersion = Number(globalServices().coordination.layoutWorker?.version);
  const installedSemanticReplayRevision = Number(
    globalServices().coordination.layoutWorker?.semanticReplayRevision ?? 0,
  );
  // MonotonicBridgeFeatureUpgrade: legacy v1 chunks return early for any v1
  // bridge. Keep that outer version so an old chunk cannot downgrade this
  // implementation, and use a feature revision to replace an older v1 closure.
  if (installedVersion > BRIDGE_VERSION ||
      (installedVersion === BRIDGE_VERSION &&
       installedSemanticReplayRevision >= SEMANTIC_REPLAY_REVISION)) return;
  globalServices().coordination.layoutWorker = Object.freeze({
      version: BRIDGE_VERSION,
      semanticReplayRevision: SEMANTIC_REPLAY_REVISION,
      take(_element: Element | null | undefined, sessionKey: string, requestText: string): string | null {
        const request = parsedLayoutRequest(requestText);
        if (!request) return null;
        const c = coord();
        const record = c.plans.get(preparedPlanKey(sessionKey, request));
        if (!record || record.issue) return null;
        const replay = semanticReplay(request);
        if (replay.issue) return null;
        return JSON.stringify({
          plan: record.plan,
          // LayoutPlanSemanticLateBinding: the Worker plan depends only on the
          // immutable shaping/line-break fields above. DOM semantics and
          // renderer-owned inline-box metadata are read again at commit time;
          // including them in the cache key made harmless progressive DOM
          // changes look like a missing plan for every later paragraph.
          semanticReplay: replay.mode,
          semantics: replay.semantics,
          inlineBoxes: request.renderInlineBoxes,
        });
      },
      issue(_element: Element | null | undefined, sessionKey: string, requestText: string): string | null {
        const request = parsedLayoutRequest(requestText);
        if (!request) return null;
        const c = coord();
        const record = c.plans.get(preparedPlanKey(sessionKey, request));
        if (!record) return null;
        if (record.issue) return record.issue;
        return semanticReplay(request).issue ?? null;
      },
      release(sessionKey?: string): boolean {
        const c = coord();
        for (const key of c.plans.keys()) {
          if (sessionKey !== undefined && key.startsWith(`${sessionKey}\u0000`)) c.plans.delete(key);
        }
        if (sessionKey === undefined || !c.initializedSessions.delete(sessionKey) || !c.worker) return false;
        void send({ type: "release", sessionKey }).catch(() => {});
        return true;
      },
    });
}

installBridge();

// PrepareJob: the pool-driven form of worker-plan preparation (ADR 0053 C3).
// createPrepareJob resolves after the session handshake with a job the
// coordinator frame loop advances. step() builds requests and fires Worker
// round-trips without awaiting them, so a step's main-thread cost is only
// the synchronous request builds. Replies land in their own microtasks,
// store their plans, and call onFinished, which re-arms the frame loop.
// `finished` resolves with the stored-plan count once every candidate was
// both dispatched and answered; `done` carries the same moment for
// synchronous pollers. Pacing follows the page's visibility because the
// frame loop drives it, matching the grant lanes.
export async function createPrepareJob(
  root: HTMLElement | null | undefined,
  snapshotFontSession: BrowserFontSessionHandle | null | undefined,
  options: PrepareJobOptions | null | undefined,
  isCurrent: IsCurrentPredicate,
): Promise<PrepareJob | null> {
  if (!root || !snapshotFontSession || !isCurrent()) return null;
  const canonicalOptions = optionsFromJs(options ?? {});
  const contract = browserFontSessionWorkerContract(snapshotFontSession);
  // WorkerCandidateSetMatchesCommitSet: mixed snapshot/runtime roots dispatch
  // Kotlin with an explicit completion-only paragraph selector. A full
  // runtime fallback, however, has no explicit selector and Kotlin visits all
  // paragraph-shaped p/li nodes. The manifest selector describes snapshot
  // entries only; reusing it after a width miss permanently omitted unkeyed
  // rich paragraphs from Worker preparation.
  const paragraphSelector = typeof options?.paragraphSelector === "string" &&
      options.paragraphSelector.trim()
    ? options.paragraphSelector
    : DEFAULT_RUNTIME_PARAGRAPH_SELECTOR;
  const candidates: InternalPrepareCandidate[] = Array.from(root.querySelectorAll<HTMLElement>(paragraphSelector))
    .filter((element: HTMLElement) => element.closest(ROOT_SELECTOR) === root)
    .map((element: HTMLElement, index: number) => ({ element, index, distance: distanceFromViewport(element) }))
    .sort((left: InternalPrepareCandidate, right: InternalPrepareCandidate) => left.distance - right.distance || left.index - right.index);
  await ensureSession(contract);
  if (!isCurrent()) return null;
  let index = 0;
  let inflight = 0;
  let stored = 0;
  let done = false;
  const finishIfIdle = (): void => {
    if (index >= candidates.length && inflight === 0) done = true;
  };
  const job: InternalPrepareJob = {
    get done() { return done; },
    onFinished: null,
    finished: null,
    // One step = one synchronous slice of request builds. The first
    // candidate always runs; shouldYield() stops the slice afterwards.
    // Returns the number of candidates dispatched in this step.
    step(shouldYield: ShouldYieldPredicate): number {
      let dispatched = 0;
      while (index < candidates.length) {
        if (!isCurrent()) {
          // CancelledPrepareFinishesEarly: a stale job never becomes current
          // again, so waiting for the remaining candidates would leave the
          // member parked in the coordinator forever. Finish with the plans
          // stored so far; the awaiting element re-checks staleness and
          // aborts its own dispatch.
          done = true;
          job.finishedResolve!(stored);
          return dispatched;
        }
        if (dispatched > 0 && shouldYield()) return dispatched;
        let request: WorkerLayoutRequestBody | null = null;
        try {
          // Serialization happens at the send boundary (R10): the pure builder
          // answers a DTO, the wire body crosses through JSON exactly like
          // process-paragraph's take/issue boundary.
          const built = workerLayoutRequestForRoot(root, candidates[index].element, canonicalOptions);
          if (built) request = parsedLayoutRequest(JSON.stringify(built));
        } catch {
          // ParagraphAtomicNativeRollback: an invalid candidate remains native
          // without preventing later independent paragraphs from being prepared.
        }
        index += 1;
        if (!request) continue;
        inflight += 1;
        dispatched += 1;
        send({ type: "layout", sessionKey: contract.sessionKey, request })
          .then((result: WorkerResponseEnvelope) => {
            coord().plans.set(preparedPlanKey(contract.sessionKey, request), { plan: (result as WorkerSuccessEnvelope).plan });
            stored += 1;
          })
          .catch((error: unknown) => {
            // SnapshotWorkerFailureMustStayNative: falling back to synchronous Kotlin/JS
            // recreates the navigation/scroll stall this Worker exists to remove,
            // especially under Edge's enhanced-security JIT restrictions. Publish a
            // per-request capability issue for the main-thread coordinator instead;
            // it will retain the paragraph's untouched source DOM.
            coord().plans.set(preparedPlanKey(contract.sessionKey, request), {
              issue: String(error instanceof Error ? error.message : error).slice(0, 1_000),
            });
          })
          .finally(() => {
            inflight -= 1;
            finishIfIdle();
            if (done) job.finishedResolve!(stored);
            // The coordinator owns a separate completion promise and must
            // retire the prepare member when the final Worker reply arrives.
            if (job.onFinished) job.onFinished(job as PrepareJob);
          });
      }
      finishIfIdle();
      if (done) job.finishedResolve!(stored);
      return dispatched;
    },
  };
  job.finished = new Promise<number>((resolve) => { job.finishedResolve = resolve; });
  return job as PrepareJob;
}


