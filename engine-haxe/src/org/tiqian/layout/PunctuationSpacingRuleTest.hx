package org.tiqian.layout;

import org.tiqian.core.TextRange;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class PunctuationSpacingRuleTest {
    @:test public static function closingPlusClosingCollapsesInnerToZero():Void {
        final testTrace = new TestTraceRecorder("PunctuationSpacingRuleTest");
        testTrace.section("closingPlusClosingCollapsesInnerToZero");
        final a = PunctuationSpacingRuleTestSupport.compressor.compress([
            PunctuationSpacingRuleTestSupport.atom("」", 0),
            PunctuationSpacingRuleTestSupport.atom("。", 1)
        ], PunctuationSpacingRuleTestSupport.em).adjustments[0];
        TracedAssertions.assertEqualsFloat(8, a.naturalInnerGlue);
        TracedAssertions.assertEqualsFloat(0, a.adjustedInnerGlue);
        TracedAssertions.assertEqualsFloat(8, a.reduction);
    }

    @:test public static function openingPlusOpeningCollapsesInnerToZero():Void {
        final testTrace = new TestTraceRecorder("PunctuationSpacingRuleTest");
        testTrace.section("openingPlusOpeningCollapsesInnerToZero");
        final a = PunctuationSpacingRuleTestSupport.compressor.compress([
            PunctuationSpacingRuleTestSupport.atom("「", 0),
            PunctuationSpacingRuleTestSupport.atom("（", 1)
        ], PunctuationSpacingRuleTestSupport.em).adjustments[0];
        TracedAssertions.assertEqualsFloat(8, a.naturalInnerGlue);
        TracedAssertions.assertEqualsFloat(0, a.adjustedInnerGlue);
        TracedAssertions.assertEqualsFloat(8, a.reduction);
    }

    @:test public static function closingPlusOpeningKeepsHalfEmGap():Void {
        final testTrace = new TestTraceRecorder("PunctuationSpacingRuleTest");
        testTrace.section("closingPlusOpeningKeepsHalfEmGap");
        final a = PunctuationSpacingRuleTestSupport.compressor.compress([
            PunctuationSpacingRuleTestSupport.atom("。", 0),
            PunctuationSpacingRuleTestSupport.atom("「", 1)
        ], PunctuationSpacingRuleTestSupport.em).adjustments[0];
        TracedAssertions.assertEqualsFloat(16, a.naturalInnerGlue);
        TracedAssertions.assertEqualsFloat(8, a.adjustedInnerGlue);
        TracedAssertions.assertEqualsFloat(8, a.reduction);
    }

    @:test public static function pauseStopPlusOpeningCollapsesByHalfEm():Void {
        final testTrace = new TestTraceRecorder("PunctuationSpacingRuleTest");
        testTrace.section("pauseStopPlusOpeningCollapsesByHalfEm");
        final a = PunctuationSpacingRuleTestSupport.compressor.compress([
            PunctuationSpacingRuleTestSupport.atom("，", 0),
            PunctuationSpacingRuleTestSupport.atom("「", 1)
        ], PunctuationSpacingRuleTestSupport.em).adjustments[0];
        TracedAssertions.assertEqualsFloat(16, a.naturalInnerGlue);
        TracedAssertions.assertEqualsFloat(8, a.adjustedInnerGlue);
        TracedAssertions.assertEqualsFloat(8, a.reduction);
    }

    @:test public static function consecutivePauseOrStopMarksCompressLikeAnyAdjacentPair():Void {
        final testTrace = new TestTraceRecorder("PunctuationSpacingRuleTest");
        testTrace.section("consecutivePauseOrStopMarksCompressLikeAnyAdjacentPair");
        final a = PunctuationSpacingRuleTestSupport.compressor.compress([
            PunctuationSpacingRuleTestSupport.atom("！", 0),
            PunctuationSpacingRuleTestSupport.atom("！", 1)
        ], PunctuationSpacingRuleTestSupport.em).adjustments[0];
        TracedAssertions.assertEqualsFloat(8, a.naturalInnerGlue);
        TracedAssertions.assertEqualsFloat(0, a.adjustedInnerGlue);
        TracedAssertions.assertEqualsFloat(8, a.reduction);
    }

    @:test public static function closingPlusPauseOrStopStillCompresses():Void {
        final testTrace = new TestTraceRecorder("PunctuationSpacingRuleTest");
        testTrace.section("closingPlusPauseOrStopStillCompresses");
        final a = PunctuationSpacingRuleTestSupport.compressor.compress([
            PunctuationSpacingRuleTestSupport.atom("”", 0),
            PunctuationSpacingRuleTestSupport.atom("！", 1)
        ], PunctuationSpacingRuleTestSupport.em).adjustments[0];
        TracedAssertions.assertEqualsFloat(8, a.naturalInnerGlue);
        TracedAssertions.assertEqualsFloat(0, a.adjustedInnerGlue);
        TracedAssertions.assertEqualsFloat(8, a.reduction);
    }

    @:test public static function nonAdjacentPunctuationAtomsAreNotCompressed():Void {
        final testTrace = new TestTraceRecorder("PunctuationSpacingRuleTest");
        testTrace.section("nonAdjacentPunctuationAtomsAreNotCompressed");
        TracedAssertions.assertEqualsInt(0, PunctuationSpacingRuleTestSupport.compressor.compress([
            PunctuationSpacingRuleTestSupport.atom("，", 0),
            PunctuationSpacingRuleTestSupport.atom("。", 5)
        ], PunctuationSpacingRuleTestSupport.em).adjustments.length);
    }

    @:test public static function cjkClosingBeforeAsciiPointMarkConsumesOnlyClosingGlue():Void {
        final testTrace = new TestTraceRecorder("PunctuationSpacingRuleTest");
        testTrace.section("cjkClosingBeforeAsciiPointMarkConsumesOnlyClosingGlue");
        final a = PunctuationSpacingRuleTestSupport.compressor.compressCjkClosingBeforeAsciiPointMark([PunctuationSpacingRuleTestSupport.atom("」", 0)], "」,",
            PunctuationSpacingRuleTestSupport.em)
            .adjustments[0];
        TracedAssertions.assertEqualsFloat(8, a.naturalInnerGlue);
        TracedAssertions.assertEqualsFloat(0, a.adjustedInnerGlue);
        TracedAssertions.assertEqualsFloat(8, a.reduction);
        TracedAssertions.assertEqualsRendered("TextRange(start=0, end=1)", a.reductionTargetRange.toString());
        TracedAssertions.assertEqualsString("collapse-cjk-closing-before-ascii-point-mark", a.reason);
    }

    @:test public static function cjkClosingDoesNotCompressAcrossWhitespaceBeforeAsciiPointMark():Void {
        final testTrace = new TestTraceRecorder("PunctuationSpacingRuleTest");
        testTrace.section("cjkClosingDoesNotCompressAcrossWhitespaceBeforeAsciiPointMark");
        final plan = PunctuationSpacingRuleTestSupport.compressor.compressCjkClosingBeforeAsciiPointMark([PunctuationSpacingRuleTestSupport.atom("」", 0)],
            "」 ,", PunctuationSpacingRuleTestSupport.em);
        TracedAssertions.assertEqualsRendered("[]", Std.string(plan.adjustments));
    }
}
