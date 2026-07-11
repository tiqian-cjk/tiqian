const CJK_DASH_SOURCE = "——";
const TWO_EM_DASH = "⸺";
const EM_DASH = 0x2014;
const TWO_EM_DASH_CODE_POINT = 0x2e3a;
const HAN_CENTER_PROBE = 0x4e00;
const TARGET_ADVANCE_EM = 2;
const ADVANCE_TOLERANCE_EM = 0.08;
const CENTER_TOLERANCE_EM = 0.08;
const VERTICAL_CENTER_TOLERANCE_EM = 0.12;
const MAX_SEAM_GAP_EM = 0.03;
const MIN_INK_COVERAGE = 0.85;

const faceResourcePromiseCache = new Map();
const preparationCache = new Map();
const sessions = new Map();
let backendPromise;
let nextSessionId = 1;

function needsCjkDashShaping(root) {
  const text = root?.textContent ?? "";
  return text.includes(CJK_DASH_SOURCE) || text.includes(TWO_EM_DASH);
}

function dashStyleOwner(root) {
  const paragraphs = root?.querySelectorAll?.("p") ?? [];
  for (const paragraph of paragraphs) {
    const text = paragraph.textContent ?? "";
    if (text.includes(CJK_DASH_SOURCE) || text.includes(TWO_EM_DASH)) return paragraph;
  }
  return root;
}

function loadBackends() {
  backendPromise ??= Promise.all([
    import("harfbuzzjs"),
    import("woff2-encoder/decompress"),
  ]).then(([hb, woff2]) => ({ hb, decompressWoff2: woff2.default }));
  return backendPromise;
}

export function parseFontFamilies(value) {
  const families = [];
  let token = "";
  let quote = "";
  let escaped = false;
  for (const char of String(value ?? "")) {
    if (escaped) {
      token += char;
      escaped = false;
      continue;
    }
    if (char === "\\") {
      token += char;
      escaped = true;
      continue;
    }
    if (quote) {
      if (char === quote) quote = "";
      else token += char;
      continue;
    }
    if (char === "\"" || char === "'") {
      quote = char;
      continue;
    }
    if (char === ",") {
      if (token.trim()) families.push(token.trim());
      token = "";
      continue;
    }
    token += char;
  }
  if (token.trim()) families.push(token.trim());
  return families;
}

export function parseUnicodeRange(value) {
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

export function unicodeRangeContains(ranges, codePoint) {
  return ranges == null || ranges.some(([start, end]) => codePoint >= start && codePoint <= end);
}

function unquote(value) {
  const trimmed = String(value ?? "").trim();
  if (
    trimmed.length >= 2 &&
    ((trimmed.startsWith("\"") && trimmed.endsWith("\"")) ||
      (trimmed.startsWith("'") && trimmed.endsWith("'")))
  ) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

function cssFamilyToken(family) {
  return `"${family.replaceAll("\\", "\\\\").replaceAll("\"", "\\\"")}"`;
}

function parseSourceUrls(value, baseUrl) {
  const urls = [];
  const expression = /url\(\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)'|([^)]*?))\s*\)/giu;
  for (const match of String(value ?? "").matchAll(expression)) {
    const serialized = (match[1] ?? match[2] ?? match[3] ?? "").trim();
    if (!serialized) continue;
    const unescaped = serialized.replace(/\\([\\"'])/gu, "$1");
    try {
      urls.push(new URL(unescaped, baseUrl).href);
    } catch {
      // A malformed source is not a usable, verifiable font source.
    }
  }
  return urls;
}

function numericFontWeight(value) {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (normalized === "normal") return 400;
  if (normalized === "bold") return 700;
  const parsed = Number.parseFloat(normalized);
  return Number.isFinite(parsed) ? parsed : 400;
}

function fontWeightMatches(descriptor, requested) {
  const values = String(descriptor || "normal")
    .trim()
    .split(/\s+/u)
    .map(numericFontWeight);
  const low = Math.min(...values);
  const high = Math.max(...values);
  return requested >= low && requested <= high;
}

function fontStyleMatches(descriptor, requested) {
  const available = String(descriptor || "normal").trim().toLowerCase();
  const desired = String(requested || "normal").trim().toLowerCase();
  if (desired.startsWith("italic")) return available.startsWith("italic");
  if (desired.startsWith("oblique")) return available.startsWith("oblique");
  return available === "normal";
}

function collectFontFaceRules(documentObject) {
  const faces = [];
  const visit = (rules, fallbackBaseUrl) => {
    if (!rules) return;
    for (const rule of rules) {
      if (rule.type === 5 && rule.style) {
        const style = rule.style;
        const baseUrl = rule.parentStyleSheet?.href || fallbackBaseUrl;
        const family = unquote(style.getPropertyValue("font-family"));
        const urls = parseSourceUrls(style.getPropertyValue("src"), baseUrl);
        if (!family || urls.length === 0) continue;
        faces.push({
          family,
          cssFamily: cssFamilyToken(family),
          style: style.getPropertyValue("font-style") || "normal",
          weight: style.getPropertyValue("font-weight") || "normal",
          stretch: style.getPropertyValue("font-stretch") || "normal",
          unicodeRanges: parseUnicodeRange(style.getPropertyValue("unicode-range")),
          urls,
        });
        continue;
      }
      try {
        if (rule.cssRules) visit(rule.cssRules, rule.parentStyleSheet?.href || fallbackBaseUrl);
      } catch {
        // Cross-origin nested stylesheets cannot be inspected and are reported below.
      }
    }
  };

  for (const sheet of documentObject.styleSheets ?? []) {
    try {
      visit(sheet.cssRules, sheet.href || documentObject.baseURI);
    } catch {
      // A host may explicitly provide a same-origin fallback face later in the stack.
    }
  }
  return faces;
}

function selectFace(faces, family, codePoint, fontWeight, fontStyle) {
  return faces.find(
    (face) =>
      face.family === family &&
      fontWeightMatches(face.weight, fontWeight) &&
      fontStyleMatches(face.style, fontStyle) &&
      unicodeRangeContains(face.unicodeRanges, codePoint),
  );
}

function isWoff2(bytes) {
  return bytes.length >= 4 && bytes[0] === 0x77 && bytes[1] === 0x4f && bytes[2] === 0x46 && bytes[3] === 0x32;
}

async function loadFaceResource(sourceUrl) {
  let promise = faceResourcePromiseCache.get(sourceUrl);
  if (promise) return promise;
  promise = (async () => {
    const response = await fetch(sourceUrl, { credentials: "same-origin" });
    if (!response.ok) throw new Error(`FontSourceFetchFailed:${response.status}:${sourceUrl}`);
    const downloaded = new Uint8Array(await response.arrayBuffer());
    const { hb, decompressWoff2 } = await loadBackends();
    const sfnt = isWoff2(downloaded) ? await decompressWoff2(downloaded) : downloaded;
    const bytes = sfnt instanceof Uint8Array ? sfnt : new Uint8Array(sfnt);
    const data = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    const blob = new hb.Blob(data);
    const face = new hb.Face(blob, 0);
    if (!Number.isFinite(face.upem) || face.upem <= 0) {
      throw new Error(`InvalidOpenTypeFace:${sourceUrl}`);
    }
    return {
      hb,
      blob,
      face,
      sourceUrl,
    };
  })();
  faceResourcePromiseCache.set(sourceUrl, promise);
  promise.catch(() => {
    if (faceResourcePromiseCache.get(sourceUrl) === promise) {
      faceResourcePromiseCache.delete(sourceUrl);
    }
  });
  return promise;
}

async function loadFace(faceSpec) {
  const failures = [];
  for (const sourceUrl of faceSpec.urls) {
    try {
      const resource = await loadFaceResource(sourceUrl);
      return {
        ...resource,
        spec: faceSpec,
        faceId: `${faceSpec.family}|${faceSpec.style}|${faceSpec.weight}|${faceSpec.stretch}|${sourceUrl}`,
      };
    } catch (error) {
      failures.push(error instanceof Error ? error.message : String(error));
    }
  }
  throw new Error(failures.join(" | ") || `FontSourceFetchFailed:${faceSpec.family}`);
}

function createFont(record, requestedWeight) {
  const { hb, face } = record;
  const font = new hb.Font(face);
  font.setScale(face.upem, face.upem);
  const weightAxis = face.getAxisInfos().wght;
  if (weightAxis) {
    const weight = Math.max(weightAxis.min, Math.min(weightAxis.max, requestedWeight));
    const variation = hb.Variation.fromString(`wght=${weight}`);
    if (variation) font.setVariations([variation]);
  }
  return font;
}

function shapeWithRecord(record, text, requestedWeight, disableLocl = false) {
  const { hb, face } = record;
  const font = createFont(record, requestedWeight);
  const buffer = new hb.Buffer();
  buffer.addText(text);
  buffer.guessSegmentProperties();
  buffer.setDirection(hb.Direction.LTR);
  buffer.setScript("Hani");
  buffer.setLanguage("zh-Hans");
  const features = disableLocl ? [hb.Feature.fromString("locl=0")].filter(Boolean) : undefined;
  hb.shape(font, buffer, features);

  let cursorX = 0;
  const glyphs = buffer.getGlyphInfosAndPositions().map((glyph) => {
    const extents = font.glyphExtents(glyph.codepoint);
    const originX = cursorX + glyph.xOffset;
    const bounds = extents
      ? {
          left: extents.xBearing / face.upem,
          top: -extents.yBearing / face.upem,
          right: (extents.xBearing + extents.width) / face.upem,
          bottom: -(extents.yBearing + extents.height) / face.upem,
        }
      : null;
    const result = {
      id: glyph.codepoint,
      cluster: glyph.cluster,
      advance: glyph.xAdvance / face.upem,
      x: originX / face.upem,
      y: -glyph.yOffset / face.upem,
      bounds,
      positionedBounds: bounds
        ? {
            left: bounds.left + originX / face.upem,
            top: bounds.top - glyph.yOffset / face.upem,
            right: bounds.right + originX / face.upem,
            bottom: bounds.bottom - glyph.yOffset / face.upem,
          }
        : null,
    };
    cursorX += glyph.xAdvance;
    return result;
  });

  const bounded = glyphs.filter((glyph) => glyph.positionedBounds);
  const ink = bounded.length
    ? {
        left: Math.min(...bounded.map((glyph) => glyph.positionedBounds.left)),
        top: Math.min(...bounded.map((glyph) => glyph.positionedBounds.top)),
        right: Math.max(...bounded.map((glyph) => glyph.positionedBounds.right)),
        bottom: Math.max(...bounded.map((glyph) => glyph.positionedBounds.bottom)),
      }
    : null;
  return {
    font,
    glyphs,
    advance: cursorX / face.upem,
    ink,
    missingGlyphs: glyphs.filter((glyph) => glyph.id === 0).length,
  };
}

function shapingSignature(shaped) {
  return shaped.glyphs
    .map((glyph) => [glyph.id, glyph.advance, glyph.x, glyph.y].map((value) => Number(value).toFixed(5)).join(":"))
    .join("|");
}

export function evaluateDashGeometry(shaped, hanShaped, strategy) {
  const failures = [];
  const advanceError = Math.abs(shaped.advance - TARGET_ADVANCE_EM);
  if (advanceError > ADVANCE_TOLERANCE_EM) failures.push(`advance-error=${advanceError.toFixed(4)}em`);
  if (shaped.missingGlyphs > 0) failures.push(`missing-glyphs=${shaped.missingGlyphs}`);
  if (!shaped.ink) failures.push("missing-dash-ink-bounds");
  if (!hanShaped.ink) failures.push("missing-han-center-probe");

  const inkWidth = shaped.ink ? shaped.ink.right - shaped.ink.left : 0;
  const inkCoverage = inkWidth / TARGET_ADVANCE_EM;
  if (shaped.ink && inkCoverage < MIN_INK_COVERAGE) {
    failures.push(`ink-coverage=${inkCoverage.toFixed(4)}`);
  }
  const horizontalCenterDelta = shaped.ink
    ? (shaped.ink.left + shaped.ink.right) / 2 - TARGET_ADVANCE_EM / 2
    : Number.NaN;
  if (Number.isFinite(horizontalCenterDelta) && Math.abs(horizontalCenterDelta) > CENTER_TOLERANCE_EM) {
    failures.push(`horizontal-center-delta=${horizontalCenterDelta.toFixed(4)}em`);
  }
  const dashVerticalCenter = shaped.ink ? (shaped.ink.top + shaped.ink.bottom) / 2 : Number.NaN;
  const hanVerticalCenter = hanShaped.ink ? (hanShaped.ink.top + hanShaped.ink.bottom) / 2 : Number.NaN;
  const verticalCenterDelta = dashVerticalCenter - hanVerticalCenter;
  if (Number.isFinite(verticalCenterDelta) && Math.abs(verticalCenterDelta) > VERTICAL_CENTER_TOLERANCE_EM) {
    failures.push(`vertical-center-delta=${verticalCenterDelta.toFixed(4)}em`);
  }

  let seamGap = null;
  if (strategy === "PairedEmDash") {
    if (shaped.glyphs.length !== 2) failures.push(`paired-glyph-count=${shaped.glyphs.length}`);
    const first = shaped.glyphs[0]?.positionedBounds;
    const second = shaped.glyphs[1]?.positionedBounds;
    if (first && second) {
      seamGap = second.left - first.right;
      if (seamGap > MAX_SEAM_GAP_EM) failures.push(`seam-gap=${seamGap.toFixed(4)}em`);
      const verticalOverlap = Math.min(first.bottom, second.bottom) - Math.max(first.top, second.top);
      if (verticalOverlap <= 0) failures.push(`seam-vertical-overlap=${verticalOverlap.toFixed(4)}em`);
    }
    for (const glyph of shaped.glyphs) {
      if (Math.abs(glyph.advance - 1) > ADVANCE_TOLERANCE_EM) {
        failures.push(`paired-glyph-advance=${glyph.advance.toFixed(4)}em`);
      }
    }
  }

  return {
    conforms: failures.length === 0,
    failures,
    advanceEm: shaped.advance,
    inkWidthEm: inkWidth,
    inkCoverage,
    horizontalCenterDeltaEm: horizontalCenterDelta,
    verticalCenterDeltaEm: verticalCenterDelta,
    seamGapEm: seamGap,
  };
}

async function evaluateCandidate(dashRecord, hanRecord, strategy, displayText, requestedWeight) {
  const shaped = shapeWithRecord(dashRecord, displayText, requestedWeight);
  const withoutLocl = shapeWithRecord(dashRecord, displayText, requestedWeight, true);
  const hanShaped = shapeWithRecord(hanRecord, "一", requestedWeight);
  const geometry = evaluateDashGeometry(shaped, hanShaped, strategy);
  return {
    strategy,
    displayText,
    record: dashRecord,
    hanRecord,
    requestedWeight,
    geometry,
    loclEvidence:
      shapingSignature(shaped) === shapingSignature(withoutLocl)
        ? "DefaultCjkConforming"
        : "LocalizedVariant",
  };
}

function capabilityDetail(candidate) {
  const geometry = candidate.geometry;
  return [
    `strategy=${candidate.strategy}`,
    `face=${candidate.record.faceId}`,
    `advance=${geometry.advanceEm.toFixed(4)}em`,
    `inkCoverage=${geometry.inkCoverage.toFixed(4)}`,
    `centerX=${geometry.horizontalCenterDeltaEm.toFixed(4)}em`,
    `centerY=${geometry.verticalCenterDeltaEm.toFixed(4)}em`,
    `seam=${geometry.seamGapEm == null ? "n/a" : `${geometry.seamGapEm.toFixed(4)}em`}`,
    `locl=${candidate.loclEvidence}`,
  ].join("; ");
}

async function prepareCandidate(faces, family, codePoint, strategy, displayText, fontWeight, fontStyle) {
  const dashSpec = selectFace(faces, family, codePoint, fontWeight, fontStyle);
  const hanSpec = selectFace(faces, family, HAN_CENTER_PROBE, fontWeight, fontStyle);
  if (!dashSpec || !hanSpec) return null;
  const [dashRecord, hanRecord] = await Promise.all([loadFace(dashSpec), loadFace(hanSpec)]);
  return evaluateCandidate(dashRecord, hanRecord, strategy, displayText, fontWeight);
}

async function prepare(root, options, faces, styleOwner) {
  const computed = getComputedStyle(styleOwner);
  const fontFamily = options?.cjkFontFamily || computed.fontFamily;
  const fontWeight = numericFontWeight(options?.fontWeight || computed.fontWeight);
  const fontStyle = options?.fontStyle || computed.fontStyle || "normal";
  const families = parseFontFamilies(fontFamily);
  const diagnostics = [];

  for (const family of families) {
    for (const definition of [
      { codePoint: TWO_EM_DASH_CODE_POINT, strategy: "TwoEmDash", text: TWO_EM_DASH },
      { codePoint: EM_DASH, strategy: "PairedEmDash", text: CJK_DASH_SOURCE },
    ]) {
      try {
        const candidate = await prepareCandidate(
          faces,
          family,
          definition.codePoint,
          definition.strategy,
          definition.text,
          fontWeight,
          fontStyle,
        );
        if (!candidate) {
          diagnostics.push(`${family}:${definition.strategy}:no-verifiable-css-font-face`);
          continue;
        }
        if (!candidate.geometry.conforms) {
          diagnostics.push(`${family}:${definition.strategy}:${candidate.geometry.failures.join(",")}`);
          continue;
        }
        const sessionId = `tq-dash-${nextSessionId++}`;
        sessions.set(sessionId, candidate);
        return {
          status: "conforming",
          sessionId,
          strategy: candidate.strategy,
          displayText: candidate.displayText,
          cssFontFamily: candidate.record.spec.cssFamily,
          faceId: candidate.record.faceId,
          sourceUrl: candidate.record.sourceUrl,
          script: "Hani",
          language: "zh-Hans",
          loclEvidence: candidate.loclEvidence,
          detail: capabilityDetail(candidate),
        };
      } catch (error) {
        diagnostics.push(`${family}:${definition.strategy}:${error instanceof Error ? error.message : String(error)}`);
      }
    }
  }

  return {
    status: "unavailable",
    issue: "NoConformingCjkDashGlyph",
    detail: diagnostics.join(" | ") || "no inspectable CSS @font-face matched the computed CJK stack",
  };
}

export async function prepareCjkDashShaping(root, options = {}) {
  if (!root || !needsCjkDashShaping(root)) return { status: "not-needed" };
  const styleOwner = dashStyleOwner(root);
  const computed = getComputedStyle(styleOwner);
  const faces = collectFontFaceRules(root.ownerDocument || document);
  const faceSignature = faces
    .map((face) => [
      face.family,
      face.style,
      face.weight,
      face.stretch,
      JSON.stringify(face.unicodeRanges),
      face.urls.join(","),
    ].join("\u001e"))
    .join("\u001d");
  const key = [
    options.cjkFontFamily || computed.fontFamily,
    options.fontWeight || computed.fontWeight,
    options.fontStyle || computed.fontStyle,
    faceSignature,
  ].join("\u001f");
  let promise = preparationCache.get(key);
  if (!promise) {
    promise = prepare(root, options, faces, styleOwner);
    preparationCache.set(key, promise);
    promise.then(
      (capability) => {
        if (capability.status !== "conforming" && preparationCache.get(key) === promise) {
          preparationCache.delete(key);
        }
      },
      () => {
        if (preparationCache.get(key) === promise) preparationCache.delete(key);
      },
    );
  }
  return promise;
}

function shapePreparedCjkDash(sessionId, fontSize, fontWeight, italic = false) {
  const candidate = sessions.get(sessionId);
  if (!candidate) {
    return {
      status: "unavailable",
      issue: "NoConformingCjkDashGlyph",
      detail: `unknown dash shaping session: ${sessionId}`,
    };
  }
  const requestedStyle = italic ? "italic" : "normal";
  const specs = [candidate.record.spec, candidate.hanRecord.spec];
  if (
    specs.some(
      (spec) =>
        !fontWeightMatches(spec.weight, fontWeight) ||
        !fontStyleMatches(spec.style, requestedStyle),
    )
  ) {
    return {
      status: "unavailable",
      issue: "NoConformingCjkDashGlyph",
      detail: `prepared face does not cover requested weight/style: ${fontWeight}/${requestedStyle}`,
    };
  }
  const shaped = shapeWithRecord(candidate.record, candidate.displayText, fontWeight);
  const hanShaped = shapeWithRecord(candidate.hanRecord, "一", fontWeight);
  const geometry = evaluateDashGeometry(shaped, hanShaped, candidate.strategy);
  if (!geometry.conforms) {
    return {
      status: "unavailable",
      issue: "NoConformingCjkDashGlyph",
      detail: geometry.failures.join(","),
    };
  }
  const scale = Number(fontSize);
  return {
    status: "conforming",
    strategy: candidate.strategy,
    displayText: candidate.displayText,
    cssFontFamily: candidate.record.spec.cssFamily,
    faceId: candidate.record.faceId,
    sourceUrl: candidate.record.sourceUrl,
    script: "Hani",
    language: "zh-Hans",
    loclEvidence: candidate.loclEvidence,
    advance: shaped.advance * scale,
    inkCoverage: geometry.inkCoverage,
    horizontalCenterDelta: geometry.horizontalCenterDeltaEm * scale,
    verticalCenterDelta: geometry.verticalCenterDeltaEm * scale,
    seamGap: geometry.seamGapEm == null ? Number.NaN : geometry.seamGapEm * scale,
    glyphs: shaped.glyphs.map((glyph) => ({
      id: glyph.id,
      advance: glyph.advance * scale,
      x: glyph.x * scale,
      y: glyph.y * scale,
      bounds: glyph.bounds
        ? {
            left: glyph.bounds.left * scale,
            top: glyph.bounds.top * scale,
            right: glyph.bounds.right * scale,
            bottom: glyph.bounds.bottom * scale,
          }
        : null,
    })),
  };
}

globalThis.__TiqianWebFontShaping = {
  ...(globalThis.__TiqianWebFontShaping ?? {}),
  shapeCjkDash: shapePreparedCjkDash,
};
