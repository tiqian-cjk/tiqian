import {
  FONT_BACKEND_REVISION,
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
const LINE_ADVANCE_TOLERANCE_PX = 0.75;
const INLINE_POSITION_TOLERANCE_PX = 0.75;
const LINE_VERTICAL_TOLERANCE_PX = 0.75;
const PREPARED_VERTICAL_TOLERANCE_PX = 0.02;
const RENDER_FLOW_EPSILON_PX = 0.01;
const PROPORTIONAL_CURLY_QUOTE_FEATURE_SIGNATURE = "pwid,palt";
export const EXACT_RENDER_FONT_ATTRIBUTE = "data-tiqian-exact-render-font";
const EXACT_LAYOUT_ISSUE_ATTRIBUTE = "data-tiqian-exact-layout-issue";
const TYPOGRAPHY_ISSUE_ATTRIBUTE = "data-tiqian-snapshot-typography-issue";
const states = new WeakMap();

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

function parseUnicodeRange(value) {
  const serialized = String(value ?? "").trim();
  if (!serialized) return null;
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
  return ranges;
}

function unicodeRangeContains(ranges, codePoint) {
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

function collectFontFaces(documentObject) {
  const faces = [];
  let unverifiable = false;
  const visit = (rules, fallbackBaseUrl) => {
    if (!rules) return;
    for (const rule of rules) {
      if (rule.type === 5 && rule.style) {
        const style = rule.style;
        const baseUrl = rule.parentStyleSheet?.href || fallbackBaseUrl;
        const source = style.getPropertyValue("src");
        faces.push({
          family: unquote(style.getPropertyValue("font-family")),
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

function plainParagraphSource(paragraph) {
  if (
    paragraph.getAttribute("data-tq-rendered") === "true" &&
    (paragraph.getAttribute("data-tq-canonical-source") === "true" ||
      paragraph.getAttribute("data-tq-canonical-plain") === "true")
  ) return canonicalRenderedPlainSource(paragraph);
  for (const element of paragraph.querySelectorAll("*")) {
    if (element.tagName !== "BR") return null;
  }
  const value = typeof paragraph.innerText === "string" ? paragraph.innerText : paragraph.textContent;
  return String(value ?? "").replaceAll("\r\n", "\n").replaceAll("\r", "\n");
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
    paragraph.getAttribute("data-tq-canonical-plain") === "true";
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
      fontFeatureSettings: "normal",
      fontVariantEastAsian: "normal",
    });
  }
  if (!Array.isArray(features) || features.some((feature) => typeof feature !== "string")) {
    return null;
  }
  const signature = features.join(",");
  return signature === PROPORTIONAL_CURLY_QUOTE_FEATURE_SIGNATURE
    ? Object.freeze({
      signature,
      fontFeatureSettings: '"palt" 1',
      fontVariantEastAsian: "proportional-width",
    })
    : null;
}

function boundaryOpenTypeFeatureContract(element) {
  const signature = element.getAttribute("data-tq-open-type-features");
  return signature == null
    ? openTypeFeatureContract([])
    : openTypeFeatureContract(signature.split(","));
}

function canonicalPaltFeatureSettings(value) {
  return /^["']palt["'](?:\s+1)?$/u.test(String(value ?? "").trim());
}

function boundaryOpenTypeFeatureIssue(element, style, contract) {
  if (!contract) return "Boundary:openTypeFeatures";
  if (!contract.signature) return null;
  if (style.fontVariantEastAsian !== contract.fontVariantEastAsian) {
    return "Boundary:fontVariantEastAsian";
  }
  if (!canonicalPaltFeatureSettings(style.fontFeatureSettings)) {
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

function generatedGeometryIssue(element, paragraphStyle) {
  const style = getComputedStyle(element);
  if ((style.transform || "none") !== "none") return "Geometry:transform";
  if ((style.scale || "none") !== "none") return "Geometry:scale";
  const shapingBoundary = element.hasAttribute("data-tq-shaping-boundary");
  const measuredGeometry = element.hasAttribute("data-tq-advance");
  const engineHyphen = element.hasAttribute("data-tq-engine-hyphen");
  if (!shapingBoundary && !element.textContent) {
    return pseudoGeneratedContentIsEmpty(element) ? null : "GeneratedContent";
  }
  if (shapingBoundary) {
    const contract = {
      display: "inline-block",
      whiteSpace: "pre",
      verticalAlign: "baseline",
      direction: "ltr",
      unicodeBidi: "isolate",
    };
    const stableMismatch = Object.entries(contract).find(([property, expected]) =>
      style[property] !== expected);
    if (stableMismatch) return `Boundary:${stableMismatch[0]}`;
    const featureContract = boundaryOpenTypeFeatureContract(element);
    const inheritedProperties = featureContract?.signature
      ? BOUNDARY_STYLE_PROPERTIES.filter((property) =>
        !FEATURE_OVERRIDABLE_BOUNDARY_STYLE_PROPERTIES.has(property))
      : BOUNDARY_STYLE_PROPERTIES;
    const inheritedMismatch = inheritedProperties.find((property) =>
      String(style[property] ?? "") !== String(paragraphStyle[property] ?? ""));
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
      .filter((property) => property !== "letterSpacing")
      .find((property) => String(style[property] ?? "") !== String(paragraphStyle[property] ?? ""));
    if (inheritedMismatch) return `Geometry:${inheritedMismatch}`;
  }
  return pseudoTypographyIssue(element, style);
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
  const children = Array.from(paragraph.childNodes ?? []);
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
    let contributorTop = null;
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
        if (contributorTop == null) contributorTop = rect.top;
        if (Math.abs(rect.top - contributorTop) > LINE_VERTICAL_TOLERANCE_PX) {
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
      actual - contentWidth > WIDTH_TOLERANCE_PX
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
 * for the canonical DOM freshly emitted by browser Wasm.
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
    const issue = generatedGeometryIssue(target, paragraphStyle);
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
) {
  const style = getComputedStyle(paragraph);
  const actualFamilies = parseFontFamilies(style.fontFamily).map((family) => family.toLowerCase());
  const expectedFamilies = (canonicalPreparedFlow && Array.isArray(renderFontFamilies)
    ? renderFontFamilies
    : contract.fontFamilies).map((family) => family.toLowerCase());
  if (actualFamilies.length !== expectedFamilies.length ||
      actualFamilies.some((family, index) => family !== expectedFamilies[index])) {
    const root = paragraph.closest(ROOT_SELECTOR);
    const projection = root?.getAttribute(EXACT_RENDER_FONT_ATTRIBUTE) ?? "missing";
    const variable = style.getPropertyValue("--tq-exact-render-font-family").trim() || "missing";
    const fallback = root?.hasAttribute("data-tiqian-exact-layout-fallback") ?? false;
    const rendered = paragraph.getAttribute("data-tq-rendered") ?? "missing";
    return `fontFamily:${actualFamilies.join("|")}!=${expectedFamilies.join("|")};projection=${projection};variable=${variable};fallback=${fallback};rendered=${rendered}`;
  }
  if (Math.abs(numericCssPx(style.fontSize) - contract.fontSizePx) > 0.01) return "fontSize";
  const expectedLineHeight = canonicalPreparedFlow ? 0 : contract.lineHeightPx;
  if (Math.abs(numericCssPx(style.lineHeight) - expectedLineHeight) > 0.01) return "lineHeight";
  if (numericWeight(style.fontWeight) !== contract.fontWeight) return "fontWeight";
  const actualFontStyle = style.fontStyle.toLowerCase();
  if (contract.italic ? !actualFontStyle.startsWith("italic") : actualFontStyle !== "normal") {
    return "fontStyle";
  }
  const letterSpacing = style.letterSpacing === "normal" ? 0 : numericCssPx(style.letterSpacing);
  if (!Number.isFinite(letterSpacing) || Math.abs(letterSpacing - contract.letterSpacingPx) > 0.01) {
    return "letterSpacing";
  }
  if ((style.fontFeatureSettings || "normal") !== contract.fontFeatureSettings) return "fontFeatureSettings";
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
  if ((style.fontVariantNumeric || "normal") !== "normal") return "fontVariantNumeric";
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
  if ((style.display || "block") !== "block") return "display";
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

function cssFaceContract(evidence, faces, documentObject) {
  const expectedUrl = new URL(evidence.publicUrl, documentObject.baseURI).href;
  const coverageText = evidence.coverageText || evidence.probe.text;
  const coveragePoints = Array.from(coverageText, (point) => point.codePointAt(0));
  const expectedRanges = parseUnicodeRange(evidence.unicodeRange);
  const familyCandidates = faces.filter((face) =>
    face.family.toLowerCase() === evidence.family.toLowerCase() &&
    styleMatches(face.style, evidence.probe.italic) &&
    coveragePoints.some((point) => unicodeRangeContains(face.unicodeRanges, point)));
  const candidates = cssWeightMatchedFaces(familyCandidates, evidence.probe.fontWeight);
  const defaultDescriptor = (value, defaults) => defaults.has(String(value ?? "").trim().toLowerCase());
  const exactFirstPaintDisplay = (value) => new Set(["", "auto", "block"])
    .has(String(value ?? "").trim().toLowerCase());
  const matches = candidates.length > 0 && candidates.every((face) =>
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
    exactFirstPaintDisplay(face.display));
  return {
    matches,
    compatibleLocalDeclared: matches && candidates.some((face) => face.hasLocalSource),
  };
}

function matchingCssFace(evidence, faces, documentObject) {
  return cssFaceContract(evidence, faces, documentObject).matches;
}

async function measureProbe(evidence, documentObject, featureContract) {
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
    `font-feature-settings:${featureContract.fontFeatureSettings}!important`,
    "font-variation-settings:normal!important",
    "font-kerning:normal!important",
    "font-optical-sizing:none!important",
    "letter-spacing:normal!important",
  ].join(";");
  probe.lang = evidence.probe.language;
  documentObject.body.append(probe);
  try {
    const range = documentObject.createRange();
    range.selectNodeContents(probe);
    return range.getBoundingClientRect().width;
  } finally {
    probe.remove();
  }
}

async function validateFontEvidence(evidence, faces, documentObject) {
  if (!matchingCssFace(evidence, faces, documentObject)) return "FontFaceContractMismatch";
  const featureContract = openTypeFeatureContract(evidence.probe.features);
  if (!featureContract) return "FontProbeFeaturesUnsupported";
  const descriptor = `${evidence.probe.italic ? "italic" : "normal"} ${evidence.probe.fontWeight} ` +
    `${evidence.probe.fontSizePx}px ${cssFamilyToken(evidence.family)}`;
  const loaded = await documentObject.fonts?.load?.(descriptor, evidence.probe.text);
  if (!loaded || loaded.length === 0) return "FontFaceLoadFailed";
  const actual = await measureProbe(evidence, documentObject, featureContract);
  const expected = evidence.probe.advancePx;
  const tolerance = Math.max(PROBE_ABSOLUTE_TOLERANCE_PX, expected * PROBE_RELATIVE_TOLERANCE);
  return Number.isFinite(actual) && Math.abs(actual - expected) <= tolerance
    ? null
    : "FontAdvanceProbeMismatch";
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
  const keys = manifest.entries.map((entry) => entry?.key);
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
  return canonicalPreparedFlow(paragraph) && root.getAttribute(EXACT_RENDER_FONT_ATTRIBUTE) === "true"
    ? manifest.renderFontFamilies
    : null;
}

function fontContractTypographyIssue(root, manifest) {
  const contracts = Array.from(manifest?.typographies ?? [], (entry) => entry?.value)
    .filter((value) => value && Array.isArray(value.fontFamilies));
  if (contracts.length === 0) return "manifestTypography";
  const paragraphs = rootParagraphs(root, manifest.paragraphSelector);
  if (paragraphs.length === 0) return "paragraphCandidate";
  for (const paragraph of paragraphs) {
    const issues = contracts.map((contract) => computedTypographyIssue(
      paragraph,
      contract,
      canonicalPreparedFlow(paragraph),
      liveRenderFontFamilies(root, manifest, paragraph),
    ));
    if (!issues.some((issue) => issue == null)) return issues[0] ?? "unknown";
  }
  return null;
}

function fontContractTypographyMatches(root, manifest) {
  return fontContractTypographyIssue(root, manifest) == null;
}

function templateEntry(template, key) {
  for (const entry of template.content?.querySelectorAll?.("[data-tq-entry]") ?? []) {
    if (entry.getAttribute("data-tq-entry") === key) return entry;
  }
  return null;
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
  root.dataset.tiqianSnapshotMiss = reason;
  delete root.dataset.tiqianSnapshot;
  return { adopted: false, reason };
}

function groupedFontEvidence(manifest) {
  const evidenceGroups = new Map();
  for (const entry of manifest.entries) {
    if (!entry?.fontEvidence || !Array.isArray(entry.fontEvidence.faces) ||
        entry.fontEvidence.faces.length === 0) return null;
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
  }
  return evidenceGroups;
}

async function validateManifestFontContract(manifest, documentObject) {
  if (manifest.entries.some((entry) =>
    entry?.fontEvidence?.backendRevision !== FONT_BACKEND_REVISION)) {
    return { reason: "SnapshotFontBackendRevisionMismatch" };
  }
  const evidenceGroups = groupedFontEvidence(manifest);
  if (!evidenceGroups) return { reason: "SnapshotFontEvidenceInvalid" };
  const cssFaceCollection = collectFontFaces(documentObject);
  if (cssFaceCollection.unverifiable) return { reason: "FontFaceCssomUnverifiable" };
  const cssFaces = cssFaceCollection.faces;
  let compatibleLocalDeclared = false;
  for (const group of evidenceGroups.values()) {
    const aggregate = { ...group.representative, coverageText: Array.from(group.coverage).join("") };
    const faceContract = cssFaceContract(aggregate, cssFaces, documentObject);
    if (!faceContract.matches) return { reason: "FontFaceContractMismatch" };
    compatibleLocalDeclared ||= faceContract.compatibleLocalDeclared;
    for (const evidence of group.probes.values()) {
      const issue = await validateFontEvidence(evidence, cssFaces, documentObject);
      if (issue) return { reason: issue };
    }
  }
  return { reason: null, compatibleLocalDeclared };
}

/**
 * Validates every live input that lets exact manifest bytes remain a truthful
 * measure source when snapshot adoption misses only for responsive geometry.
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
    const initialTypographyIssue = fontContractTypographyIssue(root, manifest);
    if (initialTypographyIssue) {
      root.setAttribute(TYPOGRAPHY_ISSUE_ATTRIBUTE, initialTypographyIssue);
      return { matches: false, reason: "SnapshotTypographyMismatch" };
    }
    const fontContract = await validateManifestFontContract(manifest, documentObject);
    if (fontContract.reason) return { matches: false, reason: fontContract.reason };
    if (!isCurrent()) return { matches: false, reason: "superseded" };
    const revalidatedTypographyIssue = fontContractTypographyIssue(root, manifest);
    if (revalidatedTypographyIssue) {
      root.setAttribute(TYPOGRAPHY_ISSUE_ATTRIBUTE, revalidatedTypographyIssue);
      return { matches: false, reason: "SnapshotTypographyChangedDuringValidation" };
    }
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
    const typographyIssue = computedTypographyIssue(
      paragraph,
      entry.typography,
      canonicalPreparedFlow(paragraph),
      liveRenderFontFamilies(root, manifest, paragraph),
    );
    if (typographyIssue) {
      root.setAttribute(TYPOGRAPHY_ISSUE_ATTRIBUTE, typographyIssue);
      return { matches: false, reason: "SnapshotTypographyMismatch" };
    }
  }
  const fontContract = await validateManifestFontContract(manifest, documentObject);
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
  for (const entry of manifest.entries) {
    const paragraph = currentByKey.get(entry.key);
    const source = paragraph == null ? null : plainParagraphSource(paragraph);
    if (source == null || await sha256Text(source) !== entry.sourceSha256) {
      return { matches: false, reason: "SnapshotSourceChangedDuringValidation" };
    }
    const typographyIssue = computedTypographyIssue(
      paragraph,
      entry.typography,
      canonicalPreparedFlow(paragraph),
      liveRenderFontFamilies(root, manifest, paragraph),
    );
    if (typographyIssue) {
      root.setAttribute(TYPOGRAPHY_ISSUE_ATTRIBUTE, typographyIssue);
      return { matches: false, reason: "SnapshotTypographyChangedDuringValidation" };
    }
  }
  if (!isCurrent()) return { matches: false, reason: "superseded" };
  return {
    matches: true,
    reason: null,
    paragraphSelector: manifest.paragraphSelector,
    compatibleLocalDeclared: fontContract.compatibleLocalDeclared,
  };
}

export function isPrecomputedSnapshotAdopted(root) {
  return states.has(root);
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
    return Number.isFinite(width) && Number.isFinite(entry?.maxWidthPx) &&
      Math.abs(width - entry.maxWidthPx) <= WIDTH_TOLERANCE_PX;
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
  }
  if (state.valueStylesInstalled) releasePreparedValueStyleRoot(root);
  if (state.originalExactRenderFontAttribute == null) {
    root.removeAttribute(EXACT_RENDER_FONT_ATTRIBUTE);
  } else {
    root.setAttribute(EXACT_RENDER_FONT_ATTRIBUTE, state.originalExactRenderFontAttribute);
  }
  root.removeAttribute("data-tiqian-enhanced");
  root.removeAttribute("data-tiqian-enhanced-count");
  delete root.dataset.tiqianSnapshot;
  delete root.dataset.tiqianSnapshotFontPolicy;
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
  const prepared = [];
  for (const entry of manifest.entries) {
    if (
      !entry || typeof entry.key !== "string" || typeof entry.sourceSha256 !== "string" ||
      typeof entry.typographySha256 !== "string" ||
      typeof entry.renderArtifactSha256 !== "string" || !entry.typography ||
      await sha256Text(stableStringify(entry.typography)) !== entry.typographySha256
    ) return miss(root, "SnapshotTypographyDigestMismatch");
    const paragraph = byKey.get(entry.key);
    const snapshot = serverRenderedEntries ? paragraph : templateEntry(template, entry.key);
    if (!paragraph || !snapshot) return miss(root, "SnapshotEntryMissing");
    if (!await snapshotArtifactMatches(snapshot, entry.renderArtifactSha256)) {
      return miss(root, "SnapshotArtifactDigestMismatch");
    }
    const source = plainParagraphSource(paragraph);
    if (source == null || await sha256Text(source) !== entry.sourceSha256) {
      return miss(root, "SnapshotSourceMismatch");
    }
    const width = contentBoxWidth(paragraph);
    if (!Number.isFinite(width) || Math.abs(width - entry.maxWidthPx) > WIDTH_TOLERANCE_PX) {
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
    prepared.push({ paragraph, snapshot, entry });
  }

  const fontContract = await validateManifestFontContract(manifest, documentObject);
  if (fontContract.reason) return miss(root, fontContract.reason);
  const compatibleLocalDeclared = fontContract.compatibleLocalDeclared;
  if (!isCurrent()) return { adopted: false, reason: "superseded" };

  // Font loading and probe measurement are asynchronous. The responsive page
  // may have crossed a breakpoint while they ran, before observers are active.
  // Revalidate every live input immediately before the first DOM mutation.
  for (const { paragraph, entry } of prepared) {
    const source = plainParagraphSource(paragraph);
    if (source == null || await sha256Text(source) !== entry.sourceSha256) {
      return miss(root, "SnapshotSourceChangedDuringValidation");
    }
    const width = contentBoxWidth(paragraph);
    if (!Number.isFinite(width) || Math.abs(width - entry.maxWidthPx) > WIDTH_TOLERANCE_PX) {
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
  }
  if (!isCurrent()) return { adopted: false, reason: "superseded" };

  const adopted = [];
  let valueStylesInstalled = false;
  const originalExactRenderFontAttribute = root.getAttribute(EXACT_RENDER_FONT_ATTRIBUTE);
  try {
    valueStylesInstalled = installPreparedValueStyles(
      root,
      manifest.valueStyles,
      manifest.renderFontFamilies,
    );
    for (const { paragraph, snapshot, entry } of prepared) {
      const originalContent = documentObject.createDocumentFragment();
      if (serverRenderedEntries) {
        for (const child of Array.from(paragraph.childNodes)) {
          originalContent.appendChild(child.cloneNode(true));
        }
      } else {
        while (paragraph.firstChild) originalContent.appendChild(paragraph.firstChild);
      }
      const originalRenderedAttribute = paragraph.getAttribute("data-tq-rendered");
      const originalLangAttribute = paragraph.getAttribute("lang");
      const originalCanonicalPlainAttribute = paragraph.getAttribute("data-tq-canonical-plain");
      const originalCanonicalSourceAttribute = paragraph.getAttribute("data-tq-canonical-source");
      adopted.push({
        paragraph,
        originalContent,
        originalRenderedAttribute,
        originalLangAttribute,
        originalCanonicalPlainAttribute,
        originalCanonicalSourceAttribute,
      });
      paragraph.setAttribute("data-tq-rendered", "true");
      paragraph.setAttribute("data-tq-canonical-plain", "true");
      paragraph.setAttribute("data-tq-canonical-source", "true");
      paragraph.setAttribute("lang", entry.typography.locale);
      if (!serverRenderedEntries) {
        const clone = snapshot.cloneNode(true);
        while (clone.firstChild) paragraph.appendChild(clone.firstChild);
      }
    }
    root.setAttribute(EXACT_RENDER_FONT_ATTRIBUTE, "true");
    for (const { paragraph, entry } of prepared) {
      const width = contentBoxWidth(paragraph);
      if (
        !Number.isFinite(width) || Math.abs(width - entry.maxWidthPx) > WIDTH_TOLERANCE_PX ||
        !computedTypographyMatches(paragraph, entry.typography, true, manifest.renderFontFamilies)
      ) throw new Error("RenderedSnapshotHostContractMismatch");
      const issue = renderedPreparedParagraphIssue(paragraph, width);
      if (issue) throw new Error(issue.replace("RenderedPreparedParagraph", "RenderedSnapshot"));
    }
  } catch (error) {
    states.set(root, {
      paragraphs: adopted,
      valueStylesInstalled,
      originalExactRenderFontAttribute,
    });
    restorePrecomputedSnapshot(root);
    return miss(root, `SnapshotAdoptionFailed:${error instanceof Error ? error.message : String(error)}`);
  }
  states.set(root, {
    paragraphs: adopted,
    manifest,
    valueStylesInstalled,
    originalExactRenderFontAttribute,
  });
  root.setAttribute("data-tiqian-enhanced", "true");
  root.setAttribute("data-tiqian-enhanced-count", String(adopted.length));
  root.dataset.tiqianSnapshot = "maximum-measure";
  root.dataset.tiqianSnapshotFontPolicy = compatibleLocalDeclared ? "compatible-local" : "url-only";
  root.removeAttribute(EXACT_LAYOUT_ISSUE_ATTRIBUTE);
  delete root.dataset.tiqianSnapshotMiss;
  return { adopted: true, count: adopted.length };
}
