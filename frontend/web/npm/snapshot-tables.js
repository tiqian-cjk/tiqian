// Station-table transport of ADR 0052 `TableTransport`. Roots carry a
// `tq-tables` attribute with space-separated references; each reference is a
// URL of a content-addressed table file or `#id` of an in-page element
// holding the same bytes. One global map deduplicates loads per reference,
// so every root of a page shares one table instance. A file is either the
// `TIQTBL02` binary or schema-2 JSON text; both load into the same accessor
// surface, and the raw bytes travel on so the layout worker rebuilds the
// table in its own context.

import { decodeSnapshotTableBinary, isSnapshotTableBinary } from "./snapshot-table-binary.js";

const TABLES_ATTRIBUTE = "tq-tables";

/** Reference key to loaded table; successes stay for the page lifetime. */
const loadedTables = new Map();
/** Reference key to the resolved, verified table, readable synchronously. */
const resolvedTables = new Map();

/**
 * Validates the shape of one parsed station table. Every consumer of table
 * rows goes through this check, so a hand-edited file fails with the same
 * issue whether it arrives over the network or through the worker contract.
 */
export function validateSnapshotTables(parsed) {
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed) ||
      parsed.schema !== 2 ||
      !Array.isArray(parsed.typographies) || !Array.isArray(parsed.faces) ||
      !Array.isArray(parsed.valueStyles) || !Array.isArray(parsed.probes) ||
      !Array.isArray(parsed.metrics) || !Array.isArray(parsed.strings) ||
      !parsed.valueStyles.every((row) => typeof row === "string")) {
    throw new Error("SnapshotTablesInvalid");
  }
  return parsed;
}

/** Parses and validates one station-table file of the JSON text form. */
export function parseSnapshotTables(text) {
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error("SnapshotTablesInvalid");
  }
  return validateSnapshotTables(parsed);
}

function tableRow(table, index, issue) {
  if (!Number.isSafeInteger(index) || index < 0 || index >= table.length) {
    throw new Error(issue);
  }
  return table[index];
}

/**
 * The accessor surface of one parsed JSON table: the same methods the binary
 * view exposes, resolved through the parsed arrays.
 */
export function textTableAccessors(parsed) {
  validateSnapshotTables(parsed);
  const stringAt = (ref) =>
    tableRow(parsed.strings, ref, "SnapshotFontReplayStringReferenceInvalid");
  // Manifest expansion reads the metric rows once per expansion; the rows are
  // a pure function of the parsed table, so the mapped form is memoized per
  // view and repeated expansions stop rescanning the whole table.
  let metricRowsCache = null;
  return {
    binary: false,
    stringAt,
    metricRows: () => {
      if (metricRowsCache === null) {
        metricRowsCache = parsed.metrics.map((row) => {
          if (!Array.isArray(row) || row.length !== 10 || (row[2] !== 0 && row[2] !== 1)) {
            throw new Error("SnapshotFontReplayMetricsTransportInvalid");
          }
          return {
            serializedFamilies: stringAt(row[0]),
            fontWeight: row[1],
            italic: row[2] === 1,
            role: stringAt(row[3]),
            faceSelectionText: stringAt(row[4]),
            valuesEm: row.slice(5),
          };
        });
      }
      return metricRowsCache;
    },
    probeAt: (ref) => tableRow(parsed.probes, ref, "SnapshotProbeReferenceInvalid"),
    typographyAt: (ref) => tableRow(parsed.typographies, ref, "SnapshotTypographyReferenceInvalid"),
    faceAt: (ref) => tableRow(parsed.faces, ref, "SnapshotFontFaceReferenceInvalid"),
    valueStyles: () => [...parsed.valueStyles],
    revisions: () => ({
      backendRevision: parsed.revisions?.backendRevision ?? null,
      harfbuzzVersion: parsed.revisions?.harfbuzzVersion ?? null,
    }),
  };
}

/**
 * Builds the accessor surface of one table file: the binary reader for the
 * `TIQTBL02` magic, the parsed-text accessors for JSON bytes.
 */
export function snapshotTablesFromBytes(bytes) {
  if (!(bytes instanceof Uint8Array)) throw new Error("SnapshotTablesInvalid");
  if (isSnapshotTableBinary(bytes)) return decodeSnapshotTableBinary(bytes);
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    throw new Error("SnapshotTablesInvalid");
  }
  return textTableAccessors(parseSnapshotTables(text));
}

async function digestBytes(bytes) {
  const digest = await globalThis.crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function loadTableBytes(key, documentObject) {
  if (key.startsWith("#")) {
    const element = documentObject?.getElementById?.(key.slice(1));
    const text = typeof element?.textContent === "string" ? element.textContent : "";
    if (text.trim() === "") throw new Error("SnapshotTablesReferenceMissing");
    return new TextEncoder().encode(text);
  }
  if (typeof globalThis.fetch !== "function") {
    throw new Error("SnapshotTablesFetchUnavailable");
  }
  const response = await globalThis.fetch(key);
  if (!response?.ok) throw new Error("SnapshotTablesFetchFailed");
  const buffer = await response.arrayBuffer();
  return new Uint8Array(buffer);
}

function tablePromiseFor(key, documentObject) {
  let promise = loadedTables.get(key);
  if (promise) return promise;
  // Failed loads stay uncached so a later root can retry after a transient
  // network failure; the map only memoizes verified tables.
  promise = (async () => {
    const bytes = await loadTableBytes(key, documentObject);
    const table = {
      bytes,
      view: snapshotTablesFromBytes(bytes),
      sha256: await digestBytes(bytes),
    };
    resolvedTables.set(key, table);
    return table;
  })();
  promise.catch(() => loadedTables.delete(key));
  loadedTables.set(key, promise);
  return promise;
}

function tableReferences(root) {
  const raw = root?.getAttribute?.(TABLES_ATTRIBUTE);
  if (typeof raw !== "string" || raw.trim() === "") return [];
  return raw.split(/\s+/u).filter((value) => value.length > 0);
}

/**
 * Resolves the station tables of one root. Every reference of the attribute
 * loads in order until one verifies against the sha the manifest pins; a
 * mismatch keeps walking the ladder so a stale file degrades the same way a
 * missing one does.
 */
export async function snapshotTablesForRoot(root, documentObject, expectedSha256 = null) {
  for (const key of tableReferences(root)) {
    let table;
    try {
      table = await tablePromiseFor(key, documentObject);
    } catch {
      continue;
    }
    if (expectedSha256 == null || table.sha256 === expectedSha256) return table;
  }
  return null;
}

/**
 * The already-verified table of one root, or null when no reference of the
 * attribute has finished loading. Synchronous callers use this as a
 * best-effort cache read; adoption paths resolve tables through the async
 * map instead.
 */
export function loadedSnapshotTablesForRoot(root, expectedSha256 = null) {
  for (const key of tableReferences(root)) {
    const table = resolvedTables.get(key);
    if (table == null) continue;
    if (expectedSha256 == null || table.sha256 === expectedSha256) return table;
  }
  return null;
}

/**
 * Pre-scans the document for table references and starts the loads before
 * the first root hydrates; ADR 0052 keeps this free of ordering contracts,
 * so a reference no root claims simply stays unused.
 */
export function prefetchSnapshotTables() {
  const documentObject = globalThis.document;
  if (!documentObject?.querySelectorAll) return;
  for (const element of documentObject.querySelectorAll(`[${TABLES_ATTRIBUTE}]`)) {
    for (const key of tableReferences(element)) {
      tablePromiseFor(key, documentObject).catch(() => {});
    }
  }
}
