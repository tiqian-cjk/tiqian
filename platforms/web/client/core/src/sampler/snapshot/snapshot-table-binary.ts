// The snapshot-table binary view of ADR 0052. The byte contract (magic,
// header counts, region order and lengths, delta decoding, f64 bit patterns)
// is single-sourced in Haxe and arrives generated in tiqian-protocol; this
// file is only the consumer shell on top: the public view surface, the lazy
// row caches, and the JSON interpretation of the text regions, which the
// Stage1-P2 boundary ruling keeps platform-side. A damaged file fails with
// the named issue before any row is handed out.
import { SnapshotTableBinary } from "tiqian-protocol/org/tiqian/protocol/SnapshotTableBinary";
import { TableData } from "tiqian-protocol/org/tiqian/protocol/TableData";

const MAGIC = "TIQTBL03";

export interface SnapshotMetricRow {
  serializedFamilies: string;
  fontWeight: number;
  italic: boolean;
  role: string;
  faceSelectionText: string;
  valuesEm: (number | null)[];
}

export interface SnapshotProbe {
  text: string;
  advancePx: number;
  fontSizePx: number;
  fontWeight: number;
  italic: boolean;
  script: string;
  language: string;
  features: string[];
}

export interface SnapshotRevisions {
  backendRevision: string | null;
  harfbuzzVersion: string | null;
}

export interface SnapshotTableBinaryView {
  binary: true;
  bytes: Uint8Array;
  stringAt: (ref: number) => string;
  metricRows: () => SnapshotMetricRow[];
  probeAt: (ref: number) => SnapshotProbe;
  typographyAt: (ref: number) => unknown;
  faceAt: (ref: number) => unknown;
  valueStyles: () => string[];
  revisions: () => SnapshotRevisions;
}

function invalid(): Error {
  return new Error("SnapshotTablesInvalid");
}

function decodeOrThrow(bytes: Uint8Array): TableData {
  const data = new TableData();
  const issue = SnapshotTableBinary.decodeInto(bytes, data);
  if (issue !== "") throw invalid();
  return data;
}

/** True when the bytes start with the snapshot-table magic. */
export function isSnapshotTableBinary(bytes: unknown): boolean {
  if (!(bytes instanceof Uint8Array) || bytes.length < 8) return false;
  let magic = "";
  for (let index = 0; index < 8; index += 1) magic += String.fromCharCode(bytes[index]!);
  return magic === MAGIC;
}

function jsonOrInvalid<T>(text: string): T {
  try {
    return JSON.parse(text) as T;
  } catch {
    throw invalid();
  }
}

/**
 * The binary table view: the same accessor surface as before, with every
 * byte-level read answered from the generated decoded form.
 */
function decodeView(bytes: Uint8Array): TableData {
  const data = decodeOrThrow(bytes);
  // The revision tail has no declared length; parsing it eagerly is what
  // makes a truncated or overstuffed file fail closed before any accessor
  // hands out a row (the old reader's contract, snapshot-tables tests).
  jsonOrInvalid<Record<string, string | null>>(data.revisionText);
  return data;
}

export function decodeSnapshotTableBinary(bytes: Uint8Array): SnapshotTableBinaryView {
  const data = decodeView(bytes);
  const stringCount = data.strings.length;
  const stringCache = new Array<string | undefined>(stringCount).fill(undefined);

  const stringAt = (ref: number): string => {
    if (!Number.isSafeInteger(ref) || ref < 0 || ref >= stringCount) {
      throw new Error("SnapshotFontReplayStringReferenceInvalid");
    }
    if (stringCache[ref] === undefined) {
      stringCache[ref] = data.strings[ref];
    }
    return stringCache[ref] as string;
  };

  const metricValueAt = (poolRef: number, slot: number): number | null => {
    if (!Number.isSafeInteger(poolRef) || poolRef < 0 || poolRef >= data.valuePool.length) {
      throw invalid();
    }
    const value = data.valuePool[poolRef].values[slot];
    return value === null || value === undefined ? null : value;
  };

  let metricRowsCache: SnapshotMetricRow[] | null = null;
  const metricRows = (): SnapshotMetricRow[] => {
    if (metricRowsCache !== null) return metricRowsCache;
    const rows = new Array<SnapshotMetricRow>(data.metricRows.length);
    for (let index = 0; index < data.metricRows.length; index += 1) {
      const row = data.metricRows[index];
      rows[index] = {
        serializedFamilies: stringAt(row.familiesRef),
        fontWeight: row.weight,
        italic: row.italic === 1,
        role: stringAt(row.roleRef),
        faceSelectionText: stringAt(row.faceSelectionRef),
        valuesEm: [0, 1, 2, 3, 4].map((slot) => metricValueAt(row.valuePoolRef, slot)),
      };
    }
    metricRowsCache = rows;
    return rows;
  };

  const probeCache = new Map<number, SnapshotProbe>();
  const probeAt = (ref: number): SnapshotProbe => {
    if (!Number.isSafeInteger(ref) || ref < 0 || ref >= data.probeTextRefs.length) {
      throw new Error("SnapshotProbeReferenceInvalid");
    }
    const cached = probeCache.get(ref);
    if (cached !== undefined) return cached;
    const textRef = data.probeTextRefs[ref];
    const advancePoolRef = data.probeAdvanceRefs[ref];
    const stylePoolRef = data.probeStyleRefs[ref];
    const featuresPoolRef = data.probeFeatureRefs[ref];
    if (featuresPoolRef >= data.featuresPool.length) throw invalid();
    const probe: SnapshotProbe = {
      text: stringAt(textRef),
      advancePx: data.advancePool[advancePoolRef],
      fontSizePx: data.styleFontSize[stylePoolRef],
      fontWeight: data.styleFontWeight[stylePoolRef],
      italic: data.styleItalic[stylePoolRef] === 1,
      script: stringAt(data.styleScriptRefs[stylePoolRef]),
      language: stringAt(data.styleLanguageRefs[stylePoolRef]),
      features: data.featuresPool[featuresPoolRef].map(stringAt),
    };
    probeCache.set(ref, probe);
    return probe;
  };

  const typographyCache = new Map<number, unknown>();
  const typographyAt = (ref: number): unknown => {
    if (!Number.isSafeInteger(ref) || ref < 0 || ref >= data.typographyTexts.length) {
      throw new Error("SnapshotTypographyReferenceInvalid");
    }
    if (!typographyCache.has(ref)) {
      typographyCache.set(ref, jsonOrInvalid(data.typographyTexts[ref]));
    }
    return typographyCache.get(ref);
  };

  const faceCache = new Map<number, unknown>();
  const faceAt = (ref: number): unknown => {
    if (!Number.isSafeInteger(ref) || ref < 0 || ref >= data.faceTexts.length) {
      throw new Error("SnapshotFontFaceReferenceInvalid");
    }
    if (!faceCache.has(ref)) {
      faceCache.set(ref, jsonOrInvalid(data.faceTexts[ref]));
    }
    return faceCache.get(ref);
  };

  let valueStylesCache: string[] | null = null;
  const readValueStyles = (): string[] => {
    if (valueStylesCache === null) {
      valueStylesCache = [...data.valueStyleTexts];
    }
    return valueStylesCache;
  };

  let revisionsCache: SnapshotRevisions | null = null;
  const readRevisions = (): SnapshotRevisions => {
    if (revisionsCache === null) {
      const parsed = jsonOrInvalid<Record<string, string | null>>(data.revisionText);
      revisionsCache = {
        backendRevision: parsed.backendRevision ?? null,
        harfbuzzVersion: parsed.harfbuzzVersion ?? null,
      };
    }
    return revisionsCache;
  };

  return {
    binary: true,
    bytes,
    stringAt,
    metricRows,
    probeAt,
    typographyAt,
    faceAt,
    valueStyles: readValueStyles,
    revisions: readRevisions,
  };
}
