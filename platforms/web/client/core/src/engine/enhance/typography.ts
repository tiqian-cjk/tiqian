// TypographyManager — the typography signal for one enhanced element
// (core-neutral parts ruling). Owns the typography invalidation sources
// (steady observation and the in-flight layout-work input observation),
// the scheduled typography check, the initial font retry controller, the
// lastTypography baseline (sole owner; the responsive commit path reads
// and writes it through this part), and the per-runtime CJK dash
// capability plus the browser fallback descriptor dissolved from
// root-state.ts.

import type { BrowserMetricsBridgeInstance } from "../browser-metrics-bridge.js";
import { createBrowserMetricsBridge } from "../browser-metrics-bridge.js";
import type { CanvasContextLike } from "../canvas-metrics.js";
import type { CanvasShapingEnv, ProbeElementLike } from "../canvas-shaping.js";
import { createFontFamilies } from "../canvas-fonts.js";
import type { ResolvedEnhanceOptions } from "../lifecycle.js";
import {
  createInitialFontRetryController,
  fontLoadingAffectsTypography,
} from "../loaders/font-loader.js";
import type { FontLoadingEventLike, InitialFontRetryController } from "../loaders/font-loader.js";
import { typographySignature, typographyElements } from "../../sampler/signatures.js";
import {
  rendererOwnedProgressiveStyleMutation,
} from "../raw-dom.js";
import {
  createTypographyInvalidationSource,
  createLayoutWorkTypographyInvalidationSource,
} from "../../sampler/observers.js";
import type {
  TypographyInvalidationSource,
} from "../../sampler/observers.js";
import { isLoadedSnapshotAdopted, loadedAdoptedSnapshotLiveIssue } from "../../sampler/snapshot/loaded-snapshots.js";
import { collectFontFaces } from "../../sampler/snapshot/precomputed.js";
import { computeCjkDashOutcome } from "../loaders/cjk-dash.js";
import type { CjkDashShapingOutcome } from "../loaders/cjk-dash.js";
import { InvalidationReason } from "./state.js";
import type { EnhancementStateMachine } from "./state-machine.js";
import type { SchedulerRegistration } from "./scheduler-registration.js";
import type { DiagnosisManager } from "../context/diagnosis-manager.js";
import type { SnapshotAdoption } from "./snapshot-adoption.js";
import { globalServices } from "../../services/global-services.js";
import type { FrameTaskCallback } from "../coordination/coordination-service.js";

// Browser fallback descriptor built once per runtime establishment and
// embedded in every layout path argument. Dissolved from root-state.ts;
// the TypographyManager owns the capability and the bridge. Type alias
// (not interface) so it stays assignable to the loose Record<string,
// unknown> slots in the orchestrator globals.
export type BrowserFallbackDescriptor = { bridge: BrowserMetricsBridgeInstance };

export interface TypographyHooks {
  currentGeneration(): number;
  restartConnectedLifecycle(): void;
  refreshRuntimeFromSource(): void;
  clearResponsiveRetarget(): void;
  ensureViewportResizeListener(): void;
  scheduleResponsiveGeometryCommit(): void;
  deactivateLayoutWorker(): void;
  setCommittedMeasureLedger(value: string): void;
}

export interface TypographyManager {
  readonly lastTypography: string;
  readonly cjkDashCapability: CjkDashShapingOutcome | null;
  readonly browserFallback: BrowserFallbackDescriptor | null;
  setLastTypography(value: string): void;
  advanceTypographyBaselineAfterCancellation(): void;
  establishRuntime(root: Element, resolved: ResolvedEnhanceOptions): void;
  clearRuntime(): void;
  updateCjkDashCapability(options: ResolvedEnhanceOptions, outcome: CjkDashShapingOutcome): ResolvedEnhanceOptions;
  observeTypography(): void;
  stopTypographyObservation(): void;
  scheduleTypographyCheck(force?: boolean): void;
  observeLayoutWorkInputs(): void;
  stopLayoutWorkInputObservation(): void;
  cancelCapturedLayoutForTypographyChange(): void;
  deferInitialEnhancementUntilFontsSettle(generation: number, completion: Promise<unknown>): void;
  clearInitialFontRetry(): void;
}

// The canvas modules own their probe nodes; attachProbe keeps the probe in
// the document without duplicating it across measures.
function browserMetricsEnv(): CanvasShapingEnv {
  return {
    createCanvasContext: function (): CanvasContextLike {
      return document.createElement("canvas").getContext("2d") as CanvasContextLike;
    },
    createProbeElement: function (): ProbeElementLike {
      return document.createElement("span") as ProbeElementLike;
    },
    attachProbe: function (node: ProbeElementLike): void {
      if (!node.parentNode) document.body.appendChild(node as HTMLElement);
    },
  };
}

// The {bridge} descriptor every TS layout path consumes. The inner bridge
// adapts the canvas shaper and metrics resolver to the two JSON callbacks
// of precomputeParagraphWithBrowserMetrics. Built once per root.
function buildBrowserFallbackDescriptor(resolved: ResolvedEnhanceOptions): BrowserFallbackDescriptor {
  const fontFamilies = resolved.fontFamilies;
  // buildFontFamiliesConfigJs renames the resolved monospace family to the
  // latinMonospace key that canvas-fonts.js reads for the LatinText role.
  const fonts = createFontFamilies({
    cjk: fontFamilies.cjk,
    latin: fontFamilies.latin,
    latinMonospace: fontFamilies.monospace,
    cjkSerif: fontFamilies.cjkSerif,
    latinSerif: fontFamilies.latinSerif,
  });
  const bridge: BrowserMetricsBridgeInstance = createBrowserMetricsBridge({
    fonts: fonts,
    cjkDashCapability: resolved.cjkDashCapability,
    env: browserMetricsEnv(),
  });
  return { bridge: bridge };
}

function createTypographyManager(
  root: HTMLElement,
  stateMachine: EnhancementStateMachine,
  snapshotAdoption: SnapshotAdoption,
  diagnosis: DiagnosisManager,
  scheduler: SchedulerRegistration,
  hooks: TypographyHooks,
): TypographyManager {
  let typographyInvalidation: TypographyInvalidationSource | null = null;
  let layoutWorkTypographyInvalidation: TypographyInvalidationSource | null = null;
  let typographyFrame: FrameTaskCallback | null = null;
  let initialFontRetry: InitialFontRetryController | null = null;
  let lastTypography = "";
  let lastFontState = "";
  let layoutFontState = "";
  let cjkDashCapability: CjkDashShapingOutcome | null = null;
  let browserFallback: BrowserFallbackDescriptor | null = null;

  // Stylesheet updates can recreate equivalent FontFace objects after navigation.
  // Compare sources and load states, rather than treating every loadingdone as new metrics.
  function fontState(): string {
    const documentObject = root.ownerDocument;
    const collection = collectFontFaces(documentObject);
    if (collection.unverifiable) return "";

    // A real face arrival, failure, or source replacement still invalidates layout.
    const states = Array.from(documentObject.fonts, (face) => [
      face.family, face.style, face.weight, face.stretch, face.unicodeRange,
      face.ascentOverride, face.descentOverride, face.lineGapOverride,
      face.featureSettings, (face as FontFace & { variationSettings?: string }).variationSettings, face.status,
    ]);
    return JSON.stringify([collection.faces, states]);
  }

  function fontStateChanged(baseline: string): boolean {
    const current = fontState();
    return !current || current !== baseline;
  }

  function establishRuntime(runtimeRoot: Element, resolved: ResolvedEnhanceOptions): void {
    cjkDashCapability = computeCjkDashOutcome(runtimeRoot, {
      snapshotFontSession: resolved.snapshotFontSession,
    });
    browserFallback = buildBrowserFallbackDescriptor(resolved);
  }

  function clearRuntime(): void {
    cjkDashCapability = null;
    browserFallback = null;
  }

  function updateCjkDashCapability(options: ResolvedEnhanceOptions, outcome: CjkDashShapingOutcome): ResolvedEnhanceOptions {
    if (cjkDashCapability &&
        cjkDashCapability.status === outcome.status &&
        cjkDashCapability.detail === outcome.detail) {
      return options;
    }
    cjkDashCapability = outcome;
    const updatedResolved = {
      ...options,
      cjkDashCapability: outcome,
    };
    browserFallback = buildBrowserFallbackDescriptor(updatedResolved);
    return updatedResolved;
  }

  function scheduleTypographyCheck(force = false): void {
    if (force) stateMachine.invalidate(InvalidationReason.TypographyRefreshForced);
    if (typographyFrame) return;
    const frame: FrameTaskCallback = () => {
      typographyFrame = null;
      if (!root.isConnected) return;
      // A loading font would immediately invalidate another measurement.
      // Its loadingdone event will schedule the authoritative check.
      if (root.ownerDocument?.fonts?.status === "loading") {
        stateMachine.invalidate(InvalidationReason.DeferredTypographyCheck);
        return;
      }
      stateMachine.clearInvalidation(InvalidationReason.DeferredTypographyCheck);
      const signature = typographySignature(root);
      const changed = signature !== lastTypography;
      const shouldRefresh = changed || stateMachine.isInvalidated(InvalidationReason.TypographyRefreshForced);
      stateMachine.clearInvalidation(InvalidationReason.TypographyRefreshForced);
      if (!shouldRefresh) return;
      lastTypography = signature;
      if (stateMachine.snapshotAdopted || isLoadedSnapshotAdopted(root)) {
        snapshotAdoption.invalidateAndEnhance();
        return;
      }
      hooks.refreshRuntimeFromSource();
    };
    typographyFrame = frame;
    scheduler.requestFrame(frame);
  }

  function observeTypography(): void {
    if (!typographyInvalidation) {
      typographyInvalidation = createTypographyInvalidationSource(root, {
        onMutation: () => scheduleTypographyCheck(),
        // Declared registry changes carry no FontFaceSetEvent; force past
        // the typography signature (declared sheets never enter the CSSOM
        // it reads) so the revalidate cycle re-collects the merged
        // candidates.
        onDeclaredFacesChanged: () => scheduleTypographyCheck(true),
        onFontEvent: async (event) => {
          const generation = hooks.currentGeneration();
          const snapshotAdopted = stateMachine.snapshotAdopted || isLoadedSnapshotAdopted(root);
          let snapshotLiveIssue: string | null = null;
          if (snapshotAdopted) {
            try {
              snapshotLiveIssue = await loadedAdoptedSnapshotLiveIssue(
                root,
                () => root.isConnected && generation === hooks.currentGeneration() &&
                  (stateMachine.snapshotAdopted || isLoadedSnapshotAdopted(root)),
              );
            } catch {
              snapshotLiveIssue = "SnapshotLiveValidationFailed";
            }
          }
          if (!root.isConnected || generation !== hooks.currentGeneration() ||
              snapshotLiveIssue === "superseded") return;
          if (snapshotAdopted && snapshotLiveIssue == null) {
            // SnapshotFontLoadCycleAlreadyValidated: snapshot adoption
            // awaited and probed every exact evidence face. The browser may
            // dispatch the corresponding loadingdone task only after
            // observers resume; retain the snapshot when its CSS face,
            // typography and rendered geometry contracts still hold instead
            // of starting a redundant font cycle.
            return;
          }
          if (snapshotLiveIssue) diagnosis.signal("tiqianSnapshotLiveIssue", snapshotLiveIssue);
          const relevantFaceLoaded = fontStateChanged(lastFontState) && fontLoadingAffectsTypography(
            event as FontLoadingEventLike,
            typographyElements(root),
          );
          const forced = stateMachine.isInvalidated(InvalidationReason.TypographyRefreshForced) || relevantFaceLoaded;
          if (stateMachine.isInvalidated(InvalidationReason.DeferredTypographyCheck) || forced) scheduleTypographyCheck(forced);
        },
      });
    }
    typographyInvalidation.start();
  }

  function stopTypographyObservation(): void {
    typographyInvalidation?.stop();
    if (typographyFrame) scheduler.cancelFrame(typographyFrame);
    typographyFrame = null;
    stateMachine.clearInvalidation(InvalidationReason.TypographyRefreshForced);
    stateMachine.clearInvalidation(InvalidationReason.DeferredTypographyCheck);
  }

  function observeLayoutWorkInputs(): void {
    layoutFontState = fontState();
    if (!layoutWorkTypographyInvalidation) {
      layoutWorkTypographyInvalidation = createLayoutWorkTypographyInvalidationSource(root, {
        onMutation: (records) => {
          if (!stateMachine.workInFlight || !stateMachine.work.usesCapturedMeasure) return;
          // RendererOwnedProgressiveStyleMutation: paragraph takeover itself
          // adds the containing block and, for flex items, the captured
          // inline size. Those writes are output mechanics rather than a
          // host typography change; cancelling on them makes a valid mixed
          // snapshot restart after its first viewport-near paragraphs.
          // Reverse only those exact deltas against MutationRecord.oldValue,
          // while any concurrent host style or class change still reaches
          // the full signature check below.
          let rendererOwnedOnly = true;
          for (let i = 0; i < records.length; i++) {
            const record = records[i];
            if (!rendererOwnedProgressiveStyleMutation(record, root)) {
              rendererOwnedOnly = false;
              break;
            }
          }
          if (rendererOwnedOnly) {
            // ProgressiveOutputTypographyBaseline: rendered paragraphs
            // intentionally replace host line-height/font projection and
            // install a containing block. Advance the captured baseline
            // after that verified renderer-only mutation so a later
            // viewport signal compares host changes against the current
            // mixed native/rendered state, not against the all-native DOM
            // from before the first commit. A batch containing any host
            // mutation still falls through to the invalidation check below.
            stateMachine.work.typographySignature = typographySignature(root);
            return;
          }
          if (typographySignature(root) === stateMachine.work.typographySignature) return;
          cancelCapturedLayoutForTypographyChange();
        },
        onFontEvent: (event) => {
          if (
            stateMachine.workInFlight && stateMachine.work.usesCapturedMeasure &&
            fontStateChanged(layoutFontState) &&
            fontLoadingAffectsTypography(event as FontLoadingEventLike, typographyElements(root))
          ) cancelCapturedLayoutForTypographyChange();
        },
      });
    }
    layoutWorkTypographyInvalidation.start();
  }

  function stopLayoutWorkInputObservation(): void {
    layoutWorkTypographyInvalidation?.stop();
  }

  // CancelledTypographyBaselineAdvance: cancelling a captured job keeps every
  // already committed paragraph in its rendered state, but no ready event
  // will refresh the baseline the way a finished job would. The typography
  // baseline would stay at the all-native pre-job signature while the live
  // DOM mixes rendered and native paragraphs, so the next style-driven check
  // compares a mixed-state signature against the native one, misreads
  // renderer output as a host typography change and tears the whole root
  // down. Advance the baseline to the current mixed state here; a later real
  // host change still differs from it.
  function advanceTypographyBaselineAfterCancellation(): void {
    lastTypography = typographySignature(root);
    lastFontState = fontState();
  }

  function cancelCapturedLayoutForTypographyChange(): void {
    if (!stateMachine.workInFlight || !stateMachine.work.usesCapturedMeasure) return;
    hooks.clearResponsiveRetarget();
    stateMachine.abortLayoutWork();
    advanceTypographyBaselineAfterCancellation();
    stateMachine.invalidate(InvalidationReason.ResponsiveCommit);
    stateMachine.invalidate(InvalidationReason.ResponsiveRelayout);
    // CommittedMeasureLedger: a cancelled captured job may have committed
    // part of its paragraphs; no single signature describes the mix, so the
    // forced follow-up must not be skippable against a stale ledger value.
    hooks.setCommittedMeasureLedger("");
    stopLayoutWorkInputObservation();
    globalServices().coordination.layoutJobPool.cancelJob(root);
    hooks.deactivateLayoutWorker();
    hooks.ensureViewportResizeListener();
    hooks.scheduleResponsiveGeometryCommit();
  }

  function deferInitialEnhancementUntilFontsSettle(generation: number, completion: Promise<unknown>): void {
    initialFontRetry ??= createInitialFontRetryController(root, {
      fonts: root.ownerDocument?.fonts ?? null,
      isGenerationCurrent: (candidate) => candidate === hooks.currentGeneration(),
      typographyElements: () => typographyElements(root),
      restartConnectedLifecycle: () => hooks.restartConnectedLifecycle(),
    });
    initialFontRetry.deferUntilFontsSettle(generation, completion);
  }

  function clearInitialFontRetry(): void {
    initialFontRetry?.clear();
  }

  return {
    get lastTypography() {
      return lastTypography;
    },
    get cjkDashCapability() {
      return cjkDashCapability;
    },
    get browserFallback() {
      return browserFallback;
    },
    setLastTypography(value: string) {
      lastTypography = value;
      lastFontState = fontState();
    },
    advanceTypographyBaselineAfterCancellation,
    establishRuntime,
    clearRuntime,
    updateCjkDashCapability,
    observeTypography,
    stopTypographyObservation,
    scheduleTypographyCheck,
    observeLayoutWorkInputs,
    stopLayoutWorkInputObservation,
    cancelCapturedLayoutForTypographyChange,
    deferInitialEnhancementUntilFontsSettle,
    clearInitialFontRetry,
  };
}

export { createTypographyManager };
