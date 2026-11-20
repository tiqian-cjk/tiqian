// The font capability exports of `@tiqian/ffi`, served directly by the
// single-source generated tree under ./engine-gen (copied from the bundle
// driver product engine-haxe/out/ts/gen; do not edit the vendored files). The
// JSON-through-JavaScript wire matches the retired Kotlin/JS exports
// (FontExports.kt + the WireJson.kt parse helpers): requests enter as JSON
// strings, responses leave as JSON strings, and the emission order of every
// field matches the Kotlin builder. Numbers are the exact f64 results of the
// same formulas (TCN-45: the retired Kotlin/JS values carried f32-grid
// artifacts, which are not reproduced).
//
// The FontMetricsRequest / FontRequest JSON parsing below is still a
// hand-written shell; the request models have not joined a protocol bundle
// yet, and this shell is replaced when they do.

import { TextRange } from "./engine-gen/org/tiqian/core/TextRange.js";
import { FontMetricsRequest, StubFontMetricsResolver } from "./engine-gen/org/tiqian/font/FontMetrics.js";
import { FontRole } from "./engine-gen/org/tiqian/font/FontRole.js";
import { FontRequest } from "./engine-gen/org/tiqian/font/FontPolicy.js";
import { PreferCjkForAmbiguousPunctuationResolver } from "./engine-gen/org/tiqian/font/PreferCjkForAmbiguousPunctuationResolver.js";

/** Reads one dynamically present string member; absent and mistyped are empty. */
function stringMember(raw, name) {
  if (raw === null) return "";
  const value = raw[name];
  return typeof value === "string" ? value : "";
}

/** Reads one dynamically present number member; absent and mistyped are NaN. */
function numberMember(raw, name) {
  if (raw === null) return Number.NaN;
  const value = raw[name];
  return typeof value === "number" ? value : Number.NaN;
}

/** Reads one dynamically present boolean member; absent and mistyped are false. */
function booleanMember(raw, name) {
  if (raw === null) return false;
  const value = raw[name];
  return typeof value === "boolean" ? value : false;
}

/** Reads a JSON string array the way WireJson.kt parseDynamicStringList does. */
function stringListMember(raw, name) {
  if (raw === null) return [];
  const value = raw[name];
  if (!Array.isArray(value)) return [];
  return value.map((item) => (typeof item === "string" ? item : ""));
}

/**
 * Decodes a font role name the way WireJson.kt does: a present string goes
 * through the enum name lookup, and an unknown name raises the same failure
 * identity as Kotlin's FontRole.valueOf; anything else is FontRole.Unknown.
 */
function fontRoleMember(raw, name) {
  const value = raw === null ? undefined : raw[name];
  if (typeof value !== "string") return FontRole.Unknown;
  const role = FontRole[value];
  if (role === undefined) {
    throw makeIllegalArgument("Failed to create enum FontRole entry " + value);
  }
  return role;
}

/** Mirrors the identity of Kotlin's IllegalArgumentException on this wire. */
class IllegalArgumentException extends Error {
  constructor(message) {
    super(message);
    this.name = "IllegalArgumentException";
  }
}

function makeIllegalArgument(message) {
  return new IllegalArgumentException(message);
}

/** Parses a FontMetricsRequest JSON the way WireJson.kt parseFontMetricsRequestJson does. */
function parseFontMetricsRequestJson(json) {
  let raw = JSON.parse(json);
  if (raw === null || typeof raw !== "object") raw = null;
  const fontWeight = numberMember(raw, "fontWeight");
  return new FontMetricsRequest(
    stringMember(raw, "fontKey"),
    numberMember(raw, "fontSize"),
    fontRoleMember(raw, "role"),
    stringMember(raw, "locale"),
    stringListMember(raw, "fontFamilies"),
    Number.isNaN(fontWeight) ? null : Math.trunc(fontWeight),
    booleanMember(raw, "italic"),
    stringMember(raw, "faceSelectionText"),
  );
}

/** Parses a FontRequest JSON the way WireJson.kt parseFontRequestJson does. */
function parseFontRequestJson(json) {
  let raw = JSON.parse(json);
  if (raw === null || typeof raw !== "object") raw = null;
  return new FontRequest(
    stringListMember(raw, "preferredFamilies"),
    stringMember(raw, "locale"),
    fontRoleMember(raw, "role"),
  );
}

/**
 * Renders one wire number exactly like the Kotlin builder: the ECMA shortest
 * round-trip form, with NaN/Infinity spelled out and zero folded to "0".
 */
function appendJsonNumber(out, value) {
  if (Number.isNaN(value)) {
    out.push("NaN");
  } else if (value === Number.POSITIVE_INFINITY) {
    out.push("Infinity");
  } else if (value === Number.NEGATIVE_INFINITY) {
    out.push("-Infinity");
  } else if (value === 0) {
    out.push("0");
  } else {
    out.push(String(value));
  }
}

/** Renders one wire string exactly like WireJson.kt appendJsonString. */
function appendJsonString(out, value) {
  out.push(JSON.stringify(value));
}

/**
 * Resolves the engine's data-free font metrics for a JSON FontMetricsRequest
 * and returns the RawFontMetrics as JSON (ascent/descent/leading/source, plus
 * typoAscent/typoDescent when the face carries a declared typographic box).
 */
export function fontMetricsResolve(requestJson) {
  const request = parseFontMetricsRequestJson(requestJson);
  const metrics = new StubFontMetricsResolver().resolve(request);
  const out = [];
  out.push('{"ascent":');
  appendJsonNumber(out, metrics.ascent);
  out.push(',"descent":');
  appendJsonNumber(out, metrics.descent);
  out.push(',"leading":');
  appendJsonNumber(out, metrics.leading);
  out.push(',"source":');
  appendJsonString(out, metrics.source.kind);
  if (metrics.typoAscent !== null && metrics.typoAscent !== undefined) {
    out.push(',"typoAscent":');
    appendJsonNumber(out, metrics.typoAscent);
  }
  if (metrics.typoDescent !== null && metrics.typoDescent !== undefined) {
    out.push(',"typoDescent":');
    appendJsonNumber(out, metrics.typoDescent);
  }
  out.push("}");
  return out.join("");
}

/**
 * Resolves the engine's LatinVsCjkFaceSelection fallback decision for the
 * source text substring in start..<end given a JSON FontRequest
 * (preferredFamilies/locale/role). Emission order matches FontExports.kt.
 */
export function fontFallbackResolve(text, start, end, requestJson) {
  const request = parseFontRequestJson(requestJson);
  const decision = new PreferCjkForAmbiguousPunctuationResolver().resolve(
    text,
    new TextRange(start, end),
    request,
  );
  const out = [];
  out.push('{"range":{"start":');
  appendJsonNumber(out, decision.range.start);
  out.push(',"end":');
  appendJsonNumber(out, decision.range.end);
  out.push("}");
  out.push(',"candidate":{"key":');
  appendJsonString(out, decision.candidate.key);
  out.push(',"family":');
  appendJsonString(out, decision.candidate.family);
  out.push(',"role":');
  appendJsonString(out, decision.candidate.role.kind);
  out.push('},"role":');
  appendJsonString(out, decision.role.kind);
  out.push(',"reason":');
  appendJsonString(out, decision.reason);
  out.push("}");
  return out.join("");
}
