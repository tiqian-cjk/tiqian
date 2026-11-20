// Typography font readiness gate and initial-enhancement retry control
// (ADR 0053 batch 3; decomposition report sections 8 and 11). The gate
// decides whether the first enhancement may run now or must wait for the
// prose fonts; the retry controller re-enters the connected lifecycle when
// a bounded wait times out and the fonts settle later.

import type {
  BrowserFontSessionPreparer,
  BrowserFontSessionReleaser,
  BrowserFontSessionRevalidator,
  BrowserRenderFontPreparer,
} from "../../measurement/browser-fonts.js";
import {
  prepareBrowserFontSession,
  prepareBrowserRenderFonts,
  releaseBrowserFontSession,
  revalidateBrowserFontSession,
} from "../../measurement/browser-fonts.js";
import { globalServices } from "../../services/global-services.js";
import { loadBrowserFontFaces } from "../../measurement/font-face-loader.js";
import type { DiagnosisManager } from "../context/diagnosis-manager.js";

export const DEFAULT_TYPOGRAPHY_FONT_WAIT_MS = 3_000;

export type GetComputedStyleFn = (elt: Element, pseudoElt?: string | null) => CSSStyleDeclaration;

function typographyFontDescriptor(style: CSSStyleDeclaration | null | undefined): string | null {
  const family = style?.getPropertyValue?.("font-family")?.trim();
  const size = style?.getPropertyValue?.("font-size")?.trim();
  if (!family || !size) return null;
  const fontStyle = style!.getPropertyValue("font-style").trim() || "normal";
  const weight = style!.getPropertyValue("font-weight").trim() || "400";
  const stretch = style!.getPropertyValue("font-stretch").trim();
  return [fontStyle, weight, stretch, size, family].filter(Boolean).join(" ");
}

export type TypographyFontWaitStatus = "settled" | "timeout" | "unsupported";

export interface TypographyFontWaitResult {
  status: TypographyFontWaitStatus;
  completion: Promise<unknown>;
}

export interface TypographyFontWaitOptions {
  timeoutMs?: number;
}

export async function waitForTypographyFonts(
  fonts: FontFaceSet | null | undefined,
  elements: Iterable<Element | null | undefined> | null | undefined,
  getStyle: GetComputedStyleFn = globalThis.getComputedStyle,
  { timeoutMs = DEFAULT_TYPOGRAPHY_FONT_WAIT_MS }: TypographyFontWaitOptions = {},
): Promise<TypographyFontWaitResult> {
  if (typeof fonts?.load !== "function" || typeof getStyle !== "function") {
    return { status: "unsupported", completion: Promise.resolve() };
  }
  const requests = new Map<string, Set<string>>();
  for (const element of elements ?? []) {
    const descriptor = typographyFontDescriptor(getStyle(element!));
    if (!descriptor) continue;
    let sample = requests.get(descriptor);
    if (!sample) {
      sample = new Set<string>();
      requests.set(descriptor, sample);
    }
    for (const character of element?.textContent ?? "") sample.add(character);
  }
  const completion = Promise.all(Array.from(requests, ([descriptor, characters]) => {
    if (characters.size === 0) return Promise.resolve();
    // TypographyFontReadyGate: wait only for faces and unicode-range subsets
    // used by the prose instead of unrelated document fonts.
    return Promise.resolve()
      .then(() => loadBrowserFontFaces(fonts, descriptor, Array.from(characters).join("")))
      // A rejected face has settled on its CSS fallback. The fallback is a
      // stable layout input; only a still-pending load may race measurement.
      .catch(() => []);
  }));
  if (requests.size === 0) return { status: "settled", completion };

  const boundedTimeout = Number(timeoutMs);
  if (!Number.isFinite(boundedTimeout) || boundedTimeout < 0) {
    await completion;
    return { status: "settled", completion };
  }

  let timer: ReturnType<typeof setTimeout> | number = 0;
  const status = await Promise.race([
    completion.then(() => "settled" as const),
    new Promise<"timeout">((resolve) => {
      timer = setTimeout(() => resolve("timeout"), boundedTimeout);
    }),
  ]);
  if (timer) clearTimeout(timer);
  // BoundedTypographyFontReadyGate: callers can keep native SSR after the
  // deadline while retaining `completion` as a race-free eventual retry seam.
  return { status, completion };
}

export type ContextPredicate = () => boolean;
export type TypographyElementsProvider = () => Iterable<Element>;
export type DeferFontSettlement = (generation: number, completion: Promise<unknown>) => void;

export interface InitialTypographyFontContext {
  generation: number;
  fonts: FontFaceSet | null | undefined;
  isCurrent: ContextPredicate;
  bypassesFontWait: ContextPredicate;
  typographyElements: TypographyElementsProvider;
  deferUntilFontsSettle: DeferFontSettlement;
  diagnosis: DiagnosisManager;
}

export async function awaitInitialTypographyFonts(context: InitialTypographyFontContext): Promise<boolean> {
  if (!context.isCurrent()) return false;
  // Snapshot validation loads and probes the exact declared faces itself.
  // Repeating a per-paragraph computed-style scan here delayed the first
  // layout read and did no additional validation work.
  if (context.bypassesFontWait()) return true;
  const fontWait = await waitForTypographyFonts(
    context.fonts,
    context.typographyElements(),
    globalThis.getComputedStyle,
    { timeoutMs: DEFAULT_TYPOGRAPHY_FONT_WAIT_MS },
  );
  if (!context.isCurrent()) return false;
  if (fontWait.status !== "timeout") return true;
  // BoundedInitialFontGate: a slow or stuck FontFaceSet must not leave an
  // invisible transition in flight. Native SSR remains authoritative;
  // the exact completion promise and relevant font/style events restart
  // the whole gate against the latest host state.
  context.diagnosis.set("tiqianFontWait", "timeout");
  context.deferUntilFontsSettle(context.generation, fontWait.completion);
  return false;
}

export type GenerationPredicate = (generation: number) => boolean;
export type LifecycleRestarter = () => void;

export interface FontRetryControllerContext {
  fonts: FontFaceSet | null | undefined;
  isGenerationCurrent: GenerationPredicate;
  restartConnectedLifecycle: LifecycleRestarter;
  typographyElements: TypographyElementsProvider;
}

export type FontRetryClearer = () => void;

export interface InitialFontRetryController {
  deferUntilFontsSettle: DeferFontSettlement;
  clear: FontRetryClearer;
}

export function createInitialFontRetryController(root: HTMLElement, context: FontRetryControllerContext): InitialFontRetryController {
  let token = 0;
  let listener: EventListener | null = null;
  let observer: MutationObserver | null = null;

  function clear(): void {
    token += 1;
    observer?.disconnect();
    observer = null;
    if (listener) {
      context.fonts?.removeEventListener?.("loadingdone", listener);
      context.fonts?.removeEventListener?.("loadingerror", listener);
      listener = null;
    }
  }

  function deferUntilFontsSettle(generation: number, completion: Promise<unknown>): void {
    clear();
    const captured = token;
    const restart = () => {
      if (
        captured !== token || !root.isConnected ||
        !context.isGenerationCurrent(generation)
      ) return;
      context.restartConnectedLifecycle();
    };
    listener = (event) => {
      if (fontLoadingAffectsTypography(event as FontLoadingEventLike, context.typographyElements())) restart();
    };
    context.fonts?.addEventListener?.("loadingdone", listener);
    context.fonts?.addEventListener?.("loadingerror", listener);

    if (typeof MutationObserver === "function") {
      observer = new MutationObserver(restart);
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
    }

    Promise.resolve(completion).then(restart);
  }

  return { deferUntilFontsSettle, clear };
}

// Exact font fallback loader (merged from element.js and api.js in ADR 0053
// batch 4; decomposition report section 9). Both host entries share one lazy
// import gate; the module API path and the custom element path resolve the
// same browser-font and prepared-dom adapters.

export interface SnapshotFontFallbackLoader {
  prepareBrowserFontSession: BrowserFontSessionPreparer;
  revalidateBrowserFontSession: BrowserFontSessionRevalidator;
  prepareBrowserRenderFonts: BrowserRenderFontPreparer;
  releaseBrowserFontSession: BrowserFontSessionReleaser;
}

// The snapshot-font-fallback memo lives on the service-owned
// FontCoordinationState (page-level once-per-document). The browser-font
// adapters are direct imports from the measurement module.
export function loadSnapshotFontFallback(): Promise<SnapshotFontFallbackLoader> {
  const state = globalServices().coordination.fonts;
  state.snapshotFontFallbackPromise ??= Promise.resolve({
    prepareBrowserFontSession,
    revalidateBrowserFontSession,
    prepareBrowserRenderFonts,
    releaseBrowserFontSession,
  });
  return state.snapshotFontFallbackPromise as Promise<SnapshotFontFallbackLoader>;
}

// CSS font-family parsing and the document font-loading filter moved here
// from lazy-capabilities.js in ADR 0053 batch 6.

function normalizeFontFamily(value: unknown): string {
  const trimmed = String(value ?? "").trim();
  const unquoted = trimmed.length >= 2 && (
    (trimmed.startsWith("\"") && trimmed.endsWith("\"")) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) ? trimmed.slice(1, -1) : trimmed;
  return unquoted.normalize("NFC").toLocaleLowerCase("en-US");
}

export function parseCssFontFamilies(value: unknown): string[] {
  const families: string[] = [];
  let token = "";
  let quote = "";
  let escaped = false;
  for (const char of String(value ?? "")) {
    if (escaped) {
      token += char;
      escaped = false;
    } else if (char === "\\") {
      escaped = true;
    } else if (quote) {
      if (char === quote) quote = "";
      else token += char;
    } else if (char === "\"" || char === "'") {
      quote = char;
    } else if (char === ",") {
      if (token.trim()) families.push(normalizeFontFamily(token));
      token = "";
    } else {
      token += char;
    }
  }
  if (token.trim()) families.push(normalizeFontFamily(token));
  return families;
}

function numericFontWeight(value: unknown): number | null {
  const normalized = String(value ?? "normal").trim().toLowerCase();
  if (normalized === "normal") return 400;
  if (normalized === "bold") return 700;
  const parsed = Number.parseFloat(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

function fontFaceCoversWeight(faceWeight: unknown, requestedWeight: unknown): boolean {
  const requested = numericFontWeight(requestedWeight);
  if (requested == null || faceWeight == null || String(faceWeight).trim() === "") return true;
  const bounds = String(faceWeight).trim().split(/\s+/u).map(numericFontWeight);
  if (bounds.some((value) => value == null)) return true;
  const weights = bounds.filter((value): value is number => value != null);
  return requested >= Math.min(...weights) && requested <= Math.max(...weights);
}

function fontFaceCoversStyle(faceStyle: unknown, requestedStyle: unknown): boolean {
  if (faceStyle == null || String(faceStyle).trim() === "") return true;
  const available = String(faceStyle).trim().toLowerCase();
  const requested = String(requestedStyle || "normal").trim().toLowerCase();
  if (requested.startsWith("italic")) return available.startsWith("italic");
  if (requested.startsWith("oblique")) return available.startsWith("oblique");
  return available === "normal";
}

export interface FontLoadingEventLike {
  fontfaces?: readonly FontFace[] | FontFace[];
}

export interface TypographyUsageEntry {
  families: Set<string>;
  weight: string;
  fontStyle: string;
}

export function fontLoadingAffectsTypography(
  event: FontLoadingEventLike | null | undefined,
  elements: Iterable<Element | null | undefined> | null | undefined,
  getStyle: GetComputedStyleFn = globalThis.getComputedStyle,
): boolean {
  const faces = Array.from(event?.fontfaces ?? []);
  if (faces.length === 0 || typeof getStyle !== "function") return true;
  const usages: TypographyUsageEntry[] = Array.from(elements ?? []).flatMap((element) => [
    null,
    "::before",
    "::after",
    "::first-letter",
    "::first-line",
  ].map((pseudo) => {
    const style = getStyle(element!, pseudo);
    return {
      families: new Set(parseCssFontFamilies(style.getPropertyValue("font-family"))),
      weight: style.getPropertyValue("font-weight"),
      fontStyle: style.getPropertyValue("font-style"),
    };
  }));
  return faces.some((face) => {
    const family = normalizeFontFamily(face?.family);
    return usages.some((usage) =>
      usage.families.has(family) &&
      fontFaceCoversWeight(face?.weight, usage.weight) &&
      fontFaceCoversStyle(face?.style, usage.fontStyle));
  });
}
