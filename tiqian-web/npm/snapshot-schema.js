export const SNAPSHOT_SCHEMA = 1;
export const LAYOUT_REVISION = "tiqian-layout-v2";
export const RENDER_REVISION = "prebroken-dom-v12";
export const FONT_SOURCE_POLICY = "compatible-local-render-family-v2";
export const FONT_BACKEND_REVISION = "tiqian-shared-harfbuzz-v5";
export const FONT_REPLAY_REVISION = "tiqian-server-shaping-replay-v1";
export const FONT_REPLAY_TRANSPORT = "shared-strings-v1";

export function shapeReplayKey(
  displayText,
  serializedFamilies,
  fontWeight,
  italic,
  locale,
  role,
  sourceText,
) {
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
  serializedFamilies,
  fontWeight,
  italic,
  role,
  faceSelectionText,
) {
  return JSON.stringify([
    serializedFamilies,
    Number(fontWeight),
    Boolean(italic),
    String(role),
    String(faceSelectionText),
  ]);
}

export function stableStringify(value) {
  if (value == null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  const entries = Object.keys(value).sort().map((key) =>
    `${JSON.stringify(key)}:${stableStringify(value[key])}`);
  return `{${entries.join(",")}}`;
}
