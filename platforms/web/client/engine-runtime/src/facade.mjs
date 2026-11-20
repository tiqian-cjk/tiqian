// The public entry of `@tiqian/ffi`. Every capability is served directly by
// the single-source generated tree (./engine-gen): the line-break, clreq,
// font and lowering-helper capabilities since their cutover waves, and the
// two precompute capabilities since this wave. The export surface — twelve
// names, in this export order — is the compatibility contract pinned by
// package.test.mts, so the generated-tree names keep their original
// positions in the list.
//
// Cross-target ruling (2026-11-11): every capability here has a counterpart
// in the Rust facade at platforms/web/server/precompute/tiqian/src/. The
// capability names must match across targets; the transport shape may not.
// This surface carries JSON text in and out because the package exports map
// publishes only ./runtime/facade.mjs (package.test.mts:116-121), so the
// generated types are not importable by consumers. Host measurement arrives
// here as callbacks and there as trait objects, which follows from what each
// host language can express. Two entries are JS-only conveniences:
// classifyFontRoles batches classifyFontRole, and
// precomputeParagraphWithBrowserMetrics is the callbacks-object form of
// precomputeParagraphWithDiagnostics.

import { liangHyphenate, unicodePunctuationLineBreakClassOf } from "./linebreak-facade.mjs";
import { bopomofoParse, numberSymbolCohesionUnbreakableRanges } from "./clreq-facade.mjs";
import { fontMetricsResolve, fontFallbackResolve } from "./font-facade.mjs";
import {
  classifyFontRole,
  classifyFontRoles,
  unsupportedInlineShapingProperties,
  firstDivergentInlineShapingProperty,
} from "./loweringhelper-facade.mjs";
import {
  precomputeParagraphWithDiagnostics,
  precomputeParagraphWithBrowserMetrics,
  precomputeParagraphPlan,
} from "./precompute-facade.mjs";

export {
  bopomofoParse,
  numberSymbolCohesionUnbreakableRanges,
  fontMetricsResolve,
  fontFallbackResolve,
  liangHyphenate,
  unicodePunctuationLineBreakClassOf,
  classifyFontRole,
  classifyFontRoles,
  unsupportedInlineShapingProperties,
  firstDivergentInlineShapingProperty,
  precomputeParagraphWithDiagnostics,
  precomputeParagraphWithBrowserMetrics,
  precomputeParagraphPlan,
};
