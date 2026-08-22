import {
  FONT_REPLAY_REVISION,
  FONT_REPLAY_TRANSPORT,
  metricReplayKey,
  shapeReplayKey,
} from "./snapshot-schema.js";

function expandReplayShapes(shapes, stringAt) {
  return shapes.map((row) => {
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
}

/** Expands entry rows against the station-table accessors. */
function expandManifestEntries(
  entries,
  typographyAt,
  faceAt,
  evidenceVersions,
  resolveProbe,
) {
  return entries.map((entry) => {
    const typography = typographyAt(entry?.typographyRef);
    if (!typography || typeof typography.sha256 !== "string" || !typography.value) {
      throw new Error("SnapshotTypographyTableInvalid");
    }
    if (!Array.isArray(entry.fontFaceEvidence) || entry.fontFaceEvidence.length === 0) {
      throw new Error("SnapshotFontEvidenceReferenceInvalid");
    }
    const faces = entry.fontFaceEvidence.map((evidence) => ({
      ...faceAt(evidence?.faceRef),
      coverageText: evidence.coverageText,
      probe: resolveProbe(evidence),
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
      fontEvidence: { ...evidenceVersions, faces },
      renderArtifactSha256: entry.renderArtifactSha256,
    };
  });
}

/** View to its replay-metric rows; one build's expansions share the mapping. */
const replayMetricsByView = new WeakMap();

function replayMetricsOf(view) {
  let metrics = replayMetricsByView.get(view);
  if (metrics === undefined) {
    metrics = view.metricRows().map((row) => ({
      key: metricReplayKey(
        row.serializedFamilies,
        row.fontWeight,
        row.italic,
        row.role,
        row.faceSelectionText,
      ),
      valuesEm: row.valuesEm,
    }));
    replayMetricsByView.set(view, metrics);
  }
  return metrics;
}

/**
 * The table view the expansion reads: the accessor surface
 * `snapshotTablesFromBytes` builds from the binary file. Any other shape
 * fails closed instead of failing on a missing method later.
 */
function tableViewOf(tables) {
  if (typeof tables.stringAt !== "function" || typeof tables.metricRows !== "function" ||
      typeof tables.probeAt !== "function" || typeof tables.typographyAt !== "function" ||
      typeof tables.faceAt !== "function" || typeof tables.valueStyles !== "function" ||
      typeof tables.revisions !== "function") {
    throw new Error("SnapshotTablesInvalid");
  }
  return tables;
}

/**
 * Expands the compact transport into the canonical runtime manifest shape.
 * Integer references resolve through the station table the transport loaded
 * and verified against `manifest.tables.snapshot`; a manifest without the
 * tables pin is not a shape this build reads. Replay shapes pick up the table
 * string region, metrics come from the table, and value styles splice in so
 * the style-installation site reads one shape.
 */
export function expandSnapshotManifest(manifest, tables = null) {
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
    throw new Error("SnapshotManifestInvalid");
  }
  if (manifest.tables == null) throw new Error("SnapshotManifestTablesInvalid");
  if (tables == null) throw new Error("SnapshotTablesMissing");
  const view = tableViewOf(tables);
  if (typeof manifest.tables !== "object" || Array.isArray(manifest.tables) ||
      typeof manifest.tables.snapshot !== "string") {
    throw new Error("SnapshotManifestTablesInvalid");
  }
  const replay = manifest.fontReplay;
  if (replay != null &&
      (replay.revision !== FONT_REPLAY_REVISION ||
       replay.encoding !== FONT_REPLAY_TRANSPORT || !Array.isArray(replay.shapes))) {
    throw new Error("SnapshotFontReplayInvalid");
  }
  const fontReplay = replay == null
    ? undefined
    : {
      revision: replay.revision,
      shapes: expandReplayShapes(replay.shapes, view.stringAt),
      metrics: replayMetricsOf(view),
    };
  const evidenceVersions = {
    backendRevision: view.revisions().backendRevision,
    harfbuzzVersion: view.revisions().harfbuzzVersion,
  };
  const resolveProbe = (evidence) => evidence?.probeRef == null
    ? undefined
    : view.probeAt(evidence.probeRef);
  const expandEntries = (entries) => expandManifestEntries(
    entries,
    view.typographyAt,
    view.faceAt,
    evidenceVersions,
    resolveProbe,
  );
  const entries = expandEntries(manifest.entries);
  const fontContractEntries = Array.isArray(manifest.fontContractEntries)
    ? expandEntries(manifest.fontContractEntries)
    : undefined;
  return {
    ...manifest,
    ...(fontReplay ? { fontReplay } : {}),
    valueStyles: view.valueStyles(),
    entries,
    ...(fontContractEntries ? { fontContractEntries } : {}),
  };
}

export function parseSnapshotManifest(text, tables = null) {
  return expandSnapshotManifest(JSON.parse(text), tables);
}
