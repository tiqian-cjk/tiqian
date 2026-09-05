package org.tiqian.core;

/**
 * Stable Unicode Script evidence for language-sensitive Common punctuation.
 * Common, Inherited, and unassigned scalars are neutral: punctuation, spaces,
 * and ASCII digits do not get to decide the language of surrounding marks.
 */
enum UnicodeScriptEvidence {
    Neutral;
    EastAsian;
    Other;
}
