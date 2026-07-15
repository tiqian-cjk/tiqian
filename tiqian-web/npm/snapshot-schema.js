export const SNAPSHOT_SCHEMA = 1;
export const LAYOUT_REVISION = "tiqian-layout-v2";
export const RENDER_REVISION = "prebroken-dom-v10";
export const FONT_SOURCE_POLICY = "compatible-local-render-family-v2";
export const FONT_BACKEND_REVISION = "tiqian-shared-harfbuzz-v4";

export function stableStringify(value) {
  if (value == null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  const entries = Object.keys(value).sort().map((key) =>
    `${JSON.stringify(key)}:${stableStringify(value[key])}`);
  return `{${entries.join(",")}}`;
}
