// TiqianProseElement — the thin custom-element shell over the core
// EnhancedElementContext (core-neutral ruling). The shell owns exactly four
// jobs: (a) reflect the four platform-observed attributes into
// context.updateOptions(); (b) delegate connectedCallback /
// disconnectedCallback to context.mount() / context.unmount() (one noun
// pair: the shell's connect/disconnect lifecycle delegates to the context's
// mount/unmount); (c) synthesize the completion CustomEvents through the
// event channel's dispatcher slot — the event single truth keeps CustomEvent
// construction in the shell, while the funnel and the callback subscribers
// live in core; (d) expose the four attribute-backed property accessors.
// Every other behavior lives in the context and the services it uses.
//
// Registration (wc-s5 scope item 2): the three historical import-time side
// effects — clipboard interception, snapshot-table prefetch, and the custom
// element definition — are consolidated into the named, idempotent,
// parameterized registerTiqianProse(). The /auto entry is the canonical
// zero-config import: it calls registerTiqianProse() once with the defaults.
// Importing this module registers nothing; explicit hosts call
// registerTiqianProse() themselves (wc-s6 scope 8).
import { createEnhanceContext } from "@tiqian/core/src/engine/context/enhance-context.js";
import { OBSERVED_ATTRIBUTES } from "@tiqian/core/src/engine/enhance/options-ledger.js";
import { INTERNAL_DISPATCH_MARKER } from "@tiqian/core/src/engine/enhance/event-channel.js";
import type { MarkedCompletionEvent } from "@tiqian/core/src/engine/enhance/event-channel.js";
import { globalServices, initializeGlobalServices } from "@tiqian/core/src/services/global-services.js";
import { prefetchSnapshotTables } from "@tiqian/core/src/sampler/snapshot/snapshot-tables.js";
import { CoordinationService } from "@tiqian/core/src/engine/coordination/coordination-service.js";

const ELEMENT_NAME = "tiqian-prose";

type DomElementCtor = typeof HTMLElement;
const HTMLElementBase: DomElementCtor =
  typeof globalThis.HTMLElement === "function"
    ? globalThis.HTMLElement
    : class TiqianSsrElement {} as DomElementCtor;

class TiqianProseElement extends HTMLElementBase {
  static observedAttributes: string[] = [...OBSERVED_ATTRIBUTES];

  readonly #context = createEnhanceContext(this);

  constructor() {
    super();
    // Event single truth: the core funnel has already classified the
    // completion when the dispatcher slot runs; the shell's only job is the
    // CustomEvent synthesis the baseline dispatched on the root. The marker
    // keeps the channel's DOM listeners from funnelling this dispatch a
    // second time.
    this.#context.eventChannel.setDispatcher((kind, detail) => {
      const event = new CustomEvent(kind, { bubbles: true, composed: true, detail });
      (event as MarkedCompletionEvent)[INTERNAL_DISPATCH_MARKER] = true;
      this.dispatchEvent(event);
    });
  }

  get disabled(): boolean {
    return this.hasAttribute("disabled");
  }

  set disabled(value: boolean) {
    this.toggleAttribute("disabled", Boolean(value));
  }

  get emphasisDotGapEm(): number | null {
    const value = Number.parseFloat(this.getAttribute("emphasis-dot-gap-em") ?? "");
    return Number.isFinite(value) ? value : null;
  }

  set emphasisDotGapEm(value: number | null) {
    if (value == null) {
      this.removeAttribute("emphasis-dot-gap-em");
    } else {
      this.setAttribute("emphasis-dot-gap-em", String(value));
    }
  }

  get strongAsEmphasisMarks(): boolean {
    return this.hasAttribute("strong-as-emphasis-marks");
  }

  set strongAsEmphasisMarks(value: boolean) {
    this.toggleAttribute("strong-as-emphasis-marks", Boolean(value));
  }

  get snapshotRef(): string | null {
    return this.getAttribute("snapshot-ref");
  }

  set snapshotRef(value: string | null) {
    if (value == null) {
      this.removeAttribute("snapshot-ref");
    } else {
      this.setAttribute("snapshot-ref", String(value));
    }
  }

  rawDomFragmentOf(paragraph: Element): DocumentFragment | null {
    return this.#context.domWriteLayer.rawDomFragmentOf(paragraph);
  }

  connectedCallback() {
    this.#context.mount();
  }

  disconnectedCallback() {
    this.#context.unmount();
  }

  // Attribute reflection: the platform has already applied the attribute to
  // the element before this callback runs, so the shell only reports the
  // parsed value; the ledger's applied diff decides the reaction.
  attributeChangedCallback(name: string, oldValue: string | null, newValue: string | null) {
    if (oldValue === newValue) return;
    if (name === "disabled") {
      this.#context.updateOptions({ disabled: newValue != null });
      return;
    }
    if (name === "snapshot-ref") {
      this.#context.updateOptions({ snapshotRef: newValue });
      return;
    }
    if (name === "strong-as-emphasis-marks") {
      this.#context.updateOptions({ strongAsEmphasisMarks: newValue != null });
      return;
    }
    if (name === "emphasis-dot-gap-em") {
      this.#context.updateOptions({ emphasisDotGapEm: this.emphasisDotGapEm });
      return;
    }
  }
}

declare global {
  interface HTMLElementTagNameMap {
    "tiqian-prose": TiqianProseElement;
  }
}

/** Options for the explicit registration entry (wc-s5 scope item 2). */
export interface RegisterTiqianProseOptions {
  /** Custom element tag to define; defaults to "tiqian-prose". */
  readonly tagName?: string;
  /** Install the source-faithful copy interceptor on the document; default true. */
  readonly interceptCopy?: boolean;
  /** Start prefetching declared snapshot tables at registration; default true. */
  readonly prefetchTables?: boolean;
  /** Target document (iframe / popup / sandbox); defaults to the global document. */
  readonly targetDocument?: Document;
}

/**
 * Idempotent, SSR-safe registration of the prose runtime. Consolidates the
 * three historical import-time side effects (clipboard interception,
 * snapshot-table prefetch, custom element definition) behind one named call.
 */
export function registerTiqianProse(options: RegisterTiqianProseOptions = {}): void {
  initializeGlobalServices();
  const tagName = options.tagName ?? ELEMENT_NAME;
  const interceptCopy = options.interceptCopy ?? true;
  const prefetchTables = options.prefetchTables ?? true;
  const targetDocument = options.targetDocument ??
    (typeof globalThis.document !== "undefined" ? globalThis.document : undefined);

  if (interceptCopy && targetDocument) globalServices().clipboard.install(targetDocument);
  // The scan is document-guarded internally and a no-op without a document.
  if (prefetchTables) prefetchSnapshotTables();

  const registry = targetDocument?.defaultView?.customElements ?? globalThis.customElements;
  if (
    typeof globalThis.HTMLElement === "function" &&
    typeof registry?.get === "function" &&
    typeof registry?.define === "function" &&
    !registry.get(tagName)
  ) {
    registry.define(tagName, TiqianProseElement);
  }
}

// The /element entry exports the registration function and types. Consumers
// who want zero-config auto-registration import from @tiqian/web-component/auto.
// Explicit, parameterized registration calls registerTiqianProse() directly.

export { TiqianProseElement, CoordinationService };
