// Browser metrics bridge adapter (TsHost runtime port, Slice 4a part 4).
// Adapts the canvas font metrics resolver and canvas text shaper to the
// engine's typed host callbacks. No JSON crosses this seam.
//
// ES module: exports createBrowserMetricsBridge as a named binding. The
// shaper and resolver factories come from the named exports of
// canvas-shaping.js and canvas-metrics.js.
//
// Embedding constraint: the generator wraps this file in a Kotlin raw string,
// so the source must contain no dollar sign and no triple double-quote

import type { WebFontFamiliesInstance } from "./canvas-fonts.js";
import type { CanvasShapingEnv, CjkDashCapability } from "./canvas-shaping.js";
import { createMetricsResolver } from "./canvas-metrics.js";
import { createTextShaper } from "./canvas-shaping.js";
import { toEngineFontMetrics, toEngineShapingResult } from "./engine-access/host-result.js";
import type { EngineCallbacks } from "./engine-access/prepared-paragraph.js";
import type { ShapingInput } from "@tiqian/engine/org/tiqian/shaping/TextShaper";

export interface BrowserMetricsBridgeOptions {
  fonts: WebFontFamiliesInstance;
  cjkDashCapability?: CjkDashCapability | null;
  env: CanvasShapingEnv;
}

/**
 * Create a browser metrics bridge instance that implements the engine's host
 * callbacks: the canvas shaper answers the shaping callback and the canvas
 * resolver answers the font-metrics callback.
 */
export function createBrowserMetricsBridge(options: BrowserMetricsBridgeOptions): EngineCallbacks {
  const fonts = options.fonts;
  const cjkDashCapability = options.cjkDashCapability != null ? options.cjkDashCapability : null;
  const env = options.env;

  const shaper = createTextShaper(fonts, cjkDashCapability, env);
  const resolver = createMetricsResolver(fonts, env.createCanvasContext);

  return {
    shape(input: ShapingInput) {
      const fontDecision = input.fontDecision;
      const result = shaper.shape({
        text: input.text,
        range: { start: input.range.start, end: input.range.end },
        style: {
          fontSize: input.style.fontSize,
          fontWeight: input.style.fontWeight,
          italic: input.style.italic,
          fontFamilies: [...input.style.fontFamilies],
          locale: input.style.locale,
        },
        fontDecision: {
          role: fontDecision.role.kind,
          candidate: { key: fontDecision.candidate.key },
        },
        displayText: input.displayText,
      });
      return toEngineShapingResult(result);
    },
    resolve(request) {
      return toEngineFontMetrics(resolver.resolve({
        role: request.role.kind,
        fontSize: request.fontSize,
        fontWeight: request.fontWeight,
        italic: request.italic,
        locale: request.locale,
        fontKey: request.fontKey,
        fontFamilies: [...request.fontFamilies],
        faceSelectionText: request.faceSelectionText,
      }));
    },
  };
}
