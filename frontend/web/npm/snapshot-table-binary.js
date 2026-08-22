// The station-table binary reader of ADR 0052: decodes the `TIQTBL02` byte
// file the Rust encoder produces into lazy accessors. Adopting a root reads
// only the rows the manifest references. The byte contract lives in the
// encoder; this file mirrors the region order and validates every offset
// against the byte length, so a damaged file fails with
// `SnapshotTablesInvalid` before any row is read.

const MAGIC = "TIQTBL02";
const HEADER_U32_COUNT = 12;
const METRIC_ROW_BYTES = 25;
const METRIC_POOL_ROW_BYTES = 40;
const PROBE_ROW_BYTES = 16;
const PROBE_STYLE_ROW_BYTES = 25;
/** `f64::NAN.to_bits()`; the encoder writes exactly these bits for absent. */
const ABSENT_METRIC_BITS = 0x7ff8000000000000n;

const decoder = new TextDecoder("utf-8", { fatal: true });

function invalid() {
  return new Error("SnapshotTablesInvalid");
}

/** True when the bytes start with the station-table magic. */
export function isSnapshotTableBinary(bytes) {
  if (!(bytes instanceof Uint8Array) || bytes.length < 8) return false;
  try {
    return decoder.decode(bytes.subarray(0, 8)) === MAGIC;
  } catch {
    return false;
  }
}

function readU32(bytes, at) {
  if (at < 0 || at + 4 > bytes.length) throw invalid();
  return (bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16)) + bytes[at + 3] * 0x1000000;
}

function readU16(bytes, at) {
  if (at < 0 || at + 2 > bytes.length) throw invalid();
  return bytes[at] | (bytes[at + 1] << 8);
}

const dataViewOf = (bytes) => new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);

function readF64(view, at) {
  return view.getFloat64(at, true);
}

/**
 * One offsets region: `count + 1` u32 values, non-decreasing, the last one
 * naming the byte length of the region that follows.
 */
function readOffsetsRegion(bytes, start, count) {
  const offsets = new Array(count + 1);
  for (let index = 0; index <= count; index += 1) {
    offsets[index] = readU32(bytes, start + index * 4);
    if (index > 0 && offsets[index] < offsets[index - 1]) throw invalid();
  }
  return offsets;
}

/**
 * Decodes the header and region boundaries. Every region is walked in order,
 * so the returned layout proves the file holds every region it counts.
 */
function decodeLayout(bytes) {
  if (!isSnapshotTableBinary(bytes)) throw invalid();
  const counts = new Array(HEADER_U32_COUNT);
  for (let index = 0; index < HEADER_U32_COUNT; index += 1) {
    counts[index] = readU32(bytes, 8 + index * 4);
  }
  const [
    replayStringCount, stringCount, metricCount, metricValuePoolCount,
    probeCount, probeAdvancePoolCount, probeStylePoolCount, probeFeaturesPoolCount,
    faceCount, typographyCount, valueStyleCount, fontPreloadCount,
  ] = counts;
  let at = 8 + HEADER_U32_COUNT * 4;
  const take = (byteLength) => {
    const start = at;
    at += byteLength;
    if (at > bytes.length) throw invalid();
    return start;
  };
  const takeOffsets = (count) => {
    const start = take((count + 1) * 4);
    const offsets = readOffsetsRegion(bytes, start, count);
    return { offsets, bytesStart: take(offsets[count]) };
  };
  const stringOffsetsStart = take((stringCount + 1) * 4);
  const stringOffsets = readOffsetsRegion(bytes, stringOffsetsStart, stringCount);
  const stringBytesStart = take(stringOffsets[stringCount]);
  const sortedRefsStart = take(stringCount * 4);
  const metricRowsStart = take(metricCount * METRIC_ROW_BYTES);
  const metricValuePoolStart = take(metricValuePoolCount * METRIC_POOL_ROW_BYTES);
  const probeRowsStart = take(probeCount * PROBE_ROW_BYTES);
  const probeAdvancePoolStart = take(probeAdvancePoolCount * 8);
  const probeStylePoolStart = take(probeStylePoolCount * PROBE_STYLE_ROW_BYTES);
  const probeFeatures = takeOffsets(probeFeaturesPoolCount);
  const faceText = takeOffsets(faceCount);
  const typographyText = takeOffsets(typographyCount);
  const valueStyleText = takeOffsets(valueStyleCount);
  const fontPreloadText = takeOffsets(fontPreloadCount);
  const revisionTextStart = at;
  if (revisionTextStart > bytes.length) throw invalid();
  return {
    replayStringCount,
    stringCount,
    metricCount,
    metricValuePoolCount,
    probeCount,
    stringOffsets,
    stringBytesStart,
    sortedRefsStart,
    metricRowsStart,
    metricValuePoolStart,
    probeRowsStart,
    probeAdvancePoolStart,
    probeStylePoolStart,
    probeFeatures,
    faceText,
    typographyText,
    valueStyleText,
    fontPreloadText,
    revisionTextStart,
  };
}

function regionText(bytes, start, offsets, index, issue) {
  if (!Number.isSafeInteger(index) || index < 0 || index >= offsets.length - 1) {
    throw new Error(issue);
  }
  const from = start + offsets[index];
  const to = start + offsets[index + 1];
  try {
    return decoder.decode(bytes.subarray(from, to));
  } catch {
    throw invalid();
  }
}

function parseRegionJson(bytes, start, offsets, index, issue) {
  const text = regionText(bytes, start, offsets, index, issue);
  try {
    return JSON.parse(text);
  } catch {
    throw invalid();
  }
}

/** Parses the revision tail; called during decode and memoized per view. */
function readRevisionsOf(bytes, layout) {
  try {
    const parsed = JSON.parse(decoder.decode(bytes.subarray(layout.revisionTextStart)));
    return {
      backendRevision: parsed.backendRevision ?? null,
      harfbuzzVersion: parsed.harfbuzzVersion ?? null,
    };
  } catch {
    throw invalid();
  }
}

/**
 * The binary table view: the same accessor surface the parsed-text lane
 * wraps, reading rows from the bytes on demand and caching each decoded row.
 */export function decodeSnapshotTableBinary(bytes) {
  const layout = decodeLayout(bytes);
  const view = dataViewOf(bytes);
  // The revision tail parses during decode, mirroring the Rust reader. The
  // tail has no declared length; this parse is what makes a truncated file
  // fail before any accessor hands out a row.
  readRevisionsOf(bytes, layout);
  const stringCache = new Array(layout.stringCount).fill(undefined);

  const stringAt = (ref) => {
    if (!Number.isSafeInteger(ref) || ref < 0 || ref >= layout.stringCount) {
      throw new Error("SnapshotFontReplayStringReferenceInvalid");
    }
    if (stringCache[ref] === undefined) {
      const from = layout.stringBytesStart + layout.stringOffsets[ref];
      const to = layout.stringBytesStart + layout.stringOffsets[ref + 1];
      try {
        stringCache[ref] = decoder.decode(bytes.subarray(from, to));
      } catch {
        throw invalid();
      }
    }
    return stringCache[ref];
  };

  const metricValueAt = (poolRef, slot) => {
    const at = layout.metricValuePoolStart + poolRef * METRIC_POOL_ROW_BYTES + slot * 8;
    if (at < 0 || at + 8 > bytes.length) throw invalid();
    const bits = view.getBigUint64(at, true);
    if (bits === ABSENT_METRIC_BITS) return null;
    const value = view.getFloat64(at, true);
    if (!Number.isFinite(value)) throw invalid();
    return value;
  };

  // Manifest expansion reads the metric rows once per expansion; the rows are
  // a pure function of the bytes, so the decoded form is memoized per view
  // and repeated expansions stop rescanning the whole table.
  let metricRowsCache = null;
  const metricRows = () => {
    if (metricRowsCache !== null) return metricRowsCache;
    const rows = new Array(layout.metricCount);
    for (let index = 0; index < layout.metricCount; index += 1) {
      const at = layout.metricRowsStart + index * METRIC_ROW_BYTES;
      const poolRef = readU32(bytes, at + 21);
      rows[index] = {
        serializedFamilies: stringAt(readU32(bytes, at)),
        fontWeight: readF64(view, at + 4),
        italic: bytes[at + 12] === 1,
        role: stringAt(readU32(bytes, at + 13)),
        faceSelectionText: stringAt(readU32(bytes, at + 17)),
        valuesEm: [
          metricValueAt(poolRef, 0),
          metricValueAt(poolRef, 1),
          metricValueAt(poolRef, 2),
          metricValueAt(poolRef, 3),
          metricValueAt(poolRef, 4),
        ],
      };
    }
    metricRowsCache = rows;
    return rows;
  };

  const decodeProbe = (ref) => {
    if (!Number.isSafeInteger(ref) || ref < 0 || ref >= layout.probeCount) {
      throw new Error("SnapshotProbeReferenceInvalid");
    }
    const at = layout.probeRowsStart + ref * PROBE_ROW_BYTES;
    const advancePoolRef = readU32(bytes, at + 4);
    const stylePoolRef = readU32(bytes, at + 8);
    const featuresPoolRef = readU32(bytes, at + 12);
    if (featuresPoolRef >= layout.probeFeatures.offsets.length - 1) throw invalid();
    const advanceAt = layout.probeAdvancePoolStart + advancePoolRef * 8;
    const styleAt = layout.probeStylePoolStart + stylePoolRef * PROBE_STYLE_ROW_BYTES;
    if (advanceAt < 0 || advanceAt + 8 > bytes.length) throw invalid();
    if (styleAt < 0 || styleAt + PROBE_STYLE_ROW_BYTES > bytes.length) throw invalid();
    const featuresAt =
      layout.probeFeatures.bytesStart + layout.probeFeatures.offsets[featuresPoolRef];
    const featureCount = readU16(bytes, featuresAt);
    const features = new Array(featureCount);
    for (let index = 0; index < featureCount; index += 1) {
      features[index] = stringAt(readU32(bytes, featuresAt + 2 + index * 4));
    }
    return {
      text: stringAt(readU32(bytes, at)),
      advancePx: readF64(view, advanceAt),
      fontSizePx: readF64(view, styleAt),
      fontWeight: readF64(view, styleAt + 8),
      italic: bytes[styleAt + 16] === 1,
      script: stringAt(readU32(bytes, styleAt + 17)),
      language: stringAt(readU32(bytes, styleAt + 21)),
      features,
    };
  };

  const probeCache = new Map();
  const probeAt = (ref) => {
    if (!probeCache.has(ref)) {
      probeCache.set(ref, decodeProbe(ref));
    }
    return probeCache.get(ref);
  };

  const typographyCache = new Map();
  const typographyAt = (ref) => {
    if (!typographyCache.has(ref)) {
      typographyCache.set(
        ref,
        parseRegionJson(
          bytes,
          layout.typographyText.bytesStart,
          layout.typographyText.offsets,
          ref,
          "SnapshotTypographyReferenceInvalid",
        ),
      );
    }
    return typographyCache.get(ref);
  };

  const faceCache = new Map();
  const faceAt = (ref) => {
    if (!faceCache.has(ref)) {
      faceCache.set(
        ref,
        parseRegionJson(
          bytes,
          layout.faceText.bytesStart,
          layout.faceText.offsets,
          ref,
          "SnapshotFontFaceReferenceInvalid",
        ),
      );
    }
    return faceCache.get(ref);
  };

  let valueStyles = null;
  const readValueStyles = () => {
    if (valueStyles === null) {
      valueStyles = [];
      const { offsets, bytesStart } = layout.valueStyleText;
      for (let index = 0; index < offsets.length - 1; index += 1) {
        valueStyles.push(regionText(bytes, bytesStart, offsets, index, "SnapshotTablesInvalid"));
      }
    }
    return valueStyles;
  };

  let revisions = null;
  const readRevisions = () => {
    if (revisions === null) revisions = readRevisionsOf(bytes, layout);
    return revisions;
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
