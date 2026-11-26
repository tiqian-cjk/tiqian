// Helpers that build the engine's typed callback inputs and expect the
// engine's typed results. Tests describe their requests as plain records (the
// former wire shape) and these helpers translate them, so a test states what
// it wants without constructing engine classes inline.

import { FontCandidate, FontDecision } from "@tiqian/engine/org/tiqian/font/FontPolicy";
import { FontRole } from "@tiqian/engine/org/tiqian/font/FontRole";
import { FontMetricsRequest } from "@tiqian/engine/org/tiqian/font/FontMetrics";
import { TextRange } from "@tiqian/engine/org/tiqian/core/TextRange";
import { TextStyle } from "@tiqian/engine/org/tiqian/core/TextStyle";
import { ShapingInput } from "@tiqian/engine/org/tiqian/shaping/TextShaper";
import type { FontRole as FontRoleValue } from "@tiqian/engine/org/tiqian/font/FontRole";

export interface WireShapingInput {
  text: string;
  range: { start: number; end: number };
  style: {
    fontFamilies: string[];
    fontSize: number;
    fontWeight: number;
    italic: boolean;
    locale: string;
  };
  fontDecision: { role: string; candidateKey: string };
  displayText?: string;
  openTypeFeatures?: string[];
}

export interface WireMetricsRequest {
  fontKey?: string;
  fontSize: number;
  role: string;
  locale?: string;
  fontFamilies?: string[];
  fontWeight?: number;
  italic?: boolean;
  faceSelectionText?: string;
}

/** Resolves a role name to the engine's role value. */
export function roleFromName(name: string): FontRoleValue {
  switch (name) {
    case "CjkText": return FontRole.CjkText;
    case "CjkPunctuation": return FontRole.CjkPunctuation;
    case "LatinText": return FontRole.LatinText;
    case "Symbol": return FontRole.Symbol;
    case "Emoji": return FontRole.Emoji;
    default: return FontRole.Unknown;
  }
}

/** Builds the engine shaping input from a plain request record. */
export function shapingInput(wire: WireShapingInput): ShapingInput {
  const role = roleFromName(wire.fontDecision.role);
  const candidate = new FontCandidate(wire.fontDecision.candidateKey, wire.fontDecision.candidateKey, role);
  const decision = new FontDecision(new TextRange(0, 0), candidate, role, "");
  return new ShapingInput(
    wire.text,
    new TextRange(wire.range.start, wire.range.end),
    new TextStyle(
      wire.style.fontFamilies,
      wire.style.fontSize,
      wire.style.locale,
      wire.style.fontWeight,
      wire.style.italic,
    ),
    decision,
    wire.displayText ?? null,
    wire.openTypeFeatures ?? null,
  );
}

/** Builds the engine font-metrics request from a plain request record. */
export function metricsRequest(wire: WireMetricsRequest): FontMetricsRequest {
  return new FontMetricsRequest(
    wire.fontKey ?? "",
    wire.fontSize,
    roleFromName(wire.role),
    wire.locale ?? "zh-Hans",
    wire.fontFamilies ?? [],
    wire.fontWeight ?? 400,
    wire.italic ?? false,
    wire.faceSelectionText ?? "",
  );
}
