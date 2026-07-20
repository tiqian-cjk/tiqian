const FAMILY_SEPARATOR = "\u001f";
const RECORD_SEPARATOR = "\u001e";
const FIELD_SEPARATOR = "\u001d";
const STRUCTURAL_NO_SHAPE_CODE_POINTS = new Set([
  0x000A, // LF
  0x000B, // VT
  0x000C, // FF
  0x000D, // CR
  0x0085, // NEL
  0x200B, // ZWSP
  0x2028, // LS
  0x2029, // PS
]);

function isStructuralNoShapeControl(point) {
  return STRUCTURAL_NO_SHAPE_CODE_POINTS.has(point.codePointAt(0));
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

export function cssWeightMatched(records, requested, rangeOf) {
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

/** A face is matched by the same family or OpenType local name exposed by the host. */
export function fontRecordMatchesFamily(record, requestedFamily) {
  const requested = String(requestedFamily ?? "").trim().toLowerCase();
  if (!requested) return false;
  return String(record.family ?? "").toLowerCase() === requested ||
    Array.from(record.localNames ?? []).some(
      (name) => String(name).trim().toLowerCase() === requested,
    );
}

/**
 * ExactSubsetCoverageBoundary: keep shaping runs inside one selected CSS face.
 * The selector remains injectable because Node can additionally verify nominal
 * glyph coverage while the browser Worker only owns validated face metadata.
 */
export function sourceBoundariesForSelectedFace(
  textValue,
  baseStyle,
  textSpans,
  selectFace,
  faceIdentity = (face) => face.faceId,
) {
  const text = String(textValue);
  const spans = Array.from(textSpans ?? []);
  const boundaries = [];
  let offset = 0;
  let previousSignature = null;
  for (const point of text) {
    if (isStructuralNoShapeControl(point)) {
      // StructuralBreakControlNoShape: UAX #14 mandatory breaks and U+200B are
      // source-faithful layout controls, not glyph-bearing characters. The
      // layout core creates their zero-advance clusters before shaping, so
      // exact-font face selection must neither require a covering face nor
      // disturb adjacent face runs. CRLF advances as two UTF-16 code units but
      // remains one mandatory-break cluster in the core.
      offset += point.length;
      continue;
    }
    const style = [...spans].reverse().find((span) =>
      offset >= span.start && offset < span.end) ?? baseStyle;
    const record = selectFace(style, point);
    const signature = [
      faceIdentity(record),
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

function metadataFaceIdentity(face) {
  return JSON.stringify([
    face.family,
    face.style,
    face.weight,
    face.unicodeRange,
    face.publicUrl,
    face.faceIndex,
    face.sourceOrder,
  ]);
}

function selectMetadataFace(faces, style, point) {
  const desiredStyle = style.italic ? "italic" : "normal";
  const codePoint = point.codePointAt(0);
  for (const family of style.fontFamilies) {
    const familyMatches = faces.filter((face) =>
      fontRecordMatchesFamily(face, family) && face.style === desiredStyle);
    const weightMatched = cssWeightMatched(
      familyMatches,
      style.fontWeight,
      (face) => face.weight,
    );
    // CSS composite faces with identical descriptors use the later
    // @font-face rule when unicode-range declarations overlap.
    for (const face of weightMatched.toReversed()) {
      if (unicodeRangeContains(face.unicodeRanges, codePoint)) return face;
    }
  }
  throw new Error(
    `NoExactFontFace:families=${style.fontFamilies.join(",")};` +
    `weight=${style.fontWeight};italic=${style.italic};text=${JSON.stringify(point)}`,
  );
}

function workerTextSpans(value) {
  if (value == null || value === "") return [];
  return String(value).split(RECORD_SEPARATOR).map((record) => {
    const fields = record.split(FIELD_SEPARATOR);
    if (fields.length !== 7) throw new Error("InvalidLayoutWorkerTextSpan");
    const [start, end, families, fontSize, fontWeight, italic, baselineShift] = fields;
    const span = {
      start: Number(start),
      end: Number(end),
      fontFamilies: families.split(FAMILY_SEPARATOR).filter(Boolean),
      fontSizePx: Number(fontSize),
      fontWeight: Number(fontWeight),
      italic: italic === "true",
      baselineShiftPx: Number(baselineShift),
    };
    if (
      !Number.isSafeInteger(span.start) || !Number.isSafeInteger(span.end) ||
      span.start < 0 || span.end <= span.start ||
      span.fontFamilies.length === 0 ||
      !Number.isFinite(span.fontSizePx) || span.fontSizePx <= 0 ||
      !Number.isFinite(span.fontWeight) ||
      !Number.isFinite(span.baselineShiftPx) ||
      (italic !== "true" && italic !== "false")
    ) throw new Error("InvalidLayoutWorkerTextSpan");
    return span;
  });
}

/** Rebuild build-time font-shard boundaries from the validated Worker contract. */
export function workerExactSubsetSourceBoundaries(faceMetadata, request) {
  const faces = Array.from(faceMetadata ?? [], (face) => ({
    ...face,
    unicodeRanges: parseUnicodeRange(face.unicodeRange),
  }));
  const baseStyle = {
    fontFamilies: String(request.fontFamilies ?? "").split(FAMILY_SEPARATOR).filter(Boolean),
    fontSizePx: Number(request.fontSizePx),
    fontWeight: Number(request.fontWeight),
    italic: Boolean(request.italic),
    baselineShiftPx: 0,
  };
  if (
    faces.length === 0 || baseStyle.fontFamilies.length === 0 ||
    !Number.isFinite(baseStyle.fontSizePx) || baseStyle.fontSizePx <= 0 ||
    !Number.isFinite(baseStyle.fontWeight)
  ) throw new Error("InvalidLayoutWorkerFontContract");
  return sourceBoundariesForSelectedFace(
    request.text,
    baseStyle,
    workerTextSpans(request.textSpans),
    (style, point) => selectMetadataFace(faces, style, point),
    metadataFaceIdentity,
  );
}

export function mergeSerializedSourceBoundaries(serialized, additional) {
  const boundaries = new Set(
    String(serialized ?? "").split(",").filter(Boolean).map(Number),
  );
  for (const boundary of additional ?? []) boundaries.add(Number(boundary));
  if ([...boundaries].some((boundary) => !Number.isSafeInteger(boundary) || boundary < 0)) {
    throw new Error("InvalidSourceBoundary");
  }
  return [...boundaries].sort((left, right) => left - right).join(",");
}
