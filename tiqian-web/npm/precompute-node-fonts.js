import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import { createFontSession } from "./precompute-fonts.js";

async function readSource(source) {
  if (source instanceof Uint8Array) return source;
  if (source instanceof ArrayBuffer) return new Uint8Array(source);
  if (source instanceof URL) {
    if (source.protocol !== "file:") throw new Error(`RemoteFontSourceNotSupported:${source.href}`);
    return new Uint8Array(await readFile(fileURLToPath(source)));
  }
  if (typeof source === "string") {
    if (/^[a-z][a-z0-9+.-]*:/iu.test(source)) {
      const url = new URL(source);
      if (url.protocol !== "file:") throw new Error(`RemoteFontSourceNotSupported:${source}`);
      return new Uint8Array(await readFile(fileURLToPath(url)));
    }
    return new Uint8Array(await readFile(source));
  }
  throw new Error("UnsupportedFontSource");
}

export async function createBuildFontSession(faceSpecs) {
  if (!Array.isArray(faceSpecs) || faceSpecs.length === 0) throw new Error("MissingExplicitFontFaces");
  const loaded = await Promise.all(faceSpecs.map(async (spec) => ({
    ...spec,
    source: await readSource(spec.source),
  })));
  return createFontSession(loaded, { sessionPrefix: "tq-build-font" });
}
