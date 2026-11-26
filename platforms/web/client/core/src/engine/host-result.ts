// Conversion of host shaping results and font metrics into the engine's typed
// objects. The host (baked replay table or canvas measurement) reports plain
// records; these functions apply the engine's field defaults and construct the
// engine types, exactly as the retired JSON boundary did.

import { TextRange } from "@tiqian/engine/org/tiqian/core/TextRange";
import { Cluster } from "@tiqian/engine/org/tiqian/core/Cluster";
import { Glyph } from "@tiqian/engine/org/tiqian/core/Glyph";
import { GlyphRun } from "@tiqian/engine/org/tiqian/core/GlyphRun";
import { ShapingDecisionInfo } from "@tiqian/engine/org/tiqian/core/ShapingDecisionInfo";
import { ShapingResult } from "@tiqian/engine/org/tiqian/shaping/TextShaper";
import { RawFontMetrics } from "@tiqian/engine/org/tiqian/font/RawFontMetrics";
import { FontMetricSource } from "@tiqian/engine/org/tiqian/font/FontMetricSource";

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object";
}

function stringMember(raw: Record<string, unknown> | null, name: string): string {
  if (raw === null) return "";
  const value = raw[name];
  return typeof value === "string" ? value : "";
}

function numberMember(raw: Record<string, unknown> | null, name: string): number {
  if (raw === null) return Number.NaN;
  const value = raw[name];
  return typeof value === "number" ? value : Number.NaN;
}

// A shaping response without a baseline shift means exactly 0; a present,
// non-numeric value stays NaN so the malformed field still surfaces.
function optionalNumberMember(raw: Record<string, unknown>, name: string): number {
  const value = raw[name];
  if (value === undefined || value === null) return 0.0;
  return typeof value === "number" ? value : Number.NaN;
}

function stringListMember(raw: Record<string, unknown>, name: string): string[] {
  const value = raw[name];
  if (!Array.isArray(value)) return [];
  return value.map((item) => (typeof item === "string" ? item : ""));
}

function integerMember(raw: Record<string, unknown>, name: string): number {
  const value = raw[name];
  return typeof value === "number" ? Math.trunc(value) : 0;
}

function nullableString(raw: Record<string, unknown>, name: string): string | null {
  const value = raw[name];
  return typeof value === "string" ? value : null;
}

function rangeOf(value: unknown): TextRange {
  if (!isRecord(value)) return new TextRange(0, 0);
  return new TextRange(
    Math.trunc(typeof value.start === "number" ? value.start : 0),
    Math.trunc(typeof value.end === "number" ? value.end : 0),
  );
}

function listOf(value: unknown): Array<Record<string, unknown> | null> {
  if (!Array.isArray(value)) return [];
  return value.map((item) => (isRecord(item) ? item : null));
}

function enumConstant<T>(
  table: Readonly<Record<string, T>>,
  qualifiedName: string,
  name: string,
): T {
  const variant = table[name];
  if (variant === undefined) {
    const error = new Error("No enum constant " + qualifiedName + name);
    error.name = "IllegalArgumentException";
    throw error;
  }
  return variant;
}

/** Builds the engine shaping result from the host's plain response record. */
export function toEngineShapingResult(raw: unknown): ShapingResult {
  if (!isRecord(raw)) return new ShapingResult([], [], []);
  const clusters = listOf(raw["clusters"]).map((cluster) => new Cluster(
    rangeOf(cluster?.["range"]),
    stringMember(cluster, "text"),
    stringMember(cluster, "fontKey"),
    numberMember(cluster, "advance"),
    stringMember(cluster, "displayText"),
    optionalNumberMember(cluster ?? {}, "baselineShift"),
  ));
  const glyphRuns = listOf(raw["glyphRuns"]).map((run) => new GlyphRun(
    rangeOf(run?.["range"]),
    stringMember(run, "fontKey"),
    listOf(run?.["glyphs"]).map((glyph) => new Glyph(
      integerMember(glyph ?? {}, "id"),
      rangeOf(glyph?.["clusterRange"]),
      numberMember(glyph, "advance"),
      numberMember(glyph, "x"),
      numberMember(glyph, "y"),
    )),
    numberMember(run, "advance"),
    stringListMember(run ?? {}, "openTypeFeatures"),
  ));
  const decisions = listOf(raw["decisions"]).map((decision) => new ShapingDecisionInfo(
    rangeOf(decision?.["range"]),
    stringMember(decision, "sourceText"),
    stringMember(decision, "displayText"),
    stringMember(decision, "fontKey"),
    integerMember(decision ?? {}, "glyphCount"),
    numberMember(decision, "advance"),
    stringMember(decision, "source"),
    stringMember(decision, "reason"),
    integerMember(decision ?? {}, "glyphsWithoutInkBounds"),
    integerMember(decision ?? {}, "missingGlyphs"),
    nullableString(decision ?? {}, "resolvedFace"),
    nullableString(decision ?? {}, "script"),
    nullableString(decision ?? {}, "language"),
    nullableString(decision ?? {}, "strategy"),
    nullableString(decision ?? {}, "featureEvidence"),
    nullableString(decision ?? {}, "capabilityIssue"),
  ));
  return new ShapingResult(clusters, glyphRuns, decisions);
}

/** Builds the engine font metrics from the host's plain response record. */
export function toEngineFontMetrics(raw: unknown): RawFontMetrics {
  if (!isRecord(raw)) return new RawFontMetrics(Number.NaN, Number.NaN);
  const numberOr = (name: string, fallback: number): number => {
    const value = raw[name];
    return typeof value === "number" ? value : fallback;
  };
  const sourceName = raw["source"];
  const source = typeof sourceName === "string"
    ? enumConstant(FontMetricSource, "org.tiqian.font.FontMetricSource.", sourceName)
    : FontMetricSource.RawTables;
  return new RawFontMetrics(
    numberOr("ascent", Number.NaN),
    numberOr("descent", Number.NaN),
    numberOr("leading", 0),
    source,
    raw["typoAscent"] === undefined || raw["typoAscent"] === null ? null : numberOr("typoAscent", Number.NaN),
    raw["typoDescent"] === undefined || raw["typoDescent"] === null ? null : numberOr("typoDescent", Number.NaN),
  );
}
