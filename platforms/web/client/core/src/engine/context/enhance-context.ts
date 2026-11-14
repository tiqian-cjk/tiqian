// EnhancedElementContext — the sole per-root runtime object of the web
// enhancement runtime (2026-08-25 G2 ruling, actualized by the 2026-08-27
// core-neutral wave). One context per enhanced element; createEnhanceContext
// is the single construction entry, hosts and tests build a context
// explicitly and hold it themselves — no registry is involved.
//
// The context is both the composition root and the lifecycle verb layer:
// it constructs the twelve enhance/ parts, wires their hook records, and
// exposes the host verbs (mount/unmount/updateOptions/on/relayout/invalidate)
// plus the ruling verbs update() and destroy(). The orchestration bodies
// live in core/engine/enhance/lifecycle/; the parts never hold the context,
// the lifecycle files are the sole exception.
//
// The three single truths rule the surface: the options object is the only
// option input (updateOptions diffs against the applied ledger, never
// against root attributes), the callback subscribers are the event source
// (CustomEvent synthesis belongs to the web component shell's dispatcher
// slot), and DOM access flows through the injected root.

import type { PreparedStyleState } from "../../sampler/snapshot/prepared-dom.js";
import {
  releasePreparedStyleState,
  releasePreparedValueStyleRoot,
} from "../../sampler/snapshot/prepared-dom.js";
import {
  detachLoadedSnapshot,
  isLoadedSnapshotAdopted,
  restoreLoadedSnapshot,
  tryAdoptRequestedSnapshot,
} from "../../sampler/snapshot/loaded-snapshots.js";
import { paragraphWidthSignature } from "../../sampler/signatures.js";
import { renderedRawDomParagraphs } from "../raw-dom.js";
import { destroyRoot, detachRoot } from "../lifecycle.js";
import { enhance, relayout } from "../progressive-drivers.js";
import { probeRootContentDrift, reconcileRoot } from "../content-reconcile.js";
import { globalServices } from "../../services/global-services.js";
import { createDiagnosisManager } from "./diagnosis-manager.js";
import type { DiagnosisDatasetRecord, DiagnosisManager } from "./diagnosis-manager.js";
import { InvalidationReason } from "../enhance/state.js";
import { createEnhancementStateMachine } from "../enhance/state-machine.js";
import type { EnhancementStateMachine } from "../enhance/state-machine.js";
import { createSchedulerRegistration } from "../enhance/scheduler-registration.js";
import type { SchedulerRegistration } from "../enhance/scheduler-registration.js";
import { createEventChannel } from "../enhance/event-channel.js";
import type {
  EventChannel,
  EnhancementDiagnostics,
  EnhancementEvent,
  EnhancementEventCallback,
  EnhancementEventUnsubscribe,
} from "../enhance/event-channel.js";
import { createOptionsLedger } from "../enhance/options-ledger.js";
import type {
  OptionsLedger,
  EnhancementOptions,
  OptionsChangedReaction,
} from "../enhance/options-ledger.js";
import { createContextState } from "../enhance/context-state.js";
import type { ContextState } from "../enhance/context-state.js";
import { createSnapshotAdoption } from "../enhance/snapshot-adoption.js";
import type { SnapshotAdoption } from "../enhance/snapshot-adoption.js";
import { createTypographyManager } from "../enhance/typography.js";
import type { TypographyManager } from "../enhance/typography.js";
import { createResponsiveManager } from "../enhance/responsive.js";
import type { ResponsiveManager } from "../enhance/responsive.js";
import { createEffectSync } from "../enhance/effect-sync.js";
import type { EffectSync } from "../enhance/effect-sync.js";
import { createVisibilityManager } from "../enhance/visibility.js";
import type { VisibilityManager } from "../enhance/visibility.js";
import { createDomWriteLayer } from "../enhance/dom-write-layer.js";
import type { DomWriteLayer } from "../enhance/dom-write-layer.js";
import { createForeignGuard } from "../enhance/lifecycle/foreign-guard.js";
import { createProgressiveDispatch } from "../enhance/lifecycle/progressive-dispatch.js";
import { createInitialEnhance } from "../enhance/lifecycle/initial-enhance.js";
import { createMount } from "../enhance/lifecycle/mount.js";

/** Typography overrides for one synchronous rebuild. */
export interface SynchronousRelayoutOptions {
  firstLineIndentIc?: number;
}

export interface RawDomParagraphRecord {
  fragment: DocumentFragment | null;  // detached original children
  engineWriteDepth: number;           // host engine-write suspension counter
  forwarding: boolean;                // commit-forwarding installed flag
  originalContent: DocumentFragment | null;
  renderedNodes: Node[];
  rawDomNodes: Node[];
  originalRenderedAttribute: string | null;
  originalPreparedFlowAttribute: string | null;
  originalCanonicalSourceAttribute: string | null;
  originalSnapshotPreparedDomAttribute: string | null;
  originalLangAttribute: string | null;
  originalStyleAttribute: string | null;
  originalPosition: string;
  originalPositionPriority: string;
  originalInlineSize: string;
  originalInlineSizePriority: string;
  originalFontSize: string;
  originalFontSizePriority: string;
  originalHostInlineSizeAttribute: string | null;
  containingBlockApplied: boolean;
  hostInlineSizeApplied: string | null;
  hostFontSizeApplied: string | null;
}

// Base shape the construction literal builds. The composition part surface
// and the host verbs are attached after the wiring through
// Object.defineProperties, so the literal alone cannot carry them.
interface ContextCoreBase {
  readonly element: Element;
  readonly generation: number;
  // Scoped-style identity owned by this context. Prepared-dom rules mint one
  // scope per context and use it as the style element's data attribute value;
  // uniqueness is required only among live roots of the same document, so a
  // random string suffices. Scope values never enter fixtures.
  readonly scope: string;
  readonly rawDomParagraphs: Map<Element, RawDomParagraphRecord>;
  readonly diagnosis: DiagnosisManager;
  preparedStyle: PreparedStyleState | null;
  update(): number;
  destroy(): void;
}

interface EnhancedElementContext extends ContextCoreBase {
  // Composition-root part surface: engine modules receive the context and
  // reach their dependencies through these accessors.
  readonly stateMachine: EnhancementStateMachine;
  readonly contextState: ContextState;
  readonly optionsLedger: OptionsLedger;
  readonly eventChannel: EventChannel;
  readonly scheduler: SchedulerRegistration;
  readonly responsive: ResponsiveManager;
  readonly typography: TypographyManager;
  readonly visibility: VisibilityManager;
  readonly effectSync: EffectSync;
  readonly snapshotAdoption: SnapshotAdoption;
  readonly domWriteLayer: DomWriteLayer;

  // Host verb surface (the former session public API).
  readonly isConnected: boolean;
  readonly diagnostics: EnhancementDiagnostics;
  mount(): Promise<void>;
  unmount(): void;
  updateOptions(options: EnhancementOptions): void;
  on(event: EnhancementEvent, callback: EnhancementEventCallback): EnhancementEventUnsubscribe;
  onReady(callback: EnhancementEventCallback): EnhancementEventUnsubscribe;
  onRelayoutReady(callback: EnhancementEventCallback): EnhancementEventUnsubscribe;
  relayout(): void;
  /** Rebuild all paragraphs at the live size before returning; fonts must be ready. */
  relayoutSync(options?: SynchronousRelayoutOptions): number;
  invalidate(reason: number): void;
}

// Only HTMLElement hosts carry a dataset surface; the context types its
// element as Element, so the diagnosis host resolves it live and cast-free.
function isDatasetRecord(value: unknown): value is DiagnosisDatasetRecord {
  return typeof value === "object" && value !== null;
}

// Open construction surface: builds the sole per-root object, constructs the
// twelve parts, and wires their hook records. Options supplied here run
// through updateOptions, so each reflected attribute that changes takes its
// standard reaction before the caller mounts.
function createEnhanceContext(element: Element, options?: EnhancementOptions): EnhancedElementContext {
  const root = element as HTMLElement;
  let generation = 0;
  const scope = `tqv-${Math.random().toString(36).slice(2, 10)}`;
  const rawDomParagraphs = new Map<Element, RawDomParagraphRecord>();
  let preparedStyle: PreparedStyleState | null = null;
  const diagnosis = createDiagnosisManager({
    get dataset() {
      const candidate = Reflect.get(element, "dataset");
      return isDatasetRecord(candidate) ? candidate : undefined;
    },
  });

  const stateMachine = createEnhancementStateMachine();
  const scheduler = createSchedulerRegistration();
  const eventChannel = createEventChannel(root);

  const contextBase: ContextCoreBase = {
    element,
    get generation() {
      return generation;
    },
    scope,
    rawDomParagraphs,
    diagnosis,
    get preparedStyle() {
      return preparedStyle;
    },
    set preparedStyle(value: PreparedStyleState | null) {
      preparedStyle = value;
    },
    update() {
      generation += 1;
      return generation;
    },
    destroy() {
      rawDomParagraphs.clear();
      if (preparedStyle) {
        releasePreparedStyleState(preparedStyle, context);
        preparedStyle = null;
      }
      diagnosis.dispose();
    },
  };
  // One widening to the full surface: the wiring below hands the parts a
  // context whose part fields are attached by defineProperties before any
  // part reads them.
  const context = contextBase as EnhancedElementContext;

  // Part bindings are const at their construction sites below. The hook
  // records close over those bindings, so parts may reference siblings
  // constructed after them; every hook runs after the full wiring.

  const failureReaction = (message: string, error: unknown): void => {
    context.diagnosis.set("tiqianCapabilityIssue", "FontCapabilityPreparationFailed");
    console.warn(message, error);
  };
  const destroyRuntimeRoot = (): void => {
    destroyRoot(context, root);
  };

  // Attribute-change reaction shared by the web component shell path and
  // programmatic updateOptions callers. Port of the former session's
  // #attributeChanged.
  const optionsChangedReaction: OptionsChangedReaction = (name, oldValue, newValue) => {
    if (oldValue === newValue) return;
    if (name === "disabled") {
      // DisabledAttributeOwnsTeardown: adding the attribute uses the same
      // source restoration and cancellation path as a connected lifecycle
      // restart; connectedCallback then stops before any new work. Removing it
      // re-enters the complete snapshot/runtime lifecycle from semantic source.
      if (stateMachine.connected) mountLifecycle.restartConnectedLifecycle();
      return;
    }
    if (name === "snapshot-ref") {
      // UpgradeAttributeReactionGuard: when an SSR element is defined after it
      // was parsed, the platform reports its existing observed attributes
      // before connectedCallback. `isConnected` is already true at that point,
      // but this is not a client navigation and must not discard the server's
      // snapshot-font marker.
      if (stateMachine.connected) mountLifecycle.restartConnectedLifecycle();
      return;
    }
    if (
      name !== "emphasis-dot-gap-em" &&
      name !== "strong-as-emphasis-marks"
    ) return;
    if (!root.isConnected) return;
    // PreMountAttributeReflectionNoRestart: option reflection runs before the
    // owning mount (createEnhanceContext applies options first), and a
    // restart needs a connected lifecycle to restart. The values already sit
    // on the root attributes, where the coming mount reads them; attribute
    // edits during a deferred-teardown gap still reject adoption through the
    // detach attribute snapshot comparison.
    if (!stateMachine.connected) return;
    // LatestObservedAttributeGeneration: strong emphasis controls snapshot
    // eligibility, while all public options belong to the same connection
    // generation. An initial async gate must never commit captured old values.
    if (!stateMachine.dispatched) {
      mountLifecycle.restartConnectedLifecycle();
      return;
    }
    if (stateMachine.snapshotAdopted || isLoadedSnapshotAdopted(root)) {
      snapshotAdoption.invalidateAndEnhance();
      return;
    }
    contextState.refreshRuntimeFromSource();
  };

  const optionsLedger = createOptionsLedger(root, optionsChangedReaction);

  const contextState = createContextState(root, stateMachine, scheduler, {
    currentGeneration: () => context.generation,
    clearResponsiveRetarget: () => responsive.clearResponsiveRetarget(),
    paragraphMeasureSignature: () => responsive.paragraphMeasureSignature(),
    paragraphMeasureSignatureFromObserved: () => responsive.paragraphMeasureSignatureFromObserved(),
    paragraphWidthSignature: () => paragraphWidthSignature(root),
    lastParagraphWidths: () => responsive.lastParagraphWidths(),
    lastParagraphMeasures: () => responsive.lastParagraphMeasures(),
    setTypographyBaseline: (value) => typography.setLastTypography(value),
    setPendingCommittedMeasures: (value) => responsive.setPendingCommittedMeasures(value),
    setCommittedMeasureLedger: (value) => responsive.setCommittedMeasureLedger(value),
    maximumMeasureActive: () => responsive.maximumMeasureActive(),
    settleFinishedWork: (currentMeasures, currentParagraphWidths) =>
      responsive.settleFinishedWork(currentMeasures, currentParagraphWidths),
    scheduleContentDriftProbeFrame: (operation) => effectSync.scheduleContentDriftProbeFrame(operation),
    contentProbeFramePending: () => effectSync.contentProbeFramePending(),
    ensureViewportResizeListener: () => responsive.ensureViewportResizeListener(),
    scheduleResponsiveGeometryCommit: () => responsive.scheduleResponsiveGeometryCommit(),
    stopTypographyObservation: () => typography.stopTypographyObservation(),
    observeContent: () => effectSync.observeContent(),
    observeLayoutWorkInputs: () => typography.observeLayoutWorkInputs(),
    stopLayoutWorkInputObservation: () => typography.stopLayoutWorkInputObservation(),
    advanceTypographyBaselineAfterCancellation: () => typography.advanceTypographyBaselineAfterCancellation(),
    cancelRootLayoutWork: () => globalServices().coordination.layoutJobPool.cancelJob(root),
    deactivateWorkerRegistration: () => scheduler.setWorkerActive(false),
    onWorkerAttached: () => visibility.observeParagraphTiers(globalServices().coordination.layoutJobPool),
    dispatchProgressiveEnhance: (generationValue, dispatchOptions) =>
      progressiveDispatch.dispatchProgressiveEnhance(generationValue, dispatchOptions),
    destroyRuntimeRoot,
    dropGridMetrics: () => responsive.dropGridMetrics(),
    reportRefreshFailure: failureReaction,
    runRelayoutDriver: () => relayout(context, root),
  });

  const snapshotAdoption = createSnapshotAdoption(root, stateMachine, diagnosis, {
    currentGeneration: () => context.generation,
    beginLayoutWork: (workOptions) => contextState.beginLayoutWork(workOptions),
    finishLayoutWorkAndObserve: () => contextState.finishLayoutWorkAndObserve(),
    dispatchRelayout: (observedMeasures) => contextState.dispatchRelayout(observedMeasures),
    destroyRuntimeRoot,
    restoreLoadedSnapshot: () => restoreLoadedSnapshot(root, context),
    adoptRequestedSnapshot: (isCurrent, anchors) =>
      tryAdoptRequestedSnapshot(root, context, root.ownerDocument, isCurrent, anchors),
    dispatchProgressiveEnhance: (generationValue, dispatchOptions) =>
      progressiveDispatch.dispatchProgressiveEnhance(generationValue, dispatchOptions),
    notifySnapshotRelayoutReady: (detail) =>
      eventChannel.notify("tiqian:relayout-ready", detail),
    reportMissRecoveryFailure: failureReaction,
  });

  const typography = createTypographyManager(root, stateMachine, snapshotAdoption, diagnosis, scheduler, {
    currentGeneration: () => context.generation,
    restartConnectedLifecycle: () => mountLifecycle.restartConnectedLifecycle(),
    refreshRuntimeFromSource: () => contextState.refreshRuntimeFromSource(),
    clearResponsiveRetarget: () => responsive.clearResponsiveRetarget(),
    ensureViewportResizeListener: () => responsive.ensureViewportResizeListener(),
    scheduleResponsiveGeometryCommit: () => responsive.scheduleResponsiveGeometryCommit(),
    deactivateLayoutWorker: () => contextState.deactivateLayoutWorker(),
    setCommittedMeasureLedger: (value) => responsive.setCommittedMeasureLedger(value),
  });

  const responsive = createResponsiveManager(root, stateMachine, scheduler, {
    currentGeneration: () => context.generation,
    snapshotFontSessionActive: () => snapshotAdoption.snapshotFontSessionActive(),
    observeTypography: () => typography.observeTypography(),
    scheduleTypographyCheck: (force) => typography.scheduleTypographyCheck(force),
    typographyBaseline: () => typography.lastTypography,
    setTypographyBaseline: (value) => typography.setLastTypography(value),
    observeContent: () => effectSync.observeContent(),
    contentProbeFramePending: () => effectSync.contentProbeFramePending(),
    takeContentTainted: () => effectSync.takeContentTainted(),
    dispatchContentReconcile: (paragraphs) => effectSync.dispatchContentReconcile(paragraphs),
    cancelCapturedLayoutForLatestGeometry: () => contextState.cancelCapturedLayoutForLatestGeometry(),
    dispatchRelayout: (observedMeasures) => contextState.dispatchRelayout(observedMeasures),
    finishLayoutWorkAndObserve: () => contextState.finishLayoutWorkAndObserve(),
    refreshRuntimeFromSource: (refreshOptions) => contextState.refreshRuntimeFromSource(refreshOptions),
    cancelCapturedLayoutForTypographyChange: () => typography.cancelCapturedLayoutForTypographyChange(),
    dispatchProgressiveEnhance: (generationValue, dispatchOptions) =>
      progressiveDispatch.dispatchProgressiveEnhance(generationValue, dispatchOptions),
    snapshotInvalidateAndEnhance: (invalidateOptions) => snapshotAdoption.invalidateAndEnhance(invalidateOptions),
    tryReadoptSnapshotAtMaximumMeasure: () => {
      snapshotAdoption.tryReadoptSnapshotAtMaximumMeasure();
    },
    reportRefreshFailure: failureReaction,
  });

  const effectSync = createEffectSync(root, stateMachine, scheduler, {
    renderedRawDomParagraphs: () => renderedRawDomParagraphs(context, root),
    probeRootContentDrift: () => probeRootContentDrift(context, root),
    reconcileRoot: (paragraphs) => reconcileRoot(context, root, paragraphs),
    paragraphCandidates: () => {
      const options = contextState.runtimeOptions;
      return options ? contextState.paragraphCandidates(root, options.paragraphSelector) : [];
    },
    trackedParagraphSources: () => contextState.paragraphs.map((paragraph) => paragraph.source),
    beginLayoutWork: (workOptions) => contextState.beginLayoutWork(workOptions),
    finishLayoutWorkAndObserve: () => contextState.finishLayoutWorkAndObserve(),
    ensureLayoutWorker: () => contextState.ensureLayoutWorker(),
    syncLayoutWorker: () => contextState.syncLayoutWorker(),
    cancelCapturedLayoutForLatestGeometry: () => contextState.cancelCapturedLayoutForLatestGeometry(),
    scheduleResponsiveGeometryCommit: () => responsive.scheduleResponsiveGeometryCommit(),
    paragraphMeasureSignature: () => responsive.paragraphMeasureSignature(),
    setLastParagraphMeasures: (value) => responsive.setLastParagraphMeasures(value),
    setLastParagraphWidths: (value) => responsive.setLastParagraphWidths(value),
  });

  const visibility = createVisibilityManager(root, stateMachine, scheduler, {
    scheduleResponsiveGeometryCommit: () => responsive.scheduleResponsiveGeometryCommit(),
  });

  const domWriteLayer = createDomWriteLayer(root, rawDomParagraphs, {
    setRuntimeEstablished: (value) => contextState.setRuntimeEstablished(value),
    renderedRawDomParagraphs: () => renderedRawDomParagraphs(context, root),
  });

  const foreignGuard = createForeignGuard(root, stateMachine, contextState);

  const progressiveDispatch = createProgressiveDispatch(root, context, {
    stateMachine,
    contextState,
    optionsLedger,
    snapshotAdoption,
    scheduler,
  });

  const initialEnhance = createInitialEnhance(root, context, {
    stateMachine,
    contextState,
    snapshotAdoption,
    typography,
    eventChannel,
    scheduler,
    progressiveDispatch,
    adoptRequestedSnapshot: (isCurrent) =>
      tryAdoptRequestedSnapshot(root, context, root.ownerDocument, isCurrent, snapshotAdoption.adoptionAnchors()),
    clearResponsiveRetarget: () => responsive.clearResponsiveRetarget(),
  });

  const mountLifecycle = createMount(root, context, {
    stateMachine,
    contextState,
    optionsLedger,
    snapshotAdoption,
    typography,
    visibility,
    responsive,
    effectSync,
    eventChannel,
    scheduler,
    foreignGuard,
    initialEnhance,
    destroyRuntimeRoot,
    detachRuntimeRoot: () => detachRoot(context, root),
    detachLoadedSnapshot: () => {
      detachLoadedSnapshot(root, context);
    },
    releasePreparedValueStyleRoot: () => {
      releasePreparedValueStyleRoot(root, context);
    },
    detachRootFromPool: () => globalServices().coordination.layoutJobPool.detach(root),
  });

  Object.defineProperties(context, {
    stateMachine: { value: stateMachine },
    contextState: { value: contextState },
    optionsLedger: { value: optionsLedger },
    eventChannel: { value: eventChannel },
    scheduler: { value: scheduler },
    responsive: { value: responsive },
    typography: { value: typography },
    visibility: { value: visibility },
    effectSync: { value: effectSync },
    snapshotAdoption: { value: snapshotAdoption },
    domWriteLayer: { value: domWriteLayer },
    isConnected: { get: () => root.isConnected },
    diagnostics: { get: () => eventChannel.lastDiagnostics },
    mount: { value: () => mountLifecycle.mount() },
    unmount: { value: () => mountLifecycle.unmount() },
    updateOptions: {
      value: (nextOptions: EnhancementOptions) => optionsLedger.updateOptions(nextOptions),
    },
    on: {
      value: (event: EnhancementEvent, callback: EnhancementEventCallback) => eventChannel.on(event, callback),
    },
    onReady: {
      value: (callback: EnhancementEventCallback) => eventChannel.onReady(callback),
    },
    onRelayoutReady: {
      value: (callback: EnhancementEventCallback) => eventChannel.onRelayoutReady(callback),
    },
    relayout: {
      // Host-driven relayout (a container size change or an external style
      // refresh): mark both responsive bits so the next commit treats the
      // geometry as unsettled, then schedule it through the coordinator frame.
      value: () => {
        if (!root.isConnected || !stateMachine.dispatched) return;
        stateMachine.invalidate(InvalidationReason.ResponsiveCommit);
        stateMachine.invalidate(InvalidationReason.ResponsiveRelayout);
        responsive.scheduleResponsiveGeometryCommit();
      },
    },
    relayoutSync: {
      value: (options: SynchronousRelayoutOptions = {}) => {
        if (!root.isConnected || optionsLedger.disabled) return 0;
        if (!stateMachine.dispatched) throw new Error("Wait for tiqian:ready before relayoutSync");
        if (options.firstLineIndentIc != null && !Number.isFinite(options.firstLineIndentIc)) {
          throw new TypeError("firstLineIndentIc must be finite");
        }
        const startedAt = Date.now();
        const currentOptions = contextState.runtimeOptions;

        // Supersede queued work before reclaiming its source. Synchronous
        // layout uses loaded browser fonts and never waits for a worker.
        initialEnhance.abortEnhancePipeline();
        stateMachine.claimEnhanceRequest();
        globalServices().coordination.layoutJobPool.cancelJob(root);
        scheduler.setWorkerActive(false);
        scheduler.cancelFrame(responsive.responsiveCommitCallback());
        responsive.clearResponsiveRetarget();
        responsive.dropGridMetrics();

        // Snapshots and mixed snapshot/runtime roots must both yield their
        // semantic backing; the original paragraph elements stay in place.
        destroyRoot(context, root);
        if (isLoadedSnapshotAdopted(root)) restoreLoadedSnapshot(root, context);
        stateMachine.snapshotAdopted = false;
        snapshotAdoption.setSnapshotEnhancedCount(0);
        snapshotAdoption.releaseSnapshotFontSession();
        root.removeAttribute("data-tiqian-snapshot-render-font");
        diagnosis.clear("tiqianSnapshotCount");

        // Reset a mixed snapshot's completion-only selector to the full prose
        // selector, preserving the host's other resolved typography options.
        const defaults = optionsLedger.resolveEngineOptions(root, { ...optionsLedger.baseEnhanceOptions() });
        const syncOptions = {
          ...(currentOptions ?? defaults),
          ...options,
          paragraphSelector: defaults.paragraphSelector,
          snapshotFontSession: null,
          requireSnapshotLayoutWorker: false,
        };
        stateMachine.consumeObservedGeometry();
        stateMachine.clearInvalidation(InvalidationReason.ResponsiveRelayout);
        contextState.beginLayoutWork();
        stateMachine.runtimeActive = true;
        stateMachine.completionGateOpen = true;

        // The one-shot driver completes every paragraph without frame or
        // microtask yields. Completion refreshes the normal observer baselines.
        try {
          const count = enhance(context, root, syncOptions, true);
          const durationMs = Date.now() - startedAt;
          eventChannel.notify("tiqian:relayout-ready", {
            enhancedCount: count, runtimeEnhancedCount: count, snapshotCount: 0,
            issueCount: diagnosis.issues.length, durationMs, maxSliceMs: durationMs,
            relayout: true, stale: false,
          });
          return count;
        } finally {
          if (stateMachine.workInFlight) contextState.finishLayoutWorkAndObserve();
        }
      },
    },
    invalidate: {
      // Manual orthogonal invalidation for programmatic hosts. Typography bits
      // route through the typography check; responsive bits route through the
      // geometry commit.
      value: (reason: number) => {
        stateMachine.invalidate(reason);
        if (!root.isConnected || !stateMachine.dispatched) return;
        if (
          reason & (InvalidationReason.DeferredTypographyCheck | InvalidationReason.TypographyRefreshForced)
        ) {
          typography.scheduleTypographyCheck(true);
          return;
        }
        responsive.scheduleResponsiveGeometryCommit();
      },
    },
  });

  if (options) optionsLedger.updateOptions(options);
  return context;
}

export { createEnhanceContext };
export type { EnhancedElementContext };
