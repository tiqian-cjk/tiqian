package org.tiqian.linebreak;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.linebreak.LineBreakAnalyzer.SimpleCharacterLineBreakAnalyzer;
import org.tiqian.test.trace.TracedAssertions;

class MandatoryBreakTest {
    @:test public static function recognizesMandatoryBreakCodePoints():Void {
        new TestTraceRecorder("MandatoryBreakTest").section("recognizesMandatoryBreakCodePoints");
        final y:Array<Int> = [10, 11, 12, 13, 133, 8232, 8233];
        var i = 0;
        while (i < y.length) {
            TracedAssertions.assertTrue(LineBreakFns.isMandatoryBreakCodePoint(y[i]), MandatoryBreakTestHelpers.u(y[i]));
            i++;
        }
        final n:Array<Int> = [97, 20013, 32, 9, 0x3000];
        i = 0;
        while (i < n.length) {
            TracedAssertions.assertFalse(LineBreakFns.isMandatoryBreakCodePoint(n[i]), MandatoryBreakTestHelpers.u(n[i]));
            i++;
        }
    }

    @:test public static function recognizesZeroWidthSpaceWithoutConflatingNoBreakControls():Void {
        new TestTraceRecorder("MandatoryBreakTest").section("recognizesZeroWidthSpaceWithoutConflatingNoBreakControls");
        TracedAssertions.assertTrue(LineBreakFns.isZeroWidthSpaceCodePoint(0x200B), MandatoryBreakTestHelpers.u(0x200B));
        final n:Array<Int> = [0x200C, 0x200D, 0x2060, 0xFEFF];
        var i = 0;
        while (i < n.length) {
            TracedAssertions.assertFalse(LineBreakFns.isZeroWidthSpaceCodePoint(n[i]), MandatoryBreakTestHelpers.u(n[i]));
            i++;
        }
    }

    @:test public static function marksRequiredAfterLineFeed():Void {
        new TestTraceRecorder("MandatoryBreakTest").section("marksRequiredAfterLineFeed");
        final o = new SimpleCharacterLineBreakAnalyzer().analyze("a\nb");
        TracedAssertions.assertEqualsRendered("Required", Std.string(o[1].kind));
        TracedAssertions.assertEqualsRendered("Allowed", Std.string(o[0].kind));
    }

    @:test public static function collapsesCrlfToASingleBreakAfterLf():Void {
        new TestTraceRecorder("MandatoryBreakTest").section("collapsesCrlfToASingleBreakAfterLf");
        final o = new SimpleCharacterLineBreakAnalyzer().analyze("a\r\nb");
        TracedAssertions.assertEqualsRendered("Allowed", Std.string(o[1].kind));
        TracedAssertions.assertEqualsRendered("Required", Std.string(o[2].kind));
    }

    @:test public static function preservesEachBlankLineBreak():Void {
        new TestTraceRecorder("MandatoryBreakTest").section("preservesEachBlankLineBreak");
        final o = new SimpleCharacterLineBreakAnalyzer().analyze("a\n\nb");
        TracedAssertions.assertEqualsRendered("Required", Std.string(o[1].kind));
        TracedAssertions.assertEqualsRendered("Required", Std.string(o[2].kind));
    }
}

class MandatoryBreakTestHelpers {
    public static function u(cp:Int):String {
        var s = StringTools.hex(cp, 4);
        return "U+" + s;
    }
}
