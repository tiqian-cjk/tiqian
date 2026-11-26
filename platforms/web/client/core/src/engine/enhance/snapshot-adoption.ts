// SnapshotAdoption — the snapshot lifecycle for one enhanced element
// (core-neutral parts ruling). Owns the snapshot font session entry and
// its rejected-attempt guard, the snapshot enhanced count, the adoption
// anchor bracket, the maximum-measure adoption/invalidate/re-adopt paths
// and the snapshot session descriptor view dissolved from root-state.ts.
// preparedDomEnabled had no write path in the dissolved root-state (it was
// constructed true and never flipped), so the active-options view returns
// the resolved options unchanged.

import {
  isLoadedSnapshotAdopted,
} from "../../sampler/snapshot/loaded-snapshots.js";
import { snapshotCompletionSelector } from "../../sampler/snapshot/snapshot-completion.js";
import {
  createSnapshotFontSessionEntry,
  releaseSnapshotFontSession as releaseSnapshotFontSessionEntry,
} from "../snapshot-font.js";
import type { SnapshotFontSessionEntry } from "../snapshot-font.js";
import { loadSnapshotFontFallback } from "../loaders/font-loader.js";
import { snapshotFontAttemptSignature as snapshotFontAttemptSignatureOf } from "../../sampler/signatures.js";
import {
  captureViewportAnchor,
  compensateViewportAnchor,
  releaseNativeScrollAnchoring,
} from "../coordination/viewport-anchor.js";
import { snapshotSessionCallbacks } from "../../measurement/browser-font-replay.js";
import type { SnapshotSessionCallbacks } from "../../measurement/browser-font-replay.js";
import { conformingSnapshotFontSessionId } from "../lifecycle.js";
import type { EnhanceOptions } from "../lifecycle.js";
import type { BrowserFontSessionHandle } from "../../measurement/browser-fonts.js";
import type { SnapshotAdoptAnchors } from "../../sampler/snapshot/precomputed.js";
import type { DiagnosisManager } from "../context/diagnosis-manager.js";
import type { EnhancementStateMachine } from "./state-machine.js";
import type { LayoutWorkOptions } from "./context-state.js";

export const SNAPSHOT_RENDER_FONT_ATTRIBUTE = "data-tiqian-snapshot-render-font";

const RESPONSIVE_SNAPSHOT_GEOMETRY_MISSES = new Set([
  "SnapshotWidthMismatch",
  "SnapshotWidthChangedDuringValidation",
]);

// Descriptor of a conforming snapshot session: the shaping callbacks of the
// browser replay session. Dissolved from root-state.ts (which embedded the
// root; the descriptor is now a pure function of the active options).
export type SnapshotSessionDescriptor = SnapshotSessionCallbacks;

// activeSnapshotSessionDescriptor: the former root-state view. Once prepared
// DOM is disabled the session is always null; with the dissolved flag
// permanently enabled the canonical options decide alone.
export function activeSnapshotSessionDescriptor(options: EnhanceOptions): SnapshotSessionDescriptor | null {
  const sessionId = conformingSnapshotFontSessionId(options);
  if (sessionId == null) return null;
  return snapshotSessionCallbacks(sessionId);
}

/** Callback run before the progressive dispatch starts its work. */
export type BeforeDispatchCallback = () => void;

/** Live currency probe consulted before an adoption commit. */
export type SnapshotIsCurrentProbe = () => boolean;

export interface EnhanceDispatchOptions {
  beforeDispatch?: BeforeDispatchCallback | null;
  paragraphSelector?: string | null;
  revalidateSnapshotFont?: boolean;
}

export interface SnapshotInvalidateOptions {
  restoreBeforeLoad?: boolean;
}

// A type alias on purpose: object literal types carry the implicit index
// signature that flows this detail into the event channel's Record param.
export type SnapshotRelayoutReadyDetail = {
  enhancedCount: number;
  issueCount: number;
  durationMs: number;
  maxSliceMs: number;
  relayout: true;
  snapshot: true;
}

export type SnapshotAdoptionOutcome =
  | { adopted: false; reason?: string }
  | { adopted: true; count: number };

export interface SnapshotAdoptionHooks {
  currentGeneration(): number;
  /** ContextState: layout-work drive surfaces. */
  beginLayoutWork(options?: LayoutWorkOptions): number;
  finishLayoutWorkAndObserve(): boolean;
  dispatchRelayout(observedMeasures?: string | null): void;
  destroyRuntimeRoot(): void;
  /** Composition root: the context-bound loaded-snapshot helpers. */
  restoreLoadedSnapshot(): boolean;
  adoptRequestedSnapshot(
    isCurrent: SnapshotIsCurrentProbe,
    anchors: SnapshotAdoptAnchors,
  ): Promise<SnapshotAdoptionOutcome>;
  /** Lifecycle: the progressive enhance dispatch. */
  dispatchProgressiveEnhance(generation: number, options?: EnhanceDispatchOptions): Promise<boolean>;
  /** EventChannel: the snapshot-only relayout-ready completion. */
  notifySnapshotRelayoutReady(detail: SnapshotRelayoutReadyDetail): void;
  /** DiagnosisManager + console path for miss-recovery failures. */
  reportMissRecoveryFailure(message: string, error: unknown): void;
}

export interface SnapshotAdoption {
  snapshotFontSessionActive(): boolean;
  snapshotFontSessionReference(): string | null;
  snapshotEnhancedCount(): number;
  setSnapshotEnhancedCount(value: number): void;
  snapshotFontRejectedAttempt(): string;
  setSnapshotFontRejectedAttempt(value: string): void;
  prepareSnapshotFontSession(
    generation: number,
    request: number,
    revalidateExisting?: boolean,
    signal?: AbortSignal | null,
  ): Promise<BrowserFontSessionHandle | null>;
  /** The held entry's render-font preparation (throws when no entry). */
  prepareSnapshotRenderFont(handle: BrowserFontSessionHandle): Promise<unknown>;
  releaseSnapshotFontSession(): boolean;
  snapshotFontAttemptSignature(reference?: string | null): string;
  adoptionAnchors(): SnapshotAdoptAnchors;
  invalidateAndEnhance(options?: SnapshotInvalidateOptions): Promise<void>;
  acceptValidatedSnapshotGeometry(): void;
  tryReadoptSnapshotAtMaximumMeasure(): Promise<void>;
}

function createSnapshotAdoption(
  root: HTMLElement,
  stateMachine: EnhancementStateMachine,
  diagnosis: DiagnosisManager,
  hooks: SnapshotAdoptionHooks,
): SnapshotAdoption {
  let snapshotFontSession: SnapshotFontSessionEntry | null = null;
  let snapshotFontRejectedAttempt = "";
  let snapshotEnhancedCount = 0;

  // SnapshotAdoptionAnchorCompensation adapter: the adoption loop in
  // precomputed.js commits one paragraph per cooperative slice; this feeds
  // its per-commit bracket from this element's anchor policy.
  function adoptionAnchors(): SnapshotAdoptAnchors {
    return {
      capture: () => captureViewportAnchor(root),
      compensate: (anchor) => compensateViewportAnchor(root, anchor),
    };
  }

  async function prepareSnapshotFontSession(
    generation: number,
    request: number,
    revalidateExisting = true,
    signal: AbortSignal | null = null,
  ): Promise<BrowserFontSessionHandle | null> {
    const reference = root.getAttribute("snapshot-ref");
    if (!reference) {
      if (generation === hooks.currentGeneration() && request === stateMachine.transaction.enhanceRequest) {
        releaseSnapshotFontSession();
      }
      return null;
    }
    if (snapshotFontRejectedAttempt === snapshotFontAttemptSignatureOf(root, reference)) {
      return null;
    }
    // SnapshotFontValidationRenderProjection: the SSR marker owns first paint,
    // while this session owns runtime validation. Reassert the projection here
    // so a host hydrator cannot make snapshot-font validation depend on attribute
    // reconciliation timing. The caller removes it on every failed session.
    root.setAttribute(SNAPSHOT_RENDER_FONT_ATTRIBUTE, "true");
    const loader = await loadSnapshotFontFallback();
    const existing = snapshotFontSession;
    if (existing?.reference === reference) {
      // SnapshotFontSessionLiveRevalidation: reuse immutable server replay tables
      // only after the browser adapter revalidates every live snapshot input. A
      // caller that already proved this is a width-only retarget may reuse the
      // same live contract without repeating width-independent font probes.
      if (revalidateExisting) await existing.revalidate(root, existing.handle);
      if (
        !root.isConnected || generation !== hooks.currentGeneration() ||
        request !== stateMachine.transaction.enhanceRequest ||
        root.getAttribute("snapshot-ref") !== reference || signal?.aborted
      ) return null;
      return existing.handle;
    }
    const handle = await loader.prepareBrowserFontSession(root);
    if (
      !root.isConnected || generation !== hooks.currentGeneration() ||
      request !== stateMachine.transaction.enhanceRequest ||
      root.getAttribute("snapshot-ref") !== reference || signal?.aborted
    ) {
      loader.releaseBrowserFontSession(handle);
      return null;
    }
    const previous = snapshotFontSession;
    const next = createSnapshotFontSessionEntry(reference, handle, loader);
    snapshotFontSession = next;
    if (previous && previous !== next) previous.release(previous.handle);
    return handle;
  }

  function releaseSnapshotFontSession(): boolean {
    const entry = snapshotFontSession;
    if (!entry) return false;
    snapshotFontSession = null;
    return releaseSnapshotFontSessionEntry(entry);
  }

  async function invalidateAndEnhance({ restoreBeforeLoad = false }: SnapshotInvalidateOptions = {}): Promise<void> {
    if (!stateMachine.snapshotAdopted && !isLoadedSnapshotAdopted(root)) return;
    const generation = hooks.currentGeneration();
    const signal = stateMachine.transaction.abortController?.signal ?? null;
    stateMachine.dispatched = false;
    let activeRequest = stateMachine.claimEnhanceRequest();
    hooks.beginLayoutWork();
    const restoreImmediatelyBeforeDispatch = () => {
      if (!hooks.restoreLoadedSnapshot()) throw new Error("Adopted snapshot could not be restored");
      stateMachine.snapshotAdopted = false;
      snapshotEnhancedCount = 0;
      diagnosis.clear("tiqianSnapshotCount");
      if (stateMachine.runtimeActive) {
        hooks.destroyRuntimeRoot();
        stateMachine.runtimeActive = false;
      }
    };
    if (restoreBeforeLoad) restoreImmediatelyBeforeDispatch();
    try {
      if (
        !root.isConnected || generation !== hooks.currentGeneration() ||
        activeRequest !== stateMachine.transaction.enhanceRequest || signal?.aborted
      ) return;
      const enhancement = hooks.dispatchProgressiveEnhance(generation, restoreBeforeLoad
        ? undefined
        : { beforeDispatch: restoreImmediatelyBeforeDispatch });
      // Async functions run synchronously through their first await, so this
      // captures the request generation claimed by dispatchProgressiveEnhance.
      activeRequest = stateMachine.transaction.enhanceRequest;
      await enhancement;
    } catch (error) {
      recoverSnapshotEnhanceFailure(generation, activeRequest, error);
    }
  }

  function recoverSnapshotEnhanceFailure(generation: number, request: number, error: unknown): void {
    if (
      !root.isConnected || generation !== hooks.currentGeneration() ||
      request !== stateMachine.transaction.enhanceRequest
    ) return;
    // Runtime/module failure must not strand the element in an unobserved
    // transition. Normally the adopted snapshot is still live because restore
    // is deferred until the successful dispatch task; retain it and resume the
    // responsive observers. If an exceptional synchronous restore already ran,
    // the readable runtime/SSR backing remains the fallback instead.
    const snapshotStillLive = isLoadedSnapshotAdopted(root);
    stateMachine.snapshotAdopted = snapshotStillLive;
    stateMachine.dispatched = snapshotStillLive || stateMachine.runtimeActive;
    stateMachine.completionGateOpen = false;
    hooks.finishLayoutWorkAndObserve();
    diagnosis.set("tiqianCapabilityIssue", "RuntimeLoadFailed");
    console.warn("Tiqian Web runtime failed to load after snapshot invalidation", error);
  }

  function acceptValidatedSnapshotGeometry(): void {
    // SnapshotValidationConsumesObservedGeometry: adoption rechecks live width,
    // typography and rendered geometry immediately before its atomic commit.
    // Resize/observer notifications recorded while that validation was in
    // flight are therefore already represented by the adopted result. Reset
    // only the consumed bookkeeping here; a later browser event still arrives
    // after observation resumes and invalidates the snapshot normally.
    stateMachine.consumeObservedGeometry();
  }

  async function tryReadoptSnapshotAtMaximumMeasure(): Promise<void> {
    if (!root.hasAttribute("snapshot-ref")) return;
    const generation = hooks.currentGeneration();
    const signal = stateMachine.transaction.abortController?.signal ?? null;
    const startedAt = Date.now();
    const operation = hooks.beginLayoutWork();
    const runtimeSnapshotBackingRestored = stateMachine.runtimeActive;
    if (runtimeSnapshotBackingRestored) {
      // RuntimeSnapshotBackingRestore: the first runtime enhancement retains
      // the exact server-rendered nodes as its teardown backing. Snapshot
      // validation must inspect that immutable SSR artifact, never the current
      // runtime rendering whose structure and digest are intentionally different.
      // DOM event dispatch is synchronous, so restoration and the validation
      // start stay in one task and cannot expose unvalidated SSR as a settled
      // state. A miss below immediately starts a fresh runtime enhancement.
      stateMachine.dispatched = false;
      hooks.destroyRuntimeRoot();
      stateMachine.runtimeActive = false;
    }
    try {
      const snapshot = await hooks.adoptRequestedSnapshot(
        () => root.isConnected && generation === hooks.currentGeneration() &&
          operation === stateMachine.transaction.layoutOperation &&
          !(signal?.aborted ?? false),
        adoptionAnchors(),
      );
      // The adoption commits are over; hand the scroller back to the
      // browser's own anchoring until the next commit path holds it.
      releaseNativeScrollAnchoring(root);
      if (
        !root.isConnected || generation !== hooks.currentGeneration() ||
        operation !== stateMachine.transaction.layoutOperation || signal?.aborted
      ) {
        if (snapshot.adopted) hooks.restoreLoadedSnapshot();
        return;
      }
      if (!snapshot.adopted) {
        diagnosis.set("tiqianSnapshotMiss", snapshot.reason ?? "SnapshotNotAdopted");
        // Full validation is intentionally fail-closed. The existing runtime
        // DOM stayed live throughout. It still carries the previous narrow
        // measure, so a maximum-measure miss must finish with a runtime
        // relayout instead of blessing stale lines as current geometry.
        recoverRuntimeAfterSnapshotMiss(
          operation,
          snapshot.reason,
          runtimeSnapshotBackingRestored,
        );
        return;
      }
      diagnosis.clear("tiqianSnapshotMiss");
      stateMachine.snapshotAdopted = true;
      snapshotEnhancedCount = snapshot.count;
      const completionSelector = snapshotCompletionSelector(root);
      if (completionSelector) {
        if (
          !root.isConnected || generation !== hooks.currentGeneration() ||
          operation !== stateMachine.transaction.layoutOperation || signal?.aborted
        ) {
          return;
        }
        acceptValidatedSnapshotGeometry();
        await hooks.dispatchProgressiveEnhance(generation, {
          paragraphSelector: completionSelector,
        });
        return;
      }
      releaseSnapshotFontSession();
      stateMachine.dispatched = true;
      stateMachine.completionGateOpen = true;
      acceptValidatedSnapshotGeometry();
      hooks.notifySnapshotRelayoutReady({
        enhancedCount: snapshot.count,
        issueCount: 0,
        durationMs: Date.now() - startedAt,
        maxSliceMs: 0,
        relayout: true,
        snapshot: true,
      });
    } catch (error) {
      if (
        !root.isConnected || generation !== hooks.currentGeneration() ||
        operation !== stateMachine.transaction.layoutOperation || signal?.aborted
      ) return;
      diagnosis.set("tiqianSnapshotMiss", "SnapshotValidationFailed");
      console.warn("Tiqian Web responsive snapshot validation failed", error);
      recoverRuntimeAfterSnapshotMiss(
        operation,
        "SnapshotValidationFailed",
        runtimeSnapshotBackingRestored,
      );
    }
  }

  function recoverRuntimeAfterSnapshotMiss(
    operation: number,
    reason: string | undefined,
    runtimeSnapshotBackingRestored = false,
  ): void {
    if (operation !== stateMachine.transaction.layoutOperation) return;
    if (runtimeSnapshotBackingRestored) {
      // Validation failed after the synchronous SSR backing restore. Rebuild
      // runtime state from that source for every miss category; a width-only
      // relayout cannot operate after the prior runtime instance was destroyed.
      const generation = hooks.currentGeneration();
      hooks.dispatchProgressiveEnhance(generation).catch((error) => {
        if (!root.isConnected || generation !== hooks.currentGeneration()) return;
        hooks.finishLayoutWorkAndObserve();
        hooks.reportMissRecoveryFailure("Tiqian Web snapshot miss recovery failed", error);
      });
      return;
    }
    if (reason != null && RESPONSIVE_SNAPSHOT_GEOMETRY_MISSES.has(reason)) {
      relayoutRuntimeAfterSnapshotMiss(operation);
      return;
    }
    if (!stateMachine.runtimeActive) {
      // ReadoptionMissMustReclaimSource: a rapid resize can cancel the active
      // runtime job before a maximum-measure snapshot validation begins. If
      // that validation then misses, the DOM is readable native backing but no
      // owner remains to enhance it. Start a fresh latest-geometry job instead
      // of observing the permanently unclaimed source.
      const generation = hooks.currentGeneration();
      hooks.dispatchProgressiveEnhance(generation).catch((error) => {
        if (!root.isConnected || generation !== hooks.currentGeneration()) return;
        hooks.finishLayoutWorkAndObserve();
        hooks.reportMissRecoveryFailure("Tiqian Web unclaimed snapshot miss recovery failed", error);
      });
      return;
    }
    // Source, typography, font-contract and unknown validation failures make
    // the old lowered source or snapshot-font session untrustworthy. Re-lower and
    // rebuild the font session; a cheap width-only relayout is valid only for
    // the two explicit geometry miss reasons above.
    const generation = hooks.currentGeneration();
    hooks.dispatchProgressiveEnhance(generation).catch((error) => {
      if (!root.isConnected || generation !== hooks.currentGeneration()) return;
      hooks.finishLayoutWorkAndObserve();
      hooks.reportMissRecoveryFailure("Tiqian Web snapshot miss recovery failed", error);
    });
  }

  function relayoutRuntimeAfterSnapshotMiss(operation: number): void {
    if (operation !== stateMachine.transaction.layoutOperation) return;
    hooks.dispatchRelayout(null);
  }

  return {
    snapshotFontSessionActive() {
      return snapshotFontSession != null;
    },
    snapshotFontSessionReference() {
      return snapshotFontSession?.reference ?? null;
    },
    snapshotEnhancedCount() {
      return snapshotEnhancedCount;
    },
    setSnapshotEnhancedCount(value: number) {
      snapshotEnhancedCount = value;
    },
    snapshotFontRejectedAttempt() {
      return snapshotFontRejectedAttempt;
    },
    setSnapshotFontRejectedAttempt(value: string) {
      snapshotFontRejectedAttempt = value;
    },
    prepareSnapshotFontSession,
    prepareSnapshotRenderFont(handle: BrowserFontSessionHandle): Promise<unknown> {
      const entry = snapshotFontSession;
      if (!entry) throw new Error("Snapshot font session unavailable");
      return entry.prepareRenderFont(root, handle);
    },
    releaseSnapshotFontSession,
    snapshotFontAttemptSignature(reference: string | null = root.getAttribute("snapshot-ref")) {
      return snapshotFontAttemptSignatureOf(root, reference);
    },
    adoptionAnchors,
    invalidateAndEnhance,
    acceptValidatedSnapshotGeometry,
    tryReadoptSnapshotAtMaximumMeasure,
  };
}

export { createSnapshotAdoption };
