import type { WorkerLayoutRequest } from "../engine/wire-types.js";

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

/** A face descriptor record read from the worker font contract. */
export interface FontFaceRecord {
  family: unknown;
  localNames?: Iterable<unknown>;
  style: string;
  weight: readonly unknown[];
  unicodeRange: unknown;
  publicUrl: unknown;
  faceIndex: unknown;
  sourceOrder: unknown;
}

/** The resolved style of one text run feeding face selection. */
export interface FontFaceStyle {
  fontFamilies: string[];
  fontSizePx: number;
  fontWeight: number;
  italic: boolean;
  baselineShiftPx?: number;
}

/** One parsed layout-worker text span (validated UTF-16 boundaries). */
export interface WorkerTextSpan {
  start: number;
  end: number;
  fontFamilies: string[];
  fontSizePx: number;
  fontWeight: number;
  italic: boolean;
  baselineShiftPx: number;
}

/** Font selection fields from the Worker request, with legacy benchmark input. */
export interface WorkerFontContractRequest
  extends Pick<WorkerLayoutRequest, "text" | "fontSizePx" | "fontWeight" | "italic"> {
  fontFamilies: WorkerLayoutRequest["fontFamilies"] | string;
  textSpans: WorkerLayoutRequest["textSpans"] | string | null | undefined;
}

interface SelectedMetadataFace extends FontFaceRecord {
  unicodeRanges: [number, number][] | null;
}

type FontFaceRangeOfFn<T> = (record: T) => readonly unknown[] | null | undefined;

type FontFaceSelectFaceFn<F> = (style: FontFaceStyle, point: string) => F;

type FontFaceIdentityFn<F> = (face: F) => unknown;

function isStructuralNoShapeControl(point: string): boolean {
  return STRUCTURAL_NO_SHAPE_CODE_POINTS.has(point.codePointAt(0)!);
}

/** CSS Fonts weight matching rank for one face descriptor range. */
export function cssWeightPreference(
  range: readonly unknown[] | null | undefined,
  requested: number,
): [number, number] {
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

export function cssWeightMatched<T>(
  records: T[],
  requested: number,
  rangeOf: FontFaceRangeOfFn<T>,
): T[] {
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

export function parseUnicodeRange(value: unknown): [number, number][] | null {
  const serialized = String(value ?? "").trim();
  if (!serialized) return null;
  const ranges: [number, number][] = [];
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

export function unicodeRangeContains(
  ranges: readonly (readonly [number, number])[] | null | undefined,
  codePoint: number,
): boolean {
  return ranges == null || ranges.some(([start, end]) => codePoint >= start && codePoint <= end);
}

/** A face is matched by the same family or OpenType local name exposed by the host. */
export function fontRecordMatchesFamily(record: FontFaceRecord, requestedFamily: unknown): boolean {
  const requested = String(requestedFamily ?? "").trim().toLowerCase();
  if (!requested) return false;
  return String(record.family ?? "").toLowerCase() === requested ||
    Array.from(record.localNames ?? []).some(
      (name) => String(name).trim().toLowerCase() === requested,
    );
}

/**
 * SnapshotSubsetCoverageBoundary: keep shaping runs inside one selected CSS face.
 * The selector remains injectable because Node can additionally verify nominal
 * glyph coverage while the browser Worker only owns validated face metadata.
 */
export function sourceBoundariesForSelectedFace<F>(
  textValue: unknown,
  baseStyle: FontFaceStyle,
  textSpans: Iterable<WorkerTextSpan> | null | undefined,
  selectFace: FontFaceSelectFaceFn<F>,
  faceIdentity: FontFaceIdentityFn<F> = (face) => (face as { faceId?: unknown }).faceId,
): number[] {
  const text = String(textValue);
  const spans = Array.from(textSpans ?? []);
  const boundaries: number[] = [];
  let offset = 0;
  let previousSignature: string | null = null;
  for (const point of text) {
    if (isStructuralNoShapeControl(point)) {
      // StructuralBreakControlNoShape: UAX #14 mandatory breaks and U+200B are
      // source-faithful layout controls, not glyph-bearing characters. The
      // layout core creates their zero-advance clusters before shaping, so
      // snapshot-font face selection must neither require a covering face nor
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

function metadataFaceIdentity(face: SelectedMetadataFace): string {
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

function selectMetadataFace(
  faces: readonly SelectedMetadataFace[],
  style: FontFaceStyle,
  point: string,
): SelectedMetadataFace {
  const desiredStyle = style.italic ? "italic" : "normal";
  const codePoint = point.codePointAt(0)!;
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
    `NoSnapshotFontFace:families=${style.fontFamilies.join(",")};` +
    `weight=${style.fontWeight};italic=${style.italic};text=${JSON.stringify(point)}`,
  );
}

function validateWorkerTextSpan(span: WorkerTextSpan): WorkerTextSpan {
  if (
    !Number.isSafeInteger(span.start) || !Number.isSafeInteger(span.end) ||
    span.start < 0 || span.end <= span.start ||
    span.fontFamilies.length === 0 ||
    !Number.isFinite(span.fontSizePx) || span.fontSizePx <= 0 ||
    !Number.isFinite(span.fontWeight) ||
    !Number.isFinite(span.baselineShiftPx) ||
    typeof span.italic !== "boolean"
  ) throw new Error("InvalidLayoutWorkerTextSpan");
  return span;
}

function workerTextSpans(value: WorkerFontContractRequest["textSpans"]): WorkerTextSpan[] {
  if (value == null || value === "") return [];

  // Map the structured Worker fields to the style used for face selection.
  if (typeof value !== "string") {
    if (!Array.isArray(value)) throw new Error("InvalidLayoutWorkerTextSpan");
    return value.map((span) => validateWorkerTextSpan({
      start: span.start,
      end: span.end,
      fontFamilies: Array.isArray(span.fontFamilies) ? span.fontFamilies.filter(Boolean) : [],
      fontSizePx: span.fontSize,
      fontWeight: span.fontWeight,
      italic: span.italic,
      baselineShiftPx: span.baselineShift,
    }));
  }

  // The benchmark still supplies the original delimited records.
  return value.split(RECORD_SEPARATOR).map((record) => {
    const fields = record.split(FIELD_SEPARATOR);
    const [start, end, families, fontSize, fontWeight, italic, baselineShift] = fields;
    if (fields.length !== 7 || (italic !== "true" && italic !== "false")) {
      throw new Error("InvalidLayoutWorkerTextSpan");
    }
    return validateWorkerTextSpan({
      start: Number(start),
      end: Number(end),
      fontFamilies: families.split(FAMILY_SEPARATOR).filter(Boolean),
      fontSizePx: Number(fontSize),
      fontWeight: Number(fontWeight),
      italic: italic === "true",
      baselineShiftPx: Number(baselineShift),
    });
  });
}

/** Rebuild build-time font-shard boundaries from the validated Worker contract. */
export function workerSnapshotSubsetSourceBoundaries(
  faceMetadata: Iterable<FontFaceRecord> | null | undefined,
  request: WorkerFontContractRequest,
): number[] {
  const faces = Array.from(faceMetadata ?? [], (face) => ({
    ...face,
    unicodeRanges: parseUnicodeRange(face.unicodeRange),
  }));
  const fontFamilies = typeof request.fontFamilies === "string"
    ? request.fontFamilies.split(FAMILY_SEPARATOR)
    : request.fontFamilies;
  const baseStyle: FontFaceStyle = {
    fontFamilies: Array.isArray(fontFamilies) ? fontFamilies.filter(Boolean) : [],
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

export function mergeSerializedSourceBoundaries(
  serialized: unknown,
  additional: Iterable<unknown> | null | undefined,
): string {
  const boundaries = new Set(
    String(serialized ?? "").split(",").filter(Boolean).map(Number),
  );
  for (const boundary of additional ?? []) boundaries.add(Number(boundary));
  if ([...boundaries].some((boundary) => !Number.isSafeInteger(boundary) || boundary < 0)) {
    throw new Error("InvalidSourceBoundary");
  }
  return [...boundaries].sort((left, right) => left - right).join(",");
}
