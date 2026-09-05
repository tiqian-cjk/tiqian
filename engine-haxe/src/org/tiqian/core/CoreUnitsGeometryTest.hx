package org.tiqian.core;

import org.tiqian.core.Ic;
import org.tiqian.core.Units.FloatIc;
import org.tiqian.core.Units.IntIc;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class CoreUnitsGeometryTest {
    @:test
    public static function icPlusReturnsSum():Void {
        new TestTraceRecorder("CoreUnitsGeometryTest").section("icPlusReturnsSum");
        TracedAssertions.assertEqualsIc(new Ic(5.0), Ic.plus(new Ic(2.0), new Ic(3.0)));
    }

    @:test
    public static function icUnaryMinusReturnsNegated():Void {
        new TestTraceRecorder("CoreUnitsGeometryTest").section("icUnaryMinusReturnsNegated");
        TracedAssertions.assertEqualsIc(new Ic(-3.0), Ic.unaryMinus(new Ic(3.0)));
    }

    @:test
    public static function floatIcExtensionCreatesIc():Void {
        new TestTraceRecorder("CoreUnitsGeometryTest").section("floatIcExtensionCreatesIc");
        TracedAssertions.assertEqualsIc(new Ic(2.0), FloatIc.ic(2.0));
    }

    @:test
    public static function intIcExtensionCreatesIc():Void {
        new TestTraceRecorder("CoreUnitsGeometryTest").section("intIcExtensionCreatesIc");
        TracedAssertions.assertEqualsIc(new Ic(5.0), IntIc.ic(5));
    }

    @:test
    public static function icToPxMultipliesByEmSize():Void {
        new TestTraceRecorder("CoreUnitsGeometryTest").section("icToPxMultipliesByEmSize");
        TracedAssertions.assertEqualsFloat(24.0, new Ic(3.0).toPx(8.0));
    }

    @:test
    public static function rectHeightReturnsDifference():Void {
        new TestTraceRecorder("CoreUnitsGeometryTest").section("rectHeightReturnsDifference");
        TracedAssertions.assertEqualsFloat(20.0, new Rect(0.0, 0.0, 10.0, 20.0).height);
    }

    @:test
    public static function rectWidthReturnsDifference():Void {
        new TestTraceRecorder("CoreUnitsGeometryTest").section("rectWidthReturnsDifference");
        TracedAssertions.assertEqualsFloat(10.0, new Rect(0.0, 0.0, 10.0, 20.0).width);
    }

    @:test
    public static function textRangeRejectsStartGreaterThanEnd():Void {
        new TestTraceRecorder("CoreUnitsGeometryTest").section("textRangeRejectsStartGreaterThanEnd");
        CoreUnitsGeometryTestHelpers.expectArgumentFailure(() -> new TextRange(5, 2));
    }

    @:test
    public static function textRangeRejectsNegativeStart():Void {
        new TestTraceRecorder("CoreUnitsGeometryTest").section("textRangeRejectsNegativeStart");
        CoreUnitsGeometryTestHelpers.expectArgumentFailure(() -> new TextRange(-1, 1));
    }

    @:test
    public static function layoutConstraintsRejectsNonPositiveMaxWidth():Void {
        new TestTraceRecorder("CoreUnitsGeometryTest").section("layoutConstraintsRejectsNonPositiveMaxWidth");
        CoreUnitsGeometryTestHelpers.expectArgumentFailure(() -> new LayoutConstraints(-1.0, Math.POSITIVE_INFINITY, 2147483647));
    }

    @:test
    public static function layoutConstraintsRejectsNonPositiveMaxHeight():Void {
        new TestTraceRecorder("CoreUnitsGeometryTest").section("layoutConstraintsRejectsNonPositiveMaxHeight");
        CoreUnitsGeometryTestHelpers.expectArgumentFailure(() -> new LayoutConstraints(100.0, -1.0, 2147483647));
    }

    @:test
    public static function layoutConstraintsRejectsNonPositiveMaxLines():Void {
        new TestTraceRecorder("CoreUnitsGeometryTest").section("layoutConstraintsRejectsNonPositiveMaxLines");
        CoreUnitsGeometryTestHelpers.expectArgumentFailure(() -> new LayoutConstraints(100.0, 100.0, 0));
    }

    @:test
    public static function maxLinesDecisionInfoRecordsTruncationDetails():Void {
        new TestTraceRecorder("CoreUnitsGeometryTest").section("maxLinesDecisionInfoRecordsTruncationDetails");
        final info = new MaxLinesDecisionInfo(5, 3, "MaxLinesLineTruncation");
        TracedAssertions.assertEqualsInt(5, info.laidOutLines);
        TracedAssertions.assertEqualsInt(3, info.visibleLines);
        TracedAssertions.assertEqualsString("MaxLinesLineTruncation", info.reason);
    }

    @:test
    public static function layoutDebugInfoAcceptsMaxLinesDecision():Void {
        new TestTraceRecorder("CoreUnitsGeometryTest").section("layoutDebugInfoAcceptsMaxLinesDecision");
        final debug = new LayoutDebugInfo(new MaxLinesDecisionInfo(5, 3, "MaxLinesLineTruncation"), [], [], [], [], []);
        if (debug.maxLinesDecision == null) {
            TracedAssertions.fail();
            return;
        }
        final decision:MaxLinesDecisionInfo = debug.maxLinesDecision;
        TracedAssertions.assertEqualsInt(5, decision.laidOutLines);
        TracedAssertions.assertEqualsInt(3, decision.visibleLines);
    }
}

class CoreUnitsGeometryTestHelpers {
    public static function expectArgumentFailure(block:() -> Void):Void {
        TracedAssertions.assertFailsWith(null, block);
    }
}
