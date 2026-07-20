import {
  FONT_BACKEND_REVISION,
  FONT_REPLAY_REVISION,
  FONT_SOURCE_POLICY,
  LAYOUT_REVISION,
  RENDER_REVISION,
  SNAPSHOT_SCHEMA,
  stableStringify,
} from "./snapshot-schema.js";
import {
  installPreparedValueStyles,
  releasePreparedValueStyleRoot,
} from "./prepared-dom.js";
import { parseSnapshotManifest } from "./snapshot-manifest.js";
import {
  snapshotSourceArtifactFromDom,
  snapshotSourceArtifactString,
} from "./snapshot-source.js";
import { lineLengthGridMeasure } from "./lazy-capabilities.js";

const ROOT_SELECTOR = "tiqian-prose, [data-tiqian-root]";
const WIDTH_TOLERANCE_PX = 0.5;
const PROBE_ABSOLUTE_TOLERANCE_PX = 0.75;
const PROBE_RELATIVE_TOLERANCE = 0.03;
// CompatibleLocalSegmentAdvanceTolerance: a locally installed revision may
// differ from the published face by a subpixel while retaining the prepared
// line model. Keep segment validation aligned with the already-required font
// probe, then let serialized prefix positions and the line sentinel reject any
// drift that changes the actual layout.
const SEGMENT_ADVANCE_ABSOLUTE_TOLERANCE_PX = PROBE_ABSOLUTE_TOLERANCE_PX;
const SEGMENT_ADVANCE_RELATIVE_TOLERANCE = PROBE_RELATIVE_TOLERANCE;
// BrowserSubpixelQuantizationAllowance: Range/inline fragment geometry is
// quantized to 1/64 CSS px. Add exactly one quantization step to the existing
// 0.75 px contract so a compatible-local prefix at 0.76 px does not discard an
// otherwise identical line; a full-pixel prefix drift still fails closed.
const BROWSER_SUBPIXEL_QUANTIZATION_PX = 1 / 64;
// Serialized engine floats can land a few 1e-13 px below their mathematical
// value (for example 898.9999999999998). Do not turn that representation noise
// into a rejection exactly on the named 49/64 px boundary.
const GEOMETRY_COMPARISON_EPSILON_PX = 1e-9;
const LINE_ADVANCE_TOLERANCE_PX = PROBE_ABSOLUTE_TOLERANCE_PX +
  BROWSER_SUBPIXEL_QUANTIZATION_PX + GEOMETRY_COMPARISON_EPSILON_PX;
const INLINE_POSITION_TOLERANCE_PX = PROBE_ABSOLUTE_TOLERANCE_PX +
  BROWSER_SUBPIXEL_QUANTIZATION_PX + GEOMETRY_COMPARISON_EPSILON_PX;
const LINE_VERTICAL_TOLERANCE_PX = 0.75;
const PREPARED_VERTICAL_TOLERANCE_PX = 0.02;
const exactFontReplayProofs = new WeakMap();
const FONT_FACE_LIVE_SIGNATURE_PROPERTIES = Object.freeze([
  "font-family",
  "font-style",
  "font-weight",
  "font-stretch",
  "unicode-range",
  "src",
  "size-adjust",
  "ascent-override",
  "descent-override",
  "line-gap-override",
  "font-feature-settings",
  "font-variation-settings",
  "font-language-override",
  "font-named-instance",
  "font-display",
]);
const VALIDATION_SLICE_BUDGET_MS = 8;
// Direct SSR is already exact, readable DOM; its proof can favor input and
// host rendering more aggressively without delaying a visible takeover.
const DIRECT_SSR_VALIDATION_SLICE_BUDGET_MS = 4;
const unicodeRangeCache = new Map();

async function yieldValidationIfNeeded(sliceStartedAt) {
  if (performance.now() - sliceStartedAt < VALIDATION_SLICE_BUDGET_MS) {
    return sliceStartedAt;
  }
  if (typeof globalThis.scheduler?.yield === "function") {
    await globalThis.scheduler.yield();
  } else {
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  return performance.now();
}

async function yieldDirectSsrValidationIfNeeded(sliceStartedAt) {
  if (performance.now() - sliceStartedAt < DIRECT_SSR_VALIDATION_SLICE_BUDGET_MS) {
    return sliceStartedAt;
  }
  // DirectSsrBackgroundProof: the exact server DOM is already live and needs
  // no client takeover. Continue its proof below input/rendering priority;
  // unlike scheduler.yield(), this cannot chain user-visible continuations
  // ahead of wheel frames under Edge JITless.
  if (
    typeof globalThis.requestAnimationFrame === "function" &&
    globalThis.document?.visibilityState !== "hidden"
  ) {
    await new Promise((resolve) => globalThis.requestAnimationFrame(() => {
      if (typeof globalThis.scheduler?.postTask === "function") {
        void globalThis.scheduler.postTask(resolve, { priority: "background" });
      } else {
        setTimeout(resolve, 0);
      }
    }));
  } else if (typeof globalThis.scheduler?.postTask === "function") {
    await globalThis.scheduler.postTask(() => {}, { priority: "background" });
  } else {
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  return performance.now();
}

function yieldSnapshotValidationIfNeeded(sliceStartedAt, serverRenderedEntries) {
  return serverRenderedEntries
    ? yieldDirectSsrValidationIfNeeded(sliceStartedAt)
    : yieldValidationIfNeeded(sliceStartedAt);
}
const RENDER_FLOW_EPSILON_PX = 0.01;
const PROPORTIONAL_CURLY_QUOTE_FEATURE_SIGNATURE = "pwid,palt";
const ENGINE_PUNCTUATION_FEATURE_SETTINGS = '"halt" 0, "chws" 0, "palt" 0';
const PROPORTIONAL_CURLY_QUOTE_FEATURE_SETTINGS =
  '"halt" 0, "chws" 0, "palt" 1';
export const EXACT_RENDER_FONT_ATTRIBUTE = "data-tiqian-exact-render-font";
const EXACT_PREPARED_DOM_ATTRIBUTE = "data-tq-exact-prepared-dom";
const SERVER_RENDERED_SNAPSHOT_ATTRIBUTE = "data-tq-ssr-snapshot";
const EXACT_LAYOUT_ISSUE_ATTRIBUTE = "data-tiqian-exact-layout-issue";
const TYPOGRAPHY_ISSUE_ATTRIBUTE = "data-tiqian-snapshot-typography-issue";
const states = new WeakMap();
const directServerArtifacts = new WeakMap();

function parseFontFamilies(value) {
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
      if (token.trim()) families.push(token.trim());
      token = "";
    } else {
      token += char;
    }
  }
  if (token.trim()) families.push(token.trim());
  return families;
}

function snapshotEntryWidthMatches(width, entry) {
  if (!Number.isFinite(width) || !Number.isFinite(entry?.maxWidthPx)) return false;
  if (entry.typography?.lineLengthGridEnabled === true) {
    const fontSize = Number(entry.typography.fontSizePx);
    const actualMeasure = lineLengthGridMeasure(width, fontSize);
    const preparedMeasure = lineLengthGridMeasure(entry.maxWidthPx, fontSize);
    return actualMeasure != null && preparedMeasure != null &&
      Math.abs(actualMeasure - preparedMeasure) <= WIDTH_TOLERANCE_PX;
  }
  return Math.abs(width - entry.maxWidthPx) <= WIDTH_TOLERANCE_PX;
}

function parseUnicodeRange(value) {
  const serialized = String(value ?? "").trim();
  if (!serialized) return null;
  const cached = unicodeRangeCache.get(serialized);
  if (cached) return cached;
  const ranges = [];
  for (const item of serialized.split(",")) {
    const token = item.trim().toUpperCase();
    if (!token.startsWith("U+")) continue;
    const body = token.slice(2);
    if (/^[0-9A-F?]{1,6}$/.test(body) && body.includes("?")) {
      ranges.push([
        Number.parseInt(body.replaceAll("?", "0"), 16),
        Number.parseInt(body.replaceAll("?", "F"), 16),
      ]);
      continue;
    }
    const match = /^([0-9A-F]{1,6})(?:-([0-9A-F]{1,6}))?$/.exec(body);
    if (!match) continue;
    const start = Number.parseInt(match[1], 16);
    ranges.push([start, Number.parseInt(match[2] ?? match[1], 16)]);
  }
  ranges.sort((left, right) => left[0] - right[0] || left[1] - right[1]);
  const merged = [];
  for (const range of ranges) {
    const previous = merged.at(-1);
    if (previous && range[0] <= previous[1] + 1) {
      previous[1] = Math.max(previous[1], range[1]);
    } else {
      merged.push([...range]);
    }
  }
  // Parsed CSS descriptors are immutable contract data and repeat across
  // article manifests. Keep a bounded module-level cache so client navigation
  // does not repeatedly tokenize the same unicode-range shards.
  if (unicodeRangeCache.size >= 4_096) unicodeRangeCache.clear();
  unicodeRangeCache.set(serialized, merged);
  return merged;
}

function unicodeRangesIntersectCoverage(ranges, codePoints) {
  if (ranges == null) return true;
  // UnicodeRangeFaceGroupIntersection: both inputs are sorted and parsed CSS
  // ranges are merged. Search whichever collection is smaller in the other
  // collection's index: unicode-range shards often have only a handful of
  // intervals, while a CJK article can have hundreds of distinct code points.
  if (ranges.length <= codePoints.length) {
    for (const range of ranges) {
      let low = 0;
      let high = codePoints.length;
      while (low < high) {
        const middle = (low + high) >>> 1;
        if (codePoints[middle] < range[0]) low = middle + 1;
        else high = middle;
      }
      if (low < codePoints.length && codePoints[low] <= range[1]) return true;
    }
  } else {
    for (const point of codePoints) {
      let low = 0;
      let high = ranges.length;
      while (low < high) {
        const middle = (low + high) >>> 1;
        if (ranges[middle][0] <= point) low = middle + 1;
        else high = middle;
      }
      const candidate = ranges[low - 1];
      if (candidate && point <= candidate[1]) return true;
    }
  }
  return false;
}

function unicodeRangesContainCodePoint(ranges, codePoint) {
  return ranges == null || ranges.some(([start, end]) => codePoint >= start && codePoint <= end);
}

function unquote(value) {
  const normalized = String(value ?? "").trim();
  if (
    normalized.length >= 2 &&
    ((normalized.startsWith("\"") && normalized.endsWith("\"")) ||
      (normalized.startsWith("'") && normalized.endsWith("'")))
  ) return normalized.slice(1, -1);
  return normalized;
}

function sourceUrls(value, baseUrl) {
  const urls = [];
  const expression = /url\(\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)'|([^)]*?))\s*\)/giu;
  for (const match of String(value ?? "").matchAll(expression)) {
    const source = (match[1] ?? match[2] ?? match[3] ?? "").trim();
    if (!source) continue;
    try {
      urls.push(new URL(source.replace(/\\([\\"'])/gu, "$1"), baseUrl).href);
    } catch {
      // A malformed URL is not verifiable evidence.
    }
  }
  return urls;
}

function sourceLocalNames(value) {
  const names = [];
  const expression = /local\(\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)'|([^)]*?))\s*\)/giu;
  for (const match of String(value ?? "").matchAll(expression)) {
    const name = (match[1] ?? match[2] ?? match[3] ?? "").trim();
    if (name) names.push(name.replace(/\\([\\"'])/gu, "$1"));
  }
  return names;
}

function canonicalLocalFontName(value) {
  return String(value ?? "")
    .normalize("NFC")
    .trim()
    .toLowerCase();
}

function compatibleLocalSources(face, evidence) {
  if (!face.hasLocalSource) return true;
  const allowed = new Set(Array.from(evidence.localNames ?? [], canonicalLocalFontName));
  return face.localNames.length > 0 && face.localNames.every((name) =>
    allowed.has(canonicalLocalFontName(name)));
}

function collectFontFaces(documentObject, requestedFamilies = null) {
  const faces = [];
  let unverifiable = false;
  const visit = (rules, fallbackBaseUrl) => {
    if (!rules) return;
    for (const rule of rules) {
      if (rule.type === 5 && rule.style) {
        const style = rule.style;
        const family = unquote(style.getPropertyValue("font-family"));
        if (requestedFamilies && !requestedFamilies.has(family.toLowerCase())) continue;
        const baseUrl = rule.parentStyleSheet?.href || fallbackBaseUrl;
        const source = style.getPropertyValue("src");
        faces.push({
          family,
          style: style.getPropertyValue("font-style") || "normal",
          weight: style.getPropertyValue("font-weight") || "400",
          stretch: style.getPropertyValue("font-stretch") || "normal",
          unicodeRanges: parseUnicodeRange(style.getPropertyValue("unicode-range")),
          urls: sourceUrls(source, baseUrl),
          hasLocalSource: /local\s*\(/iu.test(source),
          localNames: sourceLocalNames(source),
          sizeAdjust: style.getPropertyValue("size-adjust"),
          ascentOverride: style.getPropertyValue("ascent-override"),
          descentOverride: style.getPropertyValue("descent-override"),
          lineGapOverride: style.getPropertyValue("line-gap-override"),
          featureSettings: style.getPropertyValue("font-feature-settings"),
          variationSettings: style.getPropertyValue("font-variation-settings"),
          languageOverride: style.getPropertyValue("font-language-override"),
          namedInstance: style.getPropertyValue("font-named-instance"),
          display: style.getPropertyValue("font-display"),
        });
      } else {
        try {
          if (rule.cssRules) visit(rule.cssRules, rule.parentStyleSheet?.href || fallbackBaseUrl);
        } catch {
          unverifiable = true;
        }
      }
    }
  };
  for (const sheet of documentObject.styleSheets ?? []) {
    try {
      visit(sheet.cssRules, sheet.href || documentObject.baseURI);
    } catch {
      unverifiable = true;
    }
  }
  return { faces, unverifiable };
}

async function collectFontFacesCooperatively(
  documentObject,
  requestedFamilies = null,
  isCurrent = () => true,
  yieldIfNeeded = yieldValidationIfNeeded,
) {
  const faces = [];
  let unverifiable = false;
  let sliceStartedAt = performance.now();
  const visit = async (rules, fallbackBaseUrl) => {
    if (!rules) return true;
    for (const rule of rules) {
      if (rule.type === 5 && rule.style) {
        const style = rule.style;
        const family = unquote(style.getPropertyValue("font-family"));
        if (!requestedFamilies || requestedFamilies.has(family.toLowerCase())) {
          const baseUrl = rule.parentStyleSheet?.href || fallbackBaseUrl;
          const source = style.getPropertyValue("src");
          faces.push({
            family,
            style: style.getPropertyValue("font-style") || "normal",
            weight: style.getPropertyValue("font-weight") || "400",
            stretch: style.getPropertyValue("font-stretch") || "normal",
            unicodeRanges: parseUnicodeRange(style.getPropertyValue("unicode-range")),
            urls: sourceUrls(source, baseUrl),
            hasLocalSource: /local\s*\(/iu.test(source),
            localNames: sourceLocalNames(source),
            sizeAdjust: style.getPropertyValue("size-adjust"),
            ascentOverride: style.getPropertyValue("ascent-override"),
            descentOverride: style.getPropertyValue("descent-override"),
            lineGapOverride: style.getPropertyValue("line-gap-override"),
            featureSettings: style.getPropertyValue("font-feature-settings"),
            variationSettings: style.getPropertyValue("font-variation-settings"),
            languageOverride: style.getPropertyValue("font-language-override"),
            namedInstance: style.getPropertyValue("font-named-instance"),
            display: style.getPropertyValue("font-display"),
          });
        }
      } else {
        try {
          if (rule.cssRules && !await visit(
            rule.cssRules,
            rule.parentStyleSheet?.href || fallbackBaseUrl,
          )) return false;
        } catch {
          unverifiable = true;
        }
      }
      sliceStartedAt = await yieldIfNeeded(sliceStartedAt);
      if (!isCurrent()) return false;
    }
    return true;
  };
  for (const sheet of documentObject.styleSheets ?? []) {
    try {
      if (!await visit(sheet.cssRules, sheet.href || documentObject.baseURI)) {
        return { faces, unverifiable, superseded: true };
      }
    } catch {
      unverifiable = true;
    }
  }
  return { faces, unverifiable, superseded: !isCurrent() };
}

function relevantFontFaceLiveSignature(documentObject, requestedFamilies) {
  const descriptors = [];
  let unverifiable = false;
  const visit = (rules, fallbackBaseUrl) => {
    if (!rules) return;
    for (const rule of rules) {
      if (rule.type === 5 && rule.style) {
        const family = unquote(rule.style.getPropertyValue("font-family"));
        if (!requestedFamilies.has(family.toLowerCase())) continue;
        descriptors.push([
          rule.parentStyleSheet?.href || fallbackBaseUrl,
          ...FONT_FACE_LIVE_SIGNATURE_PROPERTIES.map((property) =>
            rule.style.getPropertyValue(property)),
        ]);
      } else {
        try {
          if (rule.cssRules) visit(rule.cssRules, rule.parentStyleSheet?.href || fallbackBaseUrl);
        } catch {
          unverifiable = true;
        }
      }
    }
  };
  for (const sheet of documentObject.styleSheets ?? []) {
    try {
      visit(sheet.cssRules, sheet.href || documentObject.baseURI);
    } catch {
      unverifiable = true;
    }
  }
  return { signature: stableStringify(descriptors), unverifiable };
}

function manifestFontFamilies(manifest) {
  const families = new Set();
  for (const entry of [...(manifest.entries ?? []), ...(manifest.fontContractEntries ?? [])]) {
    for (const face of entry?.fontEvidence?.faces ?? []) {
      if (typeof face?.family === "string" && face.family.trim()) {
        families.add(face.family.trim().toLowerCase());
      }
    }
  }
  return families;
}

function numericWeight(value) {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (normalized === "normal") return 400;
  if (normalized === "bold") return 700;
  const parsed = Number.parseFloat(normalized);
  return Number.isFinite(parsed) ? parsed : 400;
}

function weightRangeMatches(descriptor, expected) {
  if (!Array.isArray(expected) || expected.length !== 2) return false;
  const values = String(descriptor ?? "400").trim().split(/\s+/u).map(numericWeight);
  return Math.min(...values) === Number(expected[0]) && Math.max(...values) === Number(expected[1]);
}

function cssWeightPreference(descriptor, requested) {
  const values = String(descriptor ?? "400").trim().split(/\s+/u).map(numericWeight);
  const low = Math.min(...values);
  const high = Math.max(...values);
  if (requested >= low && requested <= high) return [0, 0];
  if (requested >= 400 && requested <= 500) {
    if (low > requested && low <= 500) return [1, low - requested];
    if (high < requested) return [2, requested - high];
    return [3, low - 500];
  }
  if (requested < 400) {
    return high < requested ? [1, requested - high] : [2, low - requested];
  }
  return low > requested ? [1, low - requested] : [2, requested - high];
}

function cssWeightMatchedFaces(faces, requested) {
  if (faces.length <= 1) return faces;
  const ranked = faces.map((face) => ({ face, rank: cssWeightPreference(face.weight, requested) }));
  ranked.sort((left, right) =>
    left.rank[0] - right.rank[0] || left.rank[1] - right.rank[1]);
  const best = ranked[0].rank;
  return ranked.filter(({ rank }) => rank[0] === best[0] && rank[1] === best[1])
    .map(({ face }) => face);
}

function styleMatches(descriptor, italic) {
  const available = String(descriptor ?? "normal").trim().toLowerCase();
  return italic ? available.startsWith("italic") : available === "normal";
}

function cssFamilyToken(family) {
  return `"${String(family).replaceAll("\\", "\\\\").replaceAll("\"", "\\\"")}"`;
}

function canonicalRenderedPlainSource(parent) {
  let result = "";
  const children = Array.from(parent.childNodes ?? []);
  for (let index = 0; index < children.length; index += 1) {
    const node = children[index];
    if (node.nodeType === 3) {
      result += node.textContent ?? "";
      continue;
    }
    if (node.nodeType !== 1 || node.hasAttribute("data-tq-copy-ignore")) continue;
    if (node.hasAttribute("data-tq-src")) {
      const next = children[index + 1];
      const pairedMandatoryBreak = node.hasAttribute("data-tq-hard-break") &&
        next?.tagName === "BR" && next.getAttribute("data-tq-engine-break") === "MandatoryBreak";
      if (!pairedMandatoryBreak) result += node.getAttribute("data-tq-src") ?? "";
      continue;
    }
    if (node.tagName === "BR") {
      if (node.getAttribute("data-tq-engine-break") === "MandatoryBreak") result += "\n";
      continue;
    }
    result += canonicalRenderedPlainSource(node);
  }
  return result;
}

function paragraphSourceArtifact(paragraph) {
  if (
    paragraph.getAttribute("data-tq-rendered") === "true" &&
    (paragraph.getAttribute("data-tq-canonical-source") === "true" ||
      paragraph.getAttribute("data-tq-canonical-plain") === "true")
  ) {
    const text = canonicalRenderedPlainSource(paragraph);
    return { text, serialized: null };
  }
  try {
    const artifact = snapshotSourceArtifactFromDom(paragraph);
    const liveText = typeof paragraph.innerText === "string"
      ? paragraph.innerText.replaceAll("\r\n", "\n").replaceAll("\r", "\n")
      : artifact.text;
    return {
      text: liveText,
      serialized: snapshotSourceArtifactString(liveText, artifact.semantics),
    };
  } catch {
    return null;
  }
}

function plainParagraphSource(paragraph) {
  return paragraphSourceArtifact(paragraph)?.text ?? null;
}

async function sourceArtifactMatches(paragraph, entry) {
  if (typeof entry.sourceArtifactSha256 !== "string") return true;
  const source = paragraphSourceArtifact(paragraph);
  if (source?.serialized == null) return true;
  return await sha256Text(source.serialized) === entry.sourceArtifactSha256;
}

async function sha256Text(value) {
  const bytes = new TextEncoder().encode(value);
  const digest = await globalThis.crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function numericCssPx(value) {
  const normalized = String(value ?? "").trim();
  if (!normalized.endsWith("px")) return Number.NaN;
  return Number.parseFloat(normalized);
}

function contentBoxWidth(element) {
  const style = getComputedStyle(element);
  const padding = [style.paddingLeft, style.paddingRight]
    .reduce((sum, value) => sum + (numericCssPx(value) || 0), 0);
  const border = [style.borderLeftWidth, style.borderRightWidth]
    .reduce((sum, value) => sum + (numericCssPx(value) || 0), 0);
  const resolvedWidth = numericCssPx(style.width);
  if (Number.isFinite(resolvedWidth)) {
    return style.boxSizing === "border-box" ? resolvedWidth - padding - border : resolvedWidth;
  }
  if (Number.isFinite(element.clientWidth) && element.clientWidth > 0) {
    return element.clientWidth - padding;
  }
  return element.getBoundingClientRect().width - padding - border;
}

function canonicalPreparedFlow(paragraph) {
  return paragraph.getAttribute("data-tq-rendered") === "true" &&
    (paragraph.getAttribute("data-tq-canonical-source") === "true" ||
      paragraph.getAttribute("data-tq-canonical-plain") === "true");
}

// TranslationOnlyAncestorTransformCompatibility: an ancestor's visual x/y
// offset does not change the paragraph's advances, line boxes, or content width.
// Every linear, perspective, and z component remains fail-closed.
function translationOnlyAncestorTransformIsSafe(value) {
  const normalized = String(value ?? "none").trim();
  if (!normalized || normalized === "none") return true;
  const match = /^(matrix|matrix3d)\((.*)\)$/u.exec(normalized);
  if (!match) return false;
  const components = match[2].split(",").map((component) => component.trim());
  if (components.some((component) => !component)) return false;
  const values = components.map(Number);
  if (values.some((component) => !Number.isFinite(component))) return false;
  if (match[1] === "matrix") {
    return values.length === 6 &&
      values[0] === 1 && values[1] === 0 &&
      values[2] === 0 && values[3] === 1;
  }
  return values.length === 16 &&
    values[0] === 1 && values[1] === 0 && values[2] === 0 && values[3] === 0 &&
    values[4] === 0 && values[5] === 1 && values[6] === 0 && values[7] === 0 &&
    values[8] === 0 && values[9] === 0 && values[10] === 1 && values[11] === 0 &&
    values[14] === 0 && values[15] === 1;
}

function ancestorFragmentationIsSafe(element) {
  for (let ancestor = element.parentElement; ancestor; ancestor = ancestor.parentElement) {
    const style = getComputedStyle(ancestor);
    if (!new Set(["", "auto"]).has(style.columnCount || "auto")) return false;
    if (!new Set(["", "auto"]).has(style.columnWidth || "auto")) return false;
    if (!new Set(["", "1", "normal"]).has(String(style.zoom || "1"))) return false;
    if (!translationOnlyAncestorTransformIsSafe(style.transform)) return false;
    if ((style.scale || "none") !== "none") return false;
  }
  return true;
}

const SHAPING_STYLE_PROPERTIES = [
  "fontFamily", "fontSize", "fontWeight", "fontStyle", "fontStretch",
  "fontFeatureSettings", "fontVariationSettings", "fontKerning", "fontOpticalSizing", "letterSpacing",
  "fontVariantLigatures", "fontVariantAlternates", "fontVariantEastAsian",
  "fontVariantCaps", "fontVariantNumeric", "fontVariantPosition",
  "fontLanguageOverride", "fontSizeAdjust", "wordSpacing", "lineHeight", "textTransform",
  "direction",
];
const BOUNDARY_STYLE_PROPERTIES = [
  ...SHAPING_STYLE_PROPERTIES.filter((property) => property !== "direction"),
  "textRendering",
  "writingMode",
];
const FEATURE_OVERRIDABLE_BOUNDARY_STYLE_PROPERTIES = new Set([
  "fontFeatureSettings",
  "fontVariantEastAsian",
]);

function openTypeFeatureContract(features) {
  if (features == null || (Array.isArray(features) && features.length === 0)) {
    return Object.freeze({
      signature: "",
      fontFeatureSettings: ENGINE_PUNCTUATION_FEATURE_SETTINGS,
      fontVariantEastAsian: "normal",
      fontVariantNumeric: "normal",
    });
  }
  if (!Array.isArray(features) || features.some((feature) => typeof feature !== "string")) {
    return null;
  }
  if (new Set(features).size !== features.length) return null;
  const fontVariantNumeric = features[0] === "lnum" ? "lining-nums" : "normal";
  const roleFeatures = fontVariantNumeric === "lining-nums" ? features.slice(1) : features;
  const roleSignature = roleFeatures.join(",");
  if (roleSignature !== "" && roleSignature !== PROPORTIONAL_CURLY_QUOTE_FEATURE_SIGNATURE) {
    return null;
  }
  return Object.freeze({
    signature: features.join(","),
    fontFeatureSettings: roleSignature
      ? PROPORTIONAL_CURLY_QUOTE_FEATURE_SETTINGS
      : ENGINE_PUNCTUATION_FEATURE_SETTINGS,
    fontVariantEastAsian: roleSignature ? "proportional-width" : "normal",
    fontVariantNumeric,
  });
}

function boundaryOpenTypeFeatureContract(element) {
  const signature = element.getAttribute("data-tq-open-type-features");
  return signature == null
    ? openTypeFeatureContract([])
    : openTypeFeatureContract(signature.split(","));
}

function parsedOpenTypeFeatureSettings(value) {
  const serialized = String(value ?? "").trim();
  if (!serialized || serialized === "normal") return new Map();
  const result = new Map();
  for (const item of serialized.split(",")) {
    const match = /^\s*["']([A-Za-z0-9]{4})["'](?:\s+(-?\d+))?\s*$/u.exec(item);
    if (!match || result.has(match[1])) return null;
    result.set(match[1], Number(match[2] ?? 1));
  }
  return result;
}

function canonicalEnginePunctuationFeatureSettings(value, proportionalQuote = false) {
  const settings = parsedOpenTypeFeatureSettings(value);
  if (!settings || settings.get("halt") !== 0 || settings.get("chws") !== 0) return false;
  return settings.size === 3 && settings.get("palt") === (proportionalQuote ? 1 : 0);
}

function boundaryOpenTypeFeatureIssue(element, style, contract) {
  if (!contract) return "Boundary:openTypeFeatures";
  if (!contract.signature) return null;
  if (style.fontVariantEastAsian !== contract.fontVariantEastAsian) {
    return "Boundary:fontVariantEastAsian";
  }
  if (!canonicalEnginePunctuationFeatureSettings(style.fontFeatureSettings, true)) {
    return "Boundary:fontFeatureSettings";
  }
  return null;
}

function pseudoGeneratedContentIsEmpty(element) {
  const pseudoHasContent = (pseudo) => {
    const content = String(getComputedStyle(element, pseudo).content ?? "normal").trim();
    return !new Set(["", "none", "normal", "\"\"", "''"]).has(content);
  };
  return !pseudoHasContent("::before") && !pseudoHasContent("::after");
}

function pseudoTypographyIssue(element, style) {
  if (!pseudoGeneratedContentIsEmpty(element)) return "GeneratedContent";
  const firstLetter = getComputedStyle(element, "::first-letter");
  const firstLine = getComputedStyle(element, "::first-line");
  const firstLetterMismatch = SHAPING_STYLE_PROPERTIES.find((property) =>
    String(firstLetter[property] ?? style[property] ?? "") !== String(style[property] ?? ""));
  if (firstLetterMismatch) return `FirstLetter:${firstLetterMismatch}`;
  const firstLineMismatch = SHAPING_STYLE_PROPERTIES.find((property) =>
    String(firstLine[property] ?? style[property] ?? "") !== String(style[property] ?? ""));
  if (firstLineMismatch) return `FirstLine:${firstLineMismatch}`;
  return new Set(["", "none"]).has(firstLetter.cssFloat || "none") ? null : "FirstLetter:float";
}

function generatedGeometryIssue(element, paragraph) {
  const style = getComputedStyle(element);
  let inheritedStyle = getComputedStyle(paragraph);
  for (let ancestor = element.parentElement; ancestor && ancestor !== paragraph; ancestor = ancestor.parentElement) {
    if (ancestor.hasAttribute("data-tq-source-semantic")) {
      inheritedStyle = getComputedStyle(ancestor);
      break;
    }
  }
  if ((style.transform || "none") !== "none") return "Geometry:transform";
  if ((style.scale || "none") !== "none") return "Geometry:scale";
  const shapingBoundary = element.hasAttribute("data-tq-shaping-boundary");
  const measuredGeometry = element.hasAttribute("data-tq-advance");
  const engineHyphen = element.hasAttribute("data-tq-engine-hyphen");
  const projectedRenderFont = element.getAttribute("data-tq-render-font-projection") === "true";
  if (!shapingBoundary && !element.textContent) {
    // PreparedPseudoIsolationCss owns ::before/::after for every generated
    // geometry leaf. The source paragraph is checked before adoption; probing
    // four pseudo styles on every emitted leaf after adoption only re-proves a
    // package invariant and turns an exact snapshot into a main-thread scan.
    return null;
  }
  if (shapingBoundary) {
    const contract = {
      // NativeSelectionBoundaryFlow: prepared shaping runs stay inline so
      // browser selection remains character-continuous across adjacent runs.
      display: "inline",
      whiteSpace: "pre",
      verticalAlign: "baseline",
      direction: "ltr",
      unicodeBidi: "isolate",
    };
    const stableMismatch = Object.entries(contract).find(([property, expected]) =>
      style[property] !== expected);
    if (stableMismatch) return `Boundary:${stableMismatch[0]}`;
    const featureContract = boundaryOpenTypeFeatureContract(element);
    const inheritedProperties = (featureContract?.signature
      ? BOUNDARY_STYLE_PROPERTIES.filter((property) =>
        !FEATURE_OVERRIDABLE_BOUNDARY_STYLE_PROPERTIES.has(property))
      : BOUNDARY_STYLE_PROPERTIES)
      // EngineOwnedBoundaryLetterSpacing: multi-character shaping runs can
      // also carry layout adjustment. Their serialized advance is checked
      // against the real border-box immediately below, so inherited equality
      // would reject correct engine geometry without adding protection.
      .filter((property) => property !== "letterSpacing" &&
        (!projectedRenderFont || property !== "fontFamily"));
    const inheritedMismatch = inheritedProperties.find((property) =>
      String(style[property] ?? "") !== String(inheritedStyle[property] ?? ""));
    if (inheritedMismatch) return `Boundary:${inheritedMismatch}`;
    const featureIssue = boundaryOpenTypeFeatureIssue(element, style, featureContract);
    if (featureIssue) return featureIssue;
  } else if (measuredGeometry) {
    // PreparedHyphenInlineBlockGeometry: an engine-owned hyphen is an isolated
    // inline block because its reserved advance and leading gap are replayed as
    // one visual-only unit. Ordinary measured punctuation remains inline.
    const expectedDisplay = engineHyphen ? "inline-block" : "inline";
    if (style.display !== expectedDisplay) return "Geometry:display";
    if (engineHyphen) {
      const contract = {
        whiteSpace: "pre",
        verticalAlign: "baseline",
        direction: "ltr",
        unicodeBidi: "isolate",
      };
      const stableMismatch = Object.entries(contract).find(([property, expected]) =>
        style[property] !== expected);
      if (stableMismatch) return `Geometry:${stableMismatch[0]}`;
    }
    const inheritedMismatch = BOUNDARY_STYLE_PROPERTIES
      .filter((property) => property !== "letterSpacing" &&
        (!projectedRenderFont || property !== "fontFamily"))
      .find((property) => String(style[property] ?? "") !== String(inheritedStyle[property] ?? ""));
    if (inheritedMismatch) return `Geometry:${inheritedMismatch}`;
  }
  return null;
}

function renderedBoundaryAdvanceIssue(paragraph) {
  const boundaries = Array.from(paragraph.querySelectorAll("[data-tq-shaping-boundary]"));
  if (boundaries.some((boundary) => !boundary.hasAttribute("data-tq-advance"))) return 0;
  const contributors = Array.from(paragraph.querySelectorAll("[data-tq-advance]"));
  for (let index = 0; index < contributors.length; index += 1) {
    const contributor = contributors[index];
    const serializedExpected = contributor.getAttribute("data-tq-advance");
    if (serializedExpected == null) return index;
    const expected = Number(serializedExpected);
    const actual = contributor.getBoundingClientRect().width;
    const tolerance = Math.max(
      SEGMENT_ADVANCE_ABSOLUTE_TOLERANCE_PX,
      Math.abs(expected) * SEGMENT_ADVANCE_RELATIVE_TOLERANCE,
    );
    if (!Number.isFinite(expected) || !Number.isFinite(actual) || Math.abs(actual - expected) > tolerance) {
      const text = String(contributor.textContent ?? "").slice(0, 8);
      const style = getComputedStyle(contributor);
      const features = contributor.getAttribute("data-tq-open-type-features") ?? "none";
      const source = contributor.getAttribute("data-tq-src") ?? "same";
      return `${index};expected=${expected};actual=${actual};text=${JSON.stringify(text)};letterSpacing=${style.letterSpacing};features=${features};source=${source}`;
    }
  }
  return null;
}

function renderedLineAdvanceIssue(paragraph, contentWidth) {
  const children = [];
  const appendFlowNodes = (parent) => {
    for (const node of Array.from(parent.childNodes ?? [])) {
      if (node.nodeType === 1 && node.hasAttribute("data-tq-source-semantic")) {
        appendFlowNodes(node);
      } else {
        children.push(node);
      }
    }
  };
  appendFlowNodes(paragraph);
  const markers = Array.from(paragraph.querySelectorAll("[data-tq-line-flow-width]"));
  const sentinels = Array.from(paragraph.querySelectorAll("[data-tq-line-end-sentinel]"));
  if (markers.length === 0 || markers.length !== sentinels.length) return "markers";
  for (let lineIndex = 0; lineIndex < markers.length; lineIndex += 1) {
    const issue = (detail) => `${lineIndex};${detail}`;
    const marker = markers[lineIndex];
    const sentinel = sentinels[lineIndex];
    const markerIndex = children.indexOf(marker);
    const sentinelIndex = children.indexOf(sentinel);
    const expectedFlow = Number(marker.getAttribute("data-tq-line-flow-width"));
    const expectedCore = Number(marker.getAttribute("data-tq-line-width"));
    if (
      markerIndex < 0 || sentinelIndex <= markerIndex ||
      !Number.isFinite(expectedFlow) || !Number.isFinite(expectedCore) ||
      Math.abs(expectedFlow - expectedCore) > RENDER_FLOW_EPSILON_PX
    ) return issue("structure");
    const markerStyle = getComputedStyle(marker);
    const markerRect = marker.getBoundingClientRect();
    const markerMarginLeft = numericCssPx(markerStyle.marginLeft) || 0;
    const origin = markerRect.left - markerMarginLeft;
    const contributorTops = new Map();
    let contributorIndex = 0;
    for (let index = markerIndex + 1; index < sentinelIndex; index += 1) {
      const node = children[index];
      if (node.nodeType !== 1) {
        // `NecessaryGeometrySpanOnly`: ordinary prose stays in native Text
        // nodes. The sentinel still cross-checks the complete line advance;
        // only nodes carrying an independent geometry contract need their own
        // position/advance validation below.
        continue;
      }
      if (node.tagName === "BR" || node.hasAttribute("data-tq-line-flow-width")) return issue("unexpected-line-boundary");
      const style = getComputedStyle(node);
      if (style.display === "none") continue;
      const currentContributorIndex = contributorIndex++;
      if (!node.hasAttribute("data-tq-shaping-boundary") && !node.hasAttribute("data-tq-geometry")) {
        return issue("uncontracted-element");
      }
      const rects = node.getClientRects?.();
      if (rects && rects.length !== 1) return issue(`fragment-count=${rects.length}`);
      const rect = node.getBoundingClientRect();
      if (![rect.left, rect.top, rect.right, rect.width].every(Number.isFinite)) return issue("non-finite-geometry");
      const serializedX = node.getAttribute("data-tq-x");
      if (serializedX != null) {
        const expectedX = Number(serializedX);
        if (!Number.isFinite(expectedX) || Math.abs(rect.left - origin - expectedX) > INLINE_POSITION_TOLERANCE_PX) {
          return issue(`position;expected=${expectedX};actual=${rect.left - origin}`);
        }
      }
      // InlineTextFragmentVerticalConsistency: only inline fragment boxes have
      // comparable client-rect tops. Shaping boundaries and engine hyphens are
      // zero-strut inline blocks aligned by baseline, so their border-box top
      // naturally differs from glyph-bearing inline spans. Their stable CSS,
      // serialized x/advance, and the line baseline are checked independently.
      if (style.display === "inline") {
        // InlineVerticalStyleGroupConsistency: smaller inline-code faces,
        // superscripts, and other modeled baseline shifts legitimately have a
        // different fragment top. Compare only fragments that share the same
        // shaping and vertical-placement style; the serialized line marker,
        // baseline sentinel, and paragraph height still validate the common
        // line geometry below.
        const verticalSignature = stableStringify(Object.fromEntries([
          "fontFamily", "fontSize", "fontWeight", "fontStyle", "lineHeight",
          "verticalAlign", "fontVariantPosition",
        ].map((property) => [property, String(style[property] ?? "")])));
        const contributorTop = contributorTops.get(verticalSignature);
        if (contributorTop == null) contributorTops.set(verticalSignature, rect.top);
        else if (Math.abs(rect.top - contributorTop) > LINE_VERTICAL_TOLERANCE_PX) {
          const text = JSON.stringify(String(node.textContent ?? "").slice(0, 8));
          return issue(`contributor-top;index=${currentContributorIndex};text=${text};expected=${contributorTop};actual=${rect.top};display=${style.display};verticalAlign=${style.verticalAlign};lineHeight=${style.lineHeight}`);
        }
      }
    }
    const sentinelRect = sentinel.getBoundingClientRect();
    const actual = sentinelRect.left - origin;
    if (
      !Number.isFinite(actual) || Math.abs(actual - expectedFlow) > LINE_ADVANCE_TOLERANCE_PX ||
      Math.abs(actual - expectedCore) > LINE_ADVANCE_TOLERANCE_PX ||
      // PreparedCoreProtrusionAllowance: punctuation compression and the
      // line-length grid may intentionally place the serialized line pen just
      // beyond the raw content box. Reject only browser flow beyond both the
      // live box and the engine-owned core pen; exact agreement with the core
      // is not an overflow regression.
      actual - Math.max(contentWidth, expectedCore) > WIDTH_TOLERANCE_PX
    ) return issue(`sentinel;expectedFlow=${expectedFlow};expectedCore=${expectedCore};actual=${actual};contentWidth=${contentWidth}`);
  }
  return null;
}

function renderedLineVerticalIssue(paragraph) {
  const markers = Array.from(paragraph.querySelectorAll("[data-tq-line-flow-width]"));
  const sentinels = Array.from(paragraph.querySelectorAll("[data-tq-line-end-sentinel]"));
  if (markers.length === 0 || markers.length !== sentinels.length) return "markers";
  const paragraphRect = paragraph.getBoundingClientRect();
  const paragraphStyle = getComputedStyle(paragraph);
  const topInset = [paragraphStyle.borderTopWidth, paragraphStyle.paddingTop]
    .reduce((sum, value) => sum + (numericCssPx(value) || 0), 0);
  const bottomInset = [paragraphStyle.paddingBottom, paragraphStyle.borderBottomWidth]
    .reduce((sum, value) => sum + (numericCssPx(value) || 0), 0);
  const contentTop = paragraphRect.top + topInset;
  const contentHeight = paragraphRect.height - topInset - bottomInset;
  let expectedParagraphHeight = null;
  for (let lineIndex = 0; lineIndex < markers.length; lineIndex += 1) {
    const marker = markers[lineIndex];
    const sentinel = sentinels[lineIndex];
    const top = Number(marker.getAttribute("data-tq-line-top"));
    const bottom = Number(marker.getAttribute("data-tq-line-bottom"));
    const baseline = Number(marker.getAttribute("data-tq-line-baseline"));
    const paragraphHeight = Number(marker.getAttribute("data-tq-paragraph-height"));
    const markerRect = marker.getBoundingClientRect();
    const sentinelRect = sentinel.getBoundingClientRect();
    if (
      ![top, bottom, baseline, paragraphHeight, markerRect.top, markerRect.bottom,
        markerRect.height, sentinelRect.top].every(Number.isFinite) ||
      bottom < top || baseline < top || baseline > bottom
    ) return String(lineIndex);
    if (expectedParagraphHeight == null) expectedParagraphHeight = paragraphHeight;
    if (
      Math.abs(paragraphHeight - expectedParagraphHeight) > PREPARED_VERTICAL_TOLERANCE_PX ||
      Math.abs(markerRect.top - (contentTop + top)) > PREPARED_VERTICAL_TOLERANCE_PX ||
      Math.abs(markerRect.bottom - (contentTop + bottom)) > PREPARED_VERTICAL_TOLERANCE_PX ||
      Math.abs(markerRect.height - (bottom - top)) > PREPARED_VERTICAL_TOLERANCE_PX ||
      Math.abs(sentinelRect.top - (contentTop + baseline)) > PREPARED_VERTICAL_TOLERANCE_PX
    ) return String(lineIndex);
  }
  if (
    expectedParagraphHeight == null ||
    Math.abs(contentHeight - expectedParagraphHeight) > PREPARED_VERTICAL_TOLERANCE_PX
  ) return "paragraph";
  return null;
}

function renderedFlowContractMatches(style) {
  return (style.whiteSpaceCollapse || "preserve") === "preserve" &&
    (style.textWrapMode || "nowrap") === "nowrap" &&
    (style.overflowWrap || "normal") === "normal" &&
    (style.wordBreak || "normal") === "normal" &&
    (style.hyphens || "manual") === "manual" &&
    (style.textAutospace || "no-autospace") === "no-autospace";
}

/**
 * Replays the same post-render geometry gate for an adopted SSR artifact and
 * for the canonical DOM freshly emitted by the browser runtime.
 */
export function renderedPreparedParagraphIssue(
  paragraph,
  expectedContentWidth = contentBoxWidth(paragraph),
) {
  if (!Number.isFinite(expectedContentWidth) || expectedContentWidth <= 0) {
    return "RenderedPreparedParagraphWidthInvalid";
  }
  const paragraphStyle = getComputedStyle(paragraph);
  if (!renderedFlowContractMatches(paragraphStyle)) {
    return "RenderedPreparedParagraphFlowContractMismatch";
  }
  const geometry = Array.from(paragraph.querySelectorAll("[data-tq-geometry]"));
  const boundaries = Array.from(paragraph.querySelectorAll("[data-tq-shaping-boundary]"));
  for (const target of new Set([...geometry, ...boundaries])) {
    const issue = generatedGeometryIssue(target, paragraph);
    if (issue) return `RenderedPreparedParagraphGeometryMismatch:${issue}`;
  }
  const boundaryAdvanceIssue = renderedBoundaryAdvanceIssue(paragraph);
  if (boundaryAdvanceIssue != null) {
    return `RenderedPreparedParagraphSegmentAdvanceMismatch:${boundaryAdvanceIssue}`;
  }
  const lineAdvanceIssue = renderedLineAdvanceIssue(paragraph, expectedContentWidth);
  if (lineAdvanceIssue != null) {
    return `RenderedPreparedParagraphLineAdvanceMismatch:${lineAdvanceIssue}`;
  }
  const lineVerticalIssue = renderedLineVerticalIssue(paragraph);
  if (lineVerticalIssue != null) {
    return `RenderedPreparedParagraphLineVerticalMismatch:${lineVerticalIssue}`;
  }
  return null;
}

globalThis.__TiqianPreparedDomValidator = Object.freeze({
  revision: RENDER_REVISION,
  issue(paragraph, expectedContentWidth) {
    const issue = renderedPreparedParagraphIssue(paragraph, expectedContentWidth);
    if (issue) {
      const key = paragraph.getAttribute("data-tq-snapshot-key") ?? "unkeyed";
      paragraph.closest(ROOT_SELECTOR)?.setAttribute(EXACT_LAYOUT_ISSUE_ATTRIBUTE, `${key}:${issue}`);
    }
    return issue;
  },
});

function computedTypographyIssue(
  paragraph,
  contract,
  canonicalPreparedFlow = false,
  renderFontFamilies = null,
  { allowLiveFontSizeAndLineHeight = false } = {},
) {
  const style = getComputedStyle(paragraph);
  const actualFamilies = parseFontFamilies(style.fontFamily).map((family) => family.toLowerCase());
  const expectedFamilies = contract.fontFamilies.map((family) => family.toLowerCase());
  if (actualFamilies.length !== expectedFamilies.length ||
      actualFamilies.some((family, index) => family !== expectedFamilies[index])) {
    const root = paragraph.closest(ROOT_SELECTOR);
    const projection = root?.getAttribute(EXACT_RENDER_FONT_ATTRIBUTE) ?? "missing";
    const fallback = root?.hasAttribute("data-tiqian-exact-layout-fallback") ?? false;
    const rendered = paragraph.getAttribute("data-tq-rendered") ?? "missing";
    return `fontFamily:${actualFamilies.join("|")}!=${expectedFamilies.join("|")};projection=${projection};fallback=${fallback};rendered=${rendered}`;
  }
  if (!allowLiveFontSizeAndLineHeight &&
      Math.abs(numericCssPx(style.fontSize) - contract.fontSizePx) > 0.01) return "fontSize";
  const expectedLineHeight = canonicalPreparedFlow ? 0 : contract.lineHeightPx;
  if (!allowLiveFontSizeAndLineHeight &&
      Math.abs(numericCssPx(style.lineHeight) - expectedLineHeight) > 0.01) return "lineHeight";
  if (numericWeight(style.fontWeight) !== contract.fontWeight) return "fontWeight";
  const actualFontStyle = style.fontStyle.toLowerCase();
  if (contract.italic ? !actualFontStyle.startsWith("italic") : actualFontStyle !== "normal") {
    return "fontStyle";
  }
  const letterSpacing = style.letterSpacing === "normal" ? 0 : numericCssPx(style.letterSpacing);
  if (!Number.isFinite(letterSpacing) || Math.abs(letterSpacing - contract.letterSpacingPx) > 0.01) {
    return "letterSpacing";
  }
  if (canonicalPreparedFlow) {
    if (!canonicalEnginePunctuationFeatureSettings(style.fontFeatureSettings)) {
      return "fontFeatureSettings";
    }
  } else if ((style.fontFeatureSettings || "normal") !== contract.fontFeatureSettings) {
    return "fontFeatureSettings";
  }
  if ((style.fontVariationSettings || "normal") !== contract.fontVariationSettings) return "fontVariationSettings";
  if (!new Set(["normal", "100%"]).has(style.fontStretch || "normal")) return "fontStretch";
  if (canonicalPreparedFlow
    ? (style.fontKerning || "auto") !== "normal"
    : !new Set(["auto", "normal"]).has(style.fontKerning || "auto")) return "fontKerning";
  // Exact-font sessions reject unsupported `opsz` axes, so `auto` and `none`
  // are equivalent for every snapshot face accepted by this backend.
  if (canonicalPreparedFlow
    ? (style.fontOpticalSizing || "auto") !== "none"
    : !new Set(["auto", "none"]).has(style.fontOpticalSizing || "auto")) return "fontOpticalSizing";
  if ((style.fontVariantLigatures || "normal") !== "normal") return "fontVariantLigatures";
  if ((style.fontVariantAlternates || "normal") !== "normal") return "fontVariantAlternates";
  if ((style.fontVariantEastAsian || "normal") !== "normal") return "fontVariantEastAsian";
  if ((style.fontVariantCaps || "normal") !== "normal") return "fontVariantCaps";
  if ((style.fontVariantNumeric || "normal") !== (contract.fontVariantNumeric || "normal")) {
    return "fontVariantNumeric";
  }
  if ((style.fontVariantPosition || "normal") !== "normal") return "fontVariantPosition";
  if ((style.fontLanguageOverride || "normal") !== "normal") return "fontLanguageOverride";
  if ((style.fontSizeAdjust || "none") !== "none") return "fontSizeAdjust";
  const wordSpacing = style.wordSpacing === "normal" || !style.wordSpacing
    ? 0
    : numericCssPx(style.wordSpacing);
  if (!Number.isFinite(wordSpacing) || Math.abs(wordSpacing) > 0.01) return "wordSpacing";
  const textIndent = !style.textIndent ? 0 : numericCssPx(style.textIndent);
  if (!Number.isFinite(textIndent) || Math.abs(textIndent) > 0.01) return "textIndent";
  for (const value of [style.paddingLeft, style.paddingRight, style.borderLeftWidth, style.borderRightWidth]) {
    if (value && Math.abs(numericCssPx(value)) > 0.01) return "horizontalPaddingOrBorder";
  }
  // NativeListMarkerOuterDisplay: prepared geometry replaces only the list
  // item's children. The host <li> must retain its list-item outer display so
  // the browser keeps owning marker painting, while ordinary paragraphs remain
  // strict block containers.
  const expectedDisplay = paragraph.tagName === "LI" ? "list-item" : "block";
  if ((style.display || "block") !== expectedDisplay) return "display";
  if ((style.transform || "none") !== "none") return "transform";
  if ((style.scale || "none") !== "none") return "scale";
  if (!new Set(["", "auto"]).has(style.columnCount || "auto")) return "columnCount";
  if (!new Set(["", "auto"]).has(style.columnWidth || "auto")) return "columnWidth";
  if (!new Set(["", "1", "normal"]).has(String(style.zoom || "1"))) return "zoom";
  if ((style.textTransform || "none") !== "none") return "textTransform";
  if ((style.textRendering || "auto") !== "auto") return "textRendering";
  if (!new Set(["start", "left"]).has(style.textAlign || "start")) return "textAlign";
  if (!new Set(["auto", "start"]).has(style.textAlignLast || "auto")) return "textAlignLast";
  if ((style.textJustify || "auto") !== "auto") return "textJustify";
  if ((style.direction || "ltr") !== "ltr") return "direction";
  if ((style.writingMode || "horizontal-tb") !== "horizontal-tb") return "writingMode";
  if (!ancestorFragmentationIsSafe(paragraph)) return "ancestorFragmentation";
  // PreparedPseudoIsolationCss resets paragraph and shaping-boundary pseudos.
  // Native source still takes the strict pseudo gate above, before any DOM
  // mutation; canonical prepared DOM is instead verified by its real segment,
  // line pen, baseline and paragraph-height geometry below.
  if (canonicalPreparedFlow) return null;
  const pseudoIssue = pseudoTypographyIssue(paragraph, style);
  return pseudoIssue == null ? null : `pseudo:${pseudoIssue}`;
}

function computedTypographyMatches(
  paragraph,
  contract,
  canonicalPreparedFlow = false,
  renderFontFamilies = null,
) {
  return computedTypographyIssue(
    paragraph,
    contract,
    canonicalPreparedFlow,
    renderFontFamilies,
  ) == null;
}

function canonicalUnicodeRanges(ranges) {
  if (ranges == null) return null;
  return ranges.map(([start, end]) => [start, end]).sort((left, right) =>
    left[0] - right[0] || left[1] - right[1]);
}

function unicodeRangesMatch(left, right) {
  return JSON.stringify(canonicalUnicodeRanges(left)) === JSON.stringify(canonicalUnicodeRanges(right));
}

function cssFaceContract(evidence, faces, documentObject, requireExactFirstPaintDisplay = true) {
  const expectedUrl = new URL(evidence.publicUrl, documentObject.baseURI).href;
  const coverageText = evidence.coverageText || evidence.probe.text;
  const coveragePoints = Array.from(
    new Set(Array.from(coverageText, (point) => point.codePointAt(0))),
  ).sort((left, right) => left - right);
  const expectedRanges = parseUnicodeRange(evidence.unicodeRange);
  const familyCandidates = faces.filter((face) =>
    face.family.toLowerCase() === evidence.family.toLowerCase() &&
    styleMatches(face.style, evidence.probe.italic) &&
    unicodeRangesIntersectCoverage(face.unicodeRanges, coveragePoints));
  const weightedCandidates = cssWeightMatchedFaces(familyCandidates, evidence.probe.fontWeight);
  // CSS Fonts composite faces resolve an overlapping code point to the later
  // rule with otherwise equal descriptors. Validate the effective face instead
  // of requiring every shadowed shard to have the selected shard's range/URL.
  const candidates = Array.from(new Set(coveragePoints.map((codePoint) =>
    weightedCandidates.findLast((face) =>
      unicodeRangesContainCodePoint(face.unicodeRanges, codePoint))))).filter(Boolean);
  const defaultDescriptor = (value, defaults) => defaults.has(String(value ?? "").trim().toLowerCase());
  const exactFirstPaintDisplay = (value) => new Set(["", "auto", "block"])
    .has(String(value ?? "").trim().toLowerCase());
  const matches = candidates.length > 0 && coveragePoints.every((codePoint) =>
    candidates.some((face) => unicodeRangesContainCodePoint(face.unicodeRanges, codePoint))) &&
    candidates.every((face) =>
    weightRangeMatches(face.weight, evidence.weight) &&
    unicodeRangesMatch(face.unicodeRanges, expectedRanges) &&
    compatibleLocalSources(face, evidence) && face.urls.length === 1 && face.urls[0] === expectedUrl &&
    defaultDescriptor(face.stretch, new Set(["", "normal", "100%"])) &&
    defaultDescriptor(face.sizeAdjust, new Set(["", "100%"])) &&
    defaultDescriptor(face.ascentOverride, new Set(["", "normal"])) &&
    defaultDescriptor(face.descentOverride, new Set(["", "normal"])) &&
    defaultDescriptor(face.lineGapOverride, new Set(["", "normal"])) &&
    defaultDescriptor(face.featureSettings, new Set(["", "normal"])) &&
    defaultDescriptor(face.variationSettings, new Set(["", "normal"])) &&
    defaultDescriptor(face.languageOverride, new Set(["", "normal"])) &&
    defaultDescriptor(face.namedInstance, new Set(["", "auto"])) &&
    (!requireExactFirstPaintDisplay || exactFirstPaintDisplay(face.display)));
  return {
    matches,
    compatibleLocalDeclared: matches && candidates.some((face) => face.hasLocalSource),
  };
}

function createFontEvidenceProbe(evidence, documentObject, featureContract) {
  const probe = documentObject.createElement("span");
  probe.textContent = evidence.probe.text;
  probe.setAttribute("aria-hidden", "true");
  probe.style.cssText = [
    "all:initial!important",
    "position:absolute!important",
    "visibility:hidden!important",
    "pointer-events:none!important",
    "white-space:pre!important",
    `font-family:${cssFamilyToken(evidence.family)}!important`,
    `font-size:${evidence.probe.fontSizePx}px!important`,
    `font-weight:${evidence.probe.fontWeight}!important`,
    `font-style:${evidence.probe.italic ? "italic" : "normal"}!important`,
    `font-variant-east-asian:${featureContract.fontVariantEastAsian}!important`,
    `font-variant-numeric:${featureContract.fontVariantNumeric}!important`,
    `font-feature-settings:${featureContract.fontFeatureSettings}!important`,
    "font-variation-settings:normal!important",
    "font-kerning:normal!important",
    "font-optical-sizing:none!important",
    "letter-spacing:normal!important",
  ].join(";");
  probe.lang = evidence.probe.language;
  return probe;
}

async function observeFontEvidenceProbeWidths(probes, documentObject) {
  const ResizeObserverConstructor = documentObject.defaultView?.ResizeObserver ??
    globalThis.ResizeObserver;
  if (typeof ResizeObserverConstructor !== "function") {
    return probes.map((probe) => probe.getBoundingClientRect().width);
  }
  return new Promise((resolve) => {
    const widths = new Map();
    let settled = false;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      observer.disconnect();
      resolve(value);
    };
    const observer = new ResizeObserverConstructor((entries) => {
      for (const entry of entries) {
        const borderBox = Array.isArray(entry.borderBoxSize)
          ? entry.borderBoxSize[0]
          : entry.borderBoxSize;
        const width = borderBox?.inlineSize ?? entry.contentRect?.width;
        if (Number.isFinite(width)) widths.set(entry.target, width);
      }
      if (widths.size === probes.length) {
        finish(probes.map((probe) => widths.get(probe)));
      }
    });
    const timeout = setTimeout(() => finish(null), 5_000);
    for (const probe of probes) observer.observe(probe, { box: "border-box" });
  });
}

/**
 * BatchedFontEvidenceValidation keeps the exact compatible-local contract but
 * avoids one style/layout flush for every shaping run in an article. A compact
 * font contract can carry hundreds of distinct probes; under Edge JITless,
 * appending, measuring, and removing them one at a time can monopolize the
 * main thread for tens of seconds. Load each face/descriptor coverage once,
 * append every hidden probe before the first geometry read, and then validate
 * all original advances against the same single layout snapshot.
 */
async function validateFontEvidenceGroups(
  evidenceGroups,
  documentObject,
  isCurrent = () => true,
  yieldIfNeeded = yieldValidationIfNeeded,
) {
  const validations = [];
  const loadRequests = new Map();
  let groupIndex = 0;
  let sliceStartedAt = performance.now();
  for (const group of evidenceGroups.values()) {
    for (const evidence of group.probes.values()) {
      // FaceGroupContractOwnership: family/style/weight range/unicode range,
      // URL and compatible-local identity are invariant across every probe in
      // this group and were already validated against aggregate coverage by
      // validateManifestFontContract(). Repeating that CSSOM proof for each
      // shaping run is quadratic article work and adds no evidence.
      const featureContract = openTypeFeatureContract(evidence.probe.features);
      if (!featureContract) return "FontProbeFeaturesUnsupported";
      const descriptor = `${evidence.probe.italic ? "italic" : "normal"} ` +
        `${evidence.probe.fontWeight} ${evidence.probe.fontSizePx}px ` +
        cssFamilyToken(evidence.family);
      const loadKey = `${groupIndex}\u0000${descriptor}`;
      let request = loadRequests.get(loadKey);
      if (!request) {
        request = { descriptor, coverage: new Set() };
        loadRequests.set(loadKey, request);
      }
      for (const point of evidence.probe.text) request.coverage.add(point);
      validations.push({ evidence, featureContract });
    }
    groupIndex += 1;
    sliceStartedAt = await yieldIfNeeded(sliceStartedAt);
    if (!isCurrent()) return "superseded";
  }

  const loaded = await Promise.all(Array.from(loadRequests.values(), async (request) =>
    documentObject.fonts?.load?.(
      request.descriptor,
      Array.from(request.coverage).join(""),
    )));
  if (loaded.some((faces) => !faces || faces.length === 0)) return "FontFaceLoadFailed";
  if (!isCurrent()) return "superseded";

  const probes = [];
  for (const { evidence, featureContract } of validations) {
    probes.push(createFontEvidenceProbe(evidence, documentObject, featureContract));
    sliceStartedAt = await yieldIfNeeded(sliceStartedAt);
    if (!isCurrent()) return "superseded";
  }
  try {
    for (const probe of probes) {
      documentObject.body.append(probe);
      sliceStartedAt = await yieldIfNeeded(sliceStartedAt);
      if (!isCurrent()) return "superseded";
    }
    // AsyncProbeGeometryBatch: ResizeObserver lets the rendering pipeline
    // compute every box in one lifecycle update and returns all widths in one
    // callback. Hundreds of synchronous geometry reads remain a single giant
    // task under Edge JITless even when the DOM was appended in one batch.
    const widths = await observeFontEvidenceProbeWidths(probes, documentObject);
    if (!widths) return "FontProbeObservationTimeout";
    if (!isCurrent()) return "superseded";
    for (let index = 0; index < validations.length; index += 1) {
      const { evidence } = validations[index];
      // AbsoluteProbeBoxAdvance: the probe is a shrink-to-fit, unpadded,
      // single-line `white-space: pre` box, so its observed border-box width is
      // the complete text advance and preserves trailing whitespace.
      const actual = widths[index];
      const expected = evidence.probe.advancePx;
      const tolerance = Math.max(
        PROBE_ABSOLUTE_TOLERANCE_PX,
        expected * PROBE_RELATIVE_TOLERANCE,
      );
      if (!Number.isFinite(actual) || Math.abs(actual - expected) > tolerance) {
        return "FontAdvanceProbeMismatch";
      }
      sliceStartedAt = await yieldIfNeeded(sliceStartedAt);
      if (!isCurrent()) return "superseded";
    }
    return null;
  } finally {
    for (const probe of probes) probe.remove();
  }
}

function templateManifest(template) {
  const script = template.content?.querySelector?.("[data-tq-snapshot-manifest]");
  if (!script?.textContent) throw new Error("MissingSnapshotManifest");
  return parseSnapshotManifest(script.textContent);
}

async function manifestValueStylesAreValid(manifest) {
  return Array.isArray(manifest?.valueStyles) &&
    typeof manifest.valueStylesSha256 === "string" &&
    await sha256Text(stableStringify(manifest.valueStyles)) === manifest.valueStylesSha256;
}

function manifestEntryKeysAreUnique(manifest) {
  if (!Array.isArray(manifest?.entries)) return false;
  const keys = [...manifest.entries, ...(manifest.fontContractEntries ?? [])]
    .map((entry) => entry?.key);
  return keys.every((key) => typeof key === "string" && key.length > 0) &&
    new Set(keys).size === keys.length;
}

function manifestRenderFontFamiliesAreValid(manifest) {
  return Array.isArray(manifest?.renderFontFamilies) && manifest.renderFontFamilies.length > 0 &&
    manifest.renderFontFamilies.every((family) =>
      typeof family === "string" && family.trim().length > 0);
}

function fontContractOnlyManifest(manifest) {
  return manifest?.entrySource === "font-contract-v1";
}

function liveRenderFontFamilies(root, manifest, paragraph) {
  return null;
}

function templateEntry(template, key, root = null) {
  for (const entry of template.content?.querySelectorAll?.("[data-tq-entry]") ?? []) {
    if (entry.getAttribute("data-tq-entry") === key) return entry;
  }
  return directServerArtifacts.get(root)?.get(key) ?? null;
}

async function captureServerRenderedSnapshotArtifacts(
  root,
  manifest,
  paragraphsByKey,
  isCurrent = () => true,
) {
  const artifacts = new Map();
  let sliceStartedAt = performance.now();
  for (const entry of manifest.entries) {
    const paragraph = paragraphsByKey.get(entry?.key);
    if (paragraph) artifacts.set(entry.key, paragraph.cloneNode(true));
    sliceStartedAt = await yieldDirectSsrValidationIfNeeded(sliceStartedAt);
    if (!isCurrent()) return false;
  }
  if (artifacts.size > 0) directServerArtifacts.set(root, artifacts);
  return true;
}

function templateSourceEntry(documentObject, reference, key) {
  const sourceTemplate = documentObject.getElementById(`${reference}-source`);
  if (!sourceTemplate?.content) return null;
  for (const entry of sourceTemplate.content.querySelectorAll?.("[data-tq-source-entry]") ?? []) {
    if (entry.getAttribute("data-tq-source-entry") === key) return entry;
  }
  return null;
}

/**
 * DirectSsrSourceRestore: a failed first-paint adoption must never feed the
 * prepared replay DOM into the runtime lowerer as if it were host rich text.
 * The server source template is the canonical semantic backing for every
 * direct entry. Once restored, clear the marker so a later maximum-measure
 * adoption reads the immutable prepared artifact from the normal template.
 */
function restoreServerRenderedSnapshotSource(root) {
  const reference = root?.getAttribute?.("snapshot-ref");
  if (!reference || root.getAttribute(SERVER_RENDERED_SNAPSHOT_ATTRIBUTE) !== reference) {
    return false;
  }
  const documentObject = root.ownerDocument || document;
  const sourceTemplate = documentObject.getElementById(`${reference}-source`);
  if (!sourceTemplate?.content) return false;
  const sourceEntries = Array.from(
    sourceTemplate.content.querySelectorAll?.("[data-tq-source-entry]") ?? [],
  );
  if (sourceEntries.length === 0) return false;
  const paragraphs = new Map(
    Array.from(root.querySelectorAll("[data-tq-snapshot-key]"))
      .filter((paragraph) => paragraph.closest(ROOT_SELECTOR) === root)
      .map((paragraph) => [paragraph.getAttribute("data-tq-snapshot-key"), paragraph]),
  );
  const restoreEntries = sourceEntries.map((source) => ({
    source,
    paragraph: paragraphs.get(source.getAttribute("data-tq-source-entry")),
  }));
  if (restoreEntries.some(({ paragraph }) => !paragraph)) return false;
  for (const { source, paragraph } of restoreEntries) {
    while (paragraph.firstChild) paragraph.removeChild(paragraph.firstChild);
    for (const child of Array.from(source.childNodes)) {
      paragraph.appendChild(child.cloneNode(true));
    }
    paragraph.removeAttribute("data-tq-rendered");
    paragraph.removeAttribute("data-tq-canonical-plain");
    paragraph.removeAttribute("data-tq-canonical-source");
  }
  root.removeAttribute(SERVER_RENDERED_SNAPSHOT_ATTRIBUTE);
  root.removeAttribute(EXACT_RENDER_FONT_ATTRIBUTE);
  return true;
}

function canonicalSnapshotNode(node) {
  if (node.nodeType === 3) return ["#", String(node.textContent ?? "")];
  if (node.nodeType !== 1) throw new Error("UnsupportedSnapshotArtifactNode");
  const attributes = Array.from(node.attributes ?? [], (attribute) => (
    Array.isArray(attribute)
      ? [String(attribute[0]), String(attribute[1])]
      : [String(attribute.name), String(attribute.value)]
  ))
    .sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0);
  return [
    String(node.tagName).toLowerCase(),
    attributes,
    Array.from(node.childNodes ?? [], canonicalSnapshotNode),
  ];
}

async function snapshotArtifactMatches(snapshot, expectedSha256) {
  if (typeof expectedSha256 !== "string") return false;
  try {
    const artifact = Array.from(snapshot.childNodes ?? [], canonicalSnapshotNode);
    return await sha256Text(stableStringify(artifact)) === expectedSha256;
  } catch {
    return false;
  }
}

function rootParagraphs(root, selector) {
  return Array.from(root.querySelectorAll(selector)).filter((paragraph) =>
    paragraph.closest(ROOT_SELECTOR) === root);
}

function miss(root, reason) {
  restoreServerRenderedSnapshotSource(root);
  root.dataset.tiqianSnapshotMiss = reason;
  delete root.dataset.tiqianSnapshot;
  return { adopted: false, reason };
}

function groupedFontEvidence(manifest) {
  const evidenceGroups = new Map();
  for (const entry of [...manifest.entries, ...(manifest.fontContractEntries ?? [])]) {
    if (!addFontEvidenceEntry(evidenceGroups, entry)) return null;
  }
  return evidenceGroups;
}

function addFontEvidenceEntry(evidenceGroups, entry) {
  if (!entry?.fontEvidence || !Array.isArray(entry.fontEvidence.faces) ||
      entry.fontEvidence.faces.length === 0) return false;
  for (const evidence of entry.fontEvidence.faces) {
    const key = [
      evidence.sfntSha256,
      evidence.faceIndex,
      evidence.sourceOrder,
      JSON.stringify(evidence.axes),
      JSON.stringify(evidence.localNames),
      evidence.family,
      evidence.style,
      JSON.stringify(evidence.weight),
      evidence.unicodeRange,
      evidence.publicUrl,
    ].join(":");
    let group = evidenceGroups.get(key);
    if (!group) {
      group = { representative: evidence, coverage: new Set(), probes: new Map() };
      evidenceGroups.set(key, group);
    }
    for (const point of evidence.coverageText || evidence.probe.text) group.coverage.add(point);
    const probeKey = JSON.stringify(evidence.probe);
    if (!group.probes.has(probeKey)) group.probes.set(probeKey, evidence);
  }
  return true;
}

async function groupedFontEvidenceCooperatively(
  manifest,
  isCurrent = () => true,
  yieldIfNeeded = yieldValidationIfNeeded,
) {
  const evidenceGroups = new Map();
  let sliceStartedAt = performance.now();
  for (const entry of [...manifest.entries, ...(manifest.fontContractEntries ?? [])]) {
    if (!addFontEvidenceEntry(evidenceGroups, entry)) return { evidenceGroups: null };
    sliceStartedAt = await yieldIfNeeded(sliceStartedAt);
    if (!isCurrent()) return { evidenceGroups: null, superseded: true };
  }
  return { evidenceGroups };
}

async function validateManifestFontContract(
  manifest,
  documentObject,
  isCurrent = () => true,
  yieldIfNeeded = yieldValidationIfNeeded,
) {
  let sliceStartedAt = performance.now();
  if ([...manifest.entries, ...(manifest.fontContractEntries ?? [])].some((entry) =>
    entry?.fontEvidence?.backendRevision !== FONT_BACKEND_REVISION)) {
    return { reason: "SnapshotFontBackendRevisionMismatch" };
  }
  const grouped = await groupedFontEvidenceCooperatively(manifest, isCurrent, yieldIfNeeded);
  if (grouped.superseded) return { reason: "superseded" };
  const evidenceGroups = grouped.evidenceGroups;
  if (!evidenceGroups) return { reason: "SnapshotFontEvidenceInvalid" };
  sliceStartedAt = await yieldIfNeeded(sliceStartedAt);
  if (!isCurrent()) return { reason: "superseded" };
  const requestedFamilies = new Set(Array.from(evidenceGroups.values(), (group) =>
    String(group.representative.family).toLowerCase()));
  const cssFaceCollection = await collectFontFacesCooperatively(
    documentObject,
    requestedFamilies,
    isCurrent,
    yieldIfNeeded,
  );
  if (cssFaceCollection.superseded) return { reason: "superseded" };
  if (cssFaceCollection.unverifiable) return { reason: "FontFaceCssomUnverifiable" };
  sliceStartedAt = await yieldIfNeeded(sliceStartedAt);
  if (!isCurrent()) return { reason: "superseded" };
  const cssFaces = cssFaceCollection.faces;
  const requireExactFirstPaintDisplay = manifest.entrySource === "server-dom-v1";
  let compatibleLocalDeclared = false;
  for (const group of evidenceGroups.values()) {
    const aggregate = { ...group.representative, coverageText: Array.from(group.coverage).join("") };
    const faceContract = cssFaceContract(
      aggregate,
      cssFaces,
      documentObject,
      requireExactFirstPaintDisplay,
    );
    if (!faceContract.matches) return { reason: "FontFaceContractMismatch" };
    compatibleLocalDeclared ||= faceContract.compatibleLocalDeclared;
    sliceStartedAt = await yieldIfNeeded(sliceStartedAt);
    if (!isCurrent()) return { reason: "superseded" };
  }
  const evidenceIssue = await validateFontEvidenceGroups(
    evidenceGroups,
    documentObject,
    isCurrent,
    yieldIfNeeded,
  );
  if (evidenceIssue) return { reason: evidenceIssue };
  return { reason: null, compatibleLocalDeclared };
}

/**
 * Validates immutable exact-font evidence and, for a real layout snapshot,
 * every live input needed to adopt that snapshot. A compact runtime font
 * contract is instead a reusable replay corpus: the exact shaper's ShapingInput
 * lookup is the paragraph/run eligibility gate, and an uncovered host style
 * falls back without poisoning covered paragraphs in the same root.
 */
export async function validatePrecomputedSnapshotExactFontContract(root, isCurrent = () => true) {
  root?.removeAttribute?.(TYPOGRAPHY_ISSUE_ATTRIBUTE);
  if (!isCurrent()) return { matches: false, reason: "superseded" };
  const reference = root?.getAttribute?.("snapshot-ref");
  if (!reference) return { matches: false, reason: "SnapshotReferenceMissing" };
  const documentObject = root.ownerDocument || document;
  const template = documentObject.getElementById(reference);
  if (!template?.content) return { matches: false, reason: "SnapshotTemplateMissing" };
  let manifest;
  try {
    manifest = templateManifest(template);
  } catch {
    return { matches: false, reason: "SnapshotManifestInvalid" };
  }
  if (
    manifest.schema !== SNAPSHOT_SCHEMA || manifest.layoutRevision !== LAYOUT_REVISION ||
    manifest.renderRevision !== RENDER_REVISION || manifest.fontSourcePolicy !== FONT_SOURCE_POLICY ||
    !Array.isArray(manifest.entries) || typeof manifest.paragraphSelector !== "string" ||
    !manifestRenderFontFamiliesAreValid(manifest)
  ) return { matches: false, reason: "SnapshotRevisionMismatch" };
  if (!manifestEntryKeysAreUnique(manifest)) {
    return { matches: false, reason: "SnapshotManifestEntryKeyInvalid" };
  }

  if (fontContractOnlyManifest(manifest)) {
    // RuntimeFontContractRunEligibility: a host may intentionally vary
    // typography between paragraphs (for example `font-feature-settings:
    // "hwid"`). The replay table is keyed by the complete shaping input, so a
    // mismatching paragraph cannot consume a matching replay accidentally.
    // Keep the root session available for sibling paragraphs whose runs do
    // match instead of turning one host style into an article-wide miss.
    const fontContract = await validateManifestFontContract(manifest, documentObject, isCurrent);
    if (fontContract.reason) return { matches: false, reason: fontContract.reason };
    if (!isCurrent()) return { matches: false, reason: "superseded" };
    return {
      matches: true,
      reason: null,
      paragraphSelector: manifest.paragraphSelector,
      compatibleLocalDeclared: fontContract.compatibleLocalDeclared,
    };
  }

  const paragraphs = rootParagraphs(root, manifest.paragraphSelector);
  if (paragraphs.length !== manifest.entries.length) {
    return { matches: false, reason: "SnapshotCandidateSetMismatch" };
  }
  const byKey = new Map(paragraphs.map((paragraph) => [
    paragraph.getAttribute("data-tq-snapshot-key"),
    paragraph,
  ]));
  if (byKey.size !== paragraphs.length) {
    return { matches: false, reason: "SnapshotCandidateKeyInvalid" };
  }
  let sliceStartedAt = performance.now();
  for (const entry of manifest.entries) {
    if (
      !entry || typeof entry.key !== "string" || typeof entry.sourceSha256 !== "string" ||
      typeof entry.typographySha256 !== "string" || !entry.typography ||
      await sha256Text(stableStringify(entry.typography)) !== entry.typographySha256
    ) return { matches: false, reason: "SnapshotTypographyDigestMismatch" };
    const paragraph = byKey.get(entry.key);
    if (!paragraph) return { matches: false, reason: "SnapshotEntryMissing" };
    const source = plainParagraphSource(paragraph);
    if (source == null || await sha256Text(source) !== entry.sourceSha256) {
      return { matches: false, reason: "SnapshotSourceMismatch" };
    }
    if (!await sourceArtifactMatches(paragraph, entry)) {
      return { matches: false, reason: "SnapshotSourceSemanticsMismatch" };
    }
    const typographyIssue = computedTypographyIssue(
      paragraph,
      entry.typography,
      canonicalPreparedFlow(paragraph),
      liveRenderFontFamilies(root, manifest, paragraph),
      { allowLiveFontSizeAndLineHeight: true },
    );
    if (typographyIssue) {
      root.setAttribute(TYPOGRAPHY_ISSUE_ATTRIBUTE, typographyIssue);
      return { matches: false, reason: "SnapshotTypographyMismatch" };
    }
    sliceStartedAt = await yieldValidationIfNeeded(sliceStartedAt);
    if (!isCurrent()) return { matches: false, reason: "superseded" };
  }
  const fontContract = await validateManifestFontContract(
    manifest,
    documentObject,
    isCurrent,
    manifest.entrySource === "server-dom-v1"
      ? yieldDirectSsrValidationIfNeeded
      : yieldValidationIfNeeded,
  );
  if (fontContract.reason) return { matches: false, reason: fontContract.reason };
  if (!isCurrent()) return { matches: false, reason: "superseded" };
  const currentParagraphs = rootParagraphs(root, manifest.paragraphSelector);
  if (currentParagraphs.length !== manifest.entries.length) {
    return { matches: false, reason: "SnapshotCandidateSetChangedDuringValidation" };
  }
  const currentByKey = new Map(currentParagraphs.map((paragraph) => [
    paragraph.getAttribute("data-tq-snapshot-key"),
    paragraph,
  ]));
  if (currentByKey.size !== currentParagraphs.length) {
    return { matches: false, reason: "SnapshotCandidateKeyChangedDuringValidation" };
  }
  sliceStartedAt = performance.now();
  for (const entry of manifest.entries) {
    const paragraph = currentByKey.get(entry.key);
    const source = paragraph == null ? null : plainParagraphSource(paragraph);
    if (source == null || await sha256Text(source) !== entry.sourceSha256) {
      return { matches: false, reason: "SnapshotSourceChangedDuringValidation" };
    }
    if (paragraph == null || !await sourceArtifactMatches(paragraph, entry)) {
      return { matches: false, reason: "SnapshotSourceSemanticsChangedDuringValidation" };
    }
    const typographyIssue = computedTypographyIssue(
      paragraph,
      entry.typography,
      canonicalPreparedFlow(paragraph),
      liveRenderFontFamilies(root, manifest, paragraph),
      { allowLiveFontSizeAndLineHeight: true },
    );
    if (typographyIssue) {
      root.setAttribute(TYPOGRAPHY_ISSUE_ATTRIBUTE, typographyIssue);
      return { matches: false, reason: "SnapshotTypographyChangedDuringValidation" };
    }
    sliceStartedAt = await yieldValidationIfNeeded(sliceStartedAt);
    if (!isCurrent()) return { matches: false, reason: "superseded" };
  }
  if (!isCurrent()) return { matches: false, reason: "superseded" };
  return {
    matches: true,
    reason: null,
    paragraphSelector: manifest.paragraphSelector,
    compatibleLocalDeclared: fontContract.compatibleLocalDeclared,
  };
}

/**
 * Validates the host-font contract needed to replay server geometry directly.
 * This is intentionally strict and comparatively expensive: an adopted SSR
 * snapshot paints through the host's @font-face rules, so both the CSS face
 * inventory and browser advances are part of the first-paint proof.
 */
export async function validatePrecomputedExactFontReplayContract(root, isCurrent = () => true) {
  root?.removeAttribute?.(TYPOGRAPHY_ISSUE_ATTRIBUTE);
  if (!isCurrent()) return { matches: false, reason: "superseded" };
  const reference = root?.getAttribute?.("snapshot-ref");
  if (!reference) return { matches: false, reason: "SnapshotReferenceMissing" };
  const documentObject = root.ownerDocument || document;
  const template = documentObject.getElementById(reference);
  if (!template?.content) return { matches: false, reason: "SnapshotTemplateMissing" };
  const manifestScript = template.content.querySelector?.("[data-tq-snapshot-manifest]");
  const manifestText = manifestScript?.textContent;
  let manifest;
  try {
    manifest = templateManifest(template);
  } catch {
    return { matches: false, reason: "SnapshotManifestInvalid" };
  }
  if (
    manifest.schema !== SNAPSHOT_SCHEMA || manifest.layoutRevision !== LAYOUT_REVISION ||
    manifest.renderRevision !== RENDER_REVISION || manifest.fontSourcePolicy !== FONT_SOURCE_POLICY ||
    !Array.isArray(manifest.entries) || typeof manifest.paragraphSelector !== "string" ||
    !manifestRenderFontFamiliesAreValid(manifest)
  ) return { matches: false, reason: "SnapshotRevisionMismatch" };
  if (!manifestEntryKeysAreUnique(manifest)) {
    return { matches: false, reason: "SnapshotManifestEntryKeyInvalid" };
  }

  const requestedFamilies = manifestFontFamilies(manifest);
  if (requestedFamilies.size === 0) {
    return { matches: false, reason: "SnapshotFontEvidenceInvalid" };
  }
  const initialCss = relevantFontFaceLiveSignature(documentObject, requestedFamilies);
  if (initialCss.unverifiable) {
    return { matches: false, reason: "FontFaceCssomUnverifiable" };
  }
  const fontContract = await validateManifestFontContract(
    manifest,
    documentObject,
    isCurrent,
    manifest.entrySource === "server-dom-v1"
      ? yieldDirectSsrValidationIfNeeded
      : yieldValidationIfNeeded,
  );
  if (fontContract.reason) return { matches: false, reason: fontContract.reason };
  if (!isCurrent()) return { matches: false, reason: "superseded" };
  const currentTemplate = documentObject.getElementById(reference);
  const currentManifestText = currentTemplate?.content
    ?.querySelector?.("[data-tq-snapshot-manifest]")?.textContent;
  if (currentTemplate !== template || currentManifestText !== manifestText) {
    return { matches: false, reason: "SnapshotManifestChangedDuringFontValidation" };
  }
  const currentCss = relevantFontFaceLiveSignature(documentObject, requestedFamilies);
  if (currentCss.unverifiable || currentCss.signature !== initialCss.signature) {
    return { matches: false, reason: "FontFaceContractChangedDuringValidation" };
  }
  exactFontReplayProofs.set(root, {
    reference,
    template,
    manifestText,
    requestedFamilies,
    cssSignature: currentCss.signature,
    paragraphSelector: manifest.paragraphSelector,
    compatibleLocalDeclared: fontContract.compatibleLocalDeclared,
    renderSource: "host-css",
  });
  return {
    matches: true,
    reason: null,
    paragraphSelector: manifest.paragraphSelector,
    compatibleLocalDeclared: fontContract.compatibleLocalDeclared,
  };
}

/**
 * Backward-compatible name for runtime callers. Runtime replay now paints via
 * the host font family, so it must prove the same live CSS and advance contract
 * as snapshot adoption.
 */
export function validatePrecomputedExactFontReplayRuntimeContract(
  root,
  isCurrent = () => true,
) {
  return validatePrecomputedExactFontReplayContract(root, isCurrent);
}

/** Rechecks the live identity of an already proven replay contract without repeating probes. */
export function validatePrecomputedExactFontReplayLiveContract(root, isCurrent = () => true) {
  if (!isCurrent()) return { matches: false, reason: "superseded" };
  const proof = exactFontReplayProofs.get(root);
  if (!proof) return { matches: false, reason: "ExactFontReplayProofMissing" };
  const reference = root?.getAttribute?.("snapshot-ref");
  const documentObject = root.ownerDocument || document;
  const template = reference ? documentObject.getElementById(reference) : null;
  const manifestText = template?.content
    ?.querySelector?.("[data-tq-snapshot-manifest]")?.textContent;
  if (
    reference !== proof.reference || template !== proof.template ||
    manifestText !== proof.manifestText
  ) return { matches: false, reason: "SnapshotManifestChangedDuringFontPreparation" };
  const currentCss = relevantFontFaceLiveSignature(documentObject, proof.requestedFamilies);
  if (currentCss.unverifiable || currentCss.signature !== proof.cssSignature) {
    return { matches: false, reason: "FontFaceContractChangedDuringFontPreparation" };
  }
  return {
    matches: true,
    reason: null,
    paragraphSelector: proof.paragraphSelector,
    compatibleLocalDeclared: proof.compatibleLocalDeclared,
  };
}

export function isPrecomputedSnapshotAdopted(root) {
  return states.has(root);
}

/**
 * Synchronously rechecks the contracts that a completed FontFaceSet cycle can
 * invalidate without changing source text. This deliberately does not load or
 * probe fonts again: adoption already did that, and reloading from a
 * `loadingdone` handler would create another loading cycle. A changed CSS face
 * contract or any resulting prepared geometry drift still fails closed.
 */
export async function adoptedPrecomputedSnapshotLiveIssue(root, isCurrent = () => true) {
  if (!isCurrent()) return "superseded";
  const state = states.get(root);
  const manifest = state?.manifest;
  if (!manifest) return "SnapshotStateMissing";
  if ([...manifest.entries, ...(manifest.fontContractEntries ?? [])].some((entry) =>
    entry?.fontEvidence?.backendRevision !== FONT_BACKEND_REVISION)) {
    return "SnapshotFontBackendRevisionMismatch";
  }
  const evidenceGroups = groupedFontEvidence(manifest);
  if (!evidenceGroups) return "SnapshotFontEvidenceInvalid";
  const documentObject = root.ownerDocument || document;
  const requestedFamilies = new Set(Array.from(evidenceGroups.values(), (group) =>
    String(group.representative.family).toLowerCase()));
  const cssFaceCollection = collectFontFaces(documentObject, requestedFamilies);
  if (cssFaceCollection.unverifiable) return "FontFaceCssomUnverifiable";
  const requireExactFirstPaintDisplay = manifest.entrySource === "server-dom-v1";
  let sliceStartedAt = performance.now();
  for (const group of evidenceGroups.values()) {
    const aggregate = {
      ...group.representative,
      coverageText: Array.from(group.coverage).join(""),
    };
    if (!cssFaceContract(
      aggregate,
      cssFaceCollection.faces,
      documentObject,
      requireExactFirstPaintDisplay,
    ).matches) return "FontFaceContractMismatch";
    sliceStartedAt = await yieldValidationIfNeeded(sliceStartedAt);
    if (!isCurrent()) return "superseded";
  }

  const paragraphs = rootParagraphs(root, manifest.paragraphSelector);
  if (paragraphs.length !== manifest.entries.length) return "SnapshotCandidateSetMismatch";
  const byKey = new Map(paragraphs.map((paragraph) => [
    paragraph.getAttribute("data-tq-snapshot-key"),
    paragraph,
  ]));
  if (byKey.size !== paragraphs.length) return "SnapshotCandidateKeyInvalid";
  for (const entry of manifest.entries) {
    const paragraph = byKey.get(entry?.key);
    if (!paragraph) return "SnapshotEntryMissing";
    const width = contentBoxWidth(paragraph);
    if (!snapshotEntryWidthMatches(width, entry)) return "SnapshotWidthMismatch";
    if (!computedTypographyMatches(
      paragraph,
      entry.typography,
      true,
      manifest.renderFontFamilies,
    )) return "SnapshotTypographyMismatch";
    const geometryIssue = renderedPreparedParagraphIssue(paragraph, width);
    if (geometryIssue) return geometryIssue.replace("RenderedPreparedParagraph", "RenderedSnapshot");
    // CooperativeAdoptedSnapshotAudit: a FontFaceSet event can arrive while the
    // reader is already scrolling. The exact DOM remains valid and visible
    // while its independent paragraph contracts are audited across tasks.
    sliceStartedAt = await yieldValidationIfNeeded(sliceStartedAt);
    if (!isCurrent()) return "superseded";
  }
  return null;
}

/**
 * Non-destructive maximum-measure preflight for responsive re-adoption. This
 * deliberately checks only the keyed candidate set and live content widths;
 * source, typography, font and geometry still go through the full adoption
 * contract before any DOM is changed.
 */
export function precomputedSnapshotMaximumMeasureMatches(root) {
  const reference = root?.getAttribute?.("snapshot-ref");
  if (!reference) return false;
  const documentObject = root.ownerDocument || document;
  const template = documentObject.getElementById(reference);
  if (!template?.content) return false;
  let manifest;
  try {
    manifest = templateManifest(template);
  } catch {
    return false;
  }
  if (!Array.isArray(manifest.entries) || typeof manifest.paragraphSelector !== "string") {
    return false;
  }
  if (!manifestEntryKeysAreUnique(manifest)) return false;
  const paragraphs = rootParagraphs(root, manifest.paragraphSelector);
  if (paragraphs.length !== manifest.entries.length) return false;
  const byKey = new Map(paragraphs.map((paragraph) => [
    paragraph.getAttribute("data-tq-snapshot-key"),
    paragraph,
  ]));
  if (byKey.size !== paragraphs.length) return false;
  return manifest.entries.every((entry) => {
    const paragraph = byKey.get(entry?.key);
    const width = paragraph == null ? Number.NaN : contentBoxWidth(paragraph);
    return snapshotEntryWidthMatches(width, entry);
  });
}

export function restorePrecomputedSnapshot(root) {
  const state = states.get(root);
  if (!state) return false;
  states.delete(root);
  for (const item of state.paragraphs) {
    while (item.paragraph.firstChild) item.paragraph.removeChild(item.paragraph.firstChild);
    item.paragraph.appendChild(item.originalContent);
    if (item.originalRenderedAttribute == null) {
      item.paragraph.removeAttribute("data-tq-rendered");
    } else {
      item.paragraph.setAttribute("data-tq-rendered", item.originalRenderedAttribute);
    }
    if (item.originalLangAttribute == null) {
      item.paragraph.removeAttribute("lang");
    } else {
      item.paragraph.setAttribute("lang", item.originalLangAttribute);
    }
    if (item.originalCanonicalPlainAttribute == null) {
      item.paragraph.removeAttribute("data-tq-canonical-plain");
    } else {
      item.paragraph.setAttribute("data-tq-canonical-plain", item.originalCanonicalPlainAttribute);
    }
    if (item.originalCanonicalSourceAttribute == null) {
      item.paragraph.removeAttribute("data-tq-canonical-source");
    } else {
      item.paragraph.setAttribute("data-tq-canonical-source", item.originalCanonicalSourceAttribute);
    }
    if (item.originalExactPreparedDomAttribute == null) {
      item.paragraph.removeAttribute(EXACT_PREPARED_DOM_ATTRIBUTE);
    } else {
      item.paragraph.setAttribute(EXACT_PREPARED_DOM_ATTRIBUTE, item.originalExactPreparedDomAttribute);
    }
  }
  if (state.valueStylesInstalled) releasePreparedValueStyleRoot(root);
  if (state.serverRenderedEntries) {
    root.removeAttribute(SERVER_RENDERED_SNAPSHOT_ATTRIBUTE);
    root.removeAttribute(EXACT_RENDER_FONT_ATTRIBUTE);
  } else if (state.originalExactRenderFontAttribute == null) {
    root.removeAttribute(EXACT_RENDER_FONT_ATTRIBUTE);
  } else {
    root.setAttribute(EXACT_RENDER_FONT_ATTRIBUTE, state.originalExactRenderFontAttribute);
  }
  root.removeAttribute("data-tiqian-enhanced");
  root.removeAttribute("data-tiqian-enhanced-count");
  root.removeAttribute("data-tiqian-snapshot-count");
  delete root.dataset.tiqianSnapshot;
  delete root.dataset.tiqianSnapshotFontPolicy;
  return true;
}

/**
 * Releases document-scoped snapshot styles after a root leaves the document
 * without rebuilding DOM that is no longer visible. The WeakMap state retains
 * the semantic backing if the same custom element is later reconnected; when
 * the detached tree becomes unreachable, the backing is collected with it.
 */
export function detachPrecomputedSnapshot(root) {
  const state = states.get(root);
  if (!state) return false;
  if (state.valueStylesInstalled) releasePreparedValueStyleRoot(root);
  return true;
}

export async function tryAdoptPrecomputedSnapshot(root, isCurrent = () => true) {
  if (!isCurrent()) return { adopted: false, reason: "superseded" };
  restorePrecomputedSnapshot(root);
  delete root.dataset.tiqianSnapshotMiss;
  const reference = root.getAttribute("snapshot-ref");
  if (!reference) return { adopted: false, reason: "not-requested" };
  const documentObject = root.ownerDocument || document;
  const template = documentObject.getElementById(reference);
  if (!template?.content) return miss(root, "SnapshotTemplateMissing");

  let manifest;
  try {
    manifest = templateManifest(template);
  } catch {
    return miss(root, "SnapshotManifestInvalid");
  }
  if (
    manifest.schema !== SNAPSHOT_SCHEMA || manifest.layoutRevision !== LAYOUT_REVISION ||
    manifest.renderRevision !== RENDER_REVISION || manifest.fontSourcePolicy !== FONT_SOURCE_POLICY ||
    !manifestRenderFontFamiliesAreValid(manifest)
  ) return miss(root, "SnapshotRevisionMismatch");
  if (!Array.isArray(manifest.entries) || typeof manifest.paragraphSelector !== "string") {
    return miss(root, "SnapshotManifestInvalid");
  }
  if (!manifestEntryKeysAreUnique(manifest)) {
    return miss(root, "SnapshotManifestEntryKeyInvalid");
  }
  if (!await manifestValueStylesAreValid(manifest)) {
    return miss(root, "SnapshotValueStylesDigestMismatch");
  }
  if (fontContractOnlyManifest(manifest)) {
    return miss(root, "SnapshotLayoutArtifactUnavailable");
  }

  const paragraphs = rootParagraphs(root, manifest.paragraphSelector);
  if (paragraphs.length !== manifest.entries.length) return miss(root, "SnapshotCandidateSetMismatch");
  const byKey = new Map(paragraphs.map((paragraph) => [paragraph.getAttribute("data-tq-snapshot-key"), paragraph]));
  if (byKey.size !== paragraphs.length) return miss(root, "SnapshotCandidateKeyInvalid");
  const serverRenderedEntries = manifest.entrySource === "server-dom-v1" &&
    root.getAttribute("data-tq-ssr-snapshot") === reference;
  if (serverRenderedEntries) {
    // DirectSsrFirstInputHandoff: service the navigation frame before cloning
    // immutable responsive backing. The already-rendered server DOM remains
    // authoritative while this cooperative cache is assembled.
    await yieldDirectSsrValidationIfNeeded(0);
    if (!isCurrent()) return { adopted: false, reason: "superseded" };
    if (!await captureServerRenderedSnapshotArtifacts(root, manifest, byKey, isCurrent)) {
      return { adopted: false, reason: "superseded" };
    }
  }
  const prepared = [];
  let sliceStartedAt = performance.now();
  for (const entry of manifest.entries) {
    if (
      !entry || typeof entry.key !== "string" || typeof entry.sourceSha256 !== "string" ||
      typeof entry.typographySha256 !== "string" ||
      typeof entry.renderArtifactSha256 !== "string" || !entry.typography ||
      await sha256Text(stableStringify(entry.typography)) !== entry.typographySha256
    ) return miss(root, "SnapshotTypographyDigestMismatch");
    const paragraph = byKey.get(entry.key);
    const snapshot = serverRenderedEntries ? paragraph : templateEntry(template, entry.key, root);
    if (!paragraph || !snapshot) return miss(root, "SnapshotEntryMissing");
    const sourceSnapshot = serverRenderedEntries
      ? templateSourceEntry(documentObject, reference, entry.key)
      : null;
    if (serverRenderedEntries && !sourceSnapshot) {
      return miss(root, "SnapshotSourceEntryMissing");
    }
    if (!await snapshotArtifactMatches(snapshot, entry.renderArtifactSha256)) {
      return miss(root, "SnapshotArtifactDigestMismatch");
    }
    const source = plainParagraphSource(paragraph);
    if (source == null || await sha256Text(source) !== entry.sourceSha256) {
      return miss(root, "SnapshotSourceMismatch");
    }
    if (!serverRenderedEntries && !await sourceArtifactMatches(paragraph, entry)) {
      return miss(root, "SnapshotSourceSemanticsMismatch");
    }
    const width = contentBoxWidth(paragraph);
    if (!snapshotEntryWidthMatches(width, entry)) {
      return miss(root, "SnapshotWidthMismatch");
    }
    if (!computedTypographyMatches(
      paragraph,
      entry.typography,
      canonicalPreparedFlow(paragraph),
      liveRenderFontFamilies(root, manifest, paragraph),
    )) {
      return miss(root, "SnapshotTypographyMismatch");
    }
    prepared.push({ paragraph, snapshot, sourceSnapshot, entry });
    // CooperativeSnapshotPreflight: digest, computed-style and width reads are
    // non-mutating. Keep them outside one monolithic navigation task while the
    // responsive SSR source remains the only visible paragraph DOM.
    sliceStartedAt = await yieldSnapshotValidationIfNeeded(
      sliceStartedAt,
      serverRenderedEntries,
    );
    if (!isCurrent()) return { adopted: false, reason: "superseded" };
  }

  // SnapshotFontProofHandoff: adoption and the runtime replay session consume
  // the same exact face evidence. Publish the successful proof on this root so
  // mixed snapshot/runtime completion does not immediately repeat every
  // browser font probe.
  const fontContract = await validatePrecomputedExactFontReplayContract(root, isCurrent);
  if (!fontContract.matches) return miss(root, fontContract.reason);
  const compatibleLocalDeclared = fontContract.compatibleLocalDeclared;
  if (!isCurrent()) return { adopted: false, reason: "superseded" };

  // Font loading and probe measurement are asynchronous. The responsive page
  // may have crossed a breakpoint while they ran, before observers are active.
  // Revalidate every live input immediately before the first DOM mutation.
  sliceStartedAt = performance.now();
  for (const { paragraph, entry } of prepared) {
    const source = plainParagraphSource(paragraph);
    if (source == null || await sha256Text(source) !== entry.sourceSha256) {
      return miss(root, "SnapshotSourceChangedDuringValidation");
    }
    if (!serverRenderedEntries && !await sourceArtifactMatches(paragraph, entry)) {
      return miss(root, "SnapshotSourceSemanticsChangedDuringValidation");
    }
    const width = contentBoxWidth(paragraph);
    if (!snapshotEntryWidthMatches(width, entry)) {
      return miss(root, "SnapshotWidthChangedDuringValidation");
    }
    if (!computedTypographyMatches(
      paragraph,
      entry.typography,
      canonicalPreparedFlow(paragraph),
      liveRenderFontFamilies(root, manifest, paragraph),
    )) {
      return miss(root, "SnapshotTypographyChangedDuringValidation");
    }
    sliceStartedAt = await yieldSnapshotValidationIfNeeded(
      sliceStartedAt,
      serverRenderedEntries,
    );
    if (!isCurrent()) return { adopted: false, reason: "superseded" };
  }
  if (!isCurrent()) return { adopted: false, reason: "superseded" };

  const adopted = [];
  let valueStylesInstalled = false;
  const originalExactRenderFontAttribute = root.getAttribute(EXACT_RENDER_FONT_ATTRIBUTE);
  const adoptionState = {
    paragraphs: adopted,
    manifest,
    valueStylesInstalled,
    originalExactRenderFontAttribute,
    serverRenderedEntries,
  };
  try {
    valueStylesInstalled = installPreparedValueStyles(
      root,
      manifest.valueStyles,
    );
    adoptionState.valueStylesInstalled = valueStylesInstalled;
    root.setAttribute(EXACT_RENDER_FONT_ATTRIBUTE, "true");
    // ProgressiveSnapshotCommitProof: preflight has already proven the whole
    // source/font/typography contract. Publish one provisional owner before
    // touching live DOM, then commit and prove one paragraph at a time. Each
    // geometry read now flushes only that paragraph's pending layout instead
    // of forcing a single full-article reflow after every entry was replaced.
    states.set(root, adoptionState);
    sliceStartedAt = performance.now();
    for (const { paragraph, snapshot, sourceSnapshot, entry } of prepared) {
      if (!isCurrent() || states.get(root) !== adoptionState) {
        if (states.get(root) === adoptionState) restorePrecomputedSnapshot(root);
        return { adopted: false, reason: "superseded" };
      }
      const originalContent = documentObject.createDocumentFragment();
      if (serverRenderedEntries) {
        for (const child of Array.from(sourceSnapshot?.childNodes ?? paragraph.childNodes)) {
          originalContent.appendChild(child.cloneNode(true));
        }
      } else {
        while (paragraph.firstChild) originalContent.appendChild(paragraph.firstChild);
      }
      const originalRenderedAttribute = serverRenderedEntries
        ? null
        : paragraph.getAttribute("data-tq-rendered");
      const originalLangAttribute = paragraph.getAttribute("lang");
      const originalCanonicalPlainAttribute = serverRenderedEntries
        ? null
        : paragraph.getAttribute("data-tq-canonical-plain");
      const originalCanonicalSourceAttribute = serverRenderedEntries
        ? null
        : paragraph.getAttribute("data-tq-canonical-source");
      const originalExactPreparedDomAttribute = serverRenderedEntries
        ? null
        : paragraph.getAttribute(EXACT_PREPARED_DOM_ATTRIBUTE);
      adopted.push({
        paragraph,
        originalContent,
        originalRenderedAttribute,
        originalLangAttribute,
        originalCanonicalPlainAttribute,
        originalCanonicalSourceAttribute,
        originalExactPreparedDomAttribute,
      });
      paragraph.setAttribute("data-tq-rendered", "true");
      paragraph.setAttribute(EXACT_PREPARED_DOM_ATTRIBUTE, "true");
      if (entry.semantic === true) paragraph.removeAttribute("data-tq-canonical-plain");
      else paragraph.setAttribute("data-tq-canonical-plain", "true");
      paragraph.setAttribute("data-tq-canonical-source", "true");
      paragraph.setAttribute("lang", entry.typography.locale);
      if (!serverRenderedEntries) {
        const clone = snapshot.cloneNode(true);
        while (clone.firstChild) paragraph.appendChild(clone.firstChild);
      }
      const width = contentBoxWidth(paragraph);
      if (
        !snapshotEntryWidthMatches(width, entry) ||
        !computedTypographyMatches(paragraph, entry.typography, true, manifest.renderFontFamilies)
      ) throw new Error("RenderedSnapshotHostContractMismatch");
      const issue = renderedPreparedParagraphIssue(paragraph, width);
      if (issue) throw new Error(issue.replace("RenderedPreparedParagraph", "RenderedSnapshot"));
      sliceStartedAt = await yieldSnapshotValidationIfNeeded(
        sliceStartedAt,
        serverRenderedEntries,
      );
    }
  } catch (error) {
    const currentState = states.get(root);
    if (currentState?.paragraphs === adopted) restorePrecomputedSnapshot(root);
    return miss(root, `SnapshotAdoptionFailed:${error instanceof Error ? error.message : String(error)}`);
  }
  if (!isCurrent()) {
    const currentState = states.get(root);
    if (currentState?.paragraphs === adopted) restorePrecomputedSnapshot(root);
    return { adopted: false, reason: "superseded" };
  }
  root.setAttribute("data-tiqian-enhanced", "true");
  root.setAttribute("data-tiqian-enhanced-count", String(adopted.length));
  root.setAttribute("data-tiqian-snapshot-count", String(adopted.length));
  root.dataset.tiqianSnapshot = "maximum-measure";
  root.dataset.tiqianSnapshotFontPolicy = compatibleLocalDeclared ? "compatible-local" : "url-only";
  root.removeAttribute(EXACT_LAYOUT_ISSUE_ATTRIBUTE);
  delete root.dataset.tiqianSnapshotMiss;
  return { adopted: true, count: adopted.length };
}
