import { FONT_BACKEND_REVISION } from "./snapshot-schema.js";

const FAMILY_SEPARATOR = "\u001f";
export { FONT_BACKEND_REVISION };
const BACKEND_REVISION = FONT_BACKEND_REVISION;
const LOCAL_FONT_NAME_IDS = new Set([1, 4, 6, 16, 21]);
const REGISTRY_KEY = Symbol.for(`org.tiqian.web.fonts.${BACKEND_REVISION}`);
const registry = globalThis[REGISTRY_KEY] ??= {
  sessions: new Map(),
  shapeResults: new Map(),
  metricResults: new Map(),
  nextSessionId: 1,
  nextResultId: 1,
};
const { sessions, shapeResults, metricResults } = registry;
let backendPromise;

function loadBackends() {
  backendPromise ??= Promise.all([
    import("harfbuzzjs"),
    import("woff2-encoder/decompress"),
  ]).then(([hb, woff2]) => ({ hb, decompressWoff2: woff2.default }));
  return backendPromise;
}

export async function sha256(bytes) {
  const subtle = globalThis.crypto?.subtle;
  if (!subtle) throw new Error("WebCryptoUnavailable");
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  const digest = await subtle.digest("SHA-256", view);
  return Array.from(new Uint8Array(digest), (value) => value.toString(16).padStart(2, "0")).join("");
}

function isWoff2(bytes) {
  return bytes.length >= 4 &&
    bytes[0] === 0x77 && bytes[1] === 0x4f && bytes[2] === 0x46 && bytes[3] === 0x32;
}

function isFontCollection(bytes) {
  return bytes.length >= 4 &&
    bytes[0] === 0x74 && bytes[1] === 0x74 && bytes[2] === 0x63 && bytes[3] === 0x66;
}

function normalizeStyle(value) {
  const normalized = String(value ?? "normal").trim().toLowerCase();
  if (normalized.startsWith("italic")) return "italic";
  if (normalized.startsWith("oblique")) return "oblique";
  return "normal";
}

function normalizeWeight(value) {
  if (Array.isArray(value) && value.length === 2) {
    const low = Number(value[0]);
    const high = Number(value[1]);
    if (Number.isFinite(low) && Number.isFinite(high) && low > 0 && high >= low) {
      return [low, high];
    }
  }
  const weight = Number(value ?? 400);
  if (!Number.isFinite(weight) || weight <= 0) throw new Error("InvalidFontFaceWeight");
  return [weight, weight];
}

function faceLocalNames(face) {
  const names = new Set();
  for (const entry of face.listNames()) {
    if (!LOCAL_FONT_NAME_IDS.has(entry.nameId)) continue;
    const name = face.getName(entry.nameId, entry.language)?.trim();
    if (name) names.add(name);
  }
  return Array.from(names).sort();
}

/** CSS Fonts weight matching rank for one face descriptor range. */
export function cssWeightPreference(range, requested) {
  const low = Number(range?.[0]);
  const high = Number(range?.[1]);
  if (!Number.isFinite(low) || !Number.isFinite(high) || high < low) {
    return [Number.POSITIVE_INFINITY, Number.POSITIVE_INFINITY];
  }
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

function cssWeightMatched(records, requested, rangeOf) {
  if (records.length <= 1) return records;
  const ranked = records.map((record) => ({
    record,
    rank: cssWeightPreference(rangeOf(record), requested),
  }));
  ranked.sort((left, right) =>
    left.rank[0] - right.rank[0] || left.rank[1] - right.rank[1]);
  const best = ranked[0].rank;
  return ranked.filter(({ rank }) => rank[0] === best[0] && rank[1] === best[1])
    .map(({ record }) => record);
}

function orderedFaceSpecs(faceSpecs) {
  const seen = new Set();
  return faceSpecs.map((spec, inputOrder) => {
    const sourceOrder = spec?.sourceOrder ?? inputOrder;
    if (!Number.isSafeInteger(sourceOrder) || sourceOrder < 0) {
      throw new Error(`InvalidFontFaceSourceOrder:${inputOrder}:${sourceOrder}`);
    }
    if (seen.has(sourceOrder)) {
      throw new Error(`DuplicateFontFaceSourceOrder:${sourceOrder}`);
    }
    seen.add(sourceOrder);
    return { ...spec, sourceOrder, inputOrder };
  }).sort((left, right) =>
    left.sourceOrder - right.sourceOrder || left.inputOrder - right.inputOrder);
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

function unicodeRangeContains(ranges, codePoint) {
  return ranges == null || ranges.some(([start, end]) => codePoint >= start && codePoint <= end);
}

function isContentAddressedUrl(value) {
  try {
    const pathname = new URL(value, "https://tiqian.invalid/").pathname;
    return /(?:^|[._/-])[a-f0-9]{8,}(?=[._/-]|$)/iu.test(pathname);
  } catch {
    return false;
  }
}

function sourceBytes(source) {
  if (source instanceof Uint8Array) return source;
  if (source instanceof ArrayBuffer) return new Uint8Array(source);
  throw new Error("UnsupportedFontSource");
}

function u16(bytes, offset) {
  return (bytes[offset] << 8) | bytes[offset + 1];
}

function s16(bytes, offset) {
  const value = u16(bytes, offset);
  return value & 0x8000 ? value - 0x10000 : value;
}

function baseIdeoIdtp(bytes) {
  if (!bytes || bytes.length < 6) return [null, null, false];
  try {
    const axis = u16(bytes, 4);
    if (axis === 0) return [null, null, false];
    const tagList = axis + u16(bytes, axis);
    const scriptList = axis + u16(bytes, axis + 2);
    const tagCount = u16(bytes, tagList);
    const tags = [];
    for (let index = 0; index < tagCount; index += 1) {
      tags.push(String.fromCharCode(...bytes.slice(tagList + 2 + index * 4, tagList + 6 + index * 4)));
    }
    const scriptCount = u16(bytes, scriptList);
    if (scriptCount === 0) return [null, null, false];
    const scripts = [];
    for (let index = 0; index < scriptCount; index += 1) {
      const record = scriptList + 2 + index * 6;
      scripts.push({
        tag: String.fromCharCode(...bytes.slice(record, record + 4)),
        offset: u16(bytes, record + 4),
      });
    }
    const selected = scripts.find(({ tag }) => tag === "hani") ??
      scripts.find(({ tag }) => tag === "DFLT") ?? scripts[0];
    const script = scriptList + selected.offset;
    const baseValuesOffset = u16(bytes, script);
    if (baseValuesOffset === 0) return [null, null, false];
    const baseValues = script + baseValuesOffset;
    const coordCount = u16(bytes, baseValues + 2);
    let hasVariationIndex = false;
    const coord = (tag) => {
      const index = tags.indexOf(tag);
      if (index < 0 || index >= coordCount) return null;
      const coordinateOffset = u16(bytes, baseValues + 4 + index * 2);
      if (coordinateOffset === 0) return null;
      const coordinate = baseValues + coordinateOffset;
      if (u16(bytes, coordinate) === 3) hasVariationIndex = true;
      return s16(bytes, coordinate + 2);
    };
    const ideo = coord("ideo");
    const idtp = coord("idtp");
    return [ideo, idtp, hasVariationIndex];
  } catch {
    return [null, null, false];
  }
}

function tableMetrics(face) {
  const os2 = face.referenceTable("OS/2");
  const typoAscender = os2 && os2.length >= 72 ? s16(os2, 68) : null;
  const typoDescender = os2 && os2.length >= 72 ? s16(os2, 70) : null;
  const [ideo, idtp, baseHasVariationIndex] = baseIdeoIdtp(face.referenceTable("BASE"));
  return {
    typoAscender: idtp ?? typoAscender,
    typoDescender: ideo ?? typoDescender,
    baseIdeo: ideo,
    baseIdtp: idtp,
    baseHasVariationIndex,
  };
}

function createFont(record, requestedWeight) {
  const font = new record.hb.Font(record.face);
  font.setScale(record.face.upem, record.face.upem);
  const variations = [];
  const weightAxis = record.axisInfos.wght;
  if (weightAxis) {
    const weight = Math.max(weightAxis.min, Math.min(weightAxis.max, requestedWeight));
    const variation = record.hb.Variation.fromString(`wght=${weight}`);
    if (variation) variations.push(variation);
  }
  if (variations.length > 0) font.setVariations(variations);
  return font;
}

function codePoints(value) {
  return Array.from(value, (point) => point.codePointAt(0));
}

function faceCovers(record, points) {
  if (!points.every((point) => unicodeRangeContains(record.unicodeRanges, point))) return false;
  const font = createFont(record, record.weightRange[0]);
  return points.every((point) => font.nominalGlyph(point) != null);
}

/**
 * A build/session family is allowed to be an internal CSS alias while the
 * paragraph keeps the host's original family name. The alias is evidence for
 * exact URL bytes; OpenType name-table entries are the authoritative bridge
 * back to the host family. This keeps measurement deterministic without
 * rewriting the host's computed font-family or disabling its local() path.
 */
export function fontRecordMatchesFamily(record, requestedFamily) {
  const requested = String(requestedFamily ?? "").trim().toLowerCase();
  if (!requested) return false;
  return record.family.toLowerCase() === requested ||
    record.localNames.some((name) => name.trim().toLowerCase() === requested);
}

/**
 * ExactRenderFontFamilyProjection: translate the host-facing family stack to
 * the CSS aliases backed by the exact font bytes in this session. The order is
 * inherited from the host stack; source order only orders faces within one
 * family and never becomes an accidental fallback policy.
 */
function renderFamiliesFor(session, requestedFamilies) {
  const result = [];
  const seen = new Set();
  for (const requestedFamily of requestedFamilies ?? []) {
    for (const record of session.records) {
      if (!fontRecordMatchesFamily(record, requestedFamily)) continue;
      const canonical = record.family.trim().toLowerCase();
      if (seen.has(canonical)) continue;
      seen.add(canonical);
      result.push(record.family);
    }
  }
  if (result.length === 0) {
    throw new Error(`NoExactRenderFontFamily:families=${Array.from(requestedFamilies ?? []).join(",")}`);
  }
  return Object.freeze(result);
}

/** ExactSubsetCoverageBoundary: split shaping runs when CSS unicode-range selects another face. */
function sourceBoundariesFor(session, textValue, baseStyle, textSpans = []) {
  const text = String(textValue);
  const spans = Array.from(textSpans ?? []);
  const boundaries = [];
  let offset = 0;
  let previousSignature = null;
  for (const point of text) {
    const style = [...spans].reverse().find((span) =>
      offset >= span.start && offset < span.end) ?? baseStyle;
    const record = selectFace(
      session,
      style.fontFamilies,
      style.fontWeight,
      style.italic,
      point,
    );
    const signature = [
      record.faceId,
      style.fontFamilies.join(FAMILY_SEPARATOR),
      style.fontSizePx,
      style.fontWeight,
      style.italic,
      style.baselineShiftPx ?? 0,
    ].join("|");
    if (previousSignature != null && signature !== previousSignature) boundaries.push(offset);
    previousSignature = signature;
    offset += point.length;
  }
  return boundaries;
}

function faceCandidates(session, families, requestedWeight, italic) {
  const desiredStyle = italic ? "italic" : "normal";
  for (const family of families) {
    const familyMatches = session.records.filter((record) =>
      fontRecordMatchesFamily(record, family) &&
      record.style === desiredStyle);
    const matches = cssWeightMatched(familyMatches, requestedWeight, (record) => record.weightRange);
    if (matches.length > 0) return matches;
  }
  return [];
}

function findFace(session, families, requestedWeight, italic, text) {
  const points = codePoints(text);
  const desiredStyle = italic ? "italic" : "normal";
  for (const family of families) {
    const familyMatches = session.records.filter((record) =>
      fontRecordMatchesFamily(record, family) && record.style === desiredStyle);
    const weightMatched = cssWeightMatched(
      familyMatches,
      requestedWeight,
      (record) => record.weightRange,
    );
    for (const record of weightMatched) if (faceCovers(record, points)) return record;
  }
  return null;
}

function selectFace(session, families, requestedWeight, italic, text) {
  const record = findFace(session, families, requestedWeight, italic, text);
  if (record) return record;
  throw new Error(
    `NoExactFontFace:families=${families.join(",")};weight=${requestedWeight};italic=${italic};text=${JSON.stringify(text)}`,
  );
}

/**
 * ExactDisplaySubstitutionCoverage: a display-only substitution may probe a
 * codepoint that the source face does not expose. Keep that failure inside the
 * exact session so the common layout engine can observe a missing glyph and
 * apply ADR 0003's source-text rollback instead of abandoning exact layout for
 * the whole paragraph.
 */
export function selectShapeFace(
  session,
  families,
  requestedWeight,
  italic,
  displayText,
  sourceText = displayText,
) {
  const displayRecord = findFace(session, families, requestedWeight, italic, displayText);
  if (displayRecord) return Object.freeze({ record: displayRecord, displayCovered: true });
  if (sourceText !== displayText) {
    const sourceRecord = findFace(session, families, requestedWeight, italic, sourceText);
    if (sourceRecord) return Object.freeze({ record: sourceRecord, displayCovered: false });
  }
  return Object.freeze({
    record: selectFace(session, families, requestedWeight, italic, displayText),
    displayCovered: true,
  });
}

function scriptForText(text) {
  const isHan = (point) =>
    point >= 0x2e80 && point <= 0x2fdf ||
    point === 0x3005 || point === 0x3007 ||
    point >= 0x3021 && point <= 0x3029 ||
    point >= 0x3038 && point <= 0x303b ||
    point >= 0x31c0 && point <= 0x31ef ||
    point >= 0x3400 && point <= 0x4dbf ||
    point >= 0x4e00 && point <= 0x9fff ||
    point >= 0xf900 && point <= 0xfaff ||
    point >= 0x16fe2 && point <= 0x16fe3 ||
    point >= 0x20000 && point <= 0x2ee5f ||
    point >= 0x2f800 && point <= 0x2fa1f ||
    point >= 0x30000 && point <= 0x323af;
  if (Array.from(text).some((point) => isHan(point.codePointAt(0)))) return "Hani";
  if (/[A-Za-z\u00C0-\u024F]/u.test(text)) return "Latn";
  return "Zyyy";
}

const SHARED_CURLY_QUOTE = /[\u2018-\u201d]/u;
const LATIN_CONTEXT_PROPORTIONAL_FEATURES = Object.freeze(["pwid", "palt"]);
const NO_SHAPING_FEATURES = Object.freeze([]);

/**
 * ContextualSharedQuoteShaping: the common layout pipeline resolves the quote
 * role; the exact backend turns that decision into a script and a replayable
 * feature set. `pwid` selects the Western proportional form while `palt`
 * covers fonts that expose only proportional alternate metrics.
 */
export function shapingPolicyForRole(role, displayText) {
  const normalizedRole = String(role ?? "");
  if (normalizedRole === "LatinText") {
    return Object.freeze({
      script: "Latn",
      features: SHARED_CURLY_QUOTE.test(displayText)
        ? LATIN_CONTEXT_PROPORTIONAL_FEATURES
        : NO_SHAPING_FEATURES,
    });
  }
  if (normalizedRole === "CjkText" || normalizedRole === "CjkPunctuation") {
    return Object.freeze({ script: "Hani", features: NO_SHAPING_FEATURES });
  }
  return Object.freeze({ script: scriptForText(displayText), features: NO_SHAPING_FEATURES });
}

function shapeRecord(record, displayText, fontSize, fontWeight, locale, role) {
  const font = createFont(record, fontWeight);
  const buffer = new record.hb.Buffer();
  buffer.addText(displayText);
  buffer.guessSegmentProperties();
  buffer.setDirection(record.hb.Direction.LTR);
  buffer.setLanguage(locale);
  const policy = shapingPolicyForRole(role, displayText);
  const script = policy.script;
  buffer.setScript(script);
  const features = policy.features
    .map((tag) => record.hb.Feature.fromString(`${tag}=1`))
    .filter(Boolean);
  record.hb.shape(font, buffer, features);

  const scale = fontSize / record.face.upem;
  let cursorX = 0;
  const glyphs = buffer.getGlyphInfosAndPositions().map((glyph) => {
    const extents = font.glyphExtents(glyph.codepoint);
    const originX = cursorX + (glyph.xOffset ?? 0);
    const bounds = extents ? [
      extents.xBearing * scale,
      -extents.yBearing * scale,
      (extents.xBearing + extents.width) * scale,
      -(extents.yBearing + extents.height) * scale,
    ] : null;
    const result = {
      id: glyph.codepoint,
      cluster: glyph.cluster,
      flags: glyph.flags ?? 0,
      advance: (glyph.xAdvance ?? 0) * scale,
      x: originX * scale,
      y: -(glyph.yOffset ?? 0) * scale,
      bounds,
    };
    cursorX += glyph.xAdvance ?? 0;
    return result;
  });
  return {
    record,
    fontWeight,
    fontSize,
    locale,
    role,
    script,
    features: policy.features,
    displayText,
    glyphs,
    advance: cursorX * scale,
    unsafeBreakCount: glyphs.filter((glyph) =>
      (glyph.flags & record.hb.GlyphFlag.UNSAFE_TO_BREAK) !== 0).length,
  };
}

function normalizedMetrics(record, fontWeight) {
  const font = createFont(record, fontWeight);
  const h = font.hExtents();
  const upem = record.face.upem;
  return [
    h.ascender / upem,
    -h.descender / upem,
    h.lineGap / upem,
    record.tableMetrics.typoAscender == null ? Number.NaN : record.tableMetrics.typoAscender / upem,
    record.tableMetrics.typoDescender == null ? Number.NaN : -record.tableMetrics.typoDescender / upem,
  ];
}

function metricsEqual(left, right) {
  return left.every((value, index) =>
    Number.isNaN(value) && Number.isNaN(right[index]) || Math.abs(value - right[index]) <= 1e-6);
}

function metricsFor(session, families, fontSize, fontWeight, italic, faceSelectionText) {
  const selected = faceSelectionText
    ? selectFace(session, families, fontWeight, italic, faceSelectionText)
    : faceCandidates(session, families, fontWeight, italic)[0];
  if (!selected) {
    throw new Error(`NoExactMetricFace:families=${families.join(",")};weight=${fontWeight};italic=${italic}`);
  }
  const cacheKey = `${selected.family}|${selected.style}|${fontWeight}|${fontSize}`;
  const cached = session.metricCache.get(cacheKey);
  if (cached) return cached;
  const familyCandidates = session.records.filter((record) =>
    record.family.toLowerCase() === selected.family.toLowerCase() &&
    record.style === selected.style);
  const candidates = cssWeightMatched(
    familyCandidates,
    fontWeight,
    (record) => record.weightRange,
  );
  const normalized = candidates.map((record) => normalizedMetrics(record, fontWeight));
  const selectedMetrics = normalizedMetrics(selected, fontWeight);
  if (!normalized.every((value) => metricsEqual(selectedMetrics, value))) {
    throw new Error(`NonUniformUnicodeRangeMetrics:family=${selected.family};weight=${fontWeight}`);
  }
  const result = selectedMetrics.map((value) => Number.isNaN(value) ? value : value * fontSize);
  session.metricCache.set(cacheKey, result);
  return result;
}

function instanceAxes(record, requestedWeight) {
  return record.axisInfos.wght ? { wght: requestedWeight } : {};
}

function instanceId(record, requestedWeight) {
  const axes = instanceAxes(record, requestedWeight);
  return `${record.sfntSha256}:${record.faceIndex}:${Object.entries(axes)
    .map(([tag, value]) => `${tag}=${value}`).join(",") || "default"}`;
}

function installGlobalBackend() {
  if (globalThis.__TiqianFontBackend) {
    if (globalThis.__TiqianFontBackendRevision === BACKEND_REVISION) return;
    throw new Error("FontBackendGlobalCollision");
  }
  globalThis.__TiqianFontBackendRevision = BACKEND_REVISION;
  globalThis.__TiqianFontBackend = {
    shape(
      sessionId,
      displayText,
      serializedFamilies,
      fontSize,
      fontWeight,
      italic,
      locale,
      role,
      sourceText = displayText,
    ) {
      const session = sessions.get(sessionId);
      if (!session) throw new Error(`UnknownFontSession:${sessionId}`);
      const families = serializedFamilies.split(FAMILY_SEPARATOR).filter(Boolean);
      const selection = selectShapeFace(
        session,
        families,
        fontWeight,
        italic,
        displayText,
        sourceText,
      );
      const record = selection.record;
      const result = shapeRecord(record, displayText, fontSize, fontWeight, locale, role);
      if (!selection.displayCovered) {
        // The exact CSS face contract rejected the display codepoint even if
        // the raw sfnt happens to retain an unreachable glyph. Mark the probe
        // as missing so the common engine re-shapes the original source text.
        result.glyphs = result.glyphs.map((glyph) => ({ ...glyph, id: 0 }));
      }
      const missingGlyph = result.glyphs.some((glyph) => glyph.id === 0);
      if (missingGlyph && sourceText === displayText) {
        throw new Error(`MissingGlyph:face=${record.faceId};text=${JSON.stringify(displayText)}`);
      }
      const handle = registry.nextResultId++;
      shapeResults.set(handle, result);
      if (missingGlyph) return handle;
      const usageKey = [
        instanceId(record, fontWeight),
        record.family,
        record.style,
        record.weightRange.join("-"),
        record.unicodeRange,
        record.publicUrl,
        result.features.join(","),
      ].join("|");
      if (!session.used.has(usageKey)) {
        session.used.set(usageKey, {
          record,
          fontWeight,
          italic,
          probeText: displayText,
          probeAdvancePx: result.advance,
          probeFontSizePx: fontSize,
          probeScript: result.script,
          probeLanguage: locale,
          probeFeatures: result.features,
          coverageText: new Set(Array.from(displayText)),
        });
      } else {
        const usage = session.used.get(usageKey);
        for (const point of displayText) usage.coverageText.add(point);
      }
      return handle;
    },
    shapeGlyphCount: (handle) => shapeResults.get(handle)?.glyphs.length ?? 0,
    shapeGlyphId: (handle, index) => shapeResults.get(handle)?.glyphs[index]?.id ?? 0,
    shapeGlyphAdvance: (handle, index) => shapeResults.get(handle)?.glyphs[index]?.advance ?? 0,
    shapeGlyphX: (handle, index) => shapeResults.get(handle)?.glyphs[index]?.x ?? 0,
    shapeGlyphY: (handle, index) => shapeResults.get(handle)?.glyphs[index]?.y ?? 0,
    shapeGlyphBound(handle, index, edge) {
      return shapeResults.get(handle)?.glyphs[index]?.bounds?.[edge] ?? Number.NaN;
    },
    shapeAdvance: (handle) => shapeResults.get(handle)?.advance ?? 0,
    shapeFaceId: (handle) => shapeResults.get(handle)?.record.faceId ?? "",
    shapeFontInstanceId(handle) {
      const result = shapeResults.get(handle);
      return result ? instanceId(result.record, result.fontWeight) : "";
    },
    shapeScript: (handle) => shapeResults.get(handle)?.script ?? "",
    shapeFeatureCount: (handle) => shapeResults.get(handle)?.features.length ?? 0,
    shapeFeature: (handle, index) => shapeResults.get(handle)?.features[index] ?? "",
    shapeUnsafeBreakCount: (handle) => shapeResults.get(handle)?.unsafeBreakCount ?? 0,
    releaseShape: (handle) => shapeResults.delete(handle),
    metrics(sessionId, serializedFamilies, fontSize, fontWeight, italic, _role, faceSelectionText) {
      const session = sessions.get(sessionId);
      if (!session) throw new Error(`UnknownFontSession:${sessionId}`);
      const families = serializedFamilies.split(FAMILY_SEPARATOR).filter(Boolean);
      const handle = registry.nextResultId++;
      metricResults.set(
        handle,
        metricsFor(session, families, fontSize, fontWeight, italic, faceSelectionText),
      );
      return handle;
    },
    metricValue: (handle, index) => metricResults.get(handle)?.[index] ?? Number.NaN,
    releaseMetrics: (handle) => metricResults.delete(handle),
  };
}

async function loadRecord(spec, hb, decompressWoff2) {
  const family = String(spec.family ?? "").trim();
  if (!family) throw new Error("MissingFontFaceFamily");
  const publicUrl = String(spec.publicUrl ?? "").trim();
  if (!publicUrl) throw new Error(`MissingPublicFontUrl:${family}`);
  if (!isContentAddressedUrl(publicUrl)) {
    throw new Error(`NonContentAddressedFontUrl:${publicUrl}`);
  }
  const source = sourceBytes(spec.source);
  const decompressed = isWoff2(source) ? await decompressWoff2(source) : source;
  const sfnt = decompressed instanceof Uint8Array ? decompressed : new Uint8Array(decompressed);
  if (isFontCollection(sfnt)) throw new Error(`UnsupportedFontCollection:${family}`);
  const data = sfnt.buffer.slice(sfnt.byteOffset, sfnt.byteOffset + sfnt.byteLength);
  const blob = new hb.Blob(data);
  const faceIndex = Number(spec.faceIndex ?? 0);
  if (faceIndex !== 0) throw new Error(`UnsupportedFontFaceIndex:${family}:${faceIndex}`);
  const face = new hb.Face(blob, faceIndex);
  if (!Number.isFinite(face.upem) || face.upem <= 0) throw new Error(`InvalidOpenTypeFace:${family}`);
  const axisInfos = face.getAxisInfos();
  const unsupportedAxes = Object.keys(axisInfos).filter((tag) => tag !== "wght");
  if (unsupportedAxes.length > 0) {
    throw new Error(`UnsupportedVariableFontAxes:${family}:${unsupportedAxes.join(",")}`);
  }
  const resolvedTableMetrics = tableMetrics(face);
  if (Object.keys(axisInfos).length > 0 && (
    face.referenceTable("MVAR") || resolvedTableMetrics.baseHasVariationIndex
  )) throw new Error(`UnsupportedVariableFontMetrics:${family}`);
  const sourceSha256 = await sha256(source);
  const sfntSha256 = await sha256(sfnt);
  const weightRange = normalizeWeight(spec.weight);
  const style = normalizeStyle(spec.style);
  if (style !== "normal" && style !== "italic") {
    throw new Error(`UnsupportedFontFaceStyle:${family}:${style}`);
  }
  return {
    hb,
    blob,
    face,
    faceIndex,
    sourceOrder: spec.sourceOrder,
    family,
    style,
    weightRange,
    unicodeRange: String(spec.unicodeRange ?? ""),
    unicodeRanges: parseUnicodeRange(spec.unicodeRange),
    publicUrl,
    sourceSha256,
    sfntSha256,
    axisInfos,
    localNames: faceLocalNames(face),
    tableMetrics: resolvedTableMetrics,
    faceId: `${family}|${style}|${weightRange.join("-")}|${sfntSha256.slice(0, 16)}|${faceIndex}`,
  };
}

export async function createFontSession(faceSpecs, options = {}) {
  if (!Array.isArray(faceSpecs) || faceSpecs.length === 0) throw new Error("MissingExplicitFontFaces");
  const { hb, decompressWoff2 } = await loadBackends();
  const orderedSpecs = orderedFaceSpecs(faceSpecs);
  const records = await Promise.all(orderedSpecs.map((spec) => loadRecord(spec, hb, decompressWoff2)));
  const sessionPrefix = String(options.sessionPrefix ?? "tq-font").trim() || "tq-font";
  const sessionId = `${sessionPrefix}-${registry.nextSessionId++}`;
  const session = {
    sessionId,
    records,
    used: new Map(),
    metricCache: new Map(),
    harfbuzzVersion: hb.versionString(),
  };
  installGlobalBackend();
  sessions.set(sessionId, session);
  return {
    id: sessionId,
    backendRevision: BACKEND_REVISION,
    harfbuzzVersion: session.harfbuzzVersion,
    faces: records.map((record) => Object.freeze({
      family: record.family,
      style: record.style,
      weight: Object.freeze([...record.weightRange]),
      unicodeRange: record.unicodeRange,
      publicUrl: record.publicUrl,
      sourceSha256: record.sourceSha256,
      sfntSha256: record.sfntSha256,
      faceIndex: record.faceIndex,
      sourceOrder: record.sourceOrder,
      axisTags: Object.freeze(Object.keys(record.axisInfos).sort()),
      localNames: Object.freeze([...record.localNames]),
    })),
    beginCapture() {
      session.used.clear();
    },
    renderFamilies(requestedFamilies) {
      return renderFamiliesFor(session, requestedFamilies);
    },
    sourceBoundaries(text, baseStyle, textSpans) {
      return sourceBoundariesFor(session, text, baseStyle, textSpans);
    },
    captureEvidence() {
      return {
        backendRevision: BACKEND_REVISION,
        harfbuzzVersion: session.harfbuzzVersion,
        faces: Array.from(session.used.values(), (usage) => ({
          family: usage.record.family,
          style: usage.record.style,
          weight: usage.record.weightRange,
          unicodeRange: usage.record.unicodeRange,
          publicUrl: usage.record.publicUrl,
          sourceSha256: usage.record.sourceSha256,
          sfntSha256: usage.record.sfntSha256,
          faceIndex: usage.record.faceIndex,
          sourceOrder: usage.record.sourceOrder,
          axes: instanceAxes(usage.record, usage.fontWeight),
          localNames: usage.record.localNames,
          coverageText: Array.from(usage.coverageText).join(""),
          probe: {
            text: usage.probeText,
            advancePx: usage.probeAdvancePx,
            fontSizePx: usage.probeFontSizePx,
            fontWeight: usage.fontWeight,
            italic: usage.italic,
            script: usage.probeScript,
            language: usage.probeLanguage,
            features: usage.probeFeatures,
          },
        })),
      };
    },
    close() {
      sessions.delete(sessionId);
      session.used.clear();
      session.metricCache.clear();
    },
  };
}
