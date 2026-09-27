package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.TextRange;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedSet;

class DecideHyphenBreakTest {
    @:test public static function chargesAllDeficitToCjkWhenNoSinoWesternCapacityIsKnown():Void {
        new TestTraceRecorder("DecideHyphenBreakTest").section("chargesAllDeficitToCjkWhenNoSinoWesternCapacityIsKnown");
        TracedAssertions.assertEqualsInt(4, ProgressiveBreakDecisions.decideHyphenBreak(0, 4, DecideHyphenBreakTestSupport.cs(), 74, DecideHyphenBreakTestSupport.m([4]), DecideHyphenBreakTestSupport.m([1]), 8));
    }

    @:test public static function discountsSinoWesternCapacityBeforeChargingCjkLooseness():Void {
        new TestTraceRecorder("DecideHyphenBreakTest").section("discountsSinoWesternCapacityBeforeChargingCjkLooseness");
        TracedAssertions.assertEqualsInt(3, ProgressiveBreakDecisions.decideHyphenBreak(0, 4, DecideHyphenBreakTestSupport.cs(), 74, DecideHyphenBreakTestSupport.m([4]), DecideHyphenBreakTestSupport.m([1]), 8, DecideHyphenBreakTestSupport.m([2]), 4));
    }

    public static function flushTestTrace():Void {
        TestTraceRecorder.flushClass("DecideHyphenBreakTest");
    }

}
