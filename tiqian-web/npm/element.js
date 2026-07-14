import { loadTiqianRuntime } from "./runtime.js";
import { installTiqianCopyHandler } from "./copy.js";
import {
  fontLoadingAffectsTypography,
  isLoadedSnapshotAdopted,
  lineLengthGridMeasure,
  loadedSnapshotMaximumMeasureMatches,
  needsCjkDashShaping,
  prepareCjkDashShapingIfNeeded,
  restoreLoadedSnapshot,
  tryAdoptRequestedSnapshot,
  waitForTypographyFonts,
} from "./lazy-capabilities.js";
import { ensureTiqianStyles } from "./styles.js";

const ELEMENT_NAME = "tiqian-prose";
const DEFAULT_PARAGRAPH_SELECTOR = "p, li";
const EXACT_RENDER_FONT_ATTRIBUTE = "data-tiqian-exact-render-font";
const EXACT_PREPARED_FALLBACK_ATTRIBUTE = "data-tiqian-exact-layout-fallback";
const RESPONSIVE_LATEST_RETARGET_QUIET_MS = 32;
const RESPONSIVE_SNAPSHOT_GEOMETRY_MISSES = new Set([
  "SnapshotWidthMismatch",
  "SnapshotWidthChangedDuringValidation",
]);
const HTMLElementBase = typeof globalThis.HTMLElement === "function"
  ? globalThis.HTMLElement
  : class TiqianSsrElement {};
let exactFontFallbackPromise;
installTiqianCopyHandler();
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

function loadExactFontFallback() {
  exactFontFallbackPromise ??= Promise.all([
    import("./browser-fonts.js"),
    import("./prepared-dom.js"),
  ]).then(([fonts, preparedDom]) => {
    preparedDom.installPreparedDomRendererBridge();
    return {
      prepareBrowserFontSession: fonts.prepareBrowserFontSession,
      revalidateBrowserFontSession: fonts.revalidateBrowserFontSession,
      releaseBrowserFontSession: fonts.releaseBrowserFontSession,
      installPreparedRenderFontStyle: preparedDom.installPreparedRenderFontStyle,
      releasePreparedRenderFontStyle: preparedDom.releasePreparedRenderFontStyle,
    };
  });
  return exactFontFallbackPromise;
}

class TiqianProseElement extends HTMLElementBase {
  static observedAttributes = [
    "emphasis-dot-gap-em",
    "strong-as-emphasis-marks",
    "snapshot-ref",
  ];

  #forceTypographyRefresh = false;
  #acceptLayoutCompletion = false;
  #capabilityRetryListener = null;
  #connected = false;
  #deferredTypographyCheck = false;
  #fontLoadingDoneListener = null;
  #geometryRevision = 0;
  #generation = 0;
  #hasDispatched = false;
  #layoutWorkInFlight = false;
  #layoutWorkSignaturesCaptured = false;
  #layoutWorkGeometrySignature = "";
  #layoutWorkMaximumMeasure = false;
  #layoutWorkMeasureSignature = "";
  #layoutWorkTypographySignature = "";
  #layoutWorkTypographyObserver = null;
  #layoutWorkFontLoadingDoneListener = null;
  #layoutWorkUsesCapturedMeasure = false;
  #layoutOperation = 0;
  #layoutWorkRevision = 0;
  #enhanceRequest = 0;
  #exactFontRejectedAttempt = "";
  #exactFontSession = null;
  #lastWidth = 0;
  #lastParagraphMeasures = "";
  #lastParagraphWidths = "";
  #lastTypography = "";
  #readyListener = null;
  #resizeFrame = 0;
  #resizeObserver = null;
  #responsiveCommitRequired = false;
  #responsiveRetargetTimer = 0;
  #responsiveRelayoutRequired = false;
  #runtimeCoversSnapshotParagraphs = false;
  #runtimeStateActive = false;
  #snapshotAdopted = false;
  #typographyFrame = 0;
  #typographyObserver = null;
  #viewportResizeListener = null;

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
    this.#connected = true;
    this.#exactFontRejectedAttempt = "";
    const generation = ++this.#generation;
    this.#acceptLayoutCompletion = false;
    this.#hasDispatched = false;
    this.#snapshotAdopted = isLoadedSnapshotAdopted(this);
    const loadStartedAt = performance.now();
    let initialReadyReported = false;
    // OptInStrongSnapshotExclusion: v1 snapshots contain only plain paragraphs,
    // so they cannot claim that a semantic <strong> was lowered to emphasis
    // marks. Keep the default bold path eligible for snapshots; an explicit
    // mapping request with actual <strong> content must enter the runtime.
    const strongEmphasisRuntimeRequired =
      this.strongAsEmphasisMarks && this.querySelector("strong") !== null;
    const runtimePromise = this.hasAttribute("snapshot-ref") && !strongEmphasisRuntimeRequired
      ? null
      : loadTiqianRuntime();
    runtimePromise?.catch(() => {});
    delete this.dataset.tiqianCapabilityIssue;
    delete this.dataset.tiqianEnhanceMs;
    delete this.dataset.tiqianLoadMs;
    delete this.dataset.tiqianMaxSliceMs;
    delete this.dataset.tiqianDashRetryMs;
    delete this.dataset.tiqianRelayoutMs;
    delete this.dataset.tiqianRelayoutMaxSliceMs;
    this.#removeReadyListener();
    this.#stopTypographyObservation();
    this.#readyListener = (event) => {
      if (
        generation !== this.#generation || !this.#hasDispatched ||
        !this.#acceptLayoutCompletion
      ) return;
      const { durationMs, maxSliceMs, capabilityRetry, relayout, stale } = event.detail ?? {};
      if (relayout) {
        if (Number.isFinite(durationMs)) this.dataset.tiqianRelayoutMs = durationMs.toFixed(1);
        if (Number.isFinite(maxSliceMs)) {
          this.dataset.tiqianRelayoutMaxSliceMs = maxSliceMs.toFixed(1);
        }
      } else if (capabilityRetry) {
        if (Number.isFinite(durationMs)) this.dataset.tiqianDashRetryMs = durationMs.toFixed(1);
      } else {
        if (Number.isFinite(durationMs)) this.dataset.tiqianEnhanceMs = durationMs.toFixed(1);
        if (Number.isFinite(maxSliceMs)) this.dataset.tiqianMaxSliceMs = maxSliceMs.toFixed(1);
        if (!initialReadyReported) {
          initialReadyReported = true;
          this.dataset.tiqianLoadMs = (performance.now() - loadStartedAt).toFixed(1);
        }
      }
      // ExactPreparedDomFallbackSingleFlight: once browser replay proves that
      // the exact HarfBuzz result cannot be represented at this effective
      // measure, retain the readable browser-metric rendering without letting
      // font loading events start the same failed exact session indefinitely.
      // A route reconnect or a different line-length grid gets a fresh attempt.
      if (this.hasAttribute(EXACT_PREPARED_FALLBACK_ATTRIBUTE)) {
        this.#exactFontRejectedAttempt = this.#exactFontAttemptSignature();
        this.#releaseExactFontSession();
        this.removeAttribute(EXACT_RENDER_FONT_ATTRIBUTE);
      }
      if (stale) this.#responsiveCommitRequired = true;
      this.#finishLayoutWorkAndObserve();
    };
    this.addEventListener("tiqian:ready", this.#readyListener);
    this.addEventListener("tiqian:relayout-ready", this.#readyListener);
    this.#removeCapabilityRetryListener();
    this.#capabilityRetryListener = () => {
      if (generation !== this.#generation || !this.#hasDispatched) return;
      // The Kotlin side emits this only when a retry job actually starts. A
      // request may otherwise be queued behind enhancement or become a no-op,
      // neither of which may claim responsive-work ownership here.
      this.#beginLayoutWork();
      this.#acceptLayoutCompletion = true;
    };
    this.addEventListener("tiqian:capability-retry-start", this.#capabilityRetryListener);
    this.#ensureViewportResizeListener();

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
      .then(() => this.hasAttribute("snapshot-ref") && !strongEmphasisRuntimeRequired
        ? undefined
        : waitForTypographyFonts(document.fonts, this.#typographyElements()))
      .then(nextFrame)
      .then(async () => {
        if (!this.isConnected || generation !== this.#generation) return;
        const enhanceStartedAt = performance.now();
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
          this.#snapshotAdopted = true;
          // SnapshotListRuntimeCompletion: v1 snapshots intentionally contain
          // only plain <p> entries. Keep those exact SSR paragraphs live, but
          // run the Web engine over list-item text. The static stylesheet already
          // owns the stable 2ic indent and the browser continues to own markers;
          // this runtime pass only supplies Tiqian line layout inside that box.
          if (this.querySelector("ol > li, ul > li")) {
            await (runtimePromise ?? loadTiqianRuntime());
            if (!this.isConnected || generation !== this.#generation) {
              restoreLoadedSnapshot(this);
              return;
            }
            await this.#dispatchProgressiveEnhance(generation, {
              paragraphSelector: "li",
              runtimeCoversSnapshotParagraphs: false,
            });
            return;
          }
          if (!this.#runtimeStateActive) this.#releaseExactFontSession();
          this.#hasDispatched = true;
          this.#acceptLayoutCompletion = true;
          this.dispatchEvent(new CustomEvent("tiqian:ready", {
            detail: {
              enhancedCount: snapshot.count,
              issueCount: 0,
              durationMs: performance.now() - enhanceStartedAt,
              maxSliceMs: 0,
              snapshot: true,
            },
          }));
          return;
        }
        await (runtimePromise ?? loadTiqianRuntime());
        if (!this.isConnected || generation !== this.#generation) return;
        if (!(await this.#dispatchProgressiveEnhance(generation))) return;
      })
      .catch((error) => {
        if (generation !== this.#generation) return;
        this.#acceptLayoutCompletion = false;
        this.#layoutWorkInFlight = false;
        this.#clearResponsiveRetarget();
        this.#releaseExactFontSession();
        if (!isLoadedSnapshotAdopted(this)) this.removeAttribute(EXACT_RENDER_FONT_ATTRIBUTE);
        this.#removeReadyListener();
        this.#removeCapabilityRetryListener();
        this.dataset.tiqianCapabilityIssue = "RuntimeLoadFailed";
        console.warn("Tiqian Web runtime failed to load", error);
      });
  }

  disconnectedCallback() {
    this.#connected = false;
    ++this.#generation;
    this.#enhanceRequest += 1;
    this.#layoutOperation += 1;
    this.#acceptLayoutCompletion = false;
    this.#hasDispatched = false;
    this.#layoutWorkInFlight = false;
    this.#responsiveCommitRequired = false;
    this.#responsiveRelayoutRequired = false;
    this.#clearResponsiveRetarget();
    this.#removeReadyListener();
    this.#removeCapabilityRetryListener();
    this.#stopTypographyObservation();
    this.#stopLayoutWorkInputObservation();
    this.#stopWidthObservation();
    if (this.#snapshotAdopted || isLoadedSnapshotAdopted(this)) {
      restoreLoadedSnapshot(this);
    }
    this.#snapshotAdopted = false;
    // SourceOwnerTeardown: restore the snapshot backing first, then let the
    // runtime return that exact DOM to its original SSR nodes. Synchronous
    // teardown also prevents a stale progressive ready event from completing a
    // later connection.
    if (this.#runtimeStateActive) dispatch("tiqian:destroy", this);
    this.#runtimeStateActive = false;
    this.#runtimeCoversSnapshotParagraphs = false;
    this.#releaseExactFontSession();
    this.removeAttribute(EXACT_RENDER_FONT_ATTRIBUTE);
  }

  attributeChangedCallback(name, oldValue, newValue) {
    if (oldValue === newValue) return;
    if (name === "snapshot-ref") {
      // UpgradeAttributeReactionGuard: when an SSR element is defined after it
      // was parsed, the platform reports its existing observed attributes
      // before connectedCallback. `isConnected` is already true at that point,
      // but this is not a client navigation and must not discard the server's
      // exact-font marker.
      if (this.#connected) this.#restartForSnapshotReference();
      return;
    }
    if (name !== "emphasis-dot-gap-em" && name !== "strong-as-emphasis-marks") return;
    if (!this.isConnected || !this.#hasDispatched) return;
    if (this.#snapshotAdopted || isLoadedSnapshotAdopted(this)) {
      this.#invalidateSnapshotAndEnhance();
      return;
    }
    this.#dispatchProgressiveEnhance(this.#generation).catch((error) => {
      this.dataset.tiqianCapabilityIssue = "FontCapabilityPreparationFailed";
      console.warn("Tiqian Web font capability preparation failed", error);
    });
  }

  #baseEnhanceOptions() {
    const emphasisDotGapEm = this.emphasisDotGapEm;
    const strongAsEmphasisMarks = this.strongAsEmphasisMarks;
    if (emphasisDotGapEm == null && !strongAsEmphasisMarks) return undefined;
    return {
      ...(emphasisDotGapEm == null ? {} : { emphasisDotGapEm }),
      ...(strongAsEmphasisMarks ? { strongAsEmphasisMarks: true } : {}),
    };
  }

  #restartForSnapshotReference() {
    ++this.#generation;
    this.#enhanceRequest += 1;
    this.#hasDispatched = false;
    this.#acceptLayoutCompletion = false;
    this.#snapshotAdopted = false;
    this.#removeReadyListener();
    this.#removeCapabilityRetryListener();
    this.#stopTypographyObservation();
    this.#stopLayoutWorkInputObservation();
    this.#stopWidthObservation();
    restoreLoadedSnapshot(this);
    if (this.#runtimeStateActive) dispatch("tiqian:destroy", this);
    this.#runtimeStateActive = false;
    this.#runtimeCoversSnapshotParagraphs = false;
    this.#releaseExactFontSession();
    this.removeAttribute(EXACT_RENDER_FONT_ATTRIBUTE);
    if (this.isConnected) this.connectedCallback();
  }

  async #dispatchProgressiveEnhance(
    generation,
    {
      forceAtomic = false,
      forceProgressive = false,
      beforeDispatch = null,
      paragraphSelector = null,
      runtimeCoversSnapshotParagraphs = true,
    } = {},
  ) {
    const request = ++this.#enhanceRequest;
    const atomicRefresh = !forceProgressive && (forceAtomic || this.#runtimeStateActive);
    this.#beginLayoutWork();
    const baseOptions = {
      ...(this.#baseEnhanceOptions() ?? {}),
      ...(paragraphSelector ? { paragraphSelector } : {}),
    };
    const needsDash = needsCjkDashShaping(this);
    const dashCapabilityPromise = needsDash
      ? prepareCjkDashShapingIfNeeded(this, baseOptions)
      : null;
    const cjkDashCapability = needsDash
      ? { status: "pending", detail: "CjkDashFontShapingPending" }
      : { status: "not-needed" };
    let exactFontSession = null;
    try {
      exactFontSession = await this.#prepareExactFontSession(generation, request);
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
    // source backing is restored after every await and immediately before
    // dispatch. For a server-DOM snapshot that backing is the same prepared
    // first-paint artifact, so width-only transitions can replace paragraphs in
    // bounded progressive slices without exposing browser-native layout. A
    // typography change still requests one atomic replacement because the old
    // glyph styling itself is no longer a valid visual backing.
    beforeDispatch?.();
    if (exactFontSession) {
      try {
        this.#exactFontSession.installRenderFont(
          this,
          exactFontSession.renderFontFamilies,
        );
        this.setAttribute(EXACT_RENDER_FONT_ATTRIBUTE, "true");
      } catch (error) {
        this.#releaseExactFontSession();
        exactFontSession = null;
        this.dataset.tiqianExactFontMiss = "ExactRenderFontStyleUnavailable";
        console.warn("Tiqian Web exact render font style unavailable; using browser metrics", error);
      }
    }
    if (!exactFontSession) {
      this.removeAttribute(EXACT_RENDER_FONT_ATTRIBUTE);
    }
    // Async font preparation happens before layout. Retarget the work revision
    // here so only viewport changes that overlap the actual progressive job
    // require a latest-width follow-up.
    this.#beginLayoutWork({ usesCapturedMeasure: atomicRefresh });
    this.#hasDispatched = true;
    this.#runtimeStateActive = true;
    this.#runtimeCoversSnapshotParagraphs = runtimeCoversSnapshotParagraphs;
    this.#acceptLayoutCompletion = true;
    const preparedOptions = {
      ...baseOptions,
      cjkDashCapability,
      ...(exactFontSession ? {
        exactFontSession: {
          status: "conforming",
          sessionId: exactFontSession.id,
          detail: "SnapshotExactFontBytes",
        },
      } : {}),
    };
    dispatch(
      atomicRefresh ? "tiqian:enhance-atomically" : "tiqian:enhance-progressively",
      this,
      preparedOptions,
    );
    if (dashCapabilityPromise) {
      dashCapabilityPromise.then(
        (capability) => this.#retryCjkDashCapability(
          generation,
          request,
          preparedOptions,
          capability,
        ),
        (error) => this.#retryCjkDashCapability(
          generation,
          request,
          preparedOptions,
          {
            status: "unavailable",
            issue: "NoConformingCjkDashGlyph",
            detail: error instanceof Error ? error.message : String(error),
          },
        ),
      );
    }
    return true;
  }

  #retryCjkDashCapability(generation, request, preparedOptions, cjkDashCapability) {
    if (
      !this.isConnected || generation !== this.#generation ||
      request !== this.#enhanceRequest
    ) return;
    dispatch("tiqian:retry-cjk-dash", this, {
      ...preparedOptions,
      cjkDashCapability,
    });
  }

  async #prepareExactFontSession(generation, request) {
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
    // so a host hydrator cannot make HarfBuzz validation depend on attribute
    // reconciliation timing. The caller removes it on every failed session.
    this.setAttribute(EXACT_RENDER_FONT_ATTRIBUTE, "true");
    const loader = await loadExactFontFallback();
    const existing = this.#exactFontSession;
    if (existing?.reference === reference) {
      // ExactFontSessionLiveRevalidation: reuse immutable loaded font bytes only
      // after the browser adapter revalidates every live snapshot input.
      await existing.revalidate(this, existing.handle);
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
    const width = paragraph.getBoundingClientRect().width;
    const measure = lineLengthGridMeasure(width, fontSize);
    return `${reference}\u0000${Math.fround(fontSize)}\u0000${measure ?? `invalid:${width.toFixed(3)}`}`;
  }

  #beginLayoutWork({ usesCapturedMeasure = false, captureSignatures = usesCapturedMeasure } = {}) {
    this.#clearResponsiveRetarget();
    const operation = ++this.#layoutOperation;
    this.#layoutWorkInFlight = true;
    this.#layoutWorkRevision = this.#geometryRevision;
    this.#layoutWorkSignaturesCaptured = captureSignatures;
    this.#layoutWorkGeometrySignature = captureSignatures
      ? this.#responsiveGeometrySignature()
      : "";
    this.#layoutWorkMeasureSignature = captureSignatures
      ? this.#paragraphMeasureSignature()
      : "";
    this.#layoutWorkTypographySignature = captureSignatures
      ? this.#typographySignature()
      : "";
    this.#layoutWorkMaximumMeasure = captureSignatures && this.hasAttribute("snapshot-ref") &&
      loadedSnapshotMaximumMeasureMatches(this);
    this.#layoutWorkUsesCapturedMeasure = usesCapturedMeasure;
    this.#responsiveCommitRequired = false;
    this.#responsiveRelayoutRequired = false;
    this.#acceptLayoutCompletion = false;
    this.#stopTypographyObservation();
    this.#pauseWidthObservation();
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
    const currentMeasures = this.#paragraphMeasureSignature();
    const currentMaximumMeasure = this.hasAttribute("snapshot-ref") &&
      loadedSnapshotMaximumMeasureMatches(this);
    const currentTypography = this.#typographySignature();
    const currentParagraphWidths = this.#paragraphWidthSignature();
    // CapturedMeasureFollowUpCoalescing: atomic relayout prepares every
    // paragraph from a width snapshot taken when the job starts. If resize
    // activity stays in the same N×fontSize measure and does not cross the
    // exact maximum-snapshot boundary, that result is already valid for the
    // final geometry and a second job would reproduce identical DOM.
    const effectiveLayoutChangedDuringWork =
      currentMeasures !== this.#layoutWorkMeasureSignature ||
      currentMaximumMeasure !== this.#layoutWorkMaximumMeasure;
    const capturedTypographyChanged = this.#layoutWorkUsesCapturedMeasure &&
      currentTypography !== this.#layoutWorkTypographySignature;
    // A media-query typography change invalidates shaping even when it leaves
    // font-size and the integer cell count unchanged. Keep lastTypography at
    // the committed value so the next-frame follow-up selects full enhancement.
    const layoutInputsChangedDuringWork = capturedTypographyChanged ||
      (rawGeometryChangedDuringWork &&
        (!this.#layoutWorkUsesCapturedMeasure || effectiveLayoutChangedDuringWork));
    this.#acceptLayoutCompletion = false;
    this.#layoutWorkInFlight = false;
    this.#layoutWorkSignaturesCaptured = false;
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
    this.#responsiveCommitRequired = false;
    this.#responsiveRelayoutRequired = false;
    this.#lastTypography = currentTypography;
    this.#lastWidth = this.getBoundingClientRect().width;
    this.#lastParagraphMeasures = currentMeasures;
    this.#lastParagraphWidths = currentParagraphWidths;
    this.#observeWidth();
    this.#observeTypography();
    return true;
  }

  #invalidateSnapshotAndEnhance({ typographyChanged = true } = {}) {
    if (!this.#snapshotAdopted && !isLoadedSnapshotAdopted(this)) return;
    const generation = this.#generation;
    const runtimeBacked = this.#runtimeStateActive && this.#runtimeCoversSnapshotParagraphs;
    this.#hasDispatched = false;
    let activeRequest = ++this.#enhanceRequest;
    this.#beginLayoutWork();
    const restoreImmediatelyBeforeDispatch = () => {
      if (!restoreLoadedSnapshot(this)) throw new Error("Adopted snapshot could not be restored");
      this.#snapshotAdopted = false;
    };
    if (runtimeBacked && !typographyChanged) {
      try {
        // A runtime-backed snapshot restores another Tiqian rendering, not SSR.
        // Keep the restore and relayout dispatch in this task so even that
        // backing rendering cannot become an unintended intermediate paint.
        restoreImmediatelyBeforeDispatch();
        this.#hasDispatched = true;
        this.#beginLayoutWork({ usesCapturedMeasure: true });
        this.#acceptLayoutCompletion = true;
        dispatch("tiqian:relayout", this);
      } catch (error) {
        this.#recoverSnapshotEnhanceFailure(generation, activeRequest, error);
      }
      return;
    }
    loadTiqianRuntime()
      .then(() => {
        if (
          !this.isConnected || generation !== this.#generation ||
          activeRequest !== this.#enhanceRequest
        ) return false;
        const enhancement = this.#dispatchProgressiveEnhance(generation, {
          forceAtomic: typographyChanged,
          forceProgressive: !typographyChanged,
          beforeDispatch: restoreImmediatelyBeforeDispatch,
        });
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

  #tryReadoptSnapshotAtMaximumMeasure() {
    if (!this.hasAttribute("snapshot-ref")) return;
    const generation = this.#generation;
    const startedAt = performance.now();
    const operation = this.#beginLayoutWork();
    const runtimeSnapshotBackingRestored =
      this.#runtimeStateActive && this.#runtimeCoversSnapshotParagraphs;
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
      this.#runtimeCoversSnapshotParagraphs = false;
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
      this.#snapshotAdopted = true;
      // SnapshotListRuntimeCompletion also applies to responsive re-adoption:
      // destroying the narrow runtime restores SSR for both paragraphs and
      // list items, while the v1 snapshot intentionally covers only <p>.
      if (this.querySelector("ol > li, ul > li")) {
        await loadTiqianRuntime();
        if (
          !this.isConnected || generation !== this.#generation ||
          operation !== this.#layoutOperation
        ) {
          restoreLoadedSnapshot(this);
          return;
        }
        await this.#dispatchProgressiveEnhance(generation, {
          paragraphSelector: "li",
          runtimeCoversSnapshotParagraphs: false,
        });
        return;
      }
      this.#releaseExactFontSession();
      this.#hasDispatched = true;
      this.#acceptLayoutCompletion = true;
      this.dispatchEvent(new CustomEvent("tiqian:relayout-ready", {
        detail: {
          enhancedCount: snapshot.count,
          issueCount: 0,
          durationMs: performance.now() - startedAt,
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
      this.#finishLayoutWorkAndObserve(operation);
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

  #relayoutRuntimeAfterSnapshotMiss(operation) {
    if (operation !== this.#layoutOperation) return;
    if (!this.#runtimeStateActive) {
      this.#finishLayoutWorkAndObserve(operation);
      return;
    }
    this.#beginLayoutWork({ usesCapturedMeasure: true });
    this.#hasDispatched = true;
    this.#acceptLayoutCompletion = true;
    dispatch("tiqian:relayout", this);
  }

  #removeReadyListener() {
    if (!this.#readyListener) return;
    this.removeEventListener("tiqian:ready", this.#readyListener);
    this.removeEventListener("tiqian:relayout-ready", this.#readyListener);
    this.#readyListener = null;
  }

  #removeCapabilityRetryListener() {
    if (!this.#capabilityRetryListener) return;
    this.removeEventListener("tiqian:capability-retry-start", this.#capabilityRetryListener);
    this.#capabilityRetryListener = null;
  }

  #observeWidth() {
    this.#resizeObserver?.disconnect();
    this.#resizeObserver = new ResizeObserver(() => this.#handleResponsiveGeometryChange());
    this.#resizeObserver.observe(this);
    for (const paragraph of this.querySelectorAll(DEFAULT_PARAGRAPH_SELECTOR)) {
      this.#resizeObserver.observe(paragraph);
    }
    this.#ensureViewportResizeListener();
  }

  #ensureViewportResizeListener() {
    if (this.#viewportResizeListener) return;
    this.#viewportResizeListener = () => this.#handleResponsiveGeometryChange();
    window.addEventListener("resize", this.#viewportResizeListener);
    globalThis.visualViewport?.addEventListener?.("resize", this.#viewportResizeListener);
  }

  #handleResponsiveGeometryChange() {
    this.#geometryRevision += 1;
    if (this.#layoutWorkInFlight) {
      this.#responsiveCommitRequired = true;
      this.#scheduleResponsiveRetarget();
      return;
    }
    this.#scheduleResponsiveGeometryCommit();
  }

  #scheduleResponsiveGeometryCommit() {
    // LeadingSingleFlightGridInvalidation: integer-grid coalescing below remains the
    // actual invalidation boundary. Once a potentially relevant change arrives,
    // inspect it on the next frame instead of waiting for resize to stop. At most
    // one callback is pending; changes during layout are recorded and ready
    // schedules one next-frame pass against the latest geometry.
    if (this.#layoutWorkInFlight) {
      this.#responsiveCommitRequired = true;
      return;
    }
    if (this.#resizeFrame) return;
    this.#resizeFrame = requestAnimationFrame(() => this.#commitResponsiveGeometryChange());
  }

  #commitResponsiveGeometryChange() {
    this.#resizeFrame = 0;
    if (!this.isConnected) return;
    if (this.#layoutWorkInFlight) {
      this.#responsiveCommitRequired = true;
      return;
    }
    // Before the first snapshot/runtime commit there is no layout to update.
    // The initial job will read the latest live width once its font gate opens.
    if (!this.#hasDispatched) {
      this.#responsiveCommitRequired = false;
      this.#responsiveRelayoutRequired = false;
      return;
    }
    const forceLatestWidth = this.#responsiveRelayoutRequired;
    this.#responsiveCommitRequired = false;
    this.#responsiveRelayoutRequired = false;
    const width = this.getBoundingClientRect().width;
    const paragraphWidths = this.#paragraphWidthSignature();
    const paragraphMeasures = this.#paragraphMeasureSignature();
    const widthsChanged = Math.abs(width - this.#lastWidth) >= 0.5 ||
      paragraphWidths !== this.#lastParagraphWidths;
    const measuresChanged = paragraphMeasures !== this.#lastParagraphMeasures;
    const signature = this.#typographySignature();
    const typographyChanged = signature !== this.#lastTypography;
    if (!forceLatestWidth && !widthsChanged && !measuresChanged && !typographyChanged) return;
    this.#lastWidth = width;
    this.#lastParagraphMeasures = paragraphMeasures;
    this.#lastParagraphWidths = paragraphWidths;

    const snapshotAdopted = this.#snapshotAdopted || isLoadedSnapshotAdopted(this);
    const atMaximumMeasure = this.hasAttribute("snapshot-ref") &&
      loadedSnapshotMaximumMeasureMatches(this);
    if (snapshotAdopted) {
      if (atMaximumMeasure && !typographyChanged) {
        // A parent may keep growing after the paragraph has reached max-width.
        // The snapshot contract is still valid; do not churn the DOM.
        this.#lastTypography = signature;
        this.#observeWidth();
        this.#observeTypography();
      } else {
        this.#invalidateSnapshotAndEnhance({ typographyChanged });
      }
      return;
    }
    if (atMaximumMeasure && !typographyChanged) {
      this.#tryReadoptSnapshotAtMaximumMeasure();
      return;
    }
    if (!forceLatestWidth && !measuresChanged && !typographyChanged) {
      // LineLengthGridResponsiveInvalidation: Web currently exposes the
      // engine's Start-aligned body only. Within one N×fontSize cell count,
      // the measure, line breaks, placements, and body offset are unchanged.
      // Keep observing exact geometry for snapshot evidence, but do not ask
      // the engine to reproduce identical paragraph DOM.
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
      this.#dispatchProgressiveEnhance(this.#generation).catch((error) => {
        this.dataset.tiqianCapabilityIssue = "FontCapabilityPreparationFailed";
        console.warn("Tiqian Web font capability preparation failed", error);
      });
    } else {
      this.#beginLayoutWork({ usesCapturedMeasure: true });
      this.#acceptLayoutCompletion = true;
      dispatch("tiqian:relayout", this);
    }
  }

  #removeViewportResizeListener() {
    if (!this.#viewportResizeListener) return;
    window.removeEventListener("resize", this.#viewportResizeListener);
    globalThis.visualViewport?.removeEventListener?.("resize", this.#viewportResizeListener);
    this.#viewportResizeListener = null;
  }

  #pauseWidthObservation() {
    this.#resizeObserver?.disconnect();
    this.#resizeObserver = null;
    if (this.#resizeFrame) cancelAnimationFrame(this.#resizeFrame);
    this.#resizeFrame = 0;
  }

  #stopWidthObservation() {
    this.#clearResponsiveRetarget();
    this.#pauseWidthObservation();
    this.#removeViewportResizeListener();
  }

  #scheduleResponsiveRetarget() {
    if (!this.#layoutWorkInFlight || !this.#layoutWorkUsesCapturedMeasure) return;
    this.#clearResponsiveRetarget();
    const operation = this.#layoutOperation;
    this.#responsiveRetargetTimer = setTimeout(() => {
      this.#responsiveRetargetTimer = 0;
      if (
        !this.isConnected || !this.#layoutWorkInFlight ||
        !this.#layoutWorkUsesCapturedMeasure || operation !== this.#layoutOperation
      ) return;
      if (this.#typographySignature() !== this.#layoutWorkTypographySignature) {
        this.#cancelCapturedLayoutForTypographyChange();
        return;
      }
      const maximumMeasure = this.hasAttribute("snapshot-ref") &&
        loadedSnapshotMaximumMeasureMatches(this);
      if (
        this.#paragraphMeasureSignature() === this.#layoutWorkMeasureSignature &&
        maximumMeasure === this.#layoutWorkMaximumMeasure
      ) return;
      this.#cancelCapturedLayoutForLatestGeometry();
    }, RESPONSIVE_LATEST_RETARGET_QUIET_MS);
  }

  #clearResponsiveRetarget() {
    if (!this.#responsiveRetargetTimer) return;
    clearTimeout(this.#responsiveRetargetTimer);
    this.#responsiveRetargetTimer = 0;
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
      });
    }
    if (document.fonts) {
      this.#fontLoadingDoneListener = (event) => {
        const relevantFaceLoaded = fontLoadingAffectsTypography(
          event,
          this.#typographyElements(),
        );
        const force = this.#forceTypographyRefresh || relevantFaceLoaded;
        if (this.#deferredTypographyCheck || force) this.#scheduleTypographyCheck(force);
      };
      document.fonts.addEventListener("loadingdone", this.#fontLoadingDoneListener);
    }
  }

  #stopTypographyObservation() {
    this.#typographyObserver?.disconnect();
    this.#typographyObserver = null;
    if (this.#fontLoadingDoneListener) {
      document.fonts?.removeEventListener("loadingdone", this.#fontLoadingDoneListener);
      this.#fontLoadingDoneListener = null;
    }
    if (this.#typographyFrame) cancelAnimationFrame(this.#typographyFrame);
    this.#typographyFrame = 0;
    this.#forceTypographyRefresh = false;
    this.#deferredTypographyCheck = false;
  }

  #observeLayoutWorkInputs() {
    this.#stopLayoutWorkInputObservation();
    this.#layoutWorkTypographyObserver = new MutationObserver(() => {
      if (!this.#layoutWorkInFlight || !this.#layoutWorkUsesCapturedMeasure) return;
      if (this.#typographySignature() === this.#layoutWorkTypographySignature) return;
      this.#cancelCapturedLayoutForTypographyChange();
    });
    this.#layoutWorkTypographyObserver.observe(this, {
      attributes: true,
      subtree: true,
      attributeFilter: ["class", "style", "data-theme", "data-color-mode"],
    });
    for (let ancestor = this.parentElement; ancestor; ancestor = ancestor.parentElement) {
      this.#layoutWorkTypographyObserver.observe(ancestor, { attributes: true });
    }
    if (document.fonts) {
      this.#layoutWorkFontLoadingDoneListener = (event) => {
        if (
          this.#layoutWorkInFlight && this.#layoutWorkUsesCapturedMeasure &&
          fontLoadingAffectsTypography(event, this.#typographyElements())
        ) this.#cancelCapturedLayoutForTypographyChange();
      };
      document.fonts.addEventListener("loadingdone", this.#layoutWorkFontLoadingDoneListener);
    }
  }

  #stopLayoutWorkInputObservation() {
    this.#layoutWorkTypographyObserver?.disconnect();
    this.#layoutWorkTypographyObserver = null;
    if (this.#layoutWorkFontLoadingDoneListener) {
      document.fonts?.removeEventListener(
        "loadingdone",
        this.#layoutWorkFontLoadingDoneListener,
      );
      this.#layoutWorkFontLoadingDoneListener = null;
    }
  }

  #cancelCapturedLayoutForTypographyChange() {
    if (!this.#layoutWorkInFlight || !this.#layoutWorkUsesCapturedMeasure) return;
    this.#clearResponsiveRetarget();
    ++this.#layoutOperation;
    this.#acceptLayoutCompletion = false;
    this.#layoutWorkInFlight = false;
    this.#responsiveCommitRequired = true;
    this.#responsiveRelayoutRequired = false;
    this.#stopLayoutWorkInputObservation();
    dispatch("tiqian:cancel-layout-work", this);
    this.#ensureViewportResizeListener();
    this.#scheduleResponsiveGeometryCommit();
  }

  #cancelCapturedLayoutForLatestGeometry() {
    if (!this.#layoutWorkInFlight || !this.#layoutWorkUsesCapturedMeasure) return;
    this.#clearResponsiveRetarget();
    ++this.#layoutOperation;
    this.#acceptLayoutCompletion = false;
    this.#layoutWorkInFlight = false;
    this.#stopLayoutWorkInputObservation();
    dispatch("tiqian:cancel-layout-work", this);
    // The requested target signatures were recorded before the cancelled job
    // committed. Force the existing coordinator to read live geometry and
    // dispatch the latest target even when those cached signatures match.
    this.#responsiveCommitRequired = true;
    this.#responsiveRelayoutRequired = true;
    this.#ensureViewportResizeListener();
    this.#scheduleResponsiveGeometryCommit();
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
      this.#dispatchProgressiveEnhance(this.#generation).catch((error) => {
        this.dataset.tiqianCapabilityIssue = "FontCapabilityPreparationFailed";
        console.warn("Tiqian Web font capability preparation failed", error);
      });
    });
  }

  #typographySignature() {
    return this.#typographyElements().map((element) => {
      const style = getComputedStyle(element);
      const before = getComputedStyle(element, "::before");
      const after = getComputedStyle(element, "::after");
      const values = TYPOGRAPHY_PROPERTIES.map((property) => style.getPropertyValue(property));
      const firstLetter = getComputedStyle(element, "::first-letter");
      const firstLine = getComputedStyle(element, "::first-line");
      const generated = [before, after, firstLetter, firstLine].map((pseudo) => [
        pseudo.getPropertyValue("content"),
        pseudo.getPropertyValue("font-family"),
        pseudo.getPropertyValue("font-size"),
        pseudo.getPropertyValue("font-weight"),
        pseudo.getPropertyValue("font-style"),
        pseudo.getPropertyValue("font-feature-settings"),
        pseudo.getPropertyValue("font-variation-settings"),
        pseudo.getPropertyValue("font-variant"),
        pseudo.getPropertyValue("font-language-override"),
        pseudo.getPropertyValue("letter-spacing"),
        pseudo.getPropertyValue("word-spacing"),
      ].join("\u001d"));
      return [element.tagName, ...values, ...generated].join("\u001f");
    }).join("\u001e");
  }

  #typographyElements() {
    const elements = [];
    const seenGroups = new Set();
    for (const paragraph of this.querySelectorAll(DEFAULT_PARAGRAPH_SELECTOR)) {
      elements.push(paragraph);
      const rendered = paragraph.hasAttribute("data-tq-rendered");
      const descendants = rendered
        ? paragraph.querySelectorAll("[data-tq-source-semantic], [data-tq-inline-object]")
        : paragraph.querySelectorAll("*");
      for (const element of descendants) {
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

  #paragraphWidthSignature() {
    return Array.from(this.querySelectorAll(DEFAULT_PARAGRAPH_SELECTOR), (paragraph) => {
      const rect = paragraph.getBoundingClientRect();
      return rect.width.toFixed(3);
    }).join("\u001f");
  }

  #responsiveGeometrySignature() {
    return [
      this.getBoundingClientRect().width,
      ...Array.from(this.querySelectorAll(DEFAULT_PARAGRAPH_SELECTOR), (paragraph) =>
        paragraph.getBoundingClientRect().width),
    ].join("\u001f");
  }

  #paragraphMeasureSignature() {
    const exactFontLayout = Boolean(this.#exactFontSession);
    return Array.from(this.querySelectorAll(DEFAULT_PARAGRAPH_SELECTOR), (paragraph) => {
      const style = getComputedStyle(paragraph);
      const fontSize = Number.parseFloat(style.fontSize);
      const layoutWidth = (element, elementStyle) => {
        let value = element.getBoundingClientRect().width;
        if (!exactFontLayout) return value;
        const number = (value) => Number.parseFloat(value) || 0;
        value -= number(elementStyle.paddingLeft) + number(elementStyle.paddingRight) +
          number(elementStyle.borderLeftWidth) + number(elementStyle.borderRightWidth);
        return value;
      };
      let width = layoutWidth(paragraph, style);
      if (!(width > 0)) {
        const parent = paragraph.parentElement;
        if (parent) width = layoutWidth(parent, getComputedStyle(parent));
      }
      const measure = lineLengthGridMeasure(width, fontSize);
      return measure == null
        ? `invalid:${width.toFixed(3)}:${style.fontSize}`
        : `${Math.fround(fontSize)}:${measure}`;
    }).join("\u001f");
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

export { TiqianProseElement };
