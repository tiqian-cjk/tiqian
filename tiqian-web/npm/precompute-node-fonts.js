import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { createFontSession } from "./precompute-fonts.js";

const DUMMY_PUBLIC_ORIGIN = "https://tiqian.invalid";

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

function sourceFileUrl(source) {
  if (source instanceof URL) {
    if (source.protocol !== "file:") throw new Error(`RemoteFontStylesheetNotSupported:${source.href}`);
    return source;
  }
  if (typeof source !== "string" || !source.trim()) throw new Error("UnsupportedFontStylesheetSource");
  if (/^[a-z][a-z0-9+.-]*:/iu.test(source)) {
    const url = new URL(source);
    if (url.protocol !== "file:") throw new Error(`RemoteFontStylesheetNotSupported:${source}`);
    return url;
  }
  return pathToFileURL(resolve(source));
}

function cssProperty(body, name) {
  const match = new RegExp(`(?:^|;)\\s*${name}\\s*:\\s*([^;}]+)`, "iu").exec(body);
  return match?.[1].trim() ?? "";
}

function unquote(value) {
  const trimmed = String(value ?? "").trim();
  if (trimmed.length >= 2 && (
    trimmed.startsWith('"') && trimmed.endsWith('"') ||
    trimmed.startsWith("'") && trimmed.endsWith("'")
  )) return trimmed.slice(1, -1);
  return trimmed;
}

function parseWeight(value) {
  const weights = String(value || "400").trim().split(/\s+/u).map(Number);
  if (weights.length === 1 && Number.isFinite(weights[0]) && weights[0] > 0) return weights[0];
  if (weights.length === 2 && weights.every((weight) => Number.isFinite(weight) && weight > 0) &&
      weights[1] >= weights[0]) return weights;
  throw new Error(`UnsupportedFontStylesheetWeight:${value}`);
}

function parseStyle(value) {
  const style = String(value || "normal").trim().toLowerCase();
  if (style === "normal" || style === "italic") return style;
  throw new Error(`UnsupportedFontStylesheetStyle:${value}`);
}

function resolvePublicAssetUrl(assetUrl, stylesheetPublicUrl) {
  if (/^[a-z][a-z0-9+.-]*:/iu.test(assetUrl)) return new URL(assetUrl).href;
  const stylesheetUrl = String(stylesheetPublicUrl ?? "").trim();
  if (!stylesheetUrl) throw new Error(`MissingFontStylesheetPublicUrl:${assetUrl}`);
  const base = new URL(stylesheetUrl, DUMMY_PUBLIC_ORIGIN);
  const resolved = new URL(assetUrl, base);
  return resolved.origin === DUMMY_PUBLIC_ORIGIN
    ? `${resolved.pathname}${resolved.search}${resolved.hash}`
    : resolved.href;
}

export function parseBuildFontStylesheet(css, stylesheet) {
  const stylesheetFileUrl = sourceFileUrl(stylesheet.source);
  const faces = [];
  for (const match of String(css).replaceAll(/\/\*[\s\S]*?\*\//gu, "")
    .matchAll(/@font-face\s*\{([^}]*)\}/giu)) {
    const body = match[1];
    const family = unquote(cssProperty(body, "font-family"));
    if (!family) throw new Error("MissingFontStylesheetFamily");
    const source = cssProperty(body, "src");
    const urlMatch = /url\(\s*(['"]?)([^'")]+)\1\s*\)/iu.exec(source);
    if (!urlMatch) throw new Error(`MissingFontStylesheetUrl:${family}`);
    const assetUrl = urlMatch[2];
    const sourceUrl = new URL(assetUrl, stylesheetFileUrl);
    if (sourceUrl.protocol !== "file:") {
      throw new Error(`RemoteFontSourceNotSupported:${sourceUrl.href}`);
    }
    faces.push({
      family,
      source: fileURLToPath(sourceUrl),
      publicUrl: resolvePublicAssetUrl(assetUrl, stylesheet.publicUrl),
      weight: parseWeight(cssProperty(body, "font-weight")),
      style: parseStyle(cssProperty(body, "font-style")),
      unicodeRange: cssProperty(body, "unicode-range"),
    });
  }
  if (faces.length === 0) {
    throw new Error(`MissingFontFacesInStylesheet:${fileURLToPath(stylesheetFileUrl)}`);
  }
  return faces;
}

async function loadStylesheetFaces(stylesheets) {
  const faces = [];
  for (const stylesheet of stylesheets) {
    if (!stylesheet || typeof stylesheet !== "object") throw new Error("InvalidFontStylesheet");
    const stylesheetFileUrl = sourceFileUrl(stylesheet.source);
    const css = await readFile(fileURLToPath(stylesheetFileUrl), "utf8");
    faces.push(...parseBuildFontStylesheet(css, stylesheet));
  }
  return faces.map((face, sourceOrder) => ({ ...face, sourceOrder }));
}

export async function createBuildFontSession(input = {}, options = {}) {
  const explicitFaces = Array.from(input.faces ?? []);
  const stylesheets = Array.from(input.fontStylesheets ?? []);
  if (explicitFaces.length > 0 && stylesheets.length > 0) {
    throw new Error("ConflictingBuildFontSources");
  }
  const faceSpecs = explicitFaces.length > 0
    ? explicitFaces
    : await loadStylesheetFaces(stylesheets);
  if (faceSpecs.length === 0) throw new Error("MissingBuildFontSource");
  const loaded = await Promise.all(faceSpecs.map(async (spec) => ({
    ...spec,
    source: await readSource(spec.source),
  })));
  return createFontSession(loaded, { ...options, sessionPrefix: "tq-build-font" });
}
