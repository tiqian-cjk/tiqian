import { stableStringify } from "./snapshot-schema.js";

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

  const compactEntries = entries.map((entry) => {
    const evidence = entry.fontEvidence;
    if (!evidence || !Array.isArray(evidence.faces) || evidence.faces.length === 0) {
      throw new Error(`SnapshotFontEvidenceInvalid:${entry.key}`);
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
    entries,
    ...(fontContractEntries ? { fontContractEntries } : {}),
  };
}

export function parseSnapshotManifest(text) {
  return expandSnapshotManifest(JSON.parse(text));
}
