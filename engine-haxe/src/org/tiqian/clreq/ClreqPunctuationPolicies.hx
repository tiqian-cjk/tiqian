package org.tiqian.clreq;

import std.ReadOnlyArray;

/**
 * Punctuation semantics for line breaking and width shaping. Kotlin keys the
 * classification on Char; the port passes the single UTF-16 unit as a
 * one-unit String and compares code units against the arm tables, which
 * carry the Kotlin when-arm order exactly.
 */
class ClreqPunctuationPolicies {
    /** Unambiguous Western point marks (“AsciiPointMark” in CLREQ terms). */
    public static function isAsciiPointMark(char:String):Bool {
        return containsUnit(ASCII_POINT_MARKS, char.charCodeAt(0));
    }

    public static function classify(char:String):PunctuationClass {
        final unit:Int = char.charCodeAt(0);
        if (containsUnit(OPENING_UNITS, unit)) {
            return PunctuationClass.Opening;
        }
        if (containsUnit(CLOSING_UNITS, unit)) {
            return PunctuationClass.Closing;
        }
        if (containsUnit(PAUSE_OR_STOP_UNITS, unit)) {
            return PunctuationClass.PauseOrStop;
        }
        if (unit == 0x00B7) {
            return PunctuationClass.MiddleDot;
        }
        if (containsUnit(INTERPUNCT_UNITS, unit)) {
            return PunctuationClass.Interpunct;
        }
        if (containsUnit(CONNECTOR_UNITS, unit)) {
            return PunctuationClass.Connector;
        }
        if (containsUnit(SOLIDUS_UNITS, unit)) {
            return PunctuationClass.Solidus;
        }
        if (containsUnit(ELLIPSIS_UNITS, unit)) {
            return PunctuationClass.Ellipsis;
        }
        if (containsUnit(DASH_UNITS, unit)) {
            return PunctuationClass.Dash;
        }
        return PunctuationClass.Other;
    }

    /**
     * Whether the char is forced to a fixed half-width (body only, no
     * adjustable glue) by the punctuation-width policy.
     */
    public static function forcedHalfWidth(char:String, policy:PunctuationWidthPolicy):Bool {
        final unit:Int = char.charCodeAt(0);
        // Short hyphens occupy half an em (CLREQ 5.1.6, style-independent).
        if (containsUnit(SHORT_HYPHEN_CONNECTORS, unit)) {
            return true;
        }
        final cls:PunctuationClass = classify(char);
        if (policy.gbFixedSeparators
            && (cls == PunctuationClass.Connector || cls == PunctuationClass.MiddleDot || cls == PunctuationClass.Interpunct || cls == PunctuationClass.Solidus)) {
            return true;
        }
        if (policy.interior == InteriorPunctuationStyle.Kaiming) {
            // Interior pauses and brackets drop to half width; sentence-end
            // stops keep a full em.
            if (cls == PunctuationClass.Opening || cls == PunctuationClass.Closing) {
                return true;
            }
            if (cls == PunctuationClass.PauseOrStop && !containsUnit(SENTENCE_END_STOPS, unit)) {
                return true;
            }
        }
        return false;
    }

    public static function policyFor(char:String):PunctuationPolicy {
        final punctuationClass:PunctuationClass = classify(char);
        return new PunctuationPolicy(punctuationClass, !forbiddenAtLineStart(char, KinsokuLevel.Basic), !forbiddenAtLineEnd(char, KinsokuLevel.Basic),
            defaultPunctuationBodyEm(char.charCodeAt(0), punctuationClass), defaultPunctuationAdvanceEm(char.charCodeAt(0), punctuationClass));
    }

    public static function forbiddenAtLineStart(char:String, level:KinsokuLevel):Bool {
        if (level == KinsokuLevel.None) {
            return false;
        }
        final cls:PunctuationClass = classify(char);
        // Pause marks, closing brackets, connectors, middle dots, and
        // separators are forbidden at line start at every processed level.
        if (cls == PunctuationClass.PauseOrStop || cls == PunctuationClass.Closing || cls == PunctuationClass.Connector
            || cls == PunctuationClass.MiddleDot || cls == PunctuationClass.Interpunct || cls == PunctuationClass.Solidus) {
            return true;
        }
        // Dashes and ellipses join only under strict processing.
        if (cls == PunctuationClass.Dash || cls == PunctuationClass.Ellipsis) {
            return level == KinsokuLevel.Strict;
        }
        return false;
    }

    public static function forbiddenAtLineEnd(char:String, level:KinsokuLevel):Bool {
        if (level == KinsokuLevel.None) {
            return false;
        }
        final cls:PunctuationClass = classify(char);
        // Opening brackets are forbidden at line end.
        if (cls == PunctuationClass.Opening) {
            return true;
        }
        // Separators join beyond the basic level.
        if (cls == PunctuationClass.Solidus) {
            return level != KinsokuLevel.Basic;
        }
        return false;
    }

    private static function defaultPunctuationBodyEm(unit:Int, punctuationClass:PunctuationClass):Float {
        if (unit == 0x2E3A) {
            return 2.0;
        }
        if (containsUnit(SHORT_HYPHEN_CONNECTORS, unit)) {
            return 0.5;
        }
        if (punctuationClass == PunctuationClass.PauseOrStop) {
            return 0.5;
        }
        if (punctuationClass == PunctuationClass.Closing) {
            return 0.5;
        }
        if (punctuationClass == PunctuationClass.Opening) {
            return 0.5;
        }
        return 1.0;
    }

    private static function defaultPunctuationAdvanceEm(unit:Int, punctuationClass:PunctuationClass):Float {
        if (unit == 0x2E3A) {
            return 2.0;
        }
        if (containsUnit(SHORT_HYPHEN_CONNECTORS, unit)) {
            return 0.5;
        }
        // Kotlin's remaining arms (Other and the rest) both yield 1.0.
        return 1.0;
    }

    private static function containsUnit(units:ReadOnlyArray<Int>, unit:Int):Bool {
        var index:Int = 0;
        while (index < units.length) {
            if (units[index] == unit) {
                return true;
            }
            index += 1;
        }
        return false;
    }

    private static final OPENING_UNITS:ReadOnlyArray<Int> = [
        0x201C, 0x2018, 0xFF08, 0x300A, 0x3008, 0x300C, 0x300E, 0x3010, 0x3014, 0x3016, 0x3018, 0x301A
    ];

    private static final CLOSING_UNITS:ReadOnlyArray<Int> = [
        0x201D, 0x2019, 0xFF09, 0x300B, 0x3009, 0x300D, 0x300F, 0x3011, 0x3015, 0x3017, 0x3019, 0x301B
    ];

    private static final PAUSE_OR_STOP_UNITS:ReadOnlyArray<Int> = [0xFF0C, 0x3001, 0x3002, 0xFF1B, 0xFF1A, 0xFF01, 0xFF1F];

    private static final INTERPUNCT_UNITS:ReadOnlyArray<Int> = [0x30FB, 0x2027, 0x2022];

    private static final CONNECTOR_UNITS:ReadOnlyArray<Int> = [0xFF5E, 0x007E, 0x002D, 0x2013];

    private static final SOLIDUS_UNITS:ReadOnlyArray<Int> = [0x002F, 0xFF0F];

    private static final ELLIPSIS_UNITS:ReadOnlyArray<Int> = [0x2026, 0x22EF];

    private static final DASH_UNITS:ReadOnlyArray<Int> = [0x2014, 0x2E3A];

    private static final SHORT_HYPHEN_CONNECTORS:ReadOnlyArray<Int> = [0x002D, 0x2013];

    private static final SENTENCE_END_STOPS:ReadOnlyArray<Int> = [0x3002, 0xFF01, 0xFF1F, 0xFF0E];

    private static final ASCII_POINT_MARKS:ReadOnlyArray<Int> = [0x002C, 0x002E, 0x003A, 0x003B, 0x0021, 0x003F];
}
