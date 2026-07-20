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

// CssFragmentedBlockInlineMeasure: a block fragmented by CSS columns has one
// layout inline-size even though getBoundingClientRect() returns the union of
// every horizontally separated fragment. Custom-element invalidation and the
// Kotlin runtime must compare the same per-fragment border-box measure.
function fragmentedBorderBoxInlineSize(element) {
  const fallback = Number(element?.getBoundingClientRect?.().width) || 0;
  const rects = Array.from(element?.getClientRects?.() ?? [])
    .filter((rect) => Number(rect.width) > 0);
  if (rects.length <= 1) return fallback;
  return Math.max(...rects.map((rect) => Number(rect.width) || 0));
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

class TiqianProseElement extends HTMLElementBase {
  static observedAttributes = [
    "emphasis-dot-gap-em",
    "strong-as-emphasis-marks",
    "snapshot-ref",
  ];

  #forceTypographyRefresh = false;
  #acceptLayoutCompletion = false;
  #connected = false;
  #deferredTypographyCheck = false;
  #fontLoadingSettledListener = null;
  #geometryRevision = 0;
  #generation = 0;
  #hasDispatched = false;
  #initialFontRetryListener = null;
  #initialFontRetryObserver = null;
  #initialFontRetryToken = 0;
  #layoutWorkInFlight = false;
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
  #lastWidth = 0;
  #lastParagraphMeasures = "";
  #lastParagraphWidths = "";
  #lastTypography = "";
  #readyListener = null;
  #resizeFrame = 0;
  #resizeObserver = null;
  #resizeObserverFrame = 0;
  #responsiveCommitRequired = false;
  #responsiveRetargetFrame = 0;
  #responsiveRelayoutRequired = false;
  #runtimeStateActive = false;
  #snapshotAdopted = false;
  #snapshotEnhancedCount = 0;
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
    this.#exactFontRejectedAttempt = "";
    const generation = ++this.#generation;
    this.#clearInitialFontRetry();
    this.#acceptLayoutCompletion = false;
    this.#hasDispatched = false;
    this.#snapshotAdopted = isLoadedSnapshotAdopted(this);
    this.#snapshotEnhancedCount = 0;
    const loadStartedAt = performance.now();
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
        // ResponsiveExactFontSessionReuse: the server replay tables and host
        // font proof are still valid; only this line measure failed DOM replay.
        // Retain the session so a later grid can revalidate without rebuilding
        // the replay corpus. Disconnect and snapshot adoption remain the owners
        // of final release.
        this.removeAttribute(EXACT_RENDER_FONT_ATTRIBUTE);
      }
      if (stale) this.#responsiveCommitRequired = true;
      this.#finishLayoutWorkAndObserve();
    };
    this.addEventListener("tiqian:ready", this.#readyListener);
    this.addEventListener("tiqian:relayout-ready", this.#readyListener);
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
        this.dataset.tiqianSnapshotMiss = snapshot.reason ?? "SnapshotNotAdopted";
        await (runtimePromise ?? loadTiqianRuntime());
        if (!this.isConnected || generation !== this.#generation) return;
        if (!(await this.#dispatchProgressiveEnhance(generation))) return;
      })
      .catch((error) => {
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
    // DetachedNavigationDisposal: swup and other HTML routers remove an entire
    // old article synchronously. Reconstructing every source paragraph here
    // blocks their scroll handoff and can visibly change the outgoing page.
    // Keep the backing in weak state for a possible reconnection, but cancel all
    // work and release document-scoped styles without touching detached DOM.
    if (this.#snapshotAdopted || isLoadedSnapshotAdopted(this)) {
      detachLoadedSnapshot(this);
    }
    if (this.#runtimeStateActive) dispatch("tiqian:detach", this);
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
      if (this.#connected) this.#restartConnectedLifecycle();
      return;
    }
    if (name !== "emphasis-dot-gap-em" && name !== "strong-as-emphasis-marks") return;
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
    if (emphasisDotGapEm == null && !strongAsEmphasisMarks) return undefined;
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
        this.#initialFontRetryObserver.observe(ancestor, { attributes: true });
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
    restoreLoadedSnapshot(this);
    if (this.#runtimeStateActive) dispatch("tiqian:destroy", this);
    this.#runtimeStateActive = false;
    this.#releaseExactFontSession();
    this.removeAttribute(EXACT_RENDER_FONT_ATTRIBUTE);
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
    dispatch("tiqian:enhance-progressively", this, preparedOptions);
    return true;
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
    this.#layoutWorkTypographySignature = captureSignatures
      ? this.#layoutWorkViewportTypographyEntries
          .slice(1)
          .map(({ signature }) => signature)
          .join("\u001e")
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
    // RenderOutputTypographyIsNotAnInputChange: the renderer intentionally
    // changes paragraph line-height and positioning after it commits measured
    // line boxes. Comparing that output signature with the captured native
    // source signature schedules a redundant destroy-and-enhance pass. Real
    // font, style and viewport changes are observed while work is in flight and
    // cancel the captured job before ready; completion only needs to reconcile
    // geometry revisions that survived those observers.
    const layoutInputsChangedDuringWork = rawGeometryChangedDuringWork &&
      (!this.#layoutWorkUsesCapturedMeasure || effectiveLayoutChangedDuringWork);
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
    this.#responsiveCommitRequired = false;
    this.#responsiveRelayoutRequired = false;
    this.#lastTypography = currentTypography;
    this.#lastWidth = fragmentedBorderBoxInlineSize(this);
    this.#lastParagraphMeasures = currentMeasures;
    this.#lastParagraphWidths = currentParagraphWidths;
    this.#observeWidth();
    this.#observeTypography();
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
    const startedAt = performance.now();
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

  #refreshRuntimeFromSource({ revalidateExactFont = true } = {}) {
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
    this.#resizeObserver?.disconnect();
    // ResponsiveInlineSizeObservation: takeover intentionally changes block
    // height. Seed and compare only border-box inline sizes so those commits do
    // not trigger a redundant responsive pass. A container-only width change
    // is reported from inside the browser's ResizeObserver delivery loop; DOM
    // rollback there can make a shallower host observer (for example one that
    // watches body height) miss its own notification. Defer that fallback to
    // the next frame, outside the delivery loop. Window and visual-viewport
    // resize signals still synchronously restore source before paint.
    const widths = new WeakMap();
    const targets = [
      this,
      ...Array.from(this.querySelectorAll(DEFAULT_PARAGRAPH_SELECTOR))
        .filter((paragraph) => belongsToRootScope(paragraph, this)),
    ];
    for (const target of targets) {
      widths.set(target, fragmentedBorderBoxInlineSize(target));
    }
    const observer = new ResizeObserver((entries) => {
      let changed = false;
      for (const entry of entries) {
        const width = fragmentedBorderBoxInlineSize(entry.target);
        const previous = widths.get(entry.target);
        widths.set(entry.target, width);
        if (previous == null || Math.abs(width - previous) >= 0.5) changed = true;
      }
      if (!changed) return;
      observer.disconnect();
      if (this.#resizeObserver === observer) this.#resizeObserver = null;
      if (this.#resizeObserverFrame) cancelAnimationFrame(this.#resizeObserverFrame);
      this.#resizeObserverFrame = requestAnimationFrame(() => {
        this.#resizeObserverFrame = 0;
        if (this.isConnected) this.#handleResponsiveGeometryChange();
      });
    });
    this.#resizeObserver = observer;
    for (const target of targets) observer.observe(target, { box: "border-box" });
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
        // ResponsiveRuntimeRollbackAtFirstSafeSignal: runtime paragraphs carry
        // explicit line breaks, so the same safe-signal rule applies after a
        // snapshot has already fallen back. Teardown is synchronous and leaves
        // native source readable until progressive enhancement commits
        // latest-width paragraphs atomically.
        if (
          this.hasAttribute("snapshot-ref") && loadedSnapshotMaximumMeasureMatches(this)
        ) {
          this.#tryReadoptSnapshotAtMaximumMeasure();
          return;
        }
        this.#responsiveCommitRequired = true;
        this.#responsiveRelayoutRequired = true;
        this.#restoreRuntimeSourceForRetarget();
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
    const width = fragmentedBorderBoxInlineSize(this);
    const paragraphWidths = this.#paragraphWidthSignature();
    const paragraphMeasures = this.#paragraphMeasureSignature();
    const widthsChanged = Math.abs(width - this.#lastWidth) >= 0.5 ||
      paragraphWidths !== this.#lastParagraphWidths;
    const hostInlineSizeRefresh = widthsChanged &&
      this.querySelector("[data-tq-host-inline-size]") !== null;
    const measuresChanged = paragraphMeasures !== this.#lastParagraphMeasures;
    const signature = this.#typographySignature();
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
    if (atMaximumMeasure && !typographyChanged) {
      this.#tryReadoptSnapshotAtMaximumMeasure();
      return;
    }
    if (!forceLatestWidth && !measuresChanged && !typographyChanged && !hostInlineSizeRefresh) {
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
    if (typographyChanged) this.#lastTypography = signature;
    this.#refreshRuntimeFromSource({ revalidateExactFont: typographyChanged });
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
    if (this.#resizeObserverFrame) cancelAnimationFrame(this.#resizeObserverFrame);
    this.#resizeObserverFrame = 0;
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
      if (
        this.#paragraphMeasureSignature() === this.#layoutWorkMeasureSignature &&
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
      if (records.every((record) => rendererOwnedProgressiveStyleMutation(record, this))) {
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
      this.#layoutWorkTypographyObserver.observe(ancestor, { attributes: true });
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
    this.#responsiveCommitRequired = true;
    // TypographyRetargetMustRestart: cancellation restores native source.
    // Even when that source now matches the last observed signature, a fresh
    // job is still required to replace the rolled-back paragraphs.
    this.#responsiveRelayoutRequired = true;
    this.#stopLayoutWorkInputObservation();
    this.#restoreRuntimeSourceForRetarget();
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
    this.#restoreRuntimeSourceForRetarget();
    // The requested target signatures were recorded before the cancelled job
    // committed. Force the existing coordinator to read live geometry and
    // dispatch the latest target even when those cached signatures match.
    this.#responsiveCommitRequired = true;
    this.#responsiveRelayoutRequired = true;
    this.#ensureViewportResizeListener();
    this.#scheduleResponsiveGeometryCommit();
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

  #typographySignature() {
    return this.#typographyElements()
      .map((element) => this.#elementTypographySignature(element))
      .join("\u001e");
  }

  #elementTypographySignature(
    element,
    includeGenerated = true,
    properties = TYPOGRAPHY_PROPERTIES,
  ) {
    const style = getComputedStyle(element);
    const values = properties.map((property) => style.getPropertyValue(property));
    const generated = includeGenerated
      ? ["::before", "::after", "::first-letter", "::first-line"].map((selector) => {
          const pseudo = getComputedStyle(element, selector);
          return [
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
          ].join("\u001d");
        })
      : [];
    return [element.tagName, ...values, ...generated].join("\u001f");
  }

  #captureLayoutWorkViewportTypographyEntries() {
    return [this, ...this.#typographyElements()].map((element, index) => {
      const properties = index === 0
        ? ROOT_VIEWPORT_TYPOGRAPHY_PROPERTIES
        : TYPOGRAPHY_PROPERTIES;
      return {
        element,
        includeGenerated: index !== 0,
        properties,
        signature: this.#elementTypographySignature(element, index !== 0, properties),
      };
    });
  }

  #layoutWorkViewportTypographyChanged() {
    // NativeSourceViewportTypographySignature: progressive renderer output is
    // not a layout input. Compare the root plus only source elements that have
    // not yet been replaced, using their pre-work computed typography. This
    // catches viewport media-query changes without treating Tiqian's own
    // line-height/font projection/containing-block CSS as a host mutation.
    for (const { element, includeGenerated, properties, signature } of
      this.#layoutWorkViewportTypographyEntries) {
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
      return fragmentedBorderBoxInlineSize(paragraph).toFixed(3);
    }).join("\u001f");
  }

  #responsiveGeometrySignature() {
    return [
      fragmentedBorderBoxInlineSize(this),
      ...Array.from(this.querySelectorAll(DEFAULT_PARAGRAPH_SELECTOR), (paragraph) =>
        fragmentedBorderBoxInlineSize(paragraph)),
    ].join("\u001f");
  }

  #paragraphMeasureSignature() {
    const exactFontLayout = Boolean(this.#exactFontSession);
    return Array.from(this.querySelectorAll(DEFAULT_PARAGRAPH_SELECTOR), (paragraph) => {
      const style = getComputedStyle(paragraph);
      const fontSize = Number.parseFloat(style.fontSize);
      const layoutWidth = (element, elementStyle) => {
        let value = fragmentedBorderBoxInlineSize(element);
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
