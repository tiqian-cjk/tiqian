import { browserFontSessionWorkerContract } from "./browser-fonts.js";
import {
  normalizeLiveSemantics,
  normalizeSnapshotSemantics,
  SnapshotSemanticError,
} from "./snapshot-source.js";

const ROOT_SELECTOR = "tiqian-prose, [data-tiqian-root]";
const DEFAULT_RUNTIME_PARAGRAPH_SELECTOR = "p, li";
const MAIN_SLICE_BUDGET_MS = 8;
const BRIDGE_VERSION = 1;
const SEMANTIC_REPLAY_REVISION = 1;
const LIVE_SOURCE_SEMANTIC_CODES = new Set([
  "UnsupportedSnapshotSemanticAttribute",
  "UnsupportedSnapshotSemanticTag",
  "UnsafeSnapshotSemanticHref",
]);
const LAYOUT_REQUEST_FIELDS = Object.freeze([
  "text",
  "maxWidthPx",
  "fontFamilies",
  "fontSizePx",
  "lineHeightPx",
  "locale",
  "fontWeight",
  "italic",
  "firstLineIndentIc",
  "sourceBoundaries",
  "textSpans",
  "inlineBoxes",
]);
const COORDINATOR_KEY = Symbol.for("@tiqian/prose.layout-worker-coordinator.v1");
// PageWorkerCoordinator: client routers, dev HMR and duplicated package chunks
// may evaluate this module more than once in the same document. Kotlin reaches
// the worker through one page-global bridge, so every module instance must use
// the same plans, pending requests and session ownership as that bridge.
const coordinator = globalThis[COORDINATOR_KEY] ??= {
  plans: new Map(),
  worker: null,
  nextRequestId: 1,
  pending: new Map(),
  initializedSessions: new Set(),
};
const { plans, pending, initializedSessions } = coordinator;

function ensureWorker() {
  if (coordinator.worker) return coordinator.worker;
  if (typeof Worker !== "function") throw new Error("LayoutWorkerUnavailable");
  coordinator.worker = new Worker(new URL("./layout-worker.js", import.meta.url), {
    type: "module",
  });
  coordinator.worker.addEventListener("message", (event) => {
    const message = event.data;
    const request = pending.get(message?.id);
    if (!request) return;
    pending.delete(message.id);
    if (message.ok) request.resolve(message);
    else request.reject(new Error(message.error || "LayoutWorkerFailed"));
  });
  coordinator.worker.addEventListener("error", (event) => {
    const error = event.error ?? new Error(event.message || "LayoutWorkerFailed");
    for (const request of pending.values()) request.reject(error);
    pending.clear();
    initializedSessions.clear();
    coordinator.worker?.terminate();
    coordinator.worker = null;
  });
  return coordinator.worker;
}

function send(message) {
  const target = ensureWorker();
  const id = coordinator.nextRequestId++;
  const result = new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
  target.postMessage({ ...message, id });
  return result;
}

async function ensureSession(contract) {
  if (initializedSessions.has(contract.sessionKey)) return;
  await send({ type: "init", ...contract });
  initializedSessions.add(contract.sessionKey);
}

async function yieldMainIfNeeded(startedAt) {
  if (performance.now() - startedAt < MAIN_SLICE_BUDGET_MS) return startedAt;
  if (typeof globalThis.scheduler?.yield === "function") await globalThis.scheduler.yield();
  else await new Promise((resolve) => setTimeout(resolve, 0));
  return performance.now();
}

function distanceFromViewport(element) {
  const rect = element.getBoundingClientRect();
  const height = globalThis.innerHeight || document.documentElement.clientHeight || 0;
  if (rect.bottom >= 0 && rect.top <= height) return 0;
  return rect.bottom < 0 ? -rect.bottom : rect.top - height;
}

function layoutRequestKey(request) {
  return JSON.stringify(LAYOUT_REQUEST_FIELDS.map((field) => request?.[field] ?? null));
}

function preparedPlanKey(sessionKey, request) {
  return `${sessionKey}\u0000${layoutRequestKey(request)}`;
}

function parsedLayoutRequest(requestText) {
  try {
    return JSON.parse(requestText);
  } catch {
    return null;
  }
}

function errorDetail(error) {
  return String(error instanceof Error ? error.message : error).slice(0, 1_000);
}

/**
 * WorkerPlanReplayEligibility: layout identity deliberately excludes DOM
 * semantics. Resolve replay eligibility from the current request every time,
 * without storing a semantic miss in the shared layout-plan cache.
 */
function semanticReplay(request) {
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

function installBridge() {
  const installedVersion = Number(globalThis.__TiqianLayoutWorker?.version);
  const installedSemanticReplayRevision = Number(
    globalThis.__TiqianLayoutWorker?.semanticReplayRevision ?? 0,
  );
  // MonotonicBridgeFeatureUpgrade: legacy v1 chunks return early for any v1
  // bridge. Keep that outer version so an old chunk cannot downgrade this
  // implementation, and use a feature revision to replace an older v1 closure.
  if (installedVersion > BRIDGE_VERSION ||
      (installedVersion === BRIDGE_VERSION &&
       installedSemanticReplayRevision >= SEMANTIC_REPLAY_REVISION)) return;
  Object.defineProperty(globalThis, "__TiqianLayoutWorker", {
    configurable: true,
    value: Object.freeze({
      version: BRIDGE_VERSION,
      semanticReplayRevision: SEMANTIC_REPLAY_REVISION,
      take(_element, sessionKey, requestText) {
        const request = parsedLayoutRequest(requestText);
        if (!request) return null;
        const record = plans.get(preparedPlanKey(sessionKey, request));
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
      issue(_element, sessionKey, requestText) {
        const request = parsedLayoutRequest(requestText);
        if (!request) return null;
        const record = plans.get(preparedPlanKey(sessionKey, request));
        if (!record) return null;
        if (record.issue) return record.issue;
        return semanticReplay(request).issue ?? null;
      },
      release(sessionKey) {
        for (const key of plans.keys()) {
          if (key.startsWith(`${sessionKey}\u0000`)) plans.delete(key);
        }
        if (!initializedSessions.delete(sessionKey) || !coordinator.worker) return false;
        void send({ type: "release", sessionKey }).catch(() => {});
        return true;
      },
    }),
    writable: false,
  });
}

installBridge();

export async function prepareWorkerLayouts(
  root,
  exactFontSession,
  options,
  isCurrent = () => true,
) {
  if (!root || !exactFontSession || !isCurrent()) return 0;
  const api = globalThis.TiqianWeb;
  if (typeof api?.workerLayoutRequest !== "function") return 0;
  const contract = browserFontSessionWorkerContract(exactFontSession);
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
  const candidates = Array.from(root.querySelectorAll(paragraphSelector))
    .filter((element) => element.closest(ROOT_SELECTOR) === root)
    .map((element, index) => ({ element, index, distance: distanceFromViewport(element) }))
    .sort((left, right) => left.distance - right.distance || left.index - right.index);
  await ensureSession(contract);
  if (!isCurrent()) return 0;
  let prepared = 0;
  let sliceStartedAt = performance.now();
  for (const { element } of candidates) {
    if (!isCurrent()) break;
    let request;
    try {
      const serialized = api.workerLayoutRequest(root, element, options);
      if (!serialized) continue;
      request = JSON.parse(serialized);
    } catch {
      // ParagraphAtomicNativeRollback: an invalid candidate remains native
      // without preventing later independent paragraphs from being prepared.
      continue;
    }
    sliceStartedAt = await yieldMainIfNeeded(sliceStartedAt);
    if (!isCurrent()) break;
    let result;
    try {
      result = await send({ type: "layout", sessionKey: contract.sessionKey, request });
    } catch (error) {
      // ExactWorkerFailureMustStayNative: falling back to synchronous Kotlin/JS
      // recreates the navigation/scroll stall this Worker exists to remove,
      // especially under Edge's enhanced-security JIT restrictions. Publish a
      // per-request capability issue for the main-thread coordinator instead;
      // it will retain the paragraph's untouched source DOM.
      plans.set(preparedPlanKey(contract.sessionKey, request), {
        issue: String(error instanceof Error ? error.message : error).slice(0, 1_000),
      });
      continue;
    }
    if (!isCurrent()) break;
    plans.set(preparedPlanKey(contract.sessionKey, request), {
      plan: result.plan,
    });
    prepared += 1;
  }
  return prepared;
}
