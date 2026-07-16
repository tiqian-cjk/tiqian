import {
  FONT_REPLAY_REVISION,
  FONT_REPLAY_TRANSPORT,
  metricReplayKey,
  shapeReplayKey,
  stableStringify,
} from "./snapshot-schema.js";

const FACE_DYNAMIC_KEYS = new Set(["coverageText", "probe"]);

function faceDescriptor(face) {
  return Object.fromEntries(Object.entries(face).filter(([key]) => !FACE_DYNAMIC_KEYS.has(key)));
}

function tableIndex(table, indexes, value) {
  const signature = stableStringify(value);
  const existing = indexes.get(signature);
  if (existing != null) return existing;
  const index = table.length;
  table.push(value);
  indexes.set(signature, index);
  return index;
}

function replayKeyParts(key, expectedLength, issue) {
  let parts;
  try {
    parts = JSON.parse(key);
  } catch {
    throw new Error(issue);
  }
  if (!Array.isArray(parts) || parts.length !== expectedLength) throw new Error(issue);
  return parts;
}

function compactFontReplay(shapes, metrics) {
  const strings = [];
  const indexes = new Map();
  const stringRef = (value) => {
    if (typeof value !== "string") throw new Error("SnapshotFontReplayStringInvalid");
    const existing = indexes.get(value);
    if (existing != null) return existing;
    const index = strings.length;
    strings.push(value);
    indexes.set(value, index);
    return index;
  };
  const compactShapes = shapes.map((item) => {
    if (!item || typeof item.key !== "string" || !item.result ||
        !Array.isArray(item.result.features) || !Array.isArray(item.result.glyphs)) {
      throw new Error("SnapshotFontReplayShapeInvalid");
    }
    const [displayText, serializedFamilies, fontWeight, italic, locale, role, sourceText] =
      replayKeyParts(item.key, 7, "SnapshotFontReplayShapeKeyInvalid");
    const glyphs = item.result.glyphs.flatMap((glyph) => {
      if (!glyph || typeof glyph !== "object") {
        throw new Error("SnapshotFontReplayGlyphInvalid");
      }
      const bounds = glyph.boundsEm == null ? [null, null, null, null] : glyph.boundsEm;
      if (!Array.isArray(bounds) || bounds.length !== 4) {
        throw new Error("SnapshotFontReplayGlyphBoundsInvalid");
      }
      return [glyph.id, glyph.advanceEm, glyph.xEm, glyph.yEm, ...bounds];
    });
    return [
      stringRef(displayText),
      stringRef(serializedFamilies),
      fontWeight,
      italic ? 1 : 0,
      stringRef(locale),
      stringRef(role),
      stringRef(sourceText),
      stringRef(item.result.faceId),
      stringRef(item.result.fontInstanceId),
      stringRef(item.result.script),
      item.result.features.map(stringRef),
      item.result.unsafeBreakCount,
      item.result.advanceEm,
      glyphs,
    ];
  });
  const compactMetrics = metrics.map((item) => {
    if (!item || typeof item.key !== "string" || !Array.isArray(item.valuesEm) ||
        item.valuesEm.length !== 5) {
      throw new Error("SnapshotFontReplayMetricsInvalid");
    }
    const [serializedFamilies, fontWeight, italic, role, faceSelectionText] =
      replayKeyParts(item.key, 5, "SnapshotFontReplayMetricsKeyInvalid");
    return [
      stringRef(serializedFamilies),
      fontWeight,
      italic ? 1 : 0,
      stringRef(role),
      stringRef(faceSelectionText),
      ...item.valuesEm,
    ];
  });
  return {
    revision: FONT_REPLAY_REVISION,
    encoding: FONT_REPLAY_TRANSPORT,
    strings,
    shapes: compactShapes,
    metrics: compactMetrics,
  };
}

function expandFontReplay(replay) {
  if (!replay || replay.revision !== FONT_REPLAY_REVISION ||
      !Array.isArray(replay.shapes) || !Array.isArray(replay.metrics)) {
    throw new Error("SnapshotFontReplayInvalid");
  }
  // Canonical in-memory manifests remain accepted by the parser so callers can
  // register a manifest without first serializing the compact transport.
  if (replay.encoding == null) return replay;
  if (replay.encoding !== FONT_REPLAY_TRANSPORT || !Array.isArray(replay.strings) ||
      replay.strings.some((value) => typeof value !== "string")) {
    throw new Error("SnapshotFontReplayTransportInvalid");
  }
  const stringAt = (index) => tableReference(
    replay.strings,
    index,
    "SnapshotFontReplayStringReferenceInvalid",
  );
  const shapes = replay.shapes.map((row) => {
    if (!Array.isArray(row) || row.length !== 14 || !Array.isArray(row[10]) ||
        !Array.isArray(row[13]) || row[13].length % 8 !== 0 ||
        (row[3] !== 0 && row[3] !== 1)) {
      throw new Error("SnapshotFontReplayShapeTransportInvalid");
    }
    const glyphs = [];
    for (let index = 0; index < row[13].length; index += 8) {
      const bounds = row[13].slice(index + 4, index + 8);
      const allNull = bounds.every((value) => value == null);
      if (!allNull && bounds.some((value) => value == null)) {
        throw new Error("SnapshotFontReplayGlyphBoundsInvalid");
      }
      glyphs.push({
        id: row[13][index],
        advanceEm: row[13][index + 1],
        xEm: row[13][index + 2],
        yEm: row[13][index + 3],
        boundsEm: allNull ? null : bounds,
      });
    }
    const displayText = stringAt(row[0]);
    const serializedFamilies = stringAt(row[1]);
    const fontWeight = row[2];
    const italic = row[3] === 1;
    const locale = stringAt(row[4]);
    const role = stringAt(row[5]);
    const sourceText = stringAt(row[6]);
    return {
      key: shapeReplayKey(
        displayText,
        serializedFamilies,
        fontWeight,
        italic,
        locale,
        role,
        sourceText,
      ),
      result: {
        faceId: stringAt(row[7]),
        fontInstanceId: stringAt(row[8]),
        script: stringAt(row[9]),
        features: row[10].map(stringAt),
        unsafeBreakCount: row[11],
        advanceEm: row[12],
        glyphs,
      },
    };
  });
  const metrics = replay.metrics.map((row) => {
    if (!Array.isArray(row) || row.length !== 10 || (row[2] !== 0 && row[2] !== 1)) {
      throw new Error("SnapshotFontReplayMetricsTransportInvalid");
    }
    const serializedFamilies = stringAt(row[0]);
    const fontWeight = row[1];
    const italic = row[2] === 1;
    const role = stringAt(row[3]);
    const faceSelectionText = stringAt(row[4]);
    return {
      key: metricReplayKey(
        serializedFamilies,
        fontWeight,
        italic,
        role,
        faceSelectionText,
      ),
      valuesEm: row.slice(5),
    };
  });
  return { revision: replay.revision, shapes, metrics };
}

/**
 * SharedSnapshotManifestTables: large immutable typography and font-face
 * descriptors live once per snapshot. Paragraph entries retain only table
 * references plus their source-specific coverage/probe evidence.
 */
export function compactSnapshotManifest(entries, metadata) {
  const typographies = [];
  const typographyIndexes = new Map();
  const faces = [];
  const faceIndexes = new Map();
  let backendRevision = null;
  let harfbuzzVersion = null;
  const replayShapes = [];
  const replayShapeIndexes = new Map();
  const replayMetrics = [];
  const replayMetricIndexes = new Map();

  const compactEntries = entries.map((entry) => {
    const evidence = entry.fontEvidence;
    if (!evidence || !Array.isArray(evidence.faces) || evidence.faces.length === 0) {
      throw new Error(`SnapshotFontEvidenceInvalid:${entry.key}`);
    }
    if (
      evidence.replay?.revision !== FONT_REPLAY_REVISION ||
      !Array.isArray(evidence.replay.shapes) ||
      !Array.isArray(evidence.replay.metrics)
    ) {
      throw new Error(`SnapshotFontReplayInvalid:${entry.key}`);
    }
    for (const shape of evidence.replay.shapes) {
      tableIndex(replayShapes, replayShapeIndexes, shape);
    }
    for (const metric of evidence.replay.metrics) {
      tableIndex(replayMetrics, replayMetricIndexes, metric);
    }
    backendRevision ??= evidence.backendRevision;
    harfbuzzVersion ??= evidence.harfbuzzVersion;
    if (backendRevision !== evidence.backendRevision || harfbuzzVersion !== evidence.harfbuzzVersion) {
      throw new Error("SnapshotFontEvidenceVersionConflict");
    }
    const typographyRef = tableIndex(
      typographies,
      typographyIndexes,
      { sha256: entry.typographySha256, value: entry.typography },
    );
    const fontFaceEvidence = evidence.faces.map((face) => ({
      faceRef: tableIndex(faces, faceIndexes, faceDescriptor(face)),
      coverageText: face.coverageText,
      probe: face.probe,
    }));
    return {
      key: entry.key,
      sourceSha256: entry.sourceSha256,
      ...(typeof entry.sourceArtifactSha256 === "string"
        ? { sourceArtifactSha256: entry.sourceArtifactSha256 }
        : {}),
      ...(Array.isArray(entry.semantics) && entry.semantics.length > 0 ? { semantic: true } : {}),
      typographyRef,
      maxWidthPx: entry.maxWidthPx,
      fontFaceEvidence,
      renderArtifactSha256: entry.renderArtifactSha256,
    };
  });

  return {
    ...metadata,
    typographies,
    fontEvidence: { backendRevision, harfbuzzVersion, faces },
    fontReplay: compactFontReplay(replayShapes, replayMetrics),
    entries: compactEntries,
  };
}

function tableReference(table, index, issue) {
  if (!Number.isSafeInteger(index) || index < 0 || index >= table.length) {
    throw new Error(issue);
  }
  return table[index];
}

/** Expands the compact transport into the canonical runtime manifest shape. */
export function expandSnapshotManifest(manifest) {
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
    throw new Error("SnapshotManifestInvalid");
  }
  if (!Array.isArray(manifest.typographies) ||
      !manifest.fontEvidence || !Array.isArray(manifest.fontEvidence.faces) ||
      !Array.isArray(manifest.entries)) {
    throw new Error("SnapshotManifestTablesInvalid");
  }
  const typographies = manifest.typographies;
  const descriptors = manifest.fontEvidence.faces;
  const fontReplay = manifest.fontReplay == null
    ? undefined
    : expandFontReplay(manifest.fontReplay);
  const expandEntries = (entries) => entries.map((entry) => {
    const typography = tableReference(
      typographies,
      entry?.typographyRef,
      "SnapshotTypographyReferenceInvalid",
    );
    if (!typography || typeof typography.sha256 !== "string" || !typography.value) {
      throw new Error("SnapshotTypographyTableInvalid");
    }
    if (!Array.isArray(entry.fontFaceEvidence) || entry.fontFaceEvidence.length === 0) {
      throw new Error("SnapshotFontEvidenceReferenceInvalid");
    }
    const faces = entry.fontFaceEvidence.map((evidence) => ({
      ...tableReference(
        descriptors,
        evidence?.faceRef,
        "SnapshotFontFaceReferenceInvalid",
      ),
      coverageText: evidence.coverageText,
      probe: evidence.probe,
    }));
    return {
      key: entry.key,
      sourceSha256: entry.sourceSha256,
      ...(typeof entry.sourceArtifactSha256 === "string"
        ? { sourceArtifactSha256: entry.sourceArtifactSha256 }
        : {}),
      ...(entry.semantic === true ? { semantic: true } : {}),
      typographySha256: typography.sha256,
      typography: typography.value,
      maxWidthPx: entry.maxWidthPx,
      fontEvidence: {
        backendRevision: manifest.fontEvidence.backendRevision,
        harfbuzzVersion: manifest.fontEvidence.harfbuzzVersion,
        faces,
      },
      renderArtifactSha256: entry.renderArtifactSha256,
    };
  });
  const entries = expandEntries(manifest.entries);
  const fontContractEntries = Array.isArray(manifest.fontContractEntries)
    ? expandEntries(manifest.fontContractEntries)
    : undefined;
  return {
    ...manifest,
    ...(fontReplay ? { fontReplay } : {}),
    entries,
    ...(fontContractEntries ? { fontContractEntries } : {}),
  };
}

export function parseSnapshotManifest(text) {
  return expandSnapshotManifest(JSON.parse(text));
}
