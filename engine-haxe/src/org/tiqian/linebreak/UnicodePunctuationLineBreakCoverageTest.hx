package org.tiqian.linebreak;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.linebreak.UnicodePunctuationLineBreak.UnicodePunctuationLineBreakClass;
import org.tiqian.test.trace.TracedAssertions;

class UnicodePunctuationLineBreakCoverageTest {
    @:test public static function lookupClassesCoverTheUaxTailorablePunctuationClasses():Void {
        new TestTraceRecorder("UnicodePunctuationLineBreakCoverageTest").section("lookupClassesCoverTheUaxTailorablePunctuationClasses");
        TracedAssertions.assertEqualsRendered("BreakAfter", Std.string(UnicodePunctuationLineBreak.classOf(0x7C)));
        TracedAssertions.assertEqualsRendered("BreakBoth", Std.string(UnicodePunctuationLineBreak.classOf(0x2014)));
        TracedAssertions.assertEqualsRendered("HyphenHH", Std.string(UnicodePunctuationLineBreak.classOf(0x58A)));
        TracedAssertions.assertEqualsRendered("Nonstarter", Std.string(UnicodePunctuationLineBreak.classOf(0x203C)));
    }

    @:test public static function nonScalarCodePointsAreRejected():Void {
        new TestTraceRecorder("UnicodePunctuationLineBreakCoverageTest").section("nonScalarCodePointsAreRejected");
        TracedAssertions.assertFailsWith(null, function():Void {
            UnicodePunctuationLineBreak.classOf(-1);
        });
        TracedAssertions.assertFailsWith(null, function():Void {
            UnicodePunctuationLineBreak.classOf(0x110000);
        });
        TracedAssertions.assertFailsWith(null, function():Void {
            UnicodePunctuationLineBreak.classOf(0xD800);
        });
    }
}
