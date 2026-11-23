// The lowering-helper capability exports of `@tiqian/ffi`, served directly by
// the single-source generated tree under ./engine-gen (copied by hand from the
// bundle driver product engine-haxe/out/ts/gen; do not edit the vendored
// files). The JavaScript wire matches the retired Kotlin/JS exports: role
// decisions leave as the published lowering role strings
// ("cjk-text" / "cjk-punctuation" / "other"), the shaping property list
// leaves as a fresh ordered string array, and the divergence decision leaves
// as a property name or null.
//
// This module owns only the ffi-boundary contract (ADR 0053 G3: the string
// encoding of the role decision is the ABI's duty) and normalizes the
// generated TextRange failure to the error names the previous Kotlin/JS
// facade exposed (the Kotlin data objects were observed in JavaScript as
// error names "NegativeStart" / "StartGreaterThanEnd"; the size guard as
// "IllegalArgumentException"). The classification and divergence decisions
// themselves run in the generated code: CjkFontRoleClassifier wrapped by the
// contextual quote and dash/ellipsis classifiers, and
// InlineShapingStylePolicy.

import { CjkFontRoleClassifier } from "./engine-gen/org/tiqian/font/CjkFontRoleClassifier.js";
import { FontRoleContext } from "./engine-gen/org/tiqian/font/FontRoleContext.js";
import { TextRange } from "./engine-gen/org/tiqian/core/TextRange.js";
import { QuotePairAwareFontRoleClassifier } from "./engine-gen/org/tiqian/layout/QuotePairAnalyzer.js";
import { ContextualDashEllipsisRoles } from "./engine-gen/org/tiqian/layout/ContextualDashEllipsisRoleResolver.js";
import { InlineShapingStylePolicy } from "./engine-gen/org/tiqian/font/InlineShapingStylePolicy.js";

const baseClassifier = new CjkFontRoleClassifier();

// Single-entry memo keyed on (text, locale), mirroring the previous facade:
// the contextual quote and dash/ellipsis chains are resolved once per
// paragraph instead of once per range.
let memoKey = null;
let memoClassifier = null;

function contextualFontRoleClassifier(text, context) {
  const key = text + "\u0000" + context.locale;
  if (memoKey !== key) {
    memoClassifier = ContextualDashEllipsisRoles.withContextualDashEllipsisRoles(
      QuotePairAwareFontRoleClassifier.withContextualQuoteRoles(baseClassifier, text, context),
      text,
      context,
    );
    memoKey = key;
  }
  return memoClassifier;
}

function toLoweringRoleName(role) {
  if (role.kind === "CjkText") return "cjk-text";
  if (role.kind === "CjkPunctuation") return "cjk-punctuation";
  return "other";
}

// The previous facade threw the Kotlin data objects
// TiqianIllegalArgumentException.NegativeStart / .StartGreaterThanEnd, which
// JavaScript consumers observed with error.name "NegativeStart" /
// "StartGreaterThanEnd" and the same messages the generated encoder carries.
// Re-throw under those names.
function constructRange(start, end) {
  try {
    return new TextRange(start, end);
  } catch (error) {
    if (
      error instanceof Error &&
      error.name === "TiqianIllegalArgumentException" &&
      error.error &&
      (error.error.kind === "NegativeStart" || error.error.kind === "StartGreaterThanEnd")
    ) {
      const normalized = new Error(error.message);
      normalized.name = error.error.kind;
      throw normalized;
    }
    throw error;
  }
}

/**
 * Classifies the typographic font role of [start]..<[end] within the complete
 * paragraph [text]. Maps the CjkText role to "cjk-text", CjkPunctuation to
 * "cjk-punctuation", and any other role to "other".
 */
export function classifyFontRole(text, start, end, locale) {
  const context = new FontRoleContext(locale);
  const range = constructRange(start, end);
  const role = contextualFontRoleClassifier(text, context).classify(text, range, context);
  return toLoweringRoleName(role);
}

/**
 * Classifies several ranges against one complete paragraph, resolving the
 * contextual dash and ellipsis roles once.
 */
export function classifyFontRoles(text, starts, ends, locale) {
  if (starts.length !== ends.length) {
    const error = new Error("starts and ends must have the same size");
    error.name = "IllegalArgumentException";
    throw error;
  }
  const context = new FontRoleContext(locale);
  const classifier = contextualFontRoleClassifier(text, context);
  const results = new Array(starts.length);
  for (let i = 0; i < starts.length; i++) {
    const range = constructRange(starts[i], ends[i]);
    results[i] = toLoweringRoleName(classifier.classify(text, range, context));
  }
  return results;
}

/**
 * Returns the ordered list of 16 inherited shaping properties compared during
 * markdown lowering. A fresh array per call.
 */
export function unsupportedInlineShapingProperties() {
  return InlineShapingStylePolicy.unsupportedInlineShapingProperties.slice();
}

/**
 * Finds the first shaping property whose value in [elementValues] diverges
 * from [paragraphValues]. null means no divergence within the common prefix.
 */
export function firstDivergentInlineShapingProperty(elementValues, paragraphValues) {
  return InlineShapingStylePolicy.firstDivergentProperty(elementValues, paragraphValues);
}
