import { loadTiqianRuntime } from "./runtime.js";
import { installTiqianCopyHandler } from "./copy.js";
import {
  DEFAULT_TYPOGRAPHY_FONT_WAIT_MS,
  detachLoadedSnapshot,
  fontLoadingAffectsTypography,
  isLoadedSnapshotAdopted,
  lineLengthGridMeasure,
  loadedAdoptedSnapshotLiveIssue,
  loadedSnapshotMaximumMeasureMatches,
  needsCjkDashShaping,
  prepareCjkDashShapingIfNeeded,
  restoreLoadedSnapshot,
  tryAdoptRequestedSnapshot,
  waitForTypographyFonts,
} from "./lazy-capabilities.js";
import { ensureTiqianStyles } from "./styles.js";
import { prefetchSnapshotTables } from "./snapshot-tables.js";
import {
  captureViewportAnchor,
  compensateViewportAnchor,
  releaseNativeScrollAnchoring,
} from "./viewport-anchor.js";

const ELEMENT_NAME = "tiqian-prose";
const DEFAULT_PARAGRAPH_SELECTOR = "p, li";
const ROOT_SELECTOR = `${ELEMENT_NAME}, [data-tiqian-root]`;
const SKIPPED_ANCESTOR_SELECTOR =
  ".not-prose, pre, table, .katex, .katex-display, .expressive-code, .tq-paragraph, [data-tiqian-skip]";
const EXACT_RENDER_FONT_ATTRIBUTE = "data-tiqian-exact-render-font";
const EXACT_PREPARED_FALLBACK_ATTRIBUTE = "data-tiqian-exact-layout-fallback";
const RESPONSIVE_SNAPSHOT_GEOMETRY_MISSES = new Set([
  "SnapshotWidthMismatch",
  "SnapshotWidthChangedDuringValidation",
]);
const HTMLElementBase = typeof globalThis.HTMLElement === "function"
  ? globalThis.HTMLElement
  : class TiqianSsrElement {};
let exactFontFallbackPromise;
installTiqianCopyHandler();
// Station-table loads start at module evaluation, ahead of the first root
// hydrating (ADR 0052 `TableTransport`); the scan is document-guarded and a
// no-op in non-browser entry points.
prefetchSnapshotTables();
const TYPOGRAPHY_PROPERTIES = [
  "display",
  "font-family",
  "font-size",
  "font-weight",
  "font-style",
  "font-stretch",
  "font-size-adjust",
  "font-variant-alternates",
  "font-variant-caps",
  "font-variant-east-asian",
  "font-variant-ligatures",
  "font-variant-numeric",
  "font-variant-position",
  "font-language-override",
  "font-variation-settings",
  "font-feature-settings",
  "font-kerning",
  "font-optical-sizing",
  "letter-spacing",
  "word-spacing",
  "line-height",
  "text-indent",
  "text-transform",
  "text-rendering",
  "direction",
  "writing-mode",
  "margin-left",
  "margin-right",
  "border-left-width",
  "border-right-width",
  "padding-left",
  "padding-right",
  "position",
  "top",
  "bottom",
  "vertical-align",
  "box-decoration-break",
  "transform",
  "column-count",
  "column-width",
  "zoom",
];
const TYPOGRAPHY_PSEUDO_SELECTORS = [
  "::before",
  "::after",
  "::first-letter",
  "::first-line",
];
const ROOT_VIEWPORT_TYPOGRAPHY_PROPERTIES = TYPOGRAPHY_PROPERTIES.filter(
  (property) => property !== "margin-left" && property !== "margin-right",
);

function dispatch(name, root, options = undefined) {
  document.dispatchEvent(
    new CustomEvent(name, {
      detail: { root, ...(options ? { options } : {}) },
    }),
  );
}

function nextFrame() {
  return new Promise((resolve) => requestAnimationFrame(resolve));
}

// CssFragmentedBlockInlineMeasure: plain getBoundingClientRect().width — for
// a block fragmented by CSS columns this is the union of every fragment, not
// a per-fragment measure. Every caller uses it only for coarse ≥0.5px drift
// detection, where the union error is dwarfed by the tolerance (see the ADR
// 0039 fractional fragment-aware amendment). A caller that needs the widest
// live fragment must use the elementContentWidth pattern in
// WebEnhancerSupport.kt instead of this function.
function fragmentedBorderBoxInlineSize(element) {
  if (!element) return 0;
  return Number(element.getBoundingClientRect?.().width) || 0;
}

function styleLengthPx(value) {
  return Number.parseFloat(value) || 0;
}

// Shared by the measure-signature builders: exact-font sessions measure the
// content box, browser-metric sessions the border box. Module scope keeps
// the AllocationFreeSignatureIteration promise — no per-paragraph closures.
function paragraphLayoutWidth(element, elementStyle, exactFontLayout) {
  const value = fragmentedBorderBoxInlineSize(element);
  if (!exactFontLayout) return value;
  return value - styleLengthPx(elementStyle.paddingLeft) - styleLengthPx(elementStyle.paddingRight) -
    styleLengthPx(elementStyle.borderLeftWidth) - styleLengthPx(elementStyle.borderRightWidth);
}

function belongsToRootScope(element, root) {
  return element.closest(ROOT_SELECTOR) === root;
}

function isPureBlockImageParagraph(element) {
  if (element.tagName !== "P" || (element.textContent ?? "").trim() !== "") return false;
  const children = Array.from(element.querySelectorAll(":scope > *"));
  if (children.length === 0) return false;
  const view = element.ownerDocument?.defaultView;
  const getStyle = view?.getComputedStyle ?? globalThis.getComputedStyle;
  if (typeof getStyle !== "function") return false;
  return children.every((child) =>
    child.tagName === "IMG" && getStyle.call(view, child).display.trim().toLowerCase() === "block"
  );
}

function rendererOwnedProgressiveStyleMutation(record, root) {
  if (record.attributeName !== "style") return false;
  const target = record.target;
  if (
    !(target instanceof HTMLElement) || !target.matches("p[data-tq-rendered=true], li[data-tq-rendered=true]") ||
    !belongsToRootScope(target, root)
  ) return false;

  const previous = document.createElement(target.tagName);
  if (record.oldValue != null) previous.setAttribute("style", record.oldValue);
  const projected = document.createElement(target.tagName);
  const current = target.getAttribute("style");
  if (current != null) projected.setAttribute("style", current);
  let rendererPropertyFound = false;
  if (
    projected.style.getPropertyValue("position") === "relative" &&
    projected.style.getPropertyPriority("position") === "important"
  ) {
    rendererPropertyFound = true;
    const value = previous.style.getPropertyValue("position");
    if (value) {
      projected.style.setProperty("position", value, previous.style.getPropertyPriority("position"));
    } else {
      projected.style.removeProperty("position");
    }
  }
  if (
    target.getAttribute("data-tq-host-inline-size") === "true" &&
    projected.style.getPropertyPriority("inline-size") === "important"
  ) {
    rendererPropertyFound = true;
    const value = previous.style.getPropertyValue("inline-size");
    if (value) {
      projected.style.setProperty(
        "inline-size",
        value,
        previous.style.getPropertyPriority("inline-size"),
      );
    } else {
      projected.style.removeProperty("inline-size");
    }
  }
  return rendererPropertyFound && projected.style.cssText === previous.style.cssText;
}

function isRuntimeCompletionCandidate(element, root) {
  if (!belongsToRootScope(element, root)) return false;
  if (element.closest(SKIPPED_ANCESTOR_SELECTOR)) return false;
  // PureBlockImageParagraphExclusion must match the Kotlin runtime candidate
  // set so an image-only root does not load layout code merely to do no work.
  if (isPureBlockImageParagraph(element)) return false;
  if (
    element.tagName === "LI" &&
    element.querySelector(":scope > p, :scope > ul, :scope > ol, :scope > blockquote, :scope > pre, :scope > table")
  ) return false;
  return true;
}

function snapshotCompletionSelector(root) {
  const selector = ":is(p, li):not([data-tq-snapshot-key])";
  return Array.from(root.querySelectorAll(selector))
    .some((paragraph) => isRuntimeCompletionCandidate(paragraph, root))
    ? selector
    : "";
}

function loadExactFontFallback() {
  exactFontFallbackPromise ??= Promise.all([
    import("./browser-fonts.js"),
    import("./prepared-dom.js"),
  ]).then(([fonts, preparedDom]) => {
    preparedDom.installPreparedDomRendererBridge();
    return {
      prepareBrowserFontSession: fonts.prepareBrowserFontSession,
      revalidateBrowserFontSession: fonts.revalidateBrowserFontSession,
      prepareBrowserRenderFonts: fonts.prepareBrowserRenderFonts,
      releaseBrowserFontSession: fonts.releaseBrowserFontSession,
      installPreparedRenderFontStyle: preparedDom.installPreparedRenderFontStyle,
      releasePreparedRenderFontStyle: preparedDom.releasePreparedRenderFontStyle,
    };
  });
  return exactFontFallbackPromise;
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
function sumPendingUpTo(slot, tier) {
  let total = 0;
  for (let t = 0; t < tier; t++) total += slot.pendingByTier[t];
  return total;
}

class TiqianLayoutCoordinator {
  #entries = new Map();
  // OffscreenDebounceGate: when an element is outside the viewport, its frame
  // tasks wait in this deferred lane. Each repeated request while the element
  // stays off-screen pushes the task's due time further out, so a fast drag
  // keeps postponing layout work for elements the user cannot see. One
  // shared timer moves due tasks back into the normal frame loop, where the
  // anti-starvation aging rules still apply. When an element returns to the
  // viewport, its pending task is promoted immediately, so visible content
  // never waits out the debounce.
  #deferred = new Map();
  #deferredTimer = 0;
  #workerSlots = [];
  #workerWakeTimer = 0;
  #frameCounter = 0;

  register(element) {
    this.#entries.set(element, { inViewport: true });
  }

  unregister(element) {
    this.#dropDeferred(element);
    this.#removeWorkerSlot(element);
    this.#entries.delete(element);
  }

  update(element, { inViewport, area, inlineSize, visibleArea, intersectionRatio }) {
    let entry = this.#entries.get(element);
    if (!entry) {
      entry = {
        inViewport: inViewport ?? true,
        area: area ?? 0,
        inlineSize: inlineSize ?? 0,
        visibleArea: visibleArea ?? 0,
        intersectionRatio: intersectionRatio ?? 1.0,
      };
      this.#entries.set(element, entry);
    }
    const wasInViewport = entry.inViewport;
    if (inViewport !== undefined) entry.inViewport = inViewport;
    if (area !== undefined) entry.area = area;
    if (inlineSize !== undefined) entry.inlineSize = inlineSize;
    if (visibleArea !== undefined) entry.visibleArea = visibleArea;
    if (intersectionRatio !== undefined) entry.intersectionRatio = intersectionRatio;
    if (inViewport === true && !wasInViewport) {
      this.#promoteDeferred(element);
    }
  }

  remove(element) {
    this.#dropDeferred(element);
    this.#removeWorkerSlot(element);
    this.#entries.delete(element);
  }

  #dropDeferred(element) {
    if (!this.#deferred.delete(element)) return;
    if (this.#deferred.size === 0 && this.#deferredTimer) {
      clearTimeout(this.#deferredTimer);
      this.#deferredTimer = 0;
    }
  }

  #promoteDeferred(element) {
    const bucket = this.#deferred.get(element);
    if (!bucket) return;
    this.#deferred.delete(element);
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

  #flushDeferred = () => {
    this.#deferredTimer = 0;
    const now = Date.now();
    let nextDueAt = Infinity;
    const deferredBuckets = Array.from(this.#deferred.entries());
    for (let i = 0; i < deferredBuckets.length; i++) {
      const element = deferredBuckets[i][0];
      const bucket = deferredBuckets[i][1];
      if (bucket.dueAt <= now) {
        this.#deferred.delete(element);
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

  #callbacks = new Map();
  #rafId = 0;
  #budgetMs = 6.0;
  #lastFrameTimestamp = 0;
  #hasFrameTimestamp = false;
  #measuredFrameInterval = 16.67;
  #immediateWindowStart = -Infinity;
  #immediateSpentMs = 0;

  #runFrameLoop = (now) => {
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
        const entryA = a.element ? this.#entries.get(a.element) : null;
        const entryB = b.element ? this.#entries.get(b.element) : null;

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
    // clocks never mix. Coarse lanes such as debounce due times and duration
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
  #traceFrame(now, executedCount, workerGrants) {
    const trace = globalThis.__tqTrace;
    if (!trace) return;
    const ring = globalThis.__tqFrameTrace ?? (globalThis.__tqFrameTrace = []);
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
    ]);
    const maxEntries = trace.maxEntries ?? 600;
    if (ring.length > maxEntries) ring.splice(0, ring.length - maxEntries);
  }

  // AdaptiveGrantQuota feedback pass: the constant block above holds the
  // full contract. This runs before any task or grant of the new frame, so
  // the quota a grant reads already carries the previous frame's verdict.
  // The verdict is per slot but the frame delta is shared: native follow-up
  // cost cannot be split by root, so every root that committed in the slow
  // frame is judged. An innocent neighbour recovers its headroom at one
  // quota step per frame.
  #applyGrantQuotaFeedback(frameDelta) {
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

  requestFrame(callback, element = null) {
    const existing = this.#callbacks.get(callback);
    const task = {
      callback,
      element,
      deferCount: existing ? existing.deferCount : 0,
    };
    const entry = element && this.#entries.get(element);
    if (entry && !entry.inViewport) {
      // OffscreenRequestQueue: one element can have several distinct
      // callbacks pending while off screen (initial enhance plus responsive
      // commits). Keep every callback per element; a single slot would let
      // the newest request silently drop the older ones.
      let bucket = this.#deferred.get(element);
      if (!bucket) {
        bucket = { dueAt: 0, tasks: new Map() };
        this.#deferred.set(element, bucket);
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

  cancelFrame(callback) {
    this.#callbacks.delete(callback);
    const deferredBuckets = Array.from(this.#deferred.entries());
    for (let i = 0; i < deferredBuckets.length; i++) {
      const element = deferredBuckets[i][0];
      const bucket = deferredBuckets[i][1];
      bucket.tasks.delete(callback);
      if (bucket.tasks.size === 0) this.#dropDeferred(element);
    }
    if (this.#callbacks.size === 0 && this.#rafId) {
      cancelAnimationFrame(this.#rafId);
      this.#rafId = 0;
    }
  }

  registerWorker(element, runtime) {
    for (let i = 0; i < this.#workerSlots.length; i++) {
      if (this.#workerSlots[i].element === element) {
        this.#workerSlots[i].runtime = runtime;
        return;
      }
    }
    this.#workerSlots.push({
      element,
      runtime,
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
  // allowance; once it is spent, later callers fall back to the scheduled
  // lane. Remaining tiers stay with the polled frame loop.
  grantImmediate(element) {
    let slot = null;
    for (let i = 0; i < this.#workerSlots.length; i++) {
      if (this.#workerSlots[i].element === element) {
        slot = this.#workerSlots[i];
        break;
      }
    }
    if (!slot || typeof slot.runtime?.workerRunSlice !== "function") return false;
    if (!slot.runtime.workerHasJob(element)) return false;
    const now = performance.now();
    if (now - this.#immediateWindowStart > IMMEDIATE_GRANT_WINDOW_MS) {
      this.#immediateWindowStart = now;
      this.#immediateSpentMs = 0;
    }
    // The pre-paint lane trades directly against this frame's paint
    // headroom, so it may spend up to half the measured frame interval;
    // the shared window serializes concurrent roots.
    const ceiling = Math.max(this.#budgetMs, this.#measuredFrameInterval * 0.5);
    const allowance = ceiling - this.#immediateSpentMs;
    if (allowance <= 0) return false;
    const generation = slot.runtime.workerJobGeneration(element);
    const quota = slot.quota;
    const grantDeadline = Date.now() + allowance;
    let processed = 0;
    const viewportAnchor = captureViewportAnchor(element);
    try {
      // Drain the in-viewport tier like a polled grant round: one slice per
      // quota batch until the tier is empty or the allowance is spent, so a
      // root whose visible paragraph count exceeds the adaptive quota still
      // commits atomically before this frame paints.
      while (Date.now() < grantDeadline) {
        const sliceProcessed = slot.runtime.workerRunSlice({
          root: element,
          generation,
          deadline: grantDeadline,
          quota,
          shouldStop(processedCount) {
            return processedCount >= quota || Date.now() >= grantDeadline;
          },
        }, 1);
        processed += sliceProcessed;
        if (sliceProcessed === 0) break;
        if (slot.runtime.workerPendingInTier(element, 1) === 0) break;
      }
    } finally {
      this.#immediateSpentMs += performance.now() - now;
    }
    if (processed > 0) {
      compensateViewportAnchor(element, viewportAnchor);
      slot.deferCount = 0;
      slot.lastGrantFrame = this.#frameCounter;
    }
    slot.active = slot.runtime.workerHasJob(element);
    if (!slot.active) releaseNativeScrollAnchoring(element);
    slot.pendingByTier[0] = slot.runtime.workerPendingInTier(element, 1);
    slot.pendingByTier[1] = slot.runtime.workerPendingInTier(element, 2);
    slot.pendingByTier[2] = slot.runtime.workerPendingInTier(element, 3);
    return processed > 0;
  }

  #removeWorkerSlot(element) {
    const slots = this.#workerSlots;
    for (let i = 0; i < slots.length; i++) {
      if (slots[i].element !== element) continue;
      slots[i] = slots[slots.length - 1];
      slots.pop();
      break;
    }
    if (slots.length === 0 && this.#workerWakeTimer) {
      clearTimeout(this.#workerWakeTimer);
      this.#workerWakeTimer = 0;
    }
  }

  setWorkerActive(element, active) {
    const slot = this.#findWorkerSlot(element);
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
  refreshWorkerDeferred(element) {
    const slot = this.#findWorkerSlot(element);
    if (slot) slot.deferredUntil = Date.now() + OFFSCREEN_DEBOUNCE_MS;
  }

  clearWorkerDeferred(element) {
    const slot = this.#findWorkerSlot(element);
    if (!slot) return;
    slot.deferredUntil = 0;
    if (!this.#rafId) {
      this.#rafId = requestAnimationFrame(this.#runFrameLoop);
    }
  }

  requestWorkerFrame(element) {
    if (!this.#rafId) {
      this.#rafId = requestAnimationFrame(this.#runFrameLoop);
    }
  }

  #findWorkerSlot(element) {
    for (let i = 0; i < this.#workerSlots.length; i++) {
      if (this.#workerSlots[i].element === element) return this.#workerSlots[i];
    }
    return null;
  }

  #compareWorkerSlots = (a, b) => {
    const entryA = this.#entries.get(a.element);
    const entryB = this.#entries.get(b.element);
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

  #pollWorkers(startTime, executedCount) {
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
      if (slot.runtime.workerHasJob(slot.element)) {
        slot.active = true;
        slot.generation = slot.runtime.workerJobGeneration(slot.element);
        slot.pendingByTier[0] = slot.runtime.workerPendingInTier(slot.element, 1);
        slot.pendingByTier[1] = slot.runtime.workerPendingInTier(slot.element, 2);
        slot.pendingByTier[2] = slot.runtime.workerPendingInTier(slot.element, 3);
      } else {
        slot.active = false;
        slot.generation = 0;
        slot.pendingByTier[0] = 0;
        slot.pendingByTier[1] = 0;
        slot.pendingByTier[2] = 0;
        // NativeAnchoringHandover: the job is over; hand the scroller back to
        // the browser's own anchoring until the next slice commits.
        releaseNativeScrollAnchoring(slot.element);
      }
    }
    slots.sort(this.#compareWorkerSlots);
    let visibleCount = 0;
    while (visibleCount < slots.length && this.#entries.get(slots[visibleCount].element)?.inViewport) {
      visibleCount += 1;
    }
    let grants = 0;
    let workDone = executedCount;
    const grantSlot = (slot, tier) => {
      // SliceCommitAnchorCompensation: every slice this grant runs happens in
      // this same task, so one capture/compensate pair around the drain sees
      // the pure layout displacement of all its commits.
      let viewportAnchor = null;
      let anchorCaptured = false;
      let grantProcessed = 0;
      const finish = (result) => {
        if (grantProcessed > 0) compensateViewportAnchor(slot.element, viewportAnchor);
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
          viewportAnchor = captureViewportAnchor(slot.element);
        }
        const processed = slot.runtime.workerRunSlice({
          root: slot.element,
          generation: slot.generation,
          deadline: grantDeadline,
          quota,
          shouldStop(processedCount) {
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
        slot.pendingByTier[0] = slot.runtime.workerPendingInTier(slot.element, 1);
        slot.pendingByTier[1] = slot.runtime.workerPendingInTier(slot.element, 2);
        slot.pendingByTier[2] = slot.runtime.workerPendingInTier(slot.element, 3);
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

  #retainWorkerFrame() {
    const slots = this.#workerSlots;
    const now = Date.now();
    let keepFrames = false;
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
      if (this.#entries.get(slot.element)?.inViewport) {
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

  #flushWorkerWake = () => {
    this.#workerWakeTimer = 0;
    if (!this.#rafId) {
      this.#rafId = requestAnimationFrame(this.#runFrameLoop);
    }
  };
}

const coordinator = new TiqianLayoutCoordinator();

class TiqianProseElement extends HTMLElementBase {
  static observedAttributes = [
    "disabled",
    "emphasis-dot-gap-em",
    "strong-as-emphasis-marks",
    "snapshot-ref",
  ];

  #forceTypographyRefresh = false;
  #acceptLayoutCompletion = false;
  #boundResponsiveCommit = () => {
    if (this.isConnected) this.#commitResponsiveGeometryChange();
  };
  #connected = false;
  #custodyReentry = false;
  #detachAttributeSnapshot = null;
  #layoutWorkIsRelayout = false;
  #lastCommittedParagraphMeasures = "";
  #contentObserver = null;
  #custodyTargets = new Map();
  #contentProbeFrame = 0;
  #contentReconcileRequired = false;
  #contentTainted = new Set();
  #deferredTypographyCheck = false;
  #fontLoadingSettledListener = null;
  #geometryRevision = 0;
  #generation = 0;
  #hasDispatched = false;
  #inViewport = true;
  #initialFontRetryListener = null;
  #initialFontRetryObserver = null;
  #initialFontRetryToken = 0;
  #intersectionObserver = null;
  #layoutWorkInFlight = false;
  #layoutWorkerAttached = false;
  #layoutWorkSignaturesCaptured = false;
  #layoutWorkGeometrySignature = "";
  #layoutWorkMaximumMeasure = false;
  #layoutWorkMeasureSignature = "";
  #layoutWorkTypographySignature = "";
  #layoutWorkViewportTypographyEntries = [];
  #layoutWorkTypographyObserver = null;
  #layoutWorkFontLoadingSettledListener = null;
  #layoutWorkUsesCapturedMeasure = false;
  #layoutOperation = 0;
  #layoutWorkRevision = 0;
  #enhanceRequest = 0;
  #exactFontRejectedAttempt = "";
  #exactFontSession = null;
  #lastObservedWidth = 0;
  #lastWidth = 0;
  #lastParagraphMeasures = "";
  #lastParagraphWidths = "";
  #lastTypography = "";
  #paragraphObserver = null;
  #paragraphTierIndex = new Map();
  #readyListener = null;
  #resizeFrame = 0;
  #resizeObserver = null;
  #resizeObserverFrame = 0;
  #resizeObserverWidths = null;
  #paragraphGridMetrics = null;
  #paragraphGridRootFontSize = "";
  #pendingCommittedMeasures = "";
  #responsiveCommitRequired = false;
  #responsiveRetargetFrame = 0;
  #responsiveRelayoutRequired = false;
  #runtimeStateActive = false;
  #snapshotAdopted = false;
  #snapshotEnhancedCount = 0;
  #typographyFrame = 0;
  #typographyObserver = null;
  #viewportResizeListener = null;

  get disabled() {
    return this.hasAttribute("disabled");
  }

  set disabled(value) {
    this.toggleAttribute("disabled", Boolean(value));
  }

  get emphasisDotGapEm() {
    const value = Number.parseFloat(this.getAttribute("emphasis-dot-gap-em"));
    return Number.isFinite(value) ? value : null;
  }

  set emphasisDotGapEm(value) {
    if (value == null) {
      this.removeAttribute("emphasis-dot-gap-em");
    } else {
      this.setAttribute("emphasis-dot-gap-em", String(value));
    }
  }

  get strongAsEmphasisMarks() {
    return this.hasAttribute("strong-as-emphasis-marks");
  }

  set strongAsEmphasisMarks(value) {
    this.toggleAttribute("strong-as-emphasis-marks", Boolean(value));
  }

  get snapshotRef() {
    return this.getAttribute("snapshot-ref");
  }

  set snapshotRef(value) {
    if (value == null) {
      this.removeAttribute("snapshot-ref");
    } else {
      this.setAttribute("snapshot-ref", String(value));
    }
  }

  connectedCallback() {
    coordinator.register(this);
    this.#observeIntersection();
    if (this.#canAdoptCustodyMoveReconnection()) {
      this.#adoptCustodyMoveReconnection();
      return;
    }
    // ReconnectedSourceReclamation: detached roots keep their source backing in
    // weak runtime/snapshot state so navigation can discard them without
    // rebuilding an invisible old article. A real reconnection is the one case
    // that needs to pay the restoration cost before starting a new lifecycle.
    if (!this.#connected) {
      if (isLoadedSnapshotAdopted(this)) restoreLoadedSnapshot(this);
      if (this.#runtimeStateActive) dispatch("tiqian:destroy", this);
      this.#runtimeStateActive = false;
    }
    this.#connected = true;
    this.#clearLifecycleDiagnostics();
    // ReversibleDisabledEnhancement: the Boolean attribute is the complete
    // opt-out contract. Keep semantic SSR children live and avoid stylesheet,
    // font, snapshot, runtime and observer work until the host removes it.
    if (this.disabled) return;
    this.#exactFontRejectedAttempt = "";
    const generation = ++this.#generation;
    this.#clearInitialFontRetry();
    this.#acceptLayoutCompletion = false;
    this.#hasDispatched = false;
    this.#snapshotAdopted = isLoadedSnapshotAdopted(this);
    this.#snapshotEnhancedCount = 0;
    const loadStartedAt = Date.now();
    let initialReadyReported = false;
    // OptInStrongSnapshotExclusion: v1 snapshots contain only plain paragraphs,
    // so they cannot claim that a semantic <strong> was lowered to emphasis
    // marks. Keep the default bold path eligible for snapshots; an explicit
    // mapping request with actual <strong> content must enter the runtime.
    const strongEmphasisRuntimeRequired =
      this.strongAsEmphasisMarks && this.querySelector("strong") !== null;
    // SnapshotFirstInputBeforeRuntimeCompile: even a mixed root can prove and
    // display its keyed snapshot without Kotlin. Under Edge JITless, eagerly
    // importing the full runtime for one unkeyed paragraph delays the first
    // wheel event before adoption has even started. Load it only after a
    // successful snapshot reports that completion is still required.
    const runtimePromise = this.hasAttribute("snapshot-ref") &&
        !strongEmphasisRuntimeRequired
      ? null
      : loadTiqianRuntime();
    runtimePromise?.catch(() => {});
    this.#removeReadyListener();
    this.#stopTypographyObservation();
    this.#readyListener = (event) => {
      if (
        generation !== this.#generation || !this.#hasDispatched ||
        !this.#acceptLayoutCompletion
      ) return;
      const detail = event.detail ?? {};
      if (this.#snapshotAdopted && this.#snapshotEnhancedCount > 0) {
        const snapshotCount = this.#snapshotEnhancedCount;
        const runtimeEnhancedCount = detail.snapshot
          ? 0
          : Number.isFinite(detail.runtimeEnhancedCount)
            ? detail.runtimeEnhancedCount
            : Number.isFinite(detail.snapshotCount)
              ? Math.max(0, (Number(detail.enhancedCount) || 0) - snapshotCount)
              : Math.max(0, Number(detail.enhancedCount) || 0);
        const enhancedCount = runtimeEnhancedCount + snapshotCount;
        this.dataset.tiqianSnapshotCount = String(this.#snapshotEnhancedCount);
        this.setAttribute("data-tiqian-enhanced-count", String(enhancedCount));
        try {
          detail.runtimeEnhancedCount = runtimeEnhancedCount;
          detail.snapshotCount = snapshotCount;
          detail.enhancedCount = enhancedCount;
        } catch {
          // The root attributes remain the stable observable count contract if a
          // host supplied a frozen CustomEvent detail object.
        }
      }
      const { durationMs, maxSliceMs, relayout, stale } = detail;
      if (relayout) {
        if (Number.isFinite(durationMs)) this.dataset.tiqianRelayoutMs = durationMs.toFixed(1);
        if (Number.isFinite(maxSliceMs)) {
          this.dataset.tiqianRelayoutMaxSliceMs = maxSliceMs.toFixed(1);
        }
        // CommittedMeasureLedger: forced commits (viewport revalidation,
        // stale follow-ups) skip against what the last clean relayout
        // actually committed, never against dispatch-time bookkeeping. The
        // runtime reports content reconciles through this same event kind,
        // so only jobs this element dispatched as width relayouts may move
        // the ledger.
        if (this.#layoutWorkIsRelayout) {
          if (!stale) {
            this.#lastCommittedParagraphMeasures = this.#pendingCommittedMeasures;
          } else {
            // A stale finish leaves a mix of old- and new-measure
            // paragraphs, which no single signature describes — a ledger
            // still holding the pre-mix cell would let a forced convergence
            // pass skip and strand the mix. Invalidate so the next forced
            // pass always dispatches.
            this.#lastCommittedParagraphMeasures = "";
          }
        }
      } else {
        if (Number.isFinite(durationMs)) this.dataset.tiqianEnhanceMs = durationMs.toFixed(1);
        if (Number.isFinite(maxSliceMs)) this.dataset.tiqianMaxSliceMs = maxSliceMs.toFixed(1);
        if (!initialReadyReported) {
          initialReadyReported = true;
          this.dataset.tiqianLoadMs = (Date.now() - loadStartedAt).toFixed(1);
        }
      }
      // ExactPreparedDomFallbackSingleFlight: once browser replay proves that
      // the exact HarfBuzz result cannot be represented at this effective
      // measure, retain the readable browser-metric rendering without letting
      // font loading events start the same failed exact session indefinitely.
      // A route reconnect or a different line-length grid gets a fresh attempt.
      if (this.hasAttribute(EXACT_PREPARED_FALLBACK_ATTRIBUTE)) {
        this.#exactFontRejectedAttempt = this.#exactFontAttemptSignature();
        // ResponsiveExactFontSessionReuse: the server replay tables and host
        // font proof are still valid; only this line measure failed DOM replay.
        // Retain the session so a later grid can revalidate without rebuilding
        // the replay corpus. Disconnect and snapshot adoption remain the owners
        // of final release.
        this.removeAttribute(EXACT_RENDER_FONT_ATTRIBUTE);
      }
      if (stale) this.#responsiveCommitRequired = true;
      if (stale) this.#responsiveRelayoutRequired = true;
      this.#finishLayoutWorkAndObserve();
    };
    this.addEventListener("tiqian:ready", this.#readyListener);
    this.addEventListener("tiqian:relayout-ready", this.#readyListener);
    this.#ensureViewportResizeListener();

    // DeferredEnhanceErrorContract: one failure handler serves the load chain
    // below and the frame task it queues. The coordinator's frame loop guards
    // its callbacks with a synchronous try/catch, which cannot observe an
    // async task's rejection, and the chain's own .catch resolved the moment
    // the task was queued — so without routing the task's rejection here, a
    // runtime import or enhance failure inside the frame task became an
    // unhandled rejection: no RuntimeLoadFailed marker, the ready listener
    // left attached, and consumers awaiting tiqian:ready hanging forever.
    const failInitialEnhance = (error) => {
      if (generation !== this.#generation) return;
      this.#acceptLayoutCompletion = false;
      this.#layoutWorkInFlight = false;
      this.#layoutWorkViewportTypographyEntries = [];
      this.#clearResponsiveRetarget();
      this.#releaseExactFontSession();
      if (!isLoadedSnapshotAdopted(this)) this.removeAttribute(EXACT_RENDER_FONT_ATTRIBUTE);
      this.#removeReadyListener();
      this.dataset.tiqianCapabilityIssue = "RuntimeLoadFailed";
      console.warn("Tiqian Web runtime failed to load", error);
    };
    // HostCascadeReadyGate: connectedCallback may run before an app's
    // module-loaded styles have reached the cascade. Once Tiqian's own stylesheet
    // is ready, one frame lets the parser and host cascade settle; then load only
    // the faces used by the prose and wait one painted frame. Waiting for global
    // DOMContentLoaded or document.fonts.ready would stall prose on unrelated
    // scripts, icon fonts, code fonts, or widgets.
    ensureTiqianStyles(this)
      .then(nextFrame)
      // Snapshot validation loads and probes the exact declared faces itself.
      // Repeating a per-paragraph computed-style scan here delayed the first
      // layout read and did no additional validation work.
      .then(async () => {
        if (!this.isConnected || generation !== this.#generation) return false;
        if (this.hasAttribute("snapshot-ref") && !strongEmphasisRuntimeRequired) return true;
        const fontWait = await waitForTypographyFonts(
          document.fonts,
          this.#typographyElements(),
          globalThis.getComputedStyle,
          { timeoutMs: DEFAULT_TYPOGRAPHY_FONT_WAIT_MS },
        );
        if (!this.isConnected || generation !== this.#generation) return false;
        if (fontWait.status !== "timeout") return true;
        // BoundedInitialFontGate: a slow or stuck FontFaceSet must not leave an
        // invisible transition in flight. Native SSR remains authoritative;
        // the exact completion promise and relevant font/style events restart
        // the whole gate against the latest host state.
        this.dataset.tiqianFontWait = "timeout";
        this.#deferInitialEnhancementUntilFontsSettle(generation, fontWait.completion);
        return false;
      })
      .then((fontGateOpen) => fontGateOpen ? nextFrame().then(() => true) : false)
      .then(async (fontGateOpen) => {
        if (!fontGateOpen) return;
        if (!this.isConnected || generation !== this.#generation) return;
        const runInitialEnhance = async () => {
          if (!this.isConnected || generation !== this.#generation) return;
          const enhanceStartedAt = Date.now();
          const operation = this.#beginLayoutWork({ captureSignatures: false });
          let snapshot = { adopted: false };
          try {
            if (!strongEmphasisRuntimeRequired) {
              snapshot = await tryAdoptRequestedSnapshot(
                this,
                () => this.isConnected && generation === this.#generation &&
                  operation === this.#layoutOperation,
              );
            }
          } catch (error) {
            this.dataset.tiqianSnapshotMiss = "SnapshotValidationFailed";
            console.warn("Tiqian Web maximum-measure snapshot validation failed", error);
          }
          if (
            !this.isConnected || generation !== this.#generation ||
            operation !== this.#layoutOperation
          ) {
            if (snapshot.adopted) restoreLoadedSnapshot(this);
            return;
          }
          if (snapshot.adopted) {
            delete this.dataset.tiqianSnapshotMiss;
            this.#snapshotAdopted = true;
            this.#snapshotEnhancedCount = snapshot.count;
            // MixedSnapshotRuntimeCompletion: the snapshot owns only keyed
            // paragraphs. Runtime-only prose remains semantic source and is
            // enhanced through the same Kotlin pipeline without discarding valid
            // server geometry for its keyed siblings.
            const completionSelector = snapshotCompletionSelector(this);
            if (completionSelector) {
              await (runtimePromise ?? loadTiqianRuntime());
              if (!this.isConnected || generation !== this.#generation) {
                return;
              }
              this.#acceptValidatedSnapshotGeometry();
              await this.#dispatchProgressiveEnhance(generation, {
                paragraphSelector: completionSelector,
              });
              return;
            }
            if (!this.#runtimeStateActive) this.#releaseExactFontSession();
            this.#hasDispatched = true;
            this.#acceptLayoutCompletion = true;
            this.#acceptValidatedSnapshotGeometry();
            this.dispatchEvent(new CustomEvent("tiqian:ready", {
              bubbles: true,
              composed: true,
              detail: {
                enhancedCount: snapshot.count,
                issueCount: 0,
                durationMs: Date.now() - enhanceStartedAt,
                maxSliceMs: 0,
                snapshot: true,
              },
            }));
            return;
          }
          this.dataset.tiqianSnapshotMiss = snapshot.reason ?? "SnapshotNotAdopted";
          await (runtimePromise ?? loadTiqianRuntime());
          if (!this.isConnected || generation !== this.#generation) return;
          if (!(await this.#dispatchProgressiveEnhance(generation))) return;
        };
        coordinator.requestFrame(() => {
          runInitialEnhance().catch(failInitialEnhance);
        }, this);
      })
      .catch(failInitialEnhance);
  }

  disconnectedCallback() {
    this.#connected = false;
    // CustodyMoveTeardownDeferral: React, Svelte and other reconcilers move a
    // node by removing and re-inserting it inside one synchronous commit.
    // Settling the disconnection synchronously destroys a rendered article
    // that never left host custody, so the settle runs one microtask later.
    // A same-task reconnection then re-enters the live lifecycle through
    // CustodyMoveAdoption. A real navigation settles exactly as before, still
    // before the next frame. The remount variant of
    // resize-destroy-transient.test.mjs holds this contract.
    this.#custodyReentry = true;
    this.#detachAttributeSnapshot = TiqianProseElement.observedAttributes.map(
      (name) => this.getAttribute(name),
    );
    queueMicrotask(() => {
      this.#custodyReentry = false;
      this.#detachAttributeSnapshot = null;
      if (!this.isConnected) this.#settleDisconnection();
    });
  }

  #settleDisconnection() {
    coordinator.unregister(this);
    coordinator.cancelFrame(this.#boundResponsiveCommit);
    releaseNativeScrollAnchoring(this);
    this.#stopIntersectionObservation();
    this.#stopParagraphTierObservation();
    ++this.#generation;
    this.#enhanceRequest += 1;
    this.#layoutOperation += 1;
    this.#acceptLayoutCompletion = false;
    this.#hasDispatched = false;
    this.#layoutWorkInFlight = false;
    this.#layoutWorkViewportTypographyEntries = [];
    this.#responsiveCommitRequired = false;
    this.#responsiveRelayoutRequired = false;
    this.#clearResponsiveRetarget();
    this.#clearInitialFontRetry();
    delete this.dataset.tiqianFontWait;
    this.#removeReadyListener();
    this.#stopTypographyObservation();
    this.#stopLayoutWorkInputObservation();
    this.#stopWidthObservation();
    this.#stopContentObservation();
    // DetachedNavigationDisposal: swup and other HTML routers remove an entire
    // old article synchronously. Reconstructing every source paragraph here
    // blocks their scroll handoff and can visibly change the outgoing page.
    // Keep the backing in weak state for a possible reconnection, but cancel all
    // work and release document-scoped styles without touching detached DOM.
    if (this.#snapshotAdopted || isLoadedSnapshotAdopted(this)) {
      detachLoadedSnapshot(this);
    }
    if (this.#runtimeStateActive) dispatch("tiqian:detach", this);
    if (this.#layoutWorkerAttached) {
      // tiqian:detach already cancelled the job, so workerDetach has no
      // in-flight work to finish on this disconnected root.
      globalThis.TiqianWeb?.workerDetach?.(this);
      this.#layoutWorkerAttached = false;
    }
    this.#releaseExactFontSession();
    this.removeAttribute(EXACT_RENDER_FONT_ATTRIBUTE);
  }

  #canAdoptCustodyMoveReconnection() {
    if (this.#connected || !this.#custodyReentry) return false;
    if (!this.#runtimeStateActive || this.disabled) return false;
    if (this.#snapshotAdopted || isLoadedSnapshotAdopted(this)) {
      // Snapshot custody keeps the restore and re-adopt path. Its backing is
      // cheap to rebuild and shares document-scoped styles with the runtime.
      return false;
    }
    const snapshot = this.#detachAttributeSnapshot;
    if (snapshot == null) return false;
    return TiqianProseElement.observedAttributes.every(
      (name, index) => this.getAttribute(name) === snapshot[index],
    );
  }

  // CustodyMoveAdoption: a reconnection inside the deferred settle window is
  // a host custody move. The committed LayoutResult, the exact font session
  // and any in-flight job stayed valid through the move, so only the
  // observers and the geometry baseline need re-entry. A width change from
  // the move routes through the responsive commit lane and relayouts in
  // place; a changed font context routes through the typography check and
  // refreshes from source. Observed attribute edits during the gap reject
  // adoption and take the full restart path instead.
  #adoptCustodyMoveReconnection() {
    this.#custodyReentry = false;
    this.#detachAttributeSnapshot = null;
    this.#connected = true;
    this.#ensureViewportResizeListener();
    this.#observeWidth();
    this.#observeTypography();
    this.#observeContent();
    this.#lastObservedWidth = fragmentedBorderBoxInlineSize(this);
    this.#scheduleResponsiveGeometryCommit();
    this.#scheduleTypographyCheck();
  }

  attributeChangedCallback(name, oldValue, newValue) {
    if (oldValue === newValue) return;
    if (name === "disabled") {
      // DisabledAttributeOwnsTeardown: adding the attribute uses the same
      // source restoration and cancellation path as a connected lifecycle
      // restart; connectedCallback then stops before any new work. Removing it
      // re-enters the complete snapshot/runtime lifecycle from semantic source.
      if (this.#connected) this.#restartConnectedLifecycle();
      return;
    }
    if (name === "snapshot-ref") {
      // UpgradeAttributeReactionGuard: when an SSR element is defined after it
      // was parsed, the platform reports its existing observed attributes
      // before connectedCallback. `isConnected` is already true at that point,
      // but this is not a client navigation and must not discard the server's
      // exact-font marker.
      if (this.#connected) this.#restartConnectedLifecycle();
      return;
    }
    if (
      name !== "emphasis-dot-gap-em" &&
      name !== "strong-as-emphasis-marks"
    ) return;
    if (!this.isConnected) return;
    // LatestObservedAttributeGeneration: strong emphasis controls snapshot
    // eligibility, while all public options belong to the same connection
    // generation. An initial async gate must never commit captured old values.
    if (!this.#hasDispatched) {
      this.#restartConnectedLifecycle();
      return;
    }
    if (this.#snapshotAdopted || isLoadedSnapshotAdopted(this)) {
      this.#invalidateSnapshotAndEnhance();
      return;
    }
    this.#refreshRuntimeFromSource();
  }

  #baseEnhanceOptions() {
    const emphasisDotGapEm = this.emphasisDotGapEm;
    const strongAsEmphasisMarks = this.strongAsEmphasisMarks;
    if (
      emphasisDotGapEm == null &&
      !strongAsEmphasisMarks
    ) {
      return undefined;
    }
    return {
      ...(emphasisDotGapEm == null ? {} : { emphasisDotGapEm }),
      ...(strongAsEmphasisMarks ? { strongAsEmphasisMarks: true } : {}),
    };
  }

  #deferInitialEnhancementUntilFontsSettle(generation, completion) {
    this.#clearInitialFontRetry();
    const token = this.#initialFontRetryToken;
    const restart = () => {
      if (
        token !== this.#initialFontRetryToken || !this.isConnected ||
        generation !== this.#generation
      ) return;
      this.#restartConnectedLifecycle();
    };
    this.#initialFontRetryListener = (event) => {
      if (fontLoadingAffectsTypography(event, this.#typographyElements())) restart();
    };
    document.fonts?.addEventListener?.("loadingdone", this.#initialFontRetryListener);
    document.fonts?.addEventListener?.("loadingerror", this.#initialFontRetryListener);

    if (typeof MutationObserver === "function") {
      this.#initialFontRetryObserver = new MutationObserver(restart);
      this.#initialFontRetryObserver.observe(this, {
        attributes: true,
        subtree: true,
        attributeFilter: ["class", "style", "data-theme", "data-color-mode"],
      });
      for (let ancestor = this.parentElement; ancestor; ancestor = ancestor.parentElement) {
        this.#initialFontRetryObserver.observe(ancestor, {
          attributes: true,
          attributeFilter: ["class", "data-theme", "data-color-mode", "lang", "dir"],
        });
      }
    }

    Promise.resolve(completion).then(restart);
  }

  #clearInitialFontRetry() {
    this.#initialFontRetryToken += 1;
    this.#initialFontRetryObserver?.disconnect();
    this.#initialFontRetryObserver = null;
    if (this.#initialFontRetryListener) {
      document.fonts?.removeEventListener?.("loadingdone", this.#initialFontRetryListener);
      document.fonts?.removeEventListener?.("loadingerror", this.#initialFontRetryListener);
      this.#initialFontRetryListener = null;
    }
  }

  #clearLifecycleDiagnostics() {
    delete this.dataset.tiqianCapabilityIssue;
    delete this.dataset.tiqianEnhanceMs;
    delete this.dataset.tiqianLoadMs;
    delete this.dataset.tiqianMaxSliceMs;
    delete this.dataset.tiqianRelayoutMs;
    delete this.dataset.tiqianRelayoutMaxSliceMs;
    delete this.dataset.tiqianFontWait;
    delete this.dataset.tiqianSnapshotLiveIssue;
    delete this.dataset.tiqianSnapshotCount;
    delete this.dataset.tiqianSnapshotMiss;
  }

  #restartConnectedLifecycle() {
    ++this.#generation;
    this.#enhanceRequest += 1;
    this.#hasDispatched = false;
    this.#acceptLayoutCompletion = false;
    this.#snapshotAdopted = false;
    this.#snapshotEnhancedCount = 0;
    this.#removeReadyListener();
    this.#clearInitialFontRetry();
    this.#stopTypographyObservation();
    this.#stopLayoutWorkInputObservation();
    this.#stopWidthObservation();
    this.#stopContentObservation();
    restoreLoadedSnapshot(this);
    if (this.#runtimeStateActive) dispatch("tiqian:destroy", this);
    this.#runtimeStateActive = false;
    this.#releaseExactFontSession();
    this.removeAttribute(EXACT_RENDER_FONT_ATTRIBUTE);
    releaseNativeScrollAnchoring(this);
    if (this.isConnected) this.connectedCallback();
  }

  async #dispatchProgressiveEnhance(
    generation,
    {
      beforeDispatch = null,
      paragraphSelector = null,
      revalidateExactFont = true,
    } = {},
  ) {
    const request = ++this.#enhanceRequest;
    this.#beginLayoutWork();
    const baseOptions = {
      ...(this.#baseEnhanceOptions() ?? {}),
      ...(paragraphSelector ? { paragraphSelector } : {}),
    };
    const needsDash = needsCjkDashShaping(this);
    let exactFontSession = null;
    const exactFontSessionAlreadyPrepared = !revalidateExactFont &&
      this.#exactFontSession?.reference === this.getAttribute("snapshot-ref");
    try {
      exactFontSession = await this.#prepareExactFontSession(
        generation,
        request,
        revalidateExactFont,
      );
      delete this.dataset.tiqianExactFontMiss;
    } catch (error) {
      if (
        this.isConnected && generation === this.#generation &&
        request === this.#enhanceRequest
      ) this.#releaseExactFontSession();
      this.dataset.tiqianExactFontMiss = error?.code ?? "ExactFontSessionUnavailable";
      console.warn("Tiqian Web exact snapshot font session unavailable; using browser metrics", error);
    }
    if (!this.isConnected || generation !== this.#generation || request !== this.#enhanceRequest) {
      if (!this.isConnected || generation !== this.#generation) this.#releaseExactFontSession();
      return false;
    }
    // PreparedSnapshotTransition: callers leaving a precomputed snapshot keep
    // that rendered DOM live while the runtime and exact-font session load. The
    // semantic source is restored immediately before dispatch. Viewport-near
    // paragraphs are prepared in bounded frames and replaced atomically; source
    // paragraphs not reached yet remain responsive through the same exact root
    // font and host line-height contract.
    beforeDispatch?.();
    // LatestExactLayoutDiagnostics: source DOM is live at this point, so stale
    // replay diagnostics can be cleared without briefly re-enabling exact CSS
    // on geometry from the previous measure. The current run will set them
    // again if its own prepared DOM cannot be represented.
    delete this.dataset.tiqianExactLayoutIssue;
    this.removeAttribute(EXACT_PREPARED_FALLBACK_ATTRIBUTE);
    if (exactFontSession) {
      try {
        this.#exactFontSession.installRenderFont(
          this,
          exactFontSession.renderFontFamilies,
        );
        this.setAttribute(EXACT_RENDER_FONT_ATTRIBUTE, "true");
        // HostRenderFontReadyBeforeCommit: server replay already owns the
        // layout metrics, but CSS must finish loading the proven host faces before the
        // first paragraph is committed. This avoids a second font-driven pass
        // and prevents progressive frames from painting a fallback face.
        // WidthOnlyExactFontSessionReuse: replay tables and loaded host faces do not change
        // when only the content-box measure changes. Typography/font observers
        // still take the validating path; a responsive retarget can start the
        // latest-width paragraph queue without repeating font probes first.
        if (!exactFontSessionAlreadyPrepared) {
          await this.#exactFontSession.prepareRenderFont(this, exactFontSession);
        }
        if (
          !this.isConnected || generation !== this.#generation ||
          request !== this.#enhanceRequest
        ) {
          this.#releaseExactFontSession();
          return false;
        }
      } catch (error) {
        if (
          !this.isConnected || generation !== this.#generation ||
          request !== this.#enhanceRequest
        ) {
          this.#releaseExactFontSession();
          return false;
        }
        this.#releaseExactFontSession();
        exactFontSession = null;
        this.dataset.tiqianExactFontMiss = "ExactRenderFontStyleUnavailable";
        console.warn("Tiqian Web exact render font style unavailable; using browser metrics", error);
      }
    }
    if (!exactFontSession) {
      this.removeAttribute(EXACT_RENDER_FONT_ATTRIBUTE);
    }
    // BrowserDashCapabilityBeforeDispatch: the browser no longer starts an
    // asynchronous HarfBuzz probe. Resolve the immediate capability result
    // before the first layout so a dash paragraph is never laid out once as
    // pending and then redundantly retried. An exact server-replay session is
    // carried separately and remains the authoritative dash path.
    const cjkDashCapability = needsDash
      ? await prepareCjkDashShapingIfNeeded(this, {
          ...baseOptions,
          ...(exactFontSession ? { exactFontSession } : {}),
        })
      : { status: "not-needed" };
    if (!this.isConnected || generation !== this.#generation || request !== this.#enhanceRequest) {
      this.#releaseExactFontSession();
      return false;
    }
    // Capture the input signature for cancellation. Kotlin reads the live width
    // again for each paragraph, while this coordinator cancels the remaining
    // job on the next frame if the effective line measure changes.
    const layoutOperation = this.#beginLayoutWork({ usesCapturedMeasure: true });
    this.#hasDispatched = true;
    this.#runtimeStateActive = true;
    this.#acceptLayoutCompletion = true;
    const preparedOptions = {
      ...baseOptions,
      cjkDashCapability,
      ...(exactFontSession ? {
        requireExactLayoutWorker: true,
        exactFontSession: {
          status: "conforming",
          sessionId: exactFontSession.id,
          detail: "SnapshotExactFontBytes",
        },
      } : {}),
    };
    if (exactFontSession) {
      try {
        const { prepareWorkerLayouts } = await import("./worker-layout.js");
        await prepareWorkerLayouts(
          this,
          exactFontSession,
          preparedOptions,
          () => this.isConnected && generation === this.#generation &&
            request === this.#enhanceRequest && layoutOperation === this.#layoutOperation,
        );
      } catch (error) {
        // ExactWorkerFailureMustStayNative: synchronous Kotlin/JS fallback can
        // block scroll under JIT restrictions. Progressive enhancement will
        // retain source DOM for requests without a Worker plan.
        console.warn("Tiqian Web layout Worker unavailable; retaining native paragraphs", error);
      }
      if (
        !this.isConnected || generation !== this.#generation ||
        request !== this.#enhanceRequest || layoutOperation !== this.#layoutOperation
      ) {
        if (!this.isConnected || generation !== this.#generation) {
          this.#releaseExactFontSession();
        }
        return false;
      }
    }
    this.#ensureLayoutWorker();
    dispatch("tiqian:enhance-progressively", this, preparedOptions);
    this.#syncLayoutWorker();
    return true;
  }

  #ensureLayoutWorker() {
    // WorkerPolledScheduling: attach before dispatch so the job is built
    // coordinated from the start and every slice comes from a grant. The
    // dispatch task runs inside the coordinator frame, so the first polled
    // grant lands in the same frame under the shared budget.
    const runtime = globalThis.TiqianWeb;
    if (typeof runtime?.workerAttach !== "function") return;
    runtime.workerAttach(this);
    this.#layoutWorkerAttached = true;
    coordinator.registerWorker(this, runtime);
  }

  #syncLayoutWorker() {
    const runtime = globalThis.TiqianWeb;
    if (!this.#layoutWorkerAttached || typeof runtime?.workerHasJob !== "function") return;
    coordinator.setWorkerActive(this, runtime.workerHasJob(this));
    this.#observeParagraphTiers(runtime);
    coordinator.requestWorkerFrame(this);
  }

  #deactivateLayoutWorker() {
    if (!this.#layoutWorkerAttached) return;
    coordinator.setWorkerActive(this, false);
  }

  #observeParagraphTiers(runtime) {
    const count = runtime.workerParagraphCount(this);
    if (count === 0) {
      this.#stopParagraphTierObservation();
      return;
    }
    if (!this.#paragraphObserver && typeof IntersectionObserver === "undefined") return;
    this.#paragraphObserver ??= new IntersectionObserver((entries) => {
      const live = globalThis.TiqianWeb;
      for (let i = 0; i < entries.length; i++) {
        const entry = entries[i];
        const info = this.#paragraphTierIndex.get(entry.target);
        if (!info) continue;
        const tier = this.#paragraphTierFromEntry(entry);
        if (tier === info.tier) continue;
        info.tier = tier;
        // Tier flips go straight to the running job's pending counters, so
        // the next polled frame reorders the queue without rescanning.
        if (typeof live?.workerSetParagraphTier === "function" && live.workerHasJob(this)) {
          live.workerSetParagraphTier(this, info.index, tier);
        }
      }
    }, { rootMargin: "100% 0px" });
    // Paragraph hosts survive relayout; atomic swaps replace only their
    // children. The diff converges: a stable article adds and drops nothing
    // and the observer set stops churning.
    const live = new Set();
    for (let index = 0; index < count; index++) {
      const paragraph = runtime.workerParagraphAt(this, index);
      if (!paragraph) continue;
      live.add(paragraph);
      const info = this.#paragraphTierIndex.get(paragraph);
      if (!info) {
        this.#paragraphTierIndex.set(paragraph, { index, tier: 1 });
        this.#paragraphObserver.observe(paragraph);
      } else {
        info.index = index;
      }
    }
    for (const paragraph of this.#paragraphTierIndex.keys()) {
      if (live.has(paragraph)) continue;
      this.#paragraphObserver.unobserve(paragraph);
      this.#paragraphTierIndex.delete(paragraph);
    }
  }

  #paragraphTierFromEntry(entry) {
    // ParagraphTierGating: the observer band spans one full viewport in each
    // direction via rootMargin 100%. A paragraph crossing the visible
    // viewport is tier 1; inside the band but off-screen is tier 2; beyond
    // the band is tier 3.
    if (!entry.isIntersecting) return 3;
    const rect = entry.boundingClientRect;
    if (!rect) return 2;
    const viewportHeight = globalThis.innerHeight || 0;
    return rect.bottom >= 0 && rect.top <= viewportHeight ? 1 : 2;
  }

  #stopParagraphTierObservation() {
    this.#paragraphObserver?.disconnect();
    this.#paragraphObserver = null;
    this.#paragraphTierIndex.clear();
  }

  async #prepareExactFontSession(generation, request, revalidateExisting = true) {
    const reference = this.getAttribute("snapshot-ref");
    if (!reference) {
      if (generation === this.#generation && request === this.#enhanceRequest) {
        this.#releaseExactFontSession();
      }
      return null;
    }
    if (this.#exactFontRejectedAttempt === this.#exactFontAttemptSignature(reference)) {
      return null;
    }
    // ExactFontValidationRenderProjection: the SSR marker owns first paint,
    // while this session owns runtime validation. Reassert the projection here
    // so a host hydrator cannot make exact-font validation depend on attribute
    // reconciliation timing. The caller removes it on every failed session.
    this.setAttribute(EXACT_RENDER_FONT_ATTRIBUTE, "true");
    const loader = await loadExactFontFallback();
    const existing = this.#exactFontSession;
    if (existing?.reference === reference) {
      // ExactFontSessionLiveRevalidation: reuse immutable server replay tables
      // only after the browser adapter revalidates every live snapshot input. A
      // caller that already proved this is a width-only retarget may reuse the
      // same live contract without repeating width-independent font probes.
      if (revalidateExisting) await existing.revalidate(this, existing.handle);
      if (
        !this.isConnected || generation !== this.#generation ||
        request !== this.#enhanceRequest || this.getAttribute("snapshot-ref") !== reference
      ) return null;
      return existing.handle;
    }
    const handle = await loader.prepareBrowserFontSession(this);
    if (
      !this.isConnected || generation !== this.#generation ||
      request !== this.#enhanceRequest || this.getAttribute("snapshot-ref") !== reference
    ) {
      loader.releaseBrowserFontSession(handle);
      return null;
    }
    const previous = this.#exactFontSession;
    const next = {
      reference,
      handle,
      revalidate: loader.revalidateBrowserFontSession,
      prepareRenderFont: loader.prepareBrowserRenderFonts,
      release: loader.releaseBrowserFontSession,
      installRenderFont: loader.installPreparedRenderFontStyle,
      releaseRenderFont: loader.releasePreparedRenderFontStyle,
    };
    this.#exactFontSession = next;
    if (previous && previous !== next) previous.release(previous.handle);
    return handle;
  }

  #releaseExactFontSession() {
    const entry = this.#exactFontSession;
    if (!entry) return false;
    this.#exactFontSession = null;
    entry.releaseRenderFont(this);
    return entry.release(entry.handle);
  }

  #exactFontAttemptSignature(reference = this.getAttribute("snapshot-ref")) {
    if (!reference) return "";
    const paragraph = this.querySelector("p[data-tq-snapshot-key], p, li");
    if (!paragraph) return `${reference}\u0000missing`;
    const style = getComputedStyle(paragraph);
    const fontSize = Number.parseFloat(style.fontSize);
    const width = fragmentedBorderBoxInlineSize(paragraph);
    const measure = lineLengthGridMeasure(width, fontSize);
    return `${reference}\u0000${Math.fround(fontSize)}\u0000${measure ?? `invalid:${width.toFixed(3)}`}`;
  }

  #beginLayoutWork({ usesCapturedMeasure = false, captureSignatures = usesCapturedMeasure } = {}) {
    this.#clearResponsiveRetarget();
    const operation = ++this.#layoutOperation;
    this.#layoutWorkInFlight = true;
    this.#layoutWorkIsRelayout = false;
    this.#pendingCommittedMeasures = "";
    this.#layoutWorkRevision = this.#geometryRevision;
    this.#layoutWorkSignaturesCaptured = captureSignatures;
    this.#layoutWorkGeometrySignature = captureSignatures
      ? this.#responsiveGeometrySignature()
      : "";
    this.#layoutWorkMeasureSignature = captureSignatures
      ? this.#paragraphMeasureSignature()
      : "";
    this.#layoutWorkViewportTypographyEntries = captureSignatures
      ? this.#captureLayoutWorkViewportTypographyEntries()
      : [];
    this.#layoutWorkTypographySignature = "";
    if (captureSignatures) {
      const entries = this.#layoutWorkViewportTypographyEntries;
      let signature = "";
      for (let i = 1; i < entries.length; i++) {
        if (i > 1) signature += "\u001e";
        signature += entries[i].signature;
      }
      this.#layoutWorkTypographySignature = signature;
    }
    this.#layoutWorkMaximumMeasure = captureSignatures && this.hasAttribute("snapshot-ref") &&
      loadedSnapshotMaximumMeasureMatches(this);
    this.#layoutWorkUsesCapturedMeasure = usesCapturedMeasure;
    this.#responsiveCommitRequired = false;
    this.#responsiveRelayoutRequired = false;
    this.#acceptLayoutCompletion = false;
    this.#stopTypographyObservation();
    this.#observeContent();
    if (usesCapturedMeasure) this.#observeLayoutWorkInputs();
    return operation;
  }

  #finishLayoutWorkAndObserve(expectedOperation = null) {
    if (expectedOperation != null && expectedOperation !== this.#layoutOperation) return false;
    const signaturesCaptured = this.#layoutWorkSignaturesCaptured;
    const rawGeometryChangedDuringWork = this.#layoutWorkInFlight &&
      (this.#geometryRevision !== this.#layoutWorkRevision || this.#responsiveCommitRequired ||
        (signaturesCaptured &&
          this.#responsiveGeometrySignature() !== this.#layoutWorkGeometrySignature));
    // ObserverBaselineAfterUncapturedLayout: progressive enhancement mutates
    // the paragraph DOM while ResizeObserver is paused. Seed its committed
    // width, grid and typography baselines from that final DOM exactly once;
    // leaving the old values in place makes the observer's first delivery
    // schedule a redundant full-page layout and can immediately invalidate a
    // responsive snapshot that was just adopted.
    // FinishedTypographyBaselineRefresh: the finished DOM is the new stable
    // state, so the baseline must be re-read from it. Keeping a pre-job
    // baseline works only while nothing else compares a live signature
    // against it; the drag-time commit path does exactly that once the root
    // width settles, and a mixed native/rendered DOM after a cancelled job
    // would misread renderer output as a host typography change. Refreshing
    // here triggers no comparison of its own; the next one just starts from
    // the true current state.
    const currentTypography = this.#typographySignature();
    // ResponsiveFinishSkipsDoomedSignatureReads: a finish that returns through
    // the responsive-commit branch stores no paragraph baseline. Width
    // movement puts every relayout finish onto that branch, and relayout
    // jobs capture no measure signature, so the live paragraph signatures
    // the finish read decided nothing and were discarded. Each read cost one
    // gBCR and one computed style per paragraph on DOM the job had just
    // dirtied. A finish reads the signatures only when it compares them
    // against a captured signature or stores them on the unchanged path.
    const signaturesConsumedByFinish = !rawGeometryChangedDuringWork ||
      (this.#layoutWorkUsesCapturedMeasure &&
        this.#layoutWorkMeasureSignature !== "");
    const currentParagraphWidths = signaturesConsumedByFinish &&
        !this.#layoutWorkUsesCapturedMeasure
      ? this.#paragraphWidthSignature()
      : this.#lastParagraphWidths;
    let currentMeasures;
    if (signaturesConsumedByFinish) {
      currentMeasures = this.#layoutWorkUsesCapturedMeasure && !rawGeometryChangedDuringWork
        ? this.#lastParagraphMeasures
        : this.#paragraphMeasureSignature();
    } else {
      currentMeasures = this.#lastParagraphMeasures;
    }
    const currentMaximumMeasure = this.hasAttribute("snapshot-ref") &&
      loadedSnapshotMaximumMeasureMatches(this);
    // CapturedMeasureFollowUpCoalescing: atomic relayout prepares every
    // paragraph from a width snapshot taken when the job starts. If resize
    // activity stays in the same N×fontSize measure and does not cross the
    // exact maximum-snapshot boundary, that result is already valid for the
    // final geometry and a second job would reproduce identical DOM.
    const effectiveLayoutChangedDuringWork = signaturesConsumedByFinish
      ? (currentMeasures !== this.#layoutWorkMeasureSignature ||
        currentMaximumMeasure !== this.#layoutWorkMaximumMeasure)
      : true;
    // RenderOutputTypographyIsNotAnInputChange: the renderer intentionally
    // changes paragraph line-height and positioning after it commits measured
    // line boxes. Comparing that output signature with the captured native
    // source signature schedules a redundant destroy-and-enhance pass. Real
    // font, style and viewport changes are observed while work is in flight and
    // cancel the captured job before ready; completion only needs to reconcile
    // geometry revisions that survived those observers.
    const layoutInputsChangedDuringWork = this.#responsiveCommitRequired || (
      rawGeometryChangedDuringWork &&
      (!this.#layoutWorkUsesCapturedMeasure || effectiveLayoutChangedDuringWork)
    );
    // FinishedTypographyBaselineRefresh also covers the changed-inputs branch:
    // a follow-up commit runs on the next frame and compares a live signature
    // against this baseline, so both branches must leave the baseline at the
    // finished DOM state. Skipping it on the changed branch leaves the
    // pre-job value (empty before the first completed job) and the follow-up
    // commit misreads renderer output as a host typography change.
    this.#lastTypography = currentTypography;
    this.#acceptLayoutCompletion = false;
    this.#layoutWorkInFlight = false;
    this.#layoutWorkSignaturesCaptured = false;
    this.#layoutWorkViewportTypographyEntries = [];
    this.#clearResponsiveRetarget();
    this.#stopLayoutWorkInputObservation();
    if (layoutInputsChangedDuringWork) {
      // A non-atomic progressive job may have observed intermediate widths, so
      // it must force one latest-width pass. Captured-measure relayout can let
      // the normal final measure comparison decide on the next frame.
      this.#responsiveCommitRequired = true;
      this.#responsiveRelayoutRequired = !this.#layoutWorkUsesCapturedMeasure;
      this.#ensureViewportResizeListener();
      this.#scheduleResponsiveGeometryCommit();
      return true;
    }
    if (this.#contentReconcileRequired && !this.#contentProbeFrame) {
      // ContentOnlyFinishCommit: an uncaptured job may have raced a host
      // edit. Resolve the flag with the read-only probe, never with the
      // commit lane: the records are usually this job's own output, and a
      // commit scheduled on them alone enters the offscreen deferred lane,
      // where it later fires a width commit inside the drag debounce window.
      // The probe clears an engine-owned flag without scheduling anything and
      // schedules the commit itself only on proven drift. The finish still
      // falls through to store its baselines, exactly like a finish without
      // the flag.
      this.#ensureViewportResizeListener();
      const operation = this.#layoutOperation;
      this.#contentProbeFrame = requestAnimationFrame(() => {
        this.#contentProbeFrame = 0;
        if (!this.isConnected || operation !== this.#layoutOperation) return;
        this.#probeContentDrift();
      });
    }
    this.#responsiveCommitRequired = false;
    this.#responsiveRelayoutRequired = false;
    this.#lastWidth = fragmentedBorderBoxInlineSize(this);
    this.#lastParagraphMeasures = currentMeasures;
    this.#lastParagraphWidths = currentParagraphWidths;
    this.#observeWidth();
    this.#observeTypography();
    this.#observeContent();
    return true;
  }

  #invalidateSnapshotAndEnhance({ restoreBeforeLoad = false } = {}) {
    if (!this.#snapshotAdopted && !isLoadedSnapshotAdopted(this)) return;
    const generation = this.#generation;
    this.#hasDispatched = false;
    let activeRequest = ++this.#enhanceRequest;
    this.#beginLayoutWork();
    const restoreImmediatelyBeforeDispatch = () => {
      if (!restoreLoadedSnapshot(this)) throw new Error("Adopted snapshot could not be restored");
      this.#snapshotAdopted = false;
      this.#snapshotEnhancedCount = 0;
      delete this.dataset.tiqianSnapshotCount;
      if (this.#runtimeStateActive) {
        dispatch("tiqian:destroy", this);
        this.#runtimeStateActive = false;
      }
    };
    if (restoreBeforeLoad) restoreImmediatelyBeforeDispatch();
    loadTiqianRuntime()
      .then(() => {
        if (
          !this.isConnected || generation !== this.#generation ||
          activeRequest !== this.#enhanceRequest
        ) return false;
        const enhancement = this.#dispatchProgressiveEnhance(generation, restoreBeforeLoad
          ? undefined
          : { beforeDispatch: restoreImmediatelyBeforeDispatch });
        // Async functions run synchronously through their first await, so this
        // captures the request generation claimed by #dispatchProgressiveEnhance.
        activeRequest = this.#enhanceRequest;
        return enhancement;
      })
      .catch((error) => {
        this.#recoverSnapshotEnhanceFailure(generation, activeRequest, error);
      });
  }

  #recoverSnapshotEnhanceFailure(generation, request, error) {
    if (
      !this.isConnected || generation !== this.#generation ||
      request !== this.#enhanceRequest
    ) return;
    // Runtime/module failure must not strand the element in an unobserved
    // transition. Normally the adopted snapshot is still live because restore
    // is deferred until the successful dispatch task; retain it and resume the
    // responsive observers. If an exceptional synchronous restore already ran,
    // the readable runtime/SSR backing remains the fallback instead.
    const snapshotStillLive = isLoadedSnapshotAdopted(this);
    this.#snapshotAdopted = snapshotStillLive;
    this.#hasDispatched = snapshotStillLive || this.#runtimeStateActive;
    this.#acceptLayoutCompletion = false;
    this.#finishLayoutWorkAndObserve();
    this.dataset.tiqianCapabilityIssue = "RuntimeLoadFailed";
    console.warn("Tiqian Web runtime failed to load after snapshot invalidation", error);
  }

  #acceptValidatedSnapshotGeometry() {
    // SnapshotValidationConsumesObservedGeometry: adoption rechecks live width,
    // typography and rendered geometry immediately before its atomic commit.
    // Resize/observer notifications recorded while that validation was in
    // flight are therefore already represented by the adopted result. Reset
    // only the consumed bookkeeping here; a later browser event still arrives
    // after observation resumes and invalidates the snapshot normally.
    this.#layoutWorkRevision = this.#geometryRevision;
    this.#responsiveCommitRequired = false;
    this.#responsiveRelayoutRequired = false;
  }

  #tryReadoptSnapshotAtMaximumMeasure() {
    if (!this.hasAttribute("snapshot-ref")) return;
    const generation = this.#generation;
    const startedAt = Date.now();
    const operation = this.#beginLayoutWork();
    const runtimeSnapshotBackingRestored = this.#runtimeStateActive;
    if (runtimeSnapshotBackingRestored) {
      // RuntimeSnapshotBackingRestore: the first runtime enhancement retains
      // the exact server-rendered nodes as its teardown backing. Snapshot
      // validation must inspect that immutable SSR artifact, never the current
      // runtime rendering whose structure and digest are intentionally different.
      // DOM event dispatch is synchronous, so restoration and the validation
      // start stay in one task and cannot expose unvalidated SSR as a settled
      // state. A miss below immediately starts a fresh runtime enhancement.
      this.#hasDispatched = false;
      dispatch("tiqian:destroy", this);
      this.#runtimeStateActive = false;
    }
    tryAdoptRequestedSnapshot(
      this,
      () => this.isConnected && generation === this.#generation &&
        operation === this.#layoutOperation,
    ).then(async (snapshot) => {
      if (
        !this.isConnected || generation !== this.#generation ||
        operation !== this.#layoutOperation
      ) {
        if (snapshot.adopted) restoreLoadedSnapshot(this);
        return;
      }
      if (!snapshot.adopted) {
        this.dataset.tiqianSnapshotMiss = snapshot.reason ?? "SnapshotNotAdopted";
        // Full validation is intentionally fail-closed. The existing runtime
        // DOM stayed live throughout. It still carries the previous narrow
        // measure, so a maximum-measure miss must finish with a runtime
        // relayout instead of blessing stale lines as current geometry.
        this.#recoverRuntimeAfterSnapshotMiss(
          operation,
          snapshot.reason,
          runtimeSnapshotBackingRestored,
        );
        return;
      }
      delete this.dataset.tiqianSnapshotMiss;
      this.#snapshotAdopted = true;
      this.#snapshotEnhancedCount = snapshot.count;
      const completionSelector = snapshotCompletionSelector(this);
      if (completionSelector) {
        await loadTiqianRuntime();
        if (
          !this.isConnected || generation !== this.#generation ||
          operation !== this.#layoutOperation
        ) {
          return;
        }
        this.#acceptValidatedSnapshotGeometry();
        await this.#dispatchProgressiveEnhance(generation, {
          paragraphSelector: completionSelector,
        });
        return;
      }
      this.#releaseExactFontSession();
      this.#hasDispatched = true;
      this.#acceptLayoutCompletion = true;
      this.#acceptValidatedSnapshotGeometry();
      this.dispatchEvent(new CustomEvent("tiqian:relayout-ready", {
        bubbles: true,
        composed: true,
        detail: {
          enhancedCount: snapshot.count,
          issueCount: 0,
          durationMs: Date.now() - startedAt,
          maxSliceMs: 0,
          relayout: true,
          snapshot: true,
        },
      }));
    }).catch((error) => {
      if (
        !this.isConnected || generation !== this.#generation ||
        operation !== this.#layoutOperation
      ) return;
      this.dataset.tiqianSnapshotMiss = "SnapshotValidationFailed";
      console.warn("Tiqian Web responsive snapshot validation failed", error);
      this.#recoverRuntimeAfterSnapshotMiss(
        operation,
        "SnapshotValidationFailed",
        runtimeSnapshotBackingRestored,
      );
    });
  }

  #recoverRuntimeAfterSnapshotMiss(operation, reason, runtimeSnapshotBackingRestored = false) {
    if (operation !== this.#layoutOperation) return;
    if (runtimeSnapshotBackingRestored) {
      // Validation failed after the synchronous SSR backing restore. Rebuild
      // runtime state from that source for every miss category; a width-only
      // relayout cannot operate after the prior runtime instance was destroyed.
      const generation = this.#generation;
      this.#dispatchProgressiveEnhance(generation).catch((error) => {
        if (!this.isConnected || generation !== this.#generation) return;
        this.#finishLayoutWorkAndObserve();
        this.dataset.tiqianCapabilityIssue = "FontCapabilityPreparationFailed";
        console.warn("Tiqian Web snapshot miss recovery failed", error);
      });
      return;
    }
    if (RESPONSIVE_SNAPSHOT_GEOMETRY_MISSES.has(reason)) {
      this.#relayoutRuntimeAfterSnapshotMiss(operation);
      return;
    }
    if (!this.#runtimeStateActive) {
      // ReadoptionMissMustReclaimSource: a rapid resize can cancel the active
      // runtime job before a maximum-measure snapshot validation begins. If
      // that validation then misses, the DOM is readable native backing but no
      // owner remains to enhance it. Start a fresh latest-geometry job instead
      // of observing the permanently unclaimed source.
      const generation = this.#generation;
      this.#dispatchProgressiveEnhance(generation).catch((error) => {
        if (!this.isConnected || generation !== this.#generation) return;
        this.#finishLayoutWorkAndObserve();
        this.dataset.tiqianCapabilityIssue = "FontCapabilityPreparationFailed";
        console.warn("Tiqian Web unclaimed snapshot miss recovery failed", error);
      });
      return;
    }
    // Source, typography, font-contract and unknown validation failures make
    // the old lowered source or exact-font session untrustworthy. Re-lower and
    // rebuild the font session; a cheap width-only relayout is valid only for
    // the two explicit geometry miss reasons above.
    const generation = this.#generation;
    this.#dispatchProgressiveEnhance(generation).catch((error) => {
      if (!this.isConnected || generation !== this.#generation) return;
      this.#finishLayoutWorkAndObserve();
      this.dataset.tiqianCapabilityIssue = "FontCapabilityPreparationFailed";
      console.warn("Tiqian Web snapshot miss recovery failed", error);
    });
  }

  #dispatchRelayout(observedMeasures = null) {
    if (!this.#runtimeStateActive) {
      this.#finishLayoutWorkAndObserve();
      return;
    }
    this.#beginLayoutWork({ usesCapturedMeasure: true, captureSignatures: false });
    this.#layoutWorkIsRelayout = true;
    // Callers on the commit paths pass the signature they just computed;
    // recomputing here is reserved for dispatches that never went through a
    // commit pass (snapshot-miss recovery).
    this.#pendingCommittedMeasures = observedMeasures ?? this.#paragraphMeasureSignatureFromObserved();
    this.#hasDispatched = true;
    this.#acceptLayoutCompletion = true;
    this.#ensureLayoutWorker();
    dispatch("tiqian:relayout", this);
    this.#syncLayoutWorker();
  }

  #relayoutRuntimeAfterSnapshotMiss(operation) {
    if (operation !== this.#layoutOperation) return;
    this.#dispatchRelayout();
  }

  #refreshRuntimeFromSource({ revalidateExactFont = true } = {}) {
    // A source refresh replaces the rendered paragraphs, so the seeded grid
    // metrics are for nodes about to leave the tree; drop them and let the
    // observer re-seed the rebuilt paragraphs.
    this.#paragraphGridMetrics = null;
    const generation = this.#generation;
    if (this.#runtimeStateActive) {
      // ResponsiveNativeBacking: pre-broken Tiqian lines cannot reflow while a
      // new width or typography is being prepared. Restore the complete
      // semantic source first so every remaining paragraph responds through the
      // host cascade while viewport-near paragraphs are enhanced atomically.
      dispatch("tiqian:destroy", this);
      this.#runtimeStateActive = false;
    }
    this.#dispatchProgressiveEnhance(generation, { revalidateExactFont }).catch((error) => {
      if (!this.isConnected || generation !== this.#generation) return;
      this.#finishLayoutWorkAndObserve();
      this.dataset.tiqianCapabilityIssue = "FontCapabilityPreparationFailed";
      console.warn("Tiqian Web source refresh failed", error);
    });
  }

  #removeReadyListener() {
    if (!this.#readyListener) return;
    this.removeEventListener("tiqian:ready", this.#readyListener);
    this.removeEventListener("tiqian:relayout-ready", this.#readyListener);
    this.#readyListener = null;
  }

  #observeWidth() {
    if (this.#resizeObserver) {
      // AdoptedWidthObservation: content reconcile adopts paragraphs after
      // the observer already exists. Seed and observe targets it has not
      // seen, so an adopted paragraph responds to later width changes.
      const paragraphs = this.querySelectorAll(DEFAULT_PARAGRAPH_SELECTOR);
      for (let i = 0; i < paragraphs.length; i++) {
        const paragraph = paragraphs[i];
        if (!belongsToRootScope(paragraph, this)) continue;
        // Metrics seeding is decoupled from the width map: a source refresh
        // drops the seeds while surviving paragraph nodes stay in the width
        // map, and the width gate alone would then strand them on the
        // read-based fallback for every commit.
        if (!this.#paragraphGridMetrics?.has(paragraph)) this.#seedParagraphGridMetrics(paragraph);
        if (this.#resizeObserverWidths.has(paragraph)) continue;
        this.#resizeObserverWidths.set(paragraph, fragmentedBorderBoxInlineSize(paragraph));
        this.#resizeObserver.observe(paragraph, { box: "border-box" });
      }
      return;
    }
    // ResponsiveInlineSizeObservation: takeover intentionally changes block
    // height. Seed and compare only border-box inline sizes so those commits do
    // not trigger a redundant responsive pass. Persistent observation without
    // pausing ensures drag interactions and live geometry changes are never lost.
    const widths = new WeakMap();
    const targets = [
      this,
      ...Array.from(this.querySelectorAll(DEFAULT_PARAGRAPH_SELECTOR))
        .filter((paragraph) => belongsToRootScope(paragraph, this)),
    ];
    for (let i = 0; i < targets.length; i++) {
      const target = targets[i];
      widths.set(target, fragmentedBorderBoxInlineSize(target));
      if (target !== this) this.#seedParagraphGridMetrics(target);
    }
    const observer = new ResizeObserver((entries) => {
      let changed = false;
      for (let i = 0; i < entries.length; i++) {
        const entry = entries[i];
        let width = 0;
        if (entry.borderBoxSize) {
          const box = Array.isArray(entry.borderBoxSize) ? entry.borderBoxSize[0] : entry.borderBoxSize;
          width = box?.inlineSize ?? 0;
        }
        if (!width && entry.contentRect) {
          width = entry.contentRect.width;
        }
        if (!width) {
          width = fragmentedBorderBoxInlineSize(entry.target);
        }
        const previous = widths.get(entry.target);
        widths.set(entry.target, width);
        if (entry.target === this) {
          this.#lastObservedWidth = width;
          const height = entry.contentRect ? entry.contentRect.height : 0;
          coordinator.update(this, { inlineSize: width, area: width * (height || width * 0.6) });
          if (!this.#inViewport && this.#layoutWorkInFlight) {
            // A width change while the root stays off-screen keeps pushing the
            // worker's deferred wake-up, so only the final width is laid out.
            coordinator.refreshWorkerDeferred(this);
          }
        }
        if (previous == null || Math.abs(width - previous) >= 0.5) changed = true;
      }
      if (!changed) return;
      if (this.#commitResponsiveGeometryPrePaint()) return;
      this.#scheduleResponsiveGeometryCommit();
    });
    this.#resizeObserver = observer;
    this.#resizeObserverWidths = widths;
    for (let i = 0; i < targets.length; i++) {
      const target = targets[i];
      observer.observe(target, { box: "border-box" });
    }
    this.#ensureViewportResizeListener();
  }

  #ensureViewportResizeListener() {
    if (this.#viewportResizeListener) return;
    this.#viewportResizeListener = () => {
      // ViewportResizeValidatesCapturedLayoutInputs: viewport resize is only a
      // signal that layout inputs may have changed. A fixed/max-width article
      // can receive the same event while every paragraph measure stays intact;
      // restoring native source before checking those inputs creates a visible
      // false rollback. Coalesce the live measure, maximum-snapshot and
      // typography comparison into the next pre-paint frame. A real change
      // still cancels the captured job there, while an equivalent grid keeps
      // both its committed paragraphs and remaining work.
      if (this.#layoutWorkInFlight && this.#layoutWorkUsesCapturedMeasure) {
        this.#geometryRevision += 1;
        this.#responsiveCommitRequired = true;
        this.#scheduleResponsiveRetarget();
        return;
      }
      // Uncaptured snapshot/font preparation revalidates live geometry before
      // it commits or begins captured work. It is not bound to the pre-resize
      // measure, so a raw viewport signal alone must not invalidate it.
      if (this.#layoutWorkInFlight) {
        return;
      }
      this.#handleResponsiveGeometryChange();
    };
    window.addEventListener("resize", this.#viewportResizeListener);
    globalThis.visualViewport?.addEventListener?.("resize", this.#viewportResizeListener);
  }

  #handleResponsiveGeometryChange() {
    this.#geometryRevision += 1;
    // ResponsiveNativeRetargetSingleFlight: once rendered/runtime work has
    // been rolled back to semantic source, further resize signals only move
    // the same next-frame target. Do not synchronously rescan the entire
    // article or start another exact-font preparation for every OS resize event.
    if (this.#responsiveRelayoutRequired && !this.#runtimeStateActive) {
      this.#responsiveCommitRequired = true;
      this.#scheduleResponsiveGeometryCommit();
      return;
    }
    const snapshotAdopted = this.#snapshotAdopted || isLoadedSnapshotAdopted(this);
    const committedMeasureChanged = this.#hasDispatched && (
      this.#paragraphMeasureSignature() !== this.#lastParagraphMeasures ||
      (snapshotAdopted && !loadedSnapshotMaximumMeasureMatches(this))
    );
    if (committedMeasureChanged) {
      if (this.#layoutWorkInFlight && this.#layoutWorkUsesCapturedMeasure) {
        this.#cancelCapturedLayoutForLatestGeometry();
        return;
      }
      if (snapshotAdopted) {
        // ResponsiveSnapshotRollbackAtFirstSafeSignal: a maximum-width
        // snapshot is stale when the live paragraph measure changes. Viewport
        // resize reaches this synchronously before paint; a container-only
        // ResizeObserver signal reaches it at the leading edge of the next
        // frame, outside the observer delivery loop.
        this.#invalidateSnapshotAndEnhance({ restoreBeforeLoad: true });
        return;
      }
      if (this.#runtimeStateActive) {
        // ResponsiveRuntimeDirectInPlaceRelayout: when typography is stable,
        // width changes do not tear down the rendered DOM to native text.
        // Direct single-frame in-place relayout computes the new line breaks
        // using WidthIndependentAnnotationCache and swaps DOM atomically.
        this.#responsiveCommitRequired = true;
        this.#scheduleResponsiveGeometryCommit();
        return;
      }
    }
    if (this.#layoutWorkInFlight) {
      this.#responsiveCommitRequired = true;
      this.#scheduleResponsiveRetarget();
      return;
    }
    this.#scheduleResponsiveGeometryCommit();
  }

  #scheduleResponsiveGeometryCommit() {
    if (this.#layoutWorkInFlight) {
      this.#responsiveCommitRequired = true;
      return;
    }
    coordinator.requestFrame(this.#boundResponsiveCommit, this);
  }

  // PrePaintResponsiveCommit: ResizeObserver delivers after layout and
  // before paint, so a width-only commit that completes synchronously here
  // paints with the new width in the same frame; the scheduled lane paints
  // one frame of old lines first. Only the steady width-only case
  // qualifies — every other case keeps the scheduled lane's ordering
  // guarantees. Verified by demo/web/tests/resize-prepaint-commit.test.mjs.
  #commitResponsiveGeometryPrePaint() {
    if (!this.isConnected || !this.#inViewport) return false;
    if (!this.#runtimeStateActive || !this.#hasDispatched) return false;
    if (this.#contentProbeFrame) return false;
    if (this.#snapshotAdopted || isLoadedSnapshotAdopted(this)) return false;
    if (document.fonts?.status === "loading") return false;
    if (this.#layoutWorkInFlight) {
      // PreemptiveCrossingRelayout: without preemption only a drag's first
      // crossing reaches the pre-paint lane; later ones wait out the
      // scheduled cadence behind the in-flight job. A width-only relayout
      // is safe to replace — the runtime cancels it and rebuilds at the
      // latest width (WidthSnapshotPerRelayoutJob). Preempt only on a real
      // cell crossing; enhance and reconcile jobs are never replaced here.
      if (!this.#layoutWorkIsRelayout) return false;
      // ContentBeforeGeometry still rules: a pending reconcile keeps the
      // scheduled lane, whose commit re-lowers drifted content before any
      // width pass; a geometry-only preempt would relay stale text for the
      // rest of the drag.
      if (this.#contentReconcileRequired) return false;
      const measures = this.#paragraphMeasureSignatureFromObserved();
      if (measures === this.#lastParagraphMeasures) return false;
      this.#lastWidth = this.#lastObservedWidth || fragmentedBorderBoxInlineSize(this);
      this.#lastParagraphMeasures = measures;
      return this.#withRootObservationPaused(() => this.#dispatchRelayout(measures));
    }
    return this.#withRootObservationPaused(() => this.#commitResponsiveGeometryChange());
  }

  // One pause/resume protocol for both pre-paint lanes: the root is
  // unobserved around the synchronous commit so its own height change
  // cannot queue a same-depth observation for the browser's ResizeObserver
  // loop guard to report, then re-observed with the original box option.
  #withRootObservationPaused(commit) {
    const observer = this.#resizeObserver;
    observer?.unobserve(this);
    try {
      commit();
      coordinator.grantImmediate(this);
    } finally {
      observer?.observe(this, { box: "border-box" });
    }
    return true;
  }

  #commitResponsiveGeometryChange() {
    if (!this.isConnected) return;
    if (this.#layoutWorkInFlight) {
      this.#responsiveCommitRequired = true;
      return;
    }
    if (!this.#inViewport && this.#lastObservedWidth != null) {
      // OffscreenTrailingWidthCheck: ResizeObserver delivers on animation
      // frames, so while the frame loop pauses mid-drag the observer goes
      // quiet and the off-screen debounce can expire although the width is
      // still moving. Read the live width before releasing the commit; a
      // moving width re-enters the trailing lane.
      const liveWidth = fragmentedBorderBoxInlineSize(this);
      if (Math.abs(liveWidth - this.#lastObservedWidth) >= 0.5) {
        this.#lastObservedWidth = liveWidth;
        this.#responsiveCommitRequired = true;
        this.#scheduleResponsiveGeometryCommit();
        return;
      }
    }
    // Before the first snapshot/runtime commit there is no layout to update.
    // The initial job will read the latest live width once its font gate opens.
    const forceLatestWidth = this.#responsiveRelayoutRequired || this.#responsiveCommitRequired;
    this.#responsiveCommitRequired = false;
    this.#responsiveRelayoutRequired = false;
    if (!this.#hasDispatched) return;
    if (this.#contentReconcileRequired && !this.#contentProbeFrame) {
      // ContentBeforeGeometry: one commit lane serves ResizeObserver and
      // MutationObserver alike. Content goes first because re-lowering reads
      // the live width, so a concurrent width change is absorbed by the same
      // job; the reverse order would relayout stale text first. An idle
      // reconcile falls through so a width-only change still commits.
      this.#contentReconcileRequired = false;
      const tainted = Array.from(this.#contentTainted);
      this.#contentTainted.clear();
      if (this.#snapshotAdopted || isLoadedSnapshotAdopted(this)) {
        this.#invalidateSnapshotAndEnhance({ restoreBeforeLoad: true });
        return;
      }
      if (this.#dispatchContentReconcile(tainted)) {
        // ReconcileCommitPreservesWidthIntent: a work verdict returns before
        // the width lane runs, and the reconcile job re-lowers only drifted,
        // tainted and stranded paragraphs. A width change already pending at
        // this commit would die with the flags beginLayoutWork cleared; the
        // finish would then store the live width against stale paragraphs and
        // the change would never re-enter layout. Re-arm the commit so the
        // finish schedules one latest-width pass.
        const pendingWidth = this.#lastObservedWidth || fragmentedBorderBoxInlineSize(this);
        if (forceLatestWidth || Math.abs(pendingWidth - this.#lastWidth) >= 0.5) {
          this.#responsiveCommitRequired = true;
        }
        return;
      }
    }
    const width = this.#lastObservedWidth || fragmentedBorderBoxInlineSize(this);
    this.#lastObservedWidth = width;
    const widthsChanged = Math.abs(width - this.#lastWidth) >= 0.5;
    const paragraphWidths = widthsChanged ? this.#lastParagraphWidths : this.#paragraphWidthSignature();
    // LineLengthGridResponsiveInvalidation: the quantized measure signature
    // is computed on every commit, width changes included, so the same-named
    // gate below can skip in-cell width motion instead of dispatching a job
    // that reproduces identical paragraph DOM. Layout is clean at commit
    // time (the width read above already forced it), so the per-paragraph
    // reads here do not thrash.
    const paragraphMeasures = this.#paragraphMeasureSignatureFromObserved();
    const hostInlineSizeRefresh = widthsChanged &&
      this.querySelector("[data-tq-host-inline-size]") !== null;
    const measuresChanged = paragraphMeasures !== this.#lastParagraphMeasures;
    const signature = (widthsChanged && !this.#forceTypographyRefresh)
      ? this.#lastTypography
      : this.#typographySignature();
    const typographyChanged = signature !== this.#lastTypography;
    if (!forceLatestWidth && !widthsChanged && !measuresChanged && !typographyChanged) {
      this.#observeWidth();
      return;
    }
    this.#lastWidth = width;
    this.#lastParagraphMeasures = paragraphMeasures;
    this.#lastParagraphWidths = paragraphWidths;

    const snapshotAdopted = this.#snapshotAdopted || isLoadedSnapshotAdopted(this);
    const atMaximumMeasure = this.hasAttribute("snapshot-ref") &&
      loadedSnapshotMaximumMeasureMatches(this);
    if (snapshotAdopted) {
      if (atMaximumMeasure && !typographyChanged) {
        // MixedSnapshotCompletionResume: cancelling a captured runtime-only
        // job restores just its unkeyed source; the keyed snapshot remains
        // valid. Restart that partial job instead of treating the still-valid
        // snapshot as proof that every paragraph is settled.
        const completionSelector = snapshotCompletionSelector(this);
        if (completionSelector && !this.#runtimeStateActive) {
          const generation = this.#generation;
          this.#dispatchProgressiveEnhance(generation, {
            paragraphSelector: completionSelector,
          }).catch((error) => {
            if (!this.isConnected || generation !== this.#generation) return;
            this.#finishLayoutWorkAndObserve();
            this.dataset.tiqianCapabilityIssue = "FontCapabilityPreparationFailed";
            console.warn("Tiqian Web snapshot completion restart failed", error);
          });
          return;
        }
        // A parent may keep growing after the paragraph has reached max-width.
        // The snapshot contract is still valid; do not churn the DOM.
        this.#lastTypography = signature;
        this.#observeWidth();
        this.#observeTypography();
      } else {
        this.#invalidateSnapshotAndEnhance();
      }
      return;
    }
    if (!this.#runtimeStateActive && atMaximumMeasure && !typographyChanged) {
      this.#tryReadoptSnapshotAtMaximumMeasure();
      return;
    }
    // A forced pass (viewport revalidation, stale follow-up) may only skip
    // against the CommittedMeasureLedger; a normal pass dedups against the
    // dispatch bookkeeping.
    const measureSettled = forceLatestWidth
      ? paragraphMeasures === this.#lastCommittedParagraphMeasures
      : !measuresChanged;
    if (!typographyChanged && !hostInlineSizeRefresh && measureSettled) {
      // LineLengthGridResponsiveInvalidation: Web currently exposes the
      // engine's Start-aligned body only. Within one N×fontSize cell count,
      // the measure, line breaks, placements, and body offset are unchanged.
      // Keep observing exact geometry for snapshot evidence, but do not ask
      // the engine to reproduce identical paragraph DOM. A forced pass
      // (viewport revalidation, stale follow-up) skips only against the
      // CommittedMeasureLedger: dispatch-time bookkeeping is optimistic and
      // a stale-died job must still get its convergence pass, but a ledger
      // hit proves the committed layout already matches this cell — during
      // a window drag nearly every viewport-forced pass lands here.
      this.#lastTypography = signature;
      this.#observeWidth();
      this.#observeTypography();
      return;
    }
    // ResponsiveTypographyBeforeRebreak: a media query can change font
    // metrics in the same resize without mutating any class/style attribute.
    // Re-lower in that case; reserve the cheap width-only path for stable
    // typography.
    if (document.fonts?.status === "loading") {
      this.#observeWidth();
      this.#observeTypography();
      this.#scheduleTypographyCheck(true);
      return;
    }
    if (typographyChanged) {
      this.#lastTypography = signature;
      this.#refreshRuntimeFromSource({ revalidateExactFont: true });
      return;
    }
    if (this.#runtimeStateActive) {
      this.#dispatchRelayout(paragraphMeasures);
      return;
    }
    this.#refreshRuntimeFromSource({ revalidateExactFont: false });
  }

  #removeViewportResizeListener() {
    if (!this.#viewportResizeListener) return;
    window.removeEventListener("resize", this.#viewportResizeListener);
    globalThis.visualViewport?.removeEventListener?.("resize", this.#viewportResizeListener);
    this.#viewportResizeListener = null;
  }

  #stopWidthObservation() {
    this.#clearResponsiveRetarget();
    this.#resizeObserver?.disconnect();
    this.#resizeObserver = null;
    this.#resizeObserverWidths = null;
    this.#paragraphGridMetrics = null;
    this.#lastObservedWidth = 0;
    if (this.#resizeObserverFrame) cancelAnimationFrame(this.#resizeObserverFrame);
    this.#resizeObserverFrame = 0;
    if (this.#resizeFrame) cancelAnimationFrame(this.#resizeFrame);
    this.#resizeFrame = 0;
    this.#removeViewportResizeListener();
  }

  #scheduleResponsiveRetarget() {
    if (!this.#layoutWorkInFlight || !this.#layoutWorkUsesCapturedMeasure) return;
    this.#clearResponsiveRetarget();
    const operation = this.#layoutOperation;
    this.#responsiveRetargetFrame = requestAnimationFrame(() => {
      this.#responsiveRetargetFrame = 0;
      if (
        !this.isConnected || !this.#layoutWorkInFlight ||
        !this.#layoutWorkUsesCapturedMeasure || operation !== this.#layoutOperation
      ) return;
      if (this.#layoutWorkViewportTypographyChanged()) {
        this.#cancelCapturedLayoutForTypographyChange();
        return;
      }
      const maximumMeasure = this.hasAttribute("snapshot-ref") &&
        loadedSnapshotMaximumMeasureMatches(this);
      // SameGridRetargetWithoutRestart: a responsive relayout dispatch uses
      // captureSignatures:false and reads its measure live inside the layout
      // job, so #layoutWorkMeasureSignature is empty here. Comparing against
      // that empty signature cancelled the in-flight job on every width
      // event. This guard compares against the measure of the last completed
      // job instead. While the width stays inside the same N×fontSize grid
      // cell, the committed DOM is already correct and unchanged paragraphs
      // are skipped at zero cost, so the in-flight job keeps running. When
      // the width crosses into a new cell, or when no completed measure
      // exists yet, the guard cancels the job and restarts it at the latest
      // width.
      const measureBaseline = this.#layoutWorkMeasureSignature || this.#lastParagraphMeasures;
      if (
        this.#paragraphMeasureSignature() === measureBaseline &&
        maximumMeasure === this.#layoutWorkMaximumMeasure
      ) return;
      this.#cancelCapturedLayoutForLatestGeometry();
    });
  }

  #clearResponsiveRetarget() {
    if (!this.#responsiveRetargetFrame) return;
    cancelAnimationFrame(this.#responsiveRetargetFrame);
    this.#responsiveRetargetFrame = 0;
  }

  #observeTypography() {
    this.#typographyObserver?.disconnect();
    this.#typographyObserver = new MutationObserver(() => this.#scheduleTypographyCheck());
    // Descendant class/style changes can alter inline semantics. Any ancestor
    // attribute can participate in selectors that change inherited typography.
    this.#typographyObserver.observe(this, {
      attributes: true,
      subtree: true,
      attributeFilter: ["class", "style", "data-theme", "data-color-mode"],
    });
    for (let ancestor = this.parentElement; ancestor; ancestor = ancestor.parentElement) {
      this.#typographyObserver.observe(ancestor, {
        attributes: true,
        attributeFilter: ["class", "data-theme", "data-color-mode", "lang", "dir"],
      });
    }
    if (document.fonts) {
      this.#fontLoadingSettledListener = async (event) => {
        const generation = this.#generation;
        const snapshotAdopted = this.#snapshotAdopted || isLoadedSnapshotAdopted(this);
        let snapshotLiveIssue = null;
        if (snapshotAdopted) {
          try {
            snapshotLiveIssue = await loadedAdoptedSnapshotLiveIssue(
              this,
              () => this.isConnected && generation === this.#generation &&
                (this.#snapshotAdopted || isLoadedSnapshotAdopted(this)),
            );
          } catch {
            snapshotLiveIssue = "SnapshotLiveValidationFailed";
          }
        }
        if (!this.isConnected || generation !== this.#generation ||
            snapshotLiveIssue === "superseded") return;
        if (snapshotAdopted && snapshotLiveIssue == null) {
          // SnapshotFontLoadCycleAlreadyValidated: snapshot adoption awaited
          // and probed every exact evidence face. The browser may dispatch the
          // corresponding loadingdone task only after observers resume; retain
          // the snapshot when its CSS face, typography and rendered geometry
          // contracts still hold instead of starting a redundant font cycle.
          delete this.dataset.tiqianSnapshotLiveIssue;
          return;
        }
        if (snapshotLiveIssue) this.dataset.tiqianSnapshotLiveIssue = snapshotLiveIssue;
        const relevantFaceLoaded = fontLoadingAffectsTypography(
          event,
          this.#typographyElements(),
        );
        const force = this.#forceTypographyRefresh || relevantFaceLoaded;
        if (this.#deferredTypographyCheck || force) this.#scheduleTypographyCheck(force);
      };
      document.fonts.addEventListener("loadingdone", this.#fontLoadingSettledListener);
      document.fonts.addEventListener("loadingerror", this.#fontLoadingSettledListener);
    }
  }

  #stopTypographyObservation() {
    this.#typographyObserver?.disconnect();
    this.#typographyObserver = null;
    if (this.#fontLoadingSettledListener) {
      document.fonts?.removeEventListener("loadingdone", this.#fontLoadingSettledListener);
      document.fonts?.removeEventListener("loadingerror", this.#fontLoadingSettledListener);
      this.#fontLoadingSettledListener = null;
    }
    if (this.#typographyFrame) cancelAnimationFrame(this.#typographyFrame);
    this.#typographyFrame = 0;
    this.#forceTypographyRefresh = false;
    this.#deferredTypographyCheck = false;
  }

  // HostContentSignal: childList and characterData mutations on the live DOM
  // are the only host content signals. Attributes and inline size already
  // have their own observers. This observer stays connected across layout
  // work on purpose: engine commits also produce records, and the drift
  // probe disproves those by identity instead of disconnecting and losing
  // host edits that land mid-flight.
  #observeContent() {
    if (!this.#contentObserver) {
      this.#contentObserver = new MutationObserver((records) => {
        this.#handleContentMutationRecords(records);
      });
      this.#contentObserver.observe(this, { childList: true, characterData: true, subtree: true });
    }
    this.#syncCustodyObservation();
  }

  // CustodyFragmentObservation: takeover moves the host's semantic children
  // into a detached fragment the engine holds. Frameworks keep references to
  // those original nodes (React's text update writes .data on them), so host
  // edits land inside custody where the live-DOM subtree never sees them.
  // Kotlin publishes the current fragment on each rendered paragraph; observe
  // every tracked fragment alongside the root. Re-lowering creates a fresh
  // fragment, so diff the desired set at every job boundary and re-target the
  // observer only when it changed.
  #syncCustodyObservation() {
    const desired = new Map();
    const paragraphs = this.querySelectorAll(
      `:is(${DEFAULT_PARAGRAPH_SELECTOR})[data-tq-rendered="true"]`,
    );
    for (let i = 0; i < paragraphs.length; i++) {
      const paragraph = paragraphs[i];
      if (!belongsToRootScope(paragraph, this)) continue;
      const fragment = paragraph.__tqCustodyFragment;
      if (fragment) desired.set(fragment, paragraph);
    }
    let unchanged = desired.size === this.#custodyTargets.size;
    if (unchanged) {
      for (const [fragment, paragraph] of desired) {
        if (this.#custodyTargets.get(fragment) !== paragraph) {
          unchanged = false;
          break;
        }
      }
    }
    if (unchanged) return;
    // Pending records from the outgoing target set still count. Flush them
    // through the handler first, or a host edit landing in the same frame
    // would be dropped together with the old registration.
    const pending = this.#contentObserver.takeRecords();
    if (pending.length) this.#handleContentMutationRecords(pending);
    this.#contentObserver.disconnect();
    this.#contentObserver.observe(this, { childList: true, characterData: true, subtree: true });
    for (const fragment of desired.keys()) {
      this.#contentObserver.observe(fragment, { childList: true, characterData: true, subtree: true });
    }
    this.#custodyTargets = desired;
  }

  // Attribution for a record under a custody fragment: walk up to the
  // enclosing detached fragment and map it back to its live paragraph. Live
  // nodes never reach a DocumentFragment ancestor, so the walk is safe there.
  #custodyParagraphFor(node) {
    let current = node;
    while (current) {
      if (current.nodeType === 11) {
        return this.#custodyTargets.get(current) || null;
      }
      current = current.parentNode;
    }
    return null;
  }

  #stopContentObservation() {
    this.#contentObserver?.disconnect();
    this.#contentObserver = null;
    this.#custodyTargets.clear();
    if (this.#contentProbeFrame) cancelAnimationFrame(this.#contentProbeFrame);
    this.#contentProbeFrame = 0;
    this.#contentTainted.clear();
    this.#contentReconcileRequired = false;
  }

  #handleContentMutationRecords(records) {
    if (!this.#hasDispatched) return;
    let paragraphSignal = false;
    let structureSignal = false;
    for (let i = 0; i < records.length; i++) {
      const record = records[i];
      // EnginePreparedStyleWritesAreNotContent: the prepared-dom renderer
      // rewrites its own <style data-tq-prepared-value-styles> text content on
      // every commit. Those records are engine output, never a host signal.
      const recordElement = record.type === "characterData"
        ? record.target.parentElement
        : record.target;
      if (recordElement?.closest?.("[data-tq-prepared-value-styles]")) continue;
      const custodyParagraph = this.#custodyParagraphFor(record.target);
      if (custodyParagraph) {
        // CustodyCharacterDataIsHostCertain: the engine only moves whole
        // nodes in and out of custody and never rewrites text inside it, so
        // a characterData record there is a framework editing the original
        // node it still holds. Taint directly. A childList record may be the
        // engine's own re-take or rollback refill; the custody identity
        // check in the probe tells them apart, so it only raises the flag.
        if (record.type === "characterData") this.#contentTainted.add(custodyParagraph);
        paragraphSignal = true;
        continue;
      }
      const paragraph = recordElement?.closest?.(DEFAULT_PARAGRAPH_SELECTOR);
      if (paragraph && belongsToRootScope(paragraph, this)) {
        // TopLevelChildListTrustsIdentityProbe: engine commits append and
        // remove a paragraph's direct children on every render, so a top-level
        // childList record proves nothing by itself. The Kotlin classifier
        // proves engine ownership by node identity. Only an in-place text
        // edit, which child identity cannot see, taints its paragraph.
        if (record.type === "characterData") this.#contentTainted.add(paragraph);
        paragraphSignal = true;
      } else if (record.type === "childList") {
        // Records outside any paragraph (a host adding or removing paragraph
        // wrappers or editing non-paragraph flow) change the candidate set.
        structureSignal = true;
      }
    }
    if (!paragraphSignal && !structureSignal) return;
    this.#contentReconcileRequired = true;
    if (structureSignal && (!this.#layoutWorkInFlight || this.#runtimeStateActive)) {
      // StructureChangesCommitDirectly: a childList record outside every
      // paragraph cannot be engine render output in the steady state, so no
      // probe is needed and waiting for one would only delay candidate
      // adoption. During initial enhancement the engine still installs its
      // own scaffolding at root level, so an in-flight signal there keeps
      // the probe path.
      this.#scheduleResponsiveGeometryCommit();
      return;
    }
    if (this.#layoutWorkInFlight) {
      // MutationObserverDeliveryIsAsync: records land in a microtask after the
      // engine's synchronous commit batch, so a captured job may already be
      // rendering stale content. Probe drift read-only at the next frame; an
      // engine-owned batch is disproven there without cancelling anything.
      if (!this.#contentProbeFrame) {
        const operation = this.#layoutOperation;
        this.#contentProbeFrame = requestAnimationFrame(() => {
          this.#contentProbeFrame = 0;
          if (!this.isConnected || operation !== this.#layoutOperation) return;
          this.#probeContentDrift();
        });
      }
      return;
    }
    // EngineRecordsProvenIdleStayFree: a finished job's own records arrive in
    // this microtask. Scheduling a commit on them alone would fire the width
    // lane early and break the drag debounce, so prove host intent with the
    // read-only probe first. Only real drift, taint or dead tracking schedules
    // work; the probe clears the flag otherwise.
    this.#probeContentDrift();
  }

  #probeContentDrift() {
    // Mid-job takeovers publish fresh custody fragments; adopt them before
    // reading custody identity so a host edit made during enhancement is
    // already under observation when the probe runs.
    this.#syncCustodyObservation();
    const event = new CustomEvent("tiqian:probe-content-drift", { detail: { root: this } });
    document.dispatchEvent(event);
    let drift = null;
    try {
      drift = event.detail?.result ? JSON.parse(event.detail.result) : null;
    } catch {
      drift = null;
    }
    const drifted = (drift?.drifted || 0) + (drift?.dead || 0) + (drift?.unknown || 0) +
      (drift?.custody || 0);
    const tainted = this.#contentTainted.size;
    if (drifted === 0 && tainted === 0) {
      // Engine-owned output disproven; nothing host-authored is pending.
      this.#contentReconcileRequired = false;
      return;
    }
    if (!this.#layoutWorkInFlight) {
      this.#scheduleResponsiveGeometryCommit();
      return;
    }
    // MidFlightHostEditCancelsCapturedJob: only a captured job is bound to a
    // pre-edit snapshot. Uncaptured work lowers live content per slice and
    // the finish funnel picks the edit up.
    if (this.#layoutWorkUsesCapturedMeasure) {
      this.#cancelCapturedLayoutForLatestGeometry();
    }
  }

  #dispatchContentReconcile(paragraphs) {
    if (!this.#runtimeStateActive) return false;
    this.#beginLayoutWork({ usesCapturedMeasure: true, captureSignatures: false });
    this.#hasDispatched = true;
    this.#acceptLayoutCompletion = true;
    this.#ensureLayoutWorker();
    const event = new CustomEvent("tiqian:reconcile-content", {
      detail: { root: this, options: { paragraphs } },
    });
    document.dispatchEvent(event);
    let outcome = null;
    try {
      outcome = event.detail?.result ? JSON.parse(event.detail.result) : null;
    } catch {
      outcome = null;
    }
    if (outcome?.outcome !== "work") {
      // ReconcileIdleReleasesWorkSlot: the records were engine-owned output
      // or touched nothing tracked. Release the work slot without a ready
      // round-trip so the next signal starts clean.
      this.#finishLayoutWorkAndObserve();
      // ReconcileAbsorbsLiveGeometry: a reconcile renders at the live width,
      // and an idle verdict certifies the current DOM as settled output for
      // exactly this geometry. Earlier finishes that took responsive early
      // returns never stored a paragraph baseline, so the commit fall-through
      // would compare a stale signature and dispatch a phantom relayout.
      this.#lastParagraphMeasures = this.#paragraphMeasureSignature();
      this.#lastParagraphWidths = this.#paragraphWidthSignature();
      return false;
    }
    this.#syncLayoutWorker();
    return true;
  }

  #observeLayoutWorkInputs() {
    this.#stopLayoutWorkInputObservation();
    this.#layoutWorkTypographyObserver = new MutationObserver((records) => {
      if (!this.#layoutWorkInFlight || !this.#layoutWorkUsesCapturedMeasure) return;
      // RendererOwnedProgressiveStyleMutation: paragraph takeover itself adds
      // the containing block and, for flex items, the captured inline size.
      // Those writes are output mechanics rather than a host typography
      // change; cancelling on them makes a valid mixed snapshot restart after
      // its first viewport-near paragraphs. Reverse only those exact deltas
      // against MutationRecord.oldValue, while any concurrent host style or
      // class change still reaches the full signature check below.
      let rendererOwnedOnly = true;
      for (let i = 0; i < records.length; i++) {
        const record = records[i];
        if (!rendererOwnedProgressiveStyleMutation(record, this)) {
          rendererOwnedOnly = false;
          break;
        }
      }
      if (rendererOwnedOnly) {
        // ProgressiveOutputTypographyBaseline: rendered paragraphs intentionally
        // replace host line-height/font projection and install a containing
        // block. Advance the captured baseline after that verified renderer-only
        // mutation so a later viewport signal compares host changes against the
        // current mixed native/rendered state, not against the all-native DOM
        // from before the first commit. A batch containing any host mutation
        // still falls through to the invalidation check below.
        this.#layoutWorkTypographySignature = this.#typographySignature();
        return;
      }
      if (this.#typographySignature() === this.#layoutWorkTypographySignature) return;
      this.#cancelCapturedLayoutForTypographyChange();
    });
    this.#layoutWorkTypographyObserver.observe(this, {
      attributes: true,
      subtree: true,
      attributeFilter: ["class", "style", "data-theme", "data-color-mode"],
      attributeOldValue: true,
    });
    for (let ancestor = this.parentElement; ancestor; ancestor = ancestor.parentElement) {
      this.#layoutWorkTypographyObserver.observe(ancestor, {
        attributes: true,
        attributeFilter: ["class", "data-theme", "data-color-mode", "lang", "dir"],
      });
    }
    if (document.fonts) {
      this.#layoutWorkFontLoadingSettledListener = (event) => {
        if (
          this.#layoutWorkInFlight && this.#layoutWorkUsesCapturedMeasure &&
          fontLoadingAffectsTypography(event, this.#typographyElements())
        ) this.#cancelCapturedLayoutForTypographyChange();
      };
      document.fonts.addEventListener("loadingdone", this.#layoutWorkFontLoadingSettledListener);
      document.fonts.addEventListener("loadingerror", this.#layoutWorkFontLoadingSettledListener);
    }
  }

  #stopLayoutWorkInputObservation() {
    this.#layoutWorkTypographyObserver?.disconnect();
    this.#layoutWorkTypographyObserver = null;
    if (this.#layoutWorkFontLoadingSettledListener) {
      document.fonts?.removeEventListener(
        "loadingdone",
        this.#layoutWorkFontLoadingSettledListener,
      );
      document.fonts?.removeEventListener(
        "loadingerror",
        this.#layoutWorkFontLoadingSettledListener,
      );
      this.#layoutWorkFontLoadingSettledListener = null;
    }
  }

  #cancelCapturedLayoutForTypographyChange() {
    if (!this.#layoutWorkInFlight || !this.#layoutWorkUsesCapturedMeasure) return;
    this.#clearResponsiveRetarget();
    ++this.#layoutOperation;
    this.#acceptLayoutCompletion = false;
    this.#layoutWorkInFlight = false;
    this.#layoutWorkViewportTypographyEntries = [];
    this.#advanceTypographyBaselineAfterCancellation();
    this.#responsiveCommitRequired = true;
    this.#responsiveRelayoutRequired = true;
    // CommittedMeasureLedger: a cancelled captured job may have committed
    // part of its paragraphs; no single signature describes the mix, so the
    // forced follow-up must not be skippable against a stale ledger value.
    this.#lastCommittedParagraphMeasures = "";
    this.#stopLayoutWorkInputObservation();
    dispatch("tiqian:cancel-layout-work", this);
    this.#deactivateLayoutWorker();
    this.#ensureViewportResizeListener();
    this.#scheduleResponsiveGeometryCommit();
  }

  #cancelCapturedLayoutForLatestGeometry() {
    if (!this.#layoutWorkInFlight || !this.#layoutWorkUsesCapturedMeasure) return;
    this.#clearResponsiveRetarget();
    ++this.#layoutOperation;
    this.#acceptLayoutCompletion = false;
    this.#layoutWorkInFlight = false;
    this.#layoutWorkViewportTypographyEntries = [];
    this.#stopLayoutWorkInputObservation();
    dispatch("tiqian:cancel-layout-work", this);
    this.#deactivateLayoutWorker();
    this.#advanceTypographyBaselineAfterCancellation();
    this.#responsiveCommitRequired = true;
    this.#responsiveRelayoutRequired = true;
    this.#lastCommittedParagraphMeasures = "";
    this.#ensureViewportResizeListener();
    this.#scheduleResponsiveGeometryCommit();
  }

  // CancelledTypographyBaselineAdvance: cancelling a captured job keeps every
  // already committed paragraph in its rendered state, but no ready event will
  // refresh the baseline the way a finished job would. The typography baseline
  // would stay at the all-native pre-job signature while the live DOM mixes
  // rendered and native paragraphs, so the next style-driven check compares a
  // mixed-state signature against the native one, misreads renderer output as
  // a host typography change and tears the whole root down. Advance the
  // baseline to the current mixed state here; a later real host change still
  // differs from it.
  #advanceTypographyBaselineAfterCancellation() {
    this.#lastTypography = this.#typographySignature();
  }

  #restoreRuntimeSourceForRetarget() {
    // ResponsiveRetargetNativeRollback: cancellation runs before the next
    // paint. Restore every already committed paragraph in the same callback so
    // no frame can display geometry captured for the superseded measure. The
    // next responsive commit starts viewport-priority enhancement from this
    // responsive semantic backing.
    if (this.#runtimeStateActive) {
      dispatch("tiqian:destroy", this);
      this.#runtimeStateActive = false;
    } else {
      dispatch("tiqian:cancel-layout-work", this);
    }
  }

  #scheduleTypographyCheck(force = false) {
    this.#forceTypographyRefresh ||= force;
    if (this.#typographyFrame) return;
    this.#typographyFrame = requestAnimationFrame(() => {
      this.#typographyFrame = 0;
      if (!this.isConnected) return;
      // A loading font would immediately invalidate another measurement. Its
      // loadingdone event will schedule the authoritative check.
      if (document.fonts?.status === "loading") {
        this.#deferredTypographyCheck = true;
        return;
      }
      this.#deferredTypographyCheck = false;
      const signature = this.#typographySignature();
      const changed = signature !== this.#lastTypography;
      const shouldRefresh = changed || this.#forceTypographyRefresh;
      this.#forceTypographyRefresh = false;
      if (!shouldRefresh) return;
      this.#lastTypography = signature;
      if (this.#snapshotAdopted || isLoadedSnapshotAdopted(this)) {
        this.#invalidateSnapshotAndEnhance();
        return;
      }
      this.#refreshRuntimeFromSource();
    });
  }

  #typographySignature(includeGenerated = true) {
    const elements = this.#typographyElements();
    let sig = "";
    for (let i = 0; i < elements.length; i++) {
      if (i > 0) sig += "\u001e";
      sig += this.#elementTypographySignature(elements[i], includeGenerated);
    }
    return sig;
  }

  #elementTypographySignature(
    element,
    includeGenerated = true,
    properties = TYPOGRAPHY_PROPERTIES,
  ) {
    const style = getComputedStyle(element);
    let sig = element.tagName;
    for (let i = 0; i < properties.length; i++) {
      sig += "\u001f" + style.getPropertyValue(properties[i]);
    }
    if (includeGenerated) {
      for (let i = 0; i < TYPOGRAPHY_PSEUDO_SELECTORS.length; i++) {
        const selector = TYPOGRAPHY_PSEUDO_SELECTORS[i];
        const pseudo = getComputedStyle(element, selector);
        sig += "\u001f" +
          pseudo.getPropertyValue("content") + "\u001d" +
          pseudo.getPropertyValue("font-family") + "\u001d" +
          pseudo.getPropertyValue("font-size") + "\u001d" +
          pseudo.getPropertyValue("font-weight") + "\u001d" +
          pseudo.getPropertyValue("font-style") + "\u001d" +
          pseudo.getPropertyValue("font-feature-settings") + "\u001d" +
          pseudo.getPropertyValue("font-variation-settings") + "\u001d" +
          pseudo.getPropertyValue("font-variant") + "\u001d" +
          pseudo.getPropertyValue("font-language-override") + "\u001d" +
          pseudo.getPropertyValue("letter-spacing") + "\u001d" +
          pseudo.getPropertyValue("word-spacing");
      }
    }
    return sig;
  }

  #captureLayoutWorkViewportTypographyEntries() {
    const entries = [{
      element: this,
      includeGenerated: false,
      properties: ROOT_VIEWPORT_TYPOGRAPHY_PROPERTIES,
      signature: this.#elementTypographySignature(
        this,
        false,
        ROOT_VIEWPORT_TYPOGRAPHY_PROPERTIES,
      ),
    }];
    const elements = this.#typographyElements();
    for (let i = 0; i < elements.length; i++) {
      const element = elements[i];
      entries.push({
        element,
        includeGenerated: true,
        properties: TYPOGRAPHY_PROPERTIES,
        signature: this.#elementTypographySignature(element, true, TYPOGRAPHY_PROPERTIES),
      });
    }
    return entries;
  }

  #layoutWorkViewportTypographyChanged() {
    // NativeSourceViewportTypographySignature: progressive renderer output is
    // not a layout input. Compare the root plus only source elements that have
    // not yet been replaced, using their pre-work computed typography. This
    // catches viewport media-query changes without treating Tiqian's own
    // line-height/font projection/containing-block CSS as a host mutation.
    const entries = this.#layoutWorkViewportTypographyEntries;
    for (let i = 0; i < entries.length; i++) {
      const { element, includeGenerated, properties, signature } = entries[i];
      if (element !== this && (
        !element.isConnected || element.closest("[data-tq-rendered='true']")
      )) continue;
      if (this.#elementTypographySignature(element, includeGenerated, properties) !== signature) {
        return true;
      }
    }
    return false;
  }

  #typographyElements() {
    const elements = [];
    const seenGroups = new Set();
    const paragraphs = this.querySelectorAll(DEFAULT_PARAGRAPH_SELECTOR);
    for (let i = 0; i < paragraphs.length; i++) {
      const paragraph = paragraphs[i];
      elements.push(paragraph);
      const rendered = paragraph.hasAttribute("data-tq-rendered");
      const descendants = rendered
        ? paragraph.querySelectorAll("[data-tq-source-semantic], [data-tq-inline-object]")
        : paragraph.querySelectorAll("*");
      for (let j = 0; j < descendants.length; j++) {
        const element = descendants[j];
        const group =
          element.getAttribute("data-tq-link-group") ??
          element.getAttribute("data-tq-inline-group");
        if (group && seenGroups.has(group)) continue;
        if (group) seenGroups.add(group);
        elements.push(element);
      }
    }
    return elements;
  }

  #observeIntersection() {
    if (this.#intersectionObserver || typeof IntersectionObserver === "undefined") return;
    this.#intersectionObserver = new IntersectionObserver((entries) => {
      for (let i = 0; i < entries.length; i++) {
        const entry = entries[i];
        if (entry.target === this) {
          const wasInViewport = this.#inViewport;
          this.#inViewport = entry.isIntersecting;
          const rect = entry.boundingClientRect;
          const interRect = entry.intersectionRect;
          const visibleArea = interRect ? interRect.width * interRect.height : 0;
          coordinator.update(this, {
            inViewport: this.#inViewport,
            intersectionRatio: entry.intersectionRatio || (this.#inViewport ? 1.0 : 0.0),
            visibleArea,
            inlineSize: rect ? rect.width : 0,
            area: rect ? rect.width * rect.height : 0,
          });
          if (wasInViewport && !this.#inViewport) {
            // OffscreenWorkerDebounce: an off-screen root stops receiving
            // grants immediately; its pending layout work waits out the same
            // trailing window as off-screen frame tasks and replays once the
            // drag settles or the root returns. Already committed paragraphs
            // stay committed.
            coordinator.refreshWorkerDeferred(this);
          }
          if (!wasInViewport && this.#inViewport) {
            coordinator.clearWorkerDeferred(this);
            if (this.#responsiveCommitRequired || this.#responsiveRelayoutRequired) {
              this.#scheduleResponsiveGeometryCommit();
            }
          }
        }
      }
    }, { rootMargin: "200px 0px" });
    this.#intersectionObserver.observe(this);
  }

  #stopIntersectionObservation() {
    this.#intersectionObserver?.disconnect();
    this.#intersectionObserver = null;
  }

  // AllocationFreeSignatureIteration: the signature builders run on every
  // responsive commit and layout-work finish. Indexed loops with direct
  // concatenation avoid intermediate arrays and per-paragraph closures, and
  // keep the builders on the same shape as #typographySignature.
  #paragraphWidthSignature() {
    const paragraphs = this.querySelectorAll(DEFAULT_PARAGRAPH_SELECTOR);
    let signature = "";
    for (let i = 0; i < paragraphs.length; i++) {
      if (i > 0) signature += "\u001f";
      signature += fragmentedBorderBoxInlineSize(paragraphs[i]).toFixed(3);
    }
    return signature;
  }

  #responsiveGeometrySignature() {
    const paragraphs = this.querySelectorAll(DEFAULT_PARAGRAPH_SELECTOR);
    let signature = String(fragmentedBorderBoxInlineSize(this));
    for (let i = 0; i < paragraphs.length; i++) {
      signature += "\u001f";
      signature += fragmentedBorderBoxInlineSize(paragraphs[i]);
    }
    return signature;
  }

  #paragraphMeasureSignature() {
    const exactFontLayout = Boolean(this.#exactFontSession);
    const paragraphs = this.querySelectorAll(DEFAULT_PARAGRAPH_SELECTOR);
    let signature = "";
    for (let i = 0; i < paragraphs.length; i++) {
      if (i > 0) signature += "\u001f";
      signature += this.#paragraphMeasureEntry(paragraphs[i], exactFontLayout);
    }
    return signature;
  }

  #paragraphMeasureEntry(paragraph, exactFontLayout) {
    const style = getComputedStyle(paragraph);
    const fontSize = Number.parseFloat(style.fontSize);
    let width = paragraphLayoutWidth(paragraph, style, exactFontLayout);
    if (!(width > 0)) {
      const parent = paragraph.parentElement;
      if (parent) width = paragraphLayoutWidth(parent, getComputedStyle(parent), exactFontLayout);
    }
    const measure = lineLengthGridMeasure(width, fontSize);
    return measure == null
      ? `invalid:${width.toFixed(3)}:${style.fontSize}`
      : `${Math.fround(fontSize)}:${measure}`;
  }

  // ObservedMeasureSignature: the same entries as
  // #paragraphMeasureSignature, built from ResizeObserver-delivered widths
  // and seeded font metrics — zero layout reads on the per-width-event hot
  // paths (the ResponsiveFinishSkipsDoomedSignatureReads budget). Unseeded
  // or zero-width paragraphs fall back to the read-based entry; observed
  // widths may trail live layout by one delivery, so a crossing commits at
  // most one frame later than the pre-paint lane.
  #paragraphMeasureSignatureFromObserved() {
    // Seeded metrics freeze each paragraph's fontSize at observation time,
    // which goes blind when a media or container breakpoint rescales type in
    // the same resize that crosses it. One root read per call catches the
    // inherited case and drops the seeds so this pass reads live values; a
    // paragraph whose font responds independently of the root still goes
    // through the typography lane.
    const rootFontSize = getComputedStyle(this).fontSize;
    if (rootFontSize !== this.#paragraphGridRootFontSize) {
      this.#paragraphGridRootFontSize = rootFontSize;
      this.#paragraphGridMetrics = null;
    }
    const widths = this.#resizeObserverWidths;
    const metrics = this.#paragraphGridMetrics;
    if (!widths || !metrics) return this.#paragraphMeasureSignature();
    const exactFontLayout = Boolean(this.#exactFontSession);
    const paragraphs = this.querySelectorAll(DEFAULT_PARAGRAPH_SELECTOR);
    let signature = "";
    for (let i = 0; i < paragraphs.length; i++) {
      const paragraph = paragraphs[i];
      if (i > 0) signature += "\u001f";
      const m = metrics.get(paragraph);
      let width = widths.get(paragraph);
      if (m == null || width == null) {
        signature += this.#paragraphMeasureEntry(paragraph, exactFontLayout);
        continue;
      }
      if (exactFontLayout) width -= m.inset;
      if (!(width > 0)) {
        signature += this.#paragraphMeasureEntry(paragraph, exactFontLayout);
        continue;
      }
      const measure = lineLengthGridMeasure(width, m.fontSize);
      signature += measure == null
        ? `invalid:${width.toFixed(3)}:${m.fontSizePx}`
        : `${Math.fround(m.fontSize)}:${measure}`;
    }
    return signature;
  }

  #seedParagraphGridMetrics(paragraph) {
    const style = getComputedStyle(paragraph);
    const number = (value) => Number.parseFloat(value) || 0;
    (this.#paragraphGridMetrics ??= new WeakMap()).set(paragraph, {
      fontSize: Number.parseFloat(style.fontSize),
      fontSizePx: style.fontSize,
      inset: number(style.paddingLeft) + number(style.paddingRight) +
        number(style.borderLeftWidth) + number(style.borderRightWidth),
    });
  }
}

const registry = globalThis.customElements;
if (
  typeof globalThis.HTMLElement === "function" &&
  typeof registry?.get === "function" &&
  typeof registry?.define === "function" &&
  !registry.get(ELEMENT_NAME)
) {
  registry.define(ELEMENT_NAME, TiqianProseElement);
}

export { TiqianProseElement, TiqianLayoutCoordinator };
