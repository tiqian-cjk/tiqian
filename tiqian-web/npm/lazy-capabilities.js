const CJK_DASH_SOURCE = "——";
const TWO_EM_DASH = "⸺";
export const DEFAULT_TYPOGRAPHY_FONT_WAIT_MS = 3_000;

let precomputedModule;
let precomputedPromise;
let dashShapingPromise;

export function lineLengthGridCellCount(containerWidth, fontSize) {
  const width = Math.fround(Number(containerWidth));
  const size = Math.fround(Number(fontSize));
  if (!Number.isFinite(width) || width < 0 || !Number.isFinite(size) || size <= 0) return null;
  // Match Kotlin's Float division before floor(containerWidth / fontSize).
  return Math.max(1, Math.floor(Math.fround(width / size)));
}

export function lineLengthGridMeasure(containerWidth, fontSize) {
  const width = Math.fround(Number(containerWidth));
  const size = Math.fround(Number(fontSize));
  const cells = lineLengthGridCellCount(width, size);
  if (cells == null) return null;
  return Math.min(width, Math.fround(cells * size));
}

export function needsCjkDashShaping(root) {
  const text = root?.textContent ?? "";
  return text.includes(CJK_DASH_SOURCE) || text.includes(TWO_EM_DASH);
}

function normalizeFontFamily(value) {
  const trimmed = String(value ?? "").trim();
  const unquoted = trimmed.length >= 2 && (
    (trimmed.startsWith("\"") && trimmed.endsWith("\"")) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) ? trimmed.slice(1, -1) : trimmed;
  return unquoted.normalize("NFC").toLocaleLowerCase("en-US");
}

export function parseCssFontFamilies(value) {
  const families = [];
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

function numericFontWeight(value) {
  const normalized = String(value ?? "normal").trim().toLowerCase();
  if (normalized === "normal") return 400;
  if (normalized === "bold") return 700;
  const parsed = Number.parseFloat(normalized);
  return Number.isFinite(parsed) ? parsed : null;
}

function fontFaceCoversWeight(faceWeight, requestedWeight) {
  const requested = numericFontWeight(requestedWeight);
  if (requested == null || faceWeight == null || String(faceWeight).trim() === "") return true;
  const bounds = String(faceWeight).trim().split(/\s+/u).map(numericFontWeight);
  if (bounds.some((value) => value == null)) return true;
  return requested >= Math.min(...bounds) && requested <= Math.max(...bounds);
}

function fontFaceCoversStyle(faceStyle, requestedStyle) {
  if (faceStyle == null || String(faceStyle).trim() === "") return true;
  const available = String(faceStyle).trim().toLowerCase();
  const requested = String(requestedStyle || "normal").trim().toLowerCase();
  if (requested.startsWith("italic")) return available.startsWith("italic");
  if (requested.startsWith("oblique")) return available.startsWith("oblique");
  return available === "normal";
}

export function fontLoadingAffectsTypography(event, elements, getStyle = globalThis.getComputedStyle) {
  const faces = Array.from(event?.fontfaces ?? []);
  if (faces.length === 0 || typeof getStyle !== "function") return true;
  const usages = Array.from(elements ?? []).flatMap((element) => [
    null,
    "::before",
    "::after",
    "::first-letter",
    "::first-line",
  ].map((pseudo) => {
    const style = getStyle(element, pseudo);
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

function typographyFontDescriptor(style) {
  const family = style?.getPropertyValue?.("font-family")?.trim();
  const size = style?.getPropertyValue?.("font-size")?.trim();
  if (!family || !size) return null;
  const fontStyle = style.getPropertyValue("font-style").trim() || "normal";
  const weight = style.getPropertyValue("font-weight").trim() || "400";
  const stretch = style.getPropertyValue("font-stretch").trim();
  return [fontStyle, weight, stretch, size, family].filter(Boolean).join(" ");
}

export async function waitForTypographyFonts(
  fonts,
  elements,
  getStyle = globalThis.getComputedStyle,
  { timeoutMs = DEFAULT_TYPOGRAPHY_FONT_WAIT_MS } = {},
) {
  if (typeof fonts?.load !== "function" || typeof getStyle !== "function") {
    return { status: "unsupported", completion: Promise.resolve() };
  }
  const requests = new Map();
  for (const element of elements ?? []) {
    const descriptor = typographyFontDescriptor(getStyle(element));
    if (!descriptor) continue;
    let sample = requests.get(descriptor);
    if (!sample) {
      sample = new Set();
      requests.set(descriptor, sample);
    }
    for (const character of element?.textContent ?? "") sample.add(character);
  }
  const completion = Promise.all(Array.from(requests, ([descriptor, characters]) => {
    if (characters.size === 0) return Promise.resolve();
    // TypographyFontReadyGate: wait only for faces and unicode-range subsets
    // used by the prose instead of unrelated document fonts.
    return Promise.resolve()
      .then(() => fonts.load(descriptor, Array.from(characters).join("")))
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

  let timer = 0;
  const status = await Promise.race([
    completion.then(() => "settled"),
    new Promise((resolve) => {
      timer = setTimeout(() => resolve("timeout"), boundedTimeout);
    }),
  ]);
  if (timer) clearTimeout(timer);
  // BoundedTypographyFontReadyGate: callers can keep native SSR after the
  // deadline while retaining `completion` as a race-free eventual retry seam.
  return { status, completion };
}

export function loadPrecomputedSnapshots() {
  precomputedPromise ??= import("./precomputed.js").then((module) => {
    precomputedModule = module;
    return module;
  });
  return precomputedPromise;
}

export function loadedPrecomputedSnapshots() {
  return precomputedModule ?? null;
}

export function isLoadedSnapshotAdopted(root) {
  return precomputedModule?.isPrecomputedSnapshotAdopted(root) ?? false;
}

export function loadedSnapshotMaximumMeasureMatches(root) {
  return precomputedModule?.precomputedSnapshotMaximumMeasureMatches(root) ?? false;
}

export function restoreLoadedSnapshot(root) {
  return precomputedModule?.restorePrecomputedSnapshot(root) ?? false;
}

export async function restoreAdoptedSnapshot(root) {
  const snapshots = precomputedModule ?? (
    root?.dataset?.tiqianSnapshot ? await loadPrecomputedSnapshots() : null
  );
  return snapshots?.restorePrecomputedSnapshot(root) ?? false;
}

export async function tryAdoptRequestedSnapshot(root, isCurrent = () => true) {
  if (!root?.getAttribute?.("snapshot-ref")) {
    return { adopted: false, reason: "not-requested" };
  }
  const snapshots = await loadPrecomputedSnapshots();
  return snapshots.tryAdoptPrecomputedSnapshot(root, isCurrent);
}

export function prepareCjkDashShapingIfNeeded(root, options = {}) {
  if (!needsCjkDashShaping(root)) return Promise.resolve({ status: "not-needed" });
  dashShapingPromise ??= import("./font-shaping.js");
  return dashShapingPromise.then((module) => module.prepareCjkDashShaping(root, options));
}
