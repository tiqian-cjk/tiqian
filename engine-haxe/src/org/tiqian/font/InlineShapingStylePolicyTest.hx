package org.tiqian.font;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class InlineShapingStylePolicyTest {
    @:test public static function reportsFirstPropertyWhenItDiverges():Void {
        new TestTraceRecorder("InlineShapingStylePolicyTest").section("reportsFirstPropertyWhenItDiverges");
        var a = InlineShapingStylePolicyTestSupport.vals(15);
        a[0] = "divergent";
        TracedAssertions.assertEqualsString("font-feature-settings",
            InlineShapingStylePolicy.firstDivergentProperty(a, InlineShapingStylePolicyTestSupport.vals(15)));
    }

    @:test public static function reportsMiddlePropertyWhenItIsFirstDivergence():Void {
        new TestTraceRecorder("InlineShapingStylePolicyTest").section("reportsMiddlePropertyWhenItIsFirstDivergence");
        var a = InlineShapingStylePolicyTestSupport.vals(15);
        a[3] = "divergent";
        TracedAssertions.assertEqualsString("font-kerning", InlineShapingStylePolicy.firstDivergentProperty(a, InlineShapingStylePolicyTestSupport.vals(15)));
    }

    @:test public static function returnsNullWhenAllValuesMatch():Void {
        new TestTraceRecorder("InlineShapingStylePolicyTest").section("returnsNullWhenAllValuesMatch");
        TracedAssertions.assertNullRendered(InlineShapingStylePolicy.firstDivergentProperty(InlineShapingStylePolicyTestSupport.vals(15),
            InlineShapingStylePolicyTestSupport.vals(15)) == null,
            "-");
    }

    @:test public static function returnsNullForEmptyLists():Void {
        new TestTraceRecorder("InlineShapingStylePolicyTest").section("returnsNullForEmptyLists");
        TracedAssertions.assertNullRendered(InlineShapingStylePolicy.firstDivergentProperty([], []) == null, "-");
    }

    @:test public static function longerValueListsStopAtThePropertyListBoundary():Void {
        new TestTraceRecorder("InlineShapingStylePolicyTest").section("longerValueListsStopAtThePropertyListBoundary");
        TracedAssertions.assertNullRendered(InlineShapingStylePolicy.firstDivergentProperty(InlineShapingStylePolicyTestSupport.vals(19),
            InlineShapingStylePolicyTestSupport.vals(19)) == null,
            "-");
    }
}
