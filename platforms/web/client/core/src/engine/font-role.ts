// Role classification for the lowering path, delegated to the generated
// engine entry that owns the classifier chain (CJK per code point, wrapped by
// the quote-pair roles, wrapped by the contextual dash/ellipsis roles).

import { FontRoleClassification } from "@tiqian/engine/org/tiqian/font/FontRoleClassification";
import { TextRange } from "@tiqian/engine/org/tiqian/core/TextRange";
import { TiqianIllegalArgumentException } from "@tiqian/engine/org/tiqian/core/TiqianIllegalArgumentException";
import type { FontRole } from "@tiqian/engine/org/tiqian/font/FontRole";

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
  return FontRoleClassification.classify(text, range(start, end), locale);
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
  return FontRoleClassification.classifyAll(
    text,
    starts.map((start, index) => range(start, ends[index]!)),
    locale,
  );
}
