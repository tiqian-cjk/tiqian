import { currentTiqianRuntime, loadTiqianRuntime } from "./runtime.js";
import { prepareCjkDashShaping } from "./font-shaping.js";
import { ensureTiqianStyles } from "./styles.js";

const ELEMENT_NAME = "tiqian-prose";
const TYPOGRAPHY_PROPERTIES = [
  "display",
  "font-family",
  "font-size",
  "font-weight",
  "font-style",
  "font-stretch",
  "font-variation-settings",
  "font-feature-settings",
  "font-kerning",
  "font-optical-sizing",
  "color",
  "letter-spacing",
  "line-height",
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
];

function dispatch(name, root, options = undefined) {
  document.dispatchEvent(
    new CustomEvent(name, {
      detail: { root, ...(options ? { options } : {}) },
    }),
  );
}

function documentReady() {
  if (document.readyState !== "loading") return Promise.resolve();
  return new Promise((resolve) => {
    document.addEventListener("DOMContentLoaded", resolve, { once: true });
  });
}

function nextFrame() {
  return new Promise((resolve) => requestAnimationFrame(resolve));
}

class TiqianProseElement extends HTMLElement {
  static observedAttributes = ["emphasis-dot-gap-em"];

  #forceTypographyRefresh = false;
  #fontLoadingDoneListener = null;
  #generation = 0;
  #hasDispatched = false;
  #enhanceRequest = 0;
  #lastWidth = 0;
  #lastTypography = "";
  #readyListener = null;
  #resizeFrame = 0;
  #resizeObserver = null;
  #typographyFrame = 0;
  #typographyObserver = null;

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

  connectedCallback() {
    const generation = ++this.#generation;
    this.#hasDispatched = false;
    const loadStartedAt = performance.now();
    const fontsReady = document.fonts?.ready ?? Promise.resolve();
    delete this.dataset.tiqianCapabilityIssue;
    delete this.dataset.tiqianEnhanceMs;
    delete this.dataset.tiqianMaxSliceMs;
    this.#removeReadyListener();
    this.#stopTypographyObservation();
    this.#readyListener = (event) => {
      if (generation !== this.#generation) return;
      const { durationMs, maxSliceMs } = event.detail ?? {};
      if (Number.isFinite(durationMs)) this.dataset.tiqianEnhanceMs = durationMs.toFixed(1);
      if (Number.isFinite(maxSliceMs)) this.dataset.tiqianMaxSliceMs = maxSliceMs.toFixed(1);
      // Progressive slices lower paragraphs after the initial dispatch. The
      // completion-time signature is therefore the authoritative typography
      // actually used by the engine, including responsive CSS that settled
      // between the first and final slice. Keep listening so refreshes update it.
      this.#lastTypography = this.#typographySignature();
      this.#lastWidth = this.getBoundingClientRect().width;
      this.#observeWidth();
      this.#observeTypography();
    };
    this.addEventListener("tiqian:ready", this.#readyListener);

    // HostCascadeReadyGate: connectedCallback may run before an app's
    // module-loaded styles have reached the cascade. Wait for document readiness,
    // then capture document.fonts.ready and one painted frame; otherwise the
    // engine can measure the browser default 16/normal while light DOM later
    // paints the host's 18/460 typography.
    Promise.all([loadTiqianRuntime(), ensureTiqianStyles(), documentReady()])
      .then(() => document.fonts?.ready ?? fontsReady)
      .then(nextFrame)
      .then(async () => {
        if (!this.isConnected || generation !== this.#generation) return;
        const enhanceStartedAt = performance.now();
        this.#lastTypography = this.#typographySignature();
        if (!(await this.#dispatchProgressiveEnhance(generation))) return;
        this.dataset.tiqianLoadMs = (enhanceStartedAt - loadStartedAt).toFixed(1);
      })
      .catch((error) => {
        this.#removeReadyListener();
        this.dataset.tiqianCapabilityIssue = "RuntimeLoadFailed";
        console.warn("Tiqian Web runtime failed to load", error);
      });
  }

  disconnectedCallback() {
    const generation = ++this.#generation;
    this.#enhanceRequest += 1;
    this.#hasDispatched = false;
    this.#removeReadyListener();
    this.#stopTypographyObservation();
    this.#stopWidthObservation();
    currentTiqianRuntime()
      ?.then(() => {
        // ReconnectCancellation: moving a custom element can disconnect and
        // reconnect it before the runtime promise settles. The stale teardown
        // must not destroy the new connection's enhancement.
        if (!this.isConnected && generation === this.#generation) {
          dispatch("tiqian:destroy", this);
        }
      })
      .catch(() => {});
  }

  attributeChangedCallback(name, oldValue, newValue) {
    if (name !== "emphasis-dot-gap-em" || oldValue === newValue) return;
    if (!this.isConnected || !this.#hasDispatched) return;
    this.#dispatchProgressiveEnhance(this.#generation).catch((error) => {
      this.dataset.tiqianCapabilityIssue = "FontCapabilityPreparationFailed";
      console.warn("Tiqian Web font capability preparation failed", error);
    });
  }

  #baseEnhanceOptions() {
    const emphasisDotGapEm = this.emphasisDotGapEm;
    return emphasisDotGapEm == null ? undefined : { emphasisDotGapEm };
  }

  async #dispatchProgressiveEnhance(generation) {
    const request = ++this.#enhanceRequest;
    const baseOptions = this.#baseEnhanceOptions() ?? {};
    const cjkDashCapability = await prepareCjkDashShaping(this, baseOptions);
    if (!this.isConnected || generation !== this.#generation || request !== this.#enhanceRequest) {
      return false;
    }
    // Enhancement mutates paragraph style/geometry by design. Observing those
    // writes while a progressive job is still running can continuously cancel
    // and restart the job before it reaches its first paragraph.
    this.#stopTypographyObservation();
    this.#stopWidthObservation();
    this.#hasDispatched = true;
    dispatch("tiqian:enhance-progressively", this, { ...baseOptions, cjkDashCapability });
    return true;
  }

  #removeReadyListener() {
    if (!this.#readyListener) return;
    this.removeEventListener("tiqian:ready", this.#readyListener);
    this.#readyListener = null;
  }

  #observeWidth() {
    this.#resizeObserver?.disconnect();
    this.#resizeObserver = new ResizeObserver(() => {
      const width = this.getBoundingClientRect().width;
      if (Math.abs(width - this.#lastWidth) < 0.5) return;
      this.#lastWidth = width;
      if (this.#resizeFrame) cancelAnimationFrame(this.#resizeFrame);
      this.#resizeFrame = requestAnimationFrame(() => {
        this.#resizeFrame = 0;
        if (!this.isConnected) return;
        // ResponsiveTypographyBeforeRebreak: a media query can change font
        // metrics in the same resize without mutating any class/style attribute.
        // Re-lower in that case; reserve the cheap width-only path for stable
        // typography.
        if (document.fonts?.status === "loading") {
          this.#scheduleTypographyCheck(true);
          return;
        }
        const signature = this.#typographySignature();
        if (signature !== this.#lastTypography) {
          this.#lastTypography = signature;
          this.#dispatchProgressiveEnhance(this.#generation).catch((error) => {
            this.dataset.tiqianCapabilityIssue = "FontCapabilityPreparationFailed";
            console.warn("Tiqian Web font capability preparation failed", error);
          });
        } else {
          dispatch("tiqian:relayout", this);
        }
      });
    });
    this.#resizeObserver.observe(this);
  }

  #stopWidthObservation() {
    this.#resizeObserver?.disconnect();
    this.#resizeObserver = null;
    if (this.#resizeFrame) cancelAnimationFrame(this.#resizeFrame);
    this.#resizeFrame = 0;
  }

  #observeTypography() {
    this.#typographyObserver?.disconnect();
    this.#typographyObserver = new MutationObserver(() => {
      this.#scheduleTypographyCheck(true);
    });
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
      this.#fontLoadingDoneListener = () => this.#scheduleTypographyCheck(true);
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
  }

  #scheduleTypographyCheck(force = false) {
    this.#forceTypographyRefresh ||= force;
    if (this.#typographyFrame) return;
    this.#typographyFrame = requestAnimationFrame(() => {
      this.#typographyFrame = 0;
      if (!this.isConnected) return;
      // A loading font would immediately invalidate another measurement. Its
      // loadingdone event will schedule the authoritative check.
      if (document.fonts?.status === "loading") return;
      const signature = this.#typographySignature();
      const changed = signature !== this.#lastTypography;
      const shouldRefresh = changed || this.#forceTypographyRefresh;
      this.#forceTypographyRefresh = false;
      if (!shouldRefresh) return;
      this.#lastTypography = signature;
      this.#dispatchProgressiveEnhance(this.#generation).catch((error) => {
        this.dataset.tiqianCapabilityIssue = "FontCapabilityPreparationFailed";
        console.warn("Tiqian Web font capability preparation failed", error);
      });
    });
  }

  #typographySignature() {
    const elements = [];
    const seenGroups = new Set();
    for (const paragraph of this.querySelectorAll("p")) {
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
    return elements.map((element) => {
      const style = getComputedStyle(element);
      const before = getComputedStyle(element, "::before");
      const after = getComputedStyle(element, "::after");
      const values = TYPOGRAPHY_PROPERTIES.map((property) => style.getPropertyValue(property));
      const generated = [before, after].map((pseudo) => [
        pseudo.getPropertyValue("content"),
        pseudo.getPropertyValue("font-family"),
        pseudo.getPropertyValue("font-size"),
        pseudo.getPropertyValue("font-weight"),
        pseudo.getPropertyValue("letter-spacing"),
      ].join("\u001d"));
      return [element.tagName, ...values, ...generated].join("\u001f");
    }).join("\u001e");
  }
}

if (!customElements.get(ELEMENT_NAME)) {
  customElements.define(ELEMENT_NAME, TiqianProseElement);
}

export { TiqianProseElement };
