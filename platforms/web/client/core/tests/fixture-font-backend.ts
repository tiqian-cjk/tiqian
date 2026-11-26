// Shared fixture font backend for the core test world (S1b-c).
//
// Mirrors the fixture backend of PrecomputeExportsTest.kt: one glyph per code
// point, advance and x scaled by the font size, glyph id 0 marks a missing
// glyph, metrics [1.04, 0.28, 0, 0.88, 0.12] x fontSize. The callbacks are the
// engine's typed host adapters.
//
// Tests pass the returned callbacks as the snapshot-session descriptor or the
// scripted canvas model; the engine entries take them as call parameters, so
// there is no global to install or restore.

import { toEngineFontMetrics, toEngineShapingResult } from "../src/engine/engine-access/host-result.js";
import type { ShapingInput, ShapingResult } from "@tiqian/engine/org/tiqian/shaping/TextShaper";
import type { FontMetricsRequest } from "@tiqian/engine/org/tiqian/font/FontMetrics";
import type { RawFontMetrics } from "@tiqian/engine/org/tiqian/font/RawFontMetrics";

const MISSING_GLYPH_MARKER = "\u22ef"; // "⋯"

export type ShapeFn = (input: ShapingInput) => ShapingResult;
export type MetricsFn = (request: FontMetricsRequest) => RawFontMetrics;
export type UninstallFn = () => void;

export interface FixtureFontCallbacks {
  shape: ShapeFn;
  resolve: MetricsFn;
}

export interface FixtureFontBackend {
  shape: ShapeFn;
  resolve: MetricsFn;
  uninstall: UninstallFn;
}

interface InternalGlyph {
  id: number;
  advance: number;
  x: number;
  y: number;
  bounds: [number, number, number, number];
}

function makeFixtureCallbacks(): FixtureFontCallbacks {
  return {
    shape(input: ShapingInput): ShapingResult {
      const displayText = input.displayText;
      const fontSize = input.style.fontSize;
      const missing = String(displayText).includes(MISSING_GLYPH_MARKER);
      const glyphs: InternalGlyph[] = [];
      let index = 0;
      for (const _point of displayText) {
        glyphs.push({
          id: missing ? 0 : 100 + index,
          advance: fontSize,
          x: index * fontSize,
          y: 0,
          bounds: [0, -fontSize * 0.88, fontSize, fontSize * 0.12],
        });
        index += 1;
      }
      const range = { start: input.range.start, end: input.range.end };
      const fontKey = input.fontDecision.candidate.key;
      return toEngineShapingResult({
        clusters: [{
          range,
          text: input.text.substring(input.range.start, input.range.end),
          displayText,
          fontKey,
          advance: glyphs.length * fontSize,
        }],
        glyphRuns: [{
          range,
          fontKey,
          glyphs: glyphs.map((g) => ({
            id: g.id,
            clusterRange: range,
            advance: g.advance,
            x: g.x,
            y: g.y,
            bounds: { left: g.bounds[0], top: g.bounds[1], right: g.bounds[2], bottom: g.bounds[3] },
          })),
          advance: glyphs.length * fontSize,
          openTypeFeatures: [],
        }],
        decisions: [{
          range,
          sourceText: input.text.substring(input.range.start, input.range.end),
          displayText,
          fontKey,
          glyphCount: glyphs.length,
          advance: glyphs.length * fontSize,
          source: "HarfBuzz",
          reason: "test",
          glyphsWithoutInkBounds: 0,
          missingGlyphs: missing ? glyphs.length : 0,
          resolvedFace: "Fixture CJK",
          script: "Hani",
          language: input.style.locale,
          featureEvidence: null,
        }],
      });
    },
    resolve(request: FontMetricsRequest): RawFontMetrics {
      const fontSize = request.fontSize;
      return toEngineFontMetrics({
        ascent: fontSize * 1.04,
        descent: fontSize * 0.28,
        leading: 0,
        source: "RawTables",
        typoAscent: fontSize * 0.88,
        typoDescent: fontSize * 0.12,
      });
    },
  };
}

function installFixtureFontBackend(): FixtureFontBackend {
  const callbacks = makeFixtureCallbacks();
  return {
    uninstall(): void {
      // Retained for the try/finally shape of the callers; nothing to undo.
    },
    shape: callbacks.shape,
    resolve: callbacks.resolve,
  };
}

// A throwing backend variant: every shape request throws the given error.
// This is how tests force the snapshot-session capability-failure retry and the
// rethrow path through the real precompute exports.
function installThrowingFontBackend(error: Error): FixtureFontBackend {
  return {
    uninstall(): void {
      // No globals to restore
    },
    shape: (): ShapingResult => { throw error; },
    resolve: (): RawFontMetrics => { throw error; },
  };
}

export { installFixtureFontBackend, installThrowingFontBackend };
