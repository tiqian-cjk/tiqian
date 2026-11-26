// Font-role classification for the lowering path, served by the generated
// engine tree instead of the retired the retired engine facade facade.
//
// The chain is the engine's own: the per-code-point classifier, wrapped by the
// paragraph-scoped quote-pair roles, wrapped by the contextual dash/ellipsis
// roles. Both wrappers scan the complete paragraph, so the chain is built once
// per (text, locale) and reused for every range of that paragraph.

import { CjkFontRoleClassifier } from "@tiqian/engine/org/tiqian/font/CjkFontRoleClassifier";
import { FontRoleContext } from "@tiqian/engine/org/tiqian/font/FontRoleContext";
import { InlineShapingStylePolicy } from "@tiqian/engine/org/tiqian/font/InlineShapingStylePolicy";
import { TextRange } from "@tiqian/engine/org/tiqian/core/TextRange";
import { TiqianIllegalArgumentException } from "@tiqian/engine/org/tiqian/core/TiqianIllegalArgumentException";
import { QuotePairAwareFontRoleClassifier } from "@tiqian/engine/org/tiqian/layout/QuotePairAnalyzer";
import { ContextualDashEllipsisRoles } from "@tiqian/engine/org/tiqian/layout/ContextualDashEllipsisRoleResolver";
import type { FontRole } from "@tiqian/engine/org/tiqian/font/FontRole";
import type { FontRoleClassifier } from "@tiqian/engine/org/tiqian/font/FontRoleContext";

const baseClassifier: FontRoleClassifier = new CjkFontRoleClassifier();

let memoKey: string | null = null;
let memoClassifier: FontRoleClassifier | null = null;

function contextualClassifier(text: string, context: FontRoleContext): FontRoleClassifier {
  const key = text + "\u0000" + context.locale;
  if (memoKey !== key || memoClassifier === null) {
    memoClassifier = ContextualDashEllipsisRoles.withContextualDashEllipsisRoles(
      QuotePairAwareFontRoleClassifier.withContextualQuoteRoles(baseClassifier, text, context),
      text,
      context,
    );
    memoKey = key;
  }
  return memoClassifier;
}

// The engine raises TiqianIllegalArgumentException with a TextRangeError; the
// lowering path catches these two kinds by name, so the name is kept.
function range(start: number, end: number): TextRange {
  try {
    return new TextRange(start, end);
  } catch (error) {
    if (error instanceof TiqianIllegalArgumentException) {
      const kind = error.error.kind;
      if (kind === "NegativeStart" || kind === "StartGreaterThanEnd") {
        const normalized = new Error(error.message);
        normalized.name = kind;
        throw normalized;
      }
    }
    throw error;
  }
}

export function classifyRole(text: string, start: number, end: number, locale: string): FontRole {
  const context = new FontRoleContext(locale);
  return contextualClassifier(text, context).classify(text, range(start, end), context);
}

export function classifyRoles(
  text: string,
  starts: number[],
  ends: number[],
  locale: string,
): FontRole[] {
  if (starts.length !== ends.length) {
    const error = new Error("starts and ends must have the same size");
    error.name = "IllegalArgumentException";
    throw error;
  }
  const context = new FontRoleContext(locale);
  const classifier = contextualClassifier(text, context);
  const results: FontRole[] = new Array(starts.length);
  for (let index = 0; index < starts.length; index += 1) {
    results[index] = classifier.classify(text, range(starts[index]!, ends[index]!), context);
  }
  return results;
}

/** The ordered inherited shaping properties compared during lowering. */
export function unsupportedInlineShapingProperties(): string[] {
  return InlineShapingStylePolicy.unsupportedInlineShapingProperties.slice();
}

/** The first property whose element value diverges from the paragraph value. */
export function firstDivergentInlineShapingProperty(
  elementValues: string[],
  paragraphValues: string[],
): string | null {
  return InlineShapingStylePolicy.firstDivergentProperty(elementValues, paragraphValues);
}
