// DOM invalidation sources and root sampling observers (ADR 0053 batch 2;
// decomposition report section 2). Each source owns the platform wiring
// (observer construction, observe targets, event listeners) and reports
// facts through callbacks; comparison and commit decisions stay with the
// element. Kinds: geometry, typography, content.

import { DEFAULT_PARAGRAPH_SELECTOR, fragmentedBorderBoxInlineSize } from "./signatures.js";
import { onDeclaredFacesChanged } from "./snapshot/declared-faces.js";
import { documentViewportInlineSizeDegenerate } from "../engine/responsive-measure.js";
import type { RawDomParagraphRecord } from "../engine/context/enhance-context.js";

type EmptyCallback = () => void;
type DeclaredFacesUnsubscribe = () => boolean;
type FontEventCallback = (event: Event) => void;
type MutationRecordsCallback = (records: MutationRecord[]) => void;
type RootScopeMembershipCallback = (paragraph: Element, root: Element) => boolean;
type RawDomParagraphCallback = (node: Node) => Element | null;
type PendingRecordsCallback = () => MutationRecord[];
type RootSizeEntryCallback = (entry: RootSizeEntry) => void;
type RootSizeTargetsCallback = (targets: Element[]) => void;
type RootSizeTargetCallback = (target: Element) => void;
type RootVisibilityEntryCallback = (entry: RootVisibilityEntry) => void;

const ROOT_SELECTOR = "tiqian-prose, [data-tiqian-root]";

// Root-scope membership: the closest enhanced root of an element decides its
// owner, so a paragraph nested in another tiqian root belongs to that root.
export function belongsToRootScope(element: Element, root: Element): boolean {
  return element.closest(ROOT_SELECTOR) === root;
}

// Root-scoped paragraph collection for observation seeding and retargeting:
// the default paragraph candidates that belong to this root.
export function rootScopedParagraphs(root: Element): Element[] {
  const paragraphs = root.querySelectorAll(DEFAULT_PARAGRAPH_SELECTOR);
  const scoped: Element[] = [];
  for (let i = 0; i < paragraphs.length; i += 1) {
    const paragraph = paragraphs[i];
    if (belongsToRootScope(paragraph, root)) scoped.push(paragraph);
  }
  return scoped;
}

export interface TypographyInvalidationHandlers {
  onMutation: EmptyCallback;
  onFontEvent: FontEventCallback;
  onDeclaredFacesChanged?: EmptyCallback;
}

export interface TypographyInvalidationSource {
  kind: "typography";
  start: EmptyCallback;
  stop: EmptyCallback;
}

export function createTypographyInvalidationSource(root: Element, handlers: TypographyInvalidationHandlers): TypographyInvalidationSource {
  let observer: MutationObserver | null = null;
  let fontListener: EventListener | null = null;
  let declaredUnsubscribe: DeclaredFacesUnsubscribe | null = null;

  return {
    kind: "typography",
    start() {
      observer?.disconnect();
      observer = new MutationObserver(() => handlers.onMutation());
      // Descendant class/style changes can alter inline semantics. Any ancestor
      // attribute can participate in selectors that change inherited typography.
      observer.observe(root, {
        attributes: true,
        subtree: true,
        attributeFilter: ["class", "style", "data-theme", "data-color-mode"],
      });
      for (let ancestor = root.parentElement; ancestor; ancestor = ancestor.parentElement) {
        observer.observe(ancestor, {
          attributes: true,
          attributeFilter: ["class", "data-theme", "data-color-mode", "lang", "dir"],
        });
      }
      if (document.fonts) {
        fontListener = handlers.onFontEvent;
        document.fonts.addEventListener("loadingdone", fontListener);
        document.fonts.addEventListener("loadingerror", fontListener);
      }
      // DeclaredFaceEvidence (ADR 0053): registry changes wake the root the
      // way a font loading event does. The wake only schedules a check; it
      // never validates inline. The declaration is module-level state shared
      // by every root, so each active root subscribes its own wake and
      // unsubscribes on stop.
      if (handlers.onDeclaredFacesChanged && !declaredUnsubscribe) {
        declaredUnsubscribe = onDeclaredFacesChanged(handlers.onDeclaredFacesChanged);
      }
    },
    stop() {
      observer?.disconnect();
      observer = null;
      if (fontListener) {
        document.fonts?.removeEventListener("loadingdone", fontListener);
        document.fonts?.removeEventListener("loadingerror", fontListener);
        fontListener = null;
      }
      if (declaredUnsubscribe) {
        declaredUnsubscribe();
        declaredUnsubscribe = null;
      }
    },
  };
}

export interface LayoutWorkTypographyInvalidationHandlers {
  onMutation: MutationRecordsCallback;
  onFontEvent: FontEventCallback;
}

export function createLayoutWorkTypographyInvalidationSource(root: Element, handlers: LayoutWorkTypographyInvalidationHandlers): TypographyInvalidationSource {
  let observer: MutationObserver | null = null;
  let fontListener: EventListener | null = null;

  return {
    kind: "typography",
    start() {
      this.stop();
      observer = new MutationObserver((records) => handlers.onMutation(records));
      observer.observe(root, {
        attributes: true,
        subtree: true,
        attributeFilter: ["class", "style", "data-theme", "data-color-mode"],
        attributeOldValue: true,
      });
      for (let ancestor = root.parentElement; ancestor; ancestor = ancestor.parentElement) {
        observer.observe(ancestor, {
          attributes: true,
          attributeFilter: ["class", "data-theme", "data-color-mode", "lang", "dir"],
        });
      }
      if (document.fonts) {
        fontListener = (event) => handlers.onFontEvent(event);
        document.fonts.addEventListener("loadingdone", fontListener);
        document.fonts.addEventListener("loadingerror", fontListener);
      }
    },
    stop() {
      observer?.disconnect();
      observer = null;
      if (fontListener) {
        document.fonts?.removeEventListener("loadingdone", fontListener);
        document.fonts?.removeEventListener("loadingerror", fontListener);
        fontListener = null;
      }
    },
  };
}

export interface ViewportResizeInvalidationHandlers {
  onResize: EmptyCallback;
}

export interface ViewportResizeInvalidationSource {
  kind: "geometry";
  start: EmptyCallback;
  stop: EmptyCallback;
}

export function createViewportResizeInvalidationSource(handlers: ViewportResizeInvalidationHandlers): ViewportResizeInvalidationSource {
  let listener: EventListener | null = null;

  return {
    kind: "geometry",
    start() {
      if (listener) return;
      listener = () => handlers.onResize();
      window.addEventListener("resize", listener);
      globalThis.visualViewport?.addEventListener?.("resize", listener);
    },
    stop() {
      if (!listener) return;
      window.removeEventListener("resize", listener);
      globalThis.visualViewport?.removeEventListener?.("resize", listener);
      listener = null;
    },
  };
}

type GetRawDomParagraphsFn = () => Iterable<[Element, RawDomParagraphRecord]>;

export interface ContentInvalidationHandlers {
  belongsToRootScope: RootScopeMembershipCallback;
  onRecords: MutationRecordsCallback;
  getRawDomParagraphs: GetRawDomParagraphsFn;
}

export interface ContentInvalidationSource {
  kind: "content";
  start: EmptyCallback;
  stop: EmptyCallback;
  syncRawDom: EmptyCallback;
  paragraphFor: RawDomParagraphCallback;
  takePendingRecords: PendingRecordsCallback;
}

export function createContentInvalidationSource(root: Element, handlers: ContentInvalidationHandlers): ContentInvalidationSource {
  let observer: MutationObserver | null = null;
  const rawDomTargets = new Map<DocumentFragment, Element>();

  // Attribution for a record under a raw-DOM backup fragment: walk up to the
  // enclosing detached fragment and map it back to its live paragraph. Live
  // nodes never reach a DocumentFragment ancestor, so the walk is safe there.
  function paragraphFor(node: Node) {
    let current: Node | null = node;
    while (current) {
      if (current.nodeType === 11) {
        return rawDomTargets.get(current as DocumentFragment) || null;
      }
      current = current.parentNode;
    }
    return null;
  }

  // RawDomFragmentObservation: takeover moves the host's semantic children
  // into a detached fragment the engine holds. Frameworks keep references to
  // those original nodes (React's text update writes .data on them), so host
  // edits land inside the raw-DOM backup where the live-DOM subtree never sees them.
  // Kotlin publishes the current fragment on each rendered paragraph; observe
  // every tracked fragment alongside the root. Re-lowering creates a fresh
  // fragment, so diff the desired set at every job boundary and re-target the
  // observer only when it changed.
  function syncRawDom() {
    const desired = new Map<DocumentFragment, Element>();
    for (const [paragraph, record] of handlers.getRawDomParagraphs()) {
      if (paragraph.getAttribute("data-tq-rendered") !== "true") continue;
      if (!handlers.belongsToRootScope(paragraph, root)) continue;
      if (record.fragment) desired.set(record.fragment, paragraph);
    }
    let unchanged = desired.size === rawDomTargets.size;
    if (unchanged) {
      for (const [fragment, paragraph] of desired) {
        if (rawDomTargets.get(fragment) !== paragraph) {
          unchanged = false;
          break;
        }
      }
    }
    if (unchanged) return;
    // Pending records from the outgoing target set still count. Flush them
    // through the handler first, or a host edit landing in the same frame
    // would be dropped together with the old registration.
    const pending = observer!.takeRecords();
    if (pending.length) handlers.onRecords(pending);
    observer!.disconnect();
    observer!.observe(root, { childList: true, characterData: true, subtree: true });
    for (const fragment of desired.keys()) {
      observer!.observe(fragment, { childList: true, characterData: true, subtree: true });
    }
    rawDomTargets.clear();
    for (const [fragment, paragraph] of desired) rawDomTargets.set(fragment, paragraph);
  }

  return {
    kind: "content",
    start() {
      if (!observer) {
        observer = new MutationObserver((records) => handlers.onRecords(records));
        observer.observe(root, { childList: true, characterData: true, subtree: true });
      }
      syncRawDom();
    },
    stop() {
      observer?.disconnect();
      observer = null;
      rawDomTargets.clear();
    },
    syncRawDom,
    paragraphFor,
    takePendingRecords() {
      return observer?.takeRecords() ?? [];
    },
  };
}

export interface ContentMutationClassificationContext {
  rawDomParagraphFor: RawDomParagraphCallback;
  belongsToRootScope: RootScopeMembershipCallback;
  root: Element;
}

export interface ContentMutationClassification {
  taintedParagraphs: Element[];
  paragraphSignal: boolean;
  structureSignal: boolean;
}

// Stateless per-record classification for the content invalidation source.
// The element supplies the raw-DOM backup attribution, the root-scope membership
// test and the root; everything here is a pure decision over the records.
export function classifyContentMutationRecords(
  records: MutationRecord[],
  context: ContentMutationClassificationContext,
): ContentMutationClassification {
  let paragraphSignal = false;
  let structureSignal = false;
  const taintedParagraphs: Element[] = [];
  for (let i = 0; i < records.length; i++) {
    const record = records[i];
    // EnginePreparedStyleWritesAreNotContent: the prepared-dom renderer
    // rewrites its own <style data-tq-prepared-value-styles> text content on
    // every commit. Those records are engine output, never a host signal.
    const recordElement: Element | null = record.type === "characterData"
      ? record.target.parentElement
      : (record.target as Element);
    if (recordElement?.closest?.("[data-tq-prepared-value-styles]")) continue;
    const rawDomParagraph = context.rawDomParagraphFor(record.target);
    if (rawDomParagraph) {
      // RawDomCharacterDataIsHostCertain: the engine only moves whole
      // nodes in and out of the raw-DOM backup and never rewrites text inside it, so
      // a characterData record there is a framework editing the original
      // node it still holds. Taint directly. A childList record may be the
      // engine's own re-take or rollback refill; the raw-DOM backup identity
      // check in the probe tells them apart, so it only raises the flag.
      if (record.type === "characterData") taintedParagraphs.push(rawDomParagraph);
      paragraphSignal = true;
      continue;
    }
    // Removed renderer subtrees can still deliver queued records. Their old
    // inline nodes are not host structure changes; raw-DOM backups were handled above.
    if (!recordElement || !context.belongsToRootScope(recordElement, context.root)) continue;

    const paragraph = recordElement?.closest?.(DEFAULT_PARAGRAPH_SELECTOR);
    if (paragraph && context.belongsToRootScope(paragraph, context.root)) {
      // TopLevelChildListTrustsIdentityProbe: engine commits append and
      // remove a paragraph's direct children on every render, so a top-level
      // childList record proves nothing by itself. The Kotlin classifier
      // proves engine ownership by node identity. Only an in-place text
      // edit, which child identity cannot see, taints its paragraph.
      if (record.type === "characterData") taintedParagraphs.push(paragraph);
      paragraphSignal = true;
    } else if (record.type === "childList") {
      // Records outside any paragraph (a host adding or removing paragraph
      // wrappers or editing non-paragraph flow) change the candidate set.
      structureSignal = true;
    }
  }
  return { taintedParagraphs, paragraphSignal, structureSignal };
}

export interface RootSizeEntry {
  width: number;
  height: number;
}

export interface RootSizeObservationOptions {
  widths: WeakMap<Element, number>;
  onRootEntry: RootSizeEntryCallback;
  onWidthsChanged: EmptyCallback;
  root: Element;
}

export interface RootSizeObservationSource {
  kind: "geometry";
  readonly widths: WeakMap<Element, number>;
  start: RootSizeTargetsCallback;
  observe: RootSizeTargetCallback;
  unobserve: RootSizeTargetCallback;
  stop: EmptyCallback;
}

export function createRootSizeObservation(options: RootSizeObservationOptions): RootSizeObservationSource {
  let observer: ResizeObserver | null = null;
  const { widths, onRootEntry, onWidthsChanged, root } = options;

  return {
    kind: "geometry",
    get widths() { return widths; },
    start(targets) {
      observer = new ResizeObserver((entries) => {
        // DegenerateViewportWidthRejection: entries delivered while the
        // document viewport is collapsed (a beyond-viewport screenshot
        // capture window) carry zero inline sizes for every target.
        // Recording them would overwrite the healthy baselines below and
        // dispatch responsive work at the fallback width. Skip the whole
        // delivery; the post-restore delivery compares against the kept
        // baselines, so only a real width change dispatches.
        if (documentViewportInlineSizeDegenerate()) return;
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
          if (entry.target === root) {
            const height = entry.contentRect ? entry.contentRect.height : 0;
            onRootEntry({ width, height });
          }
          if (previous == null || Math.abs(width - previous) >= 0.5) changed = true;
        }
        if (!changed) return;
        onWidthsChanged();
      });
      for (let i = 0; i < targets.length; i++) {
        observer.observe(targets[i], { box: "border-box" });
      }
    },
    observe(target) {
      observer?.observe(target, { box: "border-box" });
    },
    unobserve(target) {
      observer?.unobserve(target);
    },
    stop() {
      observer?.disconnect();
      observer = null;
    },
  };
}

export interface RootVisibilityHandlers {
  onRootEntry: RootVisibilityEntryCallback;
}

export interface RootVisibilityEntry {
  isIntersecting: boolean;
  intersectionRatio: number;
  visibleArea: number;
  inlineSize: number;
  area: number;
}

export interface RootVisibilityObservationSource {
  kind: "geometry";
  start: EmptyCallback;
  stop: EmptyCallback;
}

export function createRootVisibilityObservation(root: Element, handlers: RootVisibilityHandlers): RootVisibilityObservationSource {
  let observer: IntersectionObserver | null = null;

  return {
    kind: "geometry",
    start() {
      if (typeof IntersectionObserver === "undefined") return;
      observer = new IntersectionObserver((entries) => {
        for (let i = 0; i < entries.length; i++) {
          const entry = entries[i];
          if (entry.target === root) {
            const rect = entry.boundingClientRect;
            const interRect = entry.intersectionRect;
            const visibleArea = interRect ? interRect.width * interRect.height : 0;
            const fact: RootVisibilityEntry = {
              isIntersecting: entry.isIntersecting,
              intersectionRatio: entry.intersectionRatio || (entry.isIntersecting ? 1.0 : 0.0),
              visibleArea,
              inlineSize: rect ? rect.width : 0,
              area: rect ? rect.width * rect.height : 0,
            };
            handlers.onRootEntry(fact);
          }
        }
      }, { rootMargin: "200px 0px" });
      observer.observe(root);
    },
    stop() {
      observer?.disconnect();
      observer = null;
    },
  };
}