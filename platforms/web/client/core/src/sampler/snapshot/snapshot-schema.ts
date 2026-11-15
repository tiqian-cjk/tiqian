// The manifest schema numbers and the revision constant family are
// single-sourced in engine-haxe/src/org/tiqian/protocol/Revision.hx and
// vendored here as the generated module (boring cutover Stage1-P4); the
// re-exports below keep the module API of this file unchanged for every
// import site.
import { Revision } from "@tiqian/protocol/org/tiqian/protocol/Revision";

export const SNAPSHOT_SCHEMA = Revision.SNAPSHOT_SCHEMA;
export const SNAPSHOT_TABLES_SCHEMA = Revision.SNAPSHOT_TABLES_SCHEMA;
export const LAYOUT_REVISION = Revision.LAYOUT_REVISION;
export const RENDER_REVISION = Revision.RENDER_REVISION;
export const FONT_SOURCE_POLICY = Revision.FONT_SOURCE_POLICY;
export const FONT_BACKEND_REVISION = Revision.FONT_BACKEND_REVISION;
export const FONT_REPLAY_REVISION = Revision.FONT_REPLAY_REVISION;
export const FONT_REPLAY_TRANSPORT = Revision.FONT_REPLAY_TRANSPORT;

/** The manifest schema this runtime build reads: snapshot tables. */
export function readableSnapshotSchema(schema: unknown): boolean {
  return schema === SNAPSHOT_TABLES_SCHEMA;
}

export function shapeReplayKey(
  displayText: unknown,
  serializedFamilies: unknown,
  fontWeight: unknown,
  italic: unknown,
  locale: unknown,
  role: unknown,
  sourceText: unknown,
): string {
  return JSON.stringify([
    displayText,
    serializedFamilies,
    Number(fontWeight),
    Boolean(italic),
    String(locale),
    String(role),
    sourceText,
  ]);
}

export function metricReplayKey(
  serializedFamilies: unknown,
  fontWeight: unknown,
  italic: unknown,
  role: unknown,
  faceSelectionText: unknown,
): string {
  return JSON.stringify([
    serializedFamilies,
    Number(fontWeight),
    Boolean(italic),
    String(role),
    String(faceSelectionText),
  ]);
}

export function stableStringify(value: unknown): string {
  if (value == null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  const entries = Object.keys(value).sort().map((key) =>
    `${JSON.stringify(key)}:${stableStringify((value as Record<string, unknown>)[key])}`);
  return `{${entries.join(",")}}`;
}
