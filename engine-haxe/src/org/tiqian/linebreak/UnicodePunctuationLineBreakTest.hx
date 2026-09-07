package org.tiqian.linebreak;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.linebreak.UnicodePunctuationLineBreak.UnicodePunctuationLineBreakClass;
import org.tiqian.test.trace.TracedAssertions;

class UnicodePunctuationLineBreakTest {
    @:test public static function exposesPinnedWesternAndCjkPunctuationClasses():Void {
        new TestTraceRecorder("UnicodePunctuationLineBreakTest").section("exposesPinnedWesternAndCjkPunctuationClasses");
        final cps:Array<Int> = [40, 41, 123, 125, 33, 44, 47, 45, 0x2026, 0x201C, 0x201D, 0xFF08, 0xFF09];
        final k:Array<UnicodePunctuationLineBreakClass> = [
            OpenPunctuation,
            CloseParenthesis,
            OpenPunctuation,
            ClosePunctuation,
            Exclamation,
            InfixNumericSeparator,
            SymbolsAllowingBreakAfter,
            Hyphen,
            Inseparable,
            Quotation,
            Quotation,
            OpenPunctuation,
            ClosePunctuation
        ];
        var i = 0;
        while (i < cps.length) {
            TracedAssertions.assertEqualsRendered(Std.string(k[i]), Std.string(UnicodePunctuationLineBreak.classOf(cps[i])), String.fromCharCode(cps[i]));
            i++;
        }
    }

    @:test public static function ordinaryLettersAreOutsideThePunctuationSubset():Void {
        new TestTraceRecorder("UnicodePunctuationLineBreakTest").section("ordinaryLettersAreOutsideThePunctuationSubset");
        TracedAssertions.assertEqualsRendered("Other", Std.string(UnicodePunctuationLineBreak.classOf(65)));
        TracedAssertions.assertEqualsRendered("Other", Std.string(UnicodePunctuationLineBreak.classOf(0x4E2D)));
    }
}
