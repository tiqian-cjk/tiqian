// A test-only encoder of the `TIQTBL02` station-table bytes. It mirrors the
// Rust encoder (region order, metric sort, pool assignment, string intern
// order); re-encoding a decoded file reproduces the input bytes exactly. The
// tests use it to pin the byte contract from the consumer side.

const encoder = new TextEncoder();

function writeU32(parts, value) {
  parts.push(value, value >>> 8, value >>> 16, value >>> 24);
}

function writeU16(parts, value) {
  parts.push(value, value >>> 8);
}

function writeF64(parts, value) {
  const view = new DataView(new ArrayBuffer(8));
  view.setFloat64(0, value, true);
  for (const byte of new Uint8Array(view.buffer)) parts.push(byte);
}

const ABSENT_BITS = 0x7ff8000000000000n;

function writeAbsentF64(parts) {
  const view = new DataView(new ArrayBuffer(8));
  view.setBigUint64(0, ABSENT_BITS, true);
  for (const byte of new Uint8Array(view.buffer)) parts.push(byte);
}

/** Offsets region followed by the concatenated bytes of every row. */
function writeOffsetsAndBytes(parts, texts) {
  let at = 0;
  writeU32(parts, 0);
  for (const text of texts) {
    at += encoder.encode(text).length;
    writeU32(parts, at);
  }
  for (const text of texts) {
    parts.push(...encoder.encode(text));
  }
}

export function writeBinaryTable(table) {
  const {
    replayStrings = [],
    metrics = [],
    probes = [],
    faces = [],
    typographies = [],
    valueStyles = [],
    fontPreloads = [],
    revisions = {},
  } = table;
  const strings = [...replayStrings];
  const stringRefs = new Map(strings.map((text, index) => [text, index]));
  const intern = (text) => {
    if (!stringRefs.has(text)) {
      stringRefs.set(text, strings.length);
      strings.push(text);
    }
    return stringRefs.get(text);
  };

  const metricRows = metrics.map((row) => ({
    familiesRef: intern(row.serializedFamilies),
    weight: row.fontWeight,
    italic: row.italic ? 1 : 0,
    roleRef: intern(row.role),
    faceSelectionRef: intern(row.faceSelectionText),
    values: row.valuesEm,
  }));
  metricRows.sort((left, right) =>
    left.familiesRef - right.familiesRef ||
    left.weight - right.weight ||
    left.italic - right.italic ||
    left.roleRef - right.roleRef ||
    left.faceSelectionRef - right.faceSelectionRef);
  const valuePool = [];
  const poolIndexOf = (values) => {
    const key = JSON.stringify(values.map((value) => (value == null ? "absent" : value)));
    const existing = valuePool.findIndex((row) => row.key === key);
    if (existing >= 0) return existing;
    valuePool.push({ key, values });
    return valuePool.length - 1;
  };
  for (const row of metricRows) row.valuePoolRef = poolIndexOf(row.values);

  const advancePool = [];
  const stylePool = [];
  const featuresPool = [];
  const probeRows = probes.map((probe) => {
    // String intern order per probe mirrors the encoder: text, script,
    // language, then features.
    const textRef = intern(probe.text);
    const scriptRef = intern(probe.script);
    const languageRef = intern(probe.language);
    const featureRefs = probe.features.map(intern);
    const advance = probe.advancePx;
    let advanceRef = advancePool.indexOf(advance);
    if (advanceRef < 0) {
      advancePool.push(advance);
      advanceRef = advancePool.length - 1;
    }
    const styleKey = JSON.stringify([
      probe.fontSizePx, probe.fontWeight, probe.italic, probe.script, probe.language,
    ]);
    let styleRef = stylePool.findIndex((row) => row.key === styleKey);
    if (styleRef < 0) {
      stylePool.push({
        key: styleKey,
        fontSizePx: probe.fontSizePx,
        fontWeight: probe.fontWeight,
        italic: probe.italic,
        scriptRef,
        languageRef,
      });
      styleRef = stylePool.length - 1;
    }
    const featuresKey = JSON.stringify(featureRefs);
    let featuresRef = featuresPool.findIndex((row) => row.key === featuresKey);
    if (featuresRef < 0) {
      featuresPool.push({ key: featuresKey, refs: featureRefs });
      featuresRef = featuresPool.length - 1;
    }
    return {
      textRef,
      advanceRef,
      styleRef,
      featuresRef,
    };
  });

  const faceTexts = faces.map((face) => JSON.stringify(face));
  const typographyTexts = typographies.map((row) => JSON.stringify(row));
  const revisionText = JSON.stringify(revisions);

  const parts = [];
  parts.push(...encoder.encode("TIQTBL02"));
  writeU32(parts, replayStrings.length);
  writeU32(parts, strings.length);
  writeU32(parts, metricRows.length);
  writeU32(parts, valuePool.length);
  writeU32(parts, probeRows.length);
  writeU32(parts, advancePool.length);
  writeU32(parts, stylePool.length);
  writeU32(parts, featuresPool.length);
  writeU32(parts, faceTexts.length);
  writeU32(parts, typographyTexts.length);
  writeU32(parts, valueStyles.length);
  writeU32(parts, fontPreloads.length);

  writeOffsetsAndBytes(parts, strings);
  const sortedRefs = strings.map((_, index) => index)
    .sort((left, right) => (strings[left] < strings[right] ? -1 : strings[left] > strings[right] ? 1 : 0));
  for (const ref of sortedRefs) writeU32(parts, ref);

  for (const row of metricRows) {
    writeU32(parts, row.familiesRef);
    writeF64(parts, row.weight);
    parts.push(row.italic);
    writeU32(parts, row.roleRef);
    writeU32(parts, row.faceSelectionRef);
    writeU32(parts, row.valuePoolRef);
  }
  for (const pool of valuePool) {
    for (const value of pool.values) {
      if (value == null) writeAbsentF64(parts);
      else writeF64(parts, value);
    }
  }

  for (const row of probeRows) {
    writeU32(parts, row.textRef);
    writeU32(parts, row.advanceRef);
    writeU32(parts, row.styleRef);
    writeU32(parts, row.featuresRef);
  }
  for (const advance of advancePool) writeF64(parts, advance);
  for (const style of stylePool) {
    writeF64(parts, style.fontSizePx);
    writeF64(parts, style.fontWeight);
    parts.push(style.italic ? 1 : 0);
    writeU32(parts, style.scriptRef);
    writeU32(parts, style.languageRef);
  }
  writeOffsetsAndBytes(parts, featuresPool.map((pool) => {
    const row = [];
    writeU16(row, pool.refs.length);
    for (const ref of pool.refs) writeU32(row, ref);
    return String.fromCharCode(...row);
  }));
  writeOffsetsAndBytes(parts, faceTexts);
  writeOffsetsAndBytes(parts, typographyTexts);
  writeOffsetsAndBytes(parts, valueStyles);
  writeOffsetsAndBytes(parts, fontPreloads);
  parts.push(...encoder.encode(revisionText));
  return new Uint8Array(parts);
}
