package org.tiqian.layout;

import org.tiqian.layout.Justifier.CompressionPlan;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class JustifierCompressionTestSupport {
    public static function shrinkOf(plan:CompressionPlan, clusterIndex:Int):Null<Float> {
        var i = 0;
        while (i < plan.allocations.length) {
            if (plan.allocations[i].clusterIndex == clusterIndex)
                return plan.allocations[i].shrink;
            i++;
        }
        return null;
    }
}

class JustifierCompressionTest {
    @:test public static function consumesTiersInAscendingOrder():Void {
        new TestTraceRecorder("JustifierCompressionTest").section("consumesTiersInAscendingOrder");
        final justifier = new Justifier();
        final opps:Array<ShrinkOpportunity> = [
            new ShrinkOpportunity(0, 1, 2.0, ShrinkChannel.TrailingGlue),
            new ShrinkOpportunity(1, 2, 5.0, ShrinkChannel.TrailingGlue),
            new ShrinkOpportunity(2, 3, 5.0, ShrinkChannel.TrailingGlue),
        ];
        final plan = justifier.compress(3.0, opps);
        TracedAssertions.assertEqualsFloatTolerance(0.0, plan.unfilledSurplus, 0.0001);
        TracedAssertions.assertEqualsFloatTolerance(2.0, JustifierCompressionTestSupport.shrinkOf(plan, 0), 0.0001);
        TracedAssertions.assertEqualsFloatTolerance(1.0, JustifierCompressionTestSupport.shrinkOf(plan, 1), 0.0001);
        TracedAssertions.assertNullRendered(JustifierCompressionTestSupport.shrinkOf(plan, 2) == null, "-", "tier 3 must stay untouched while tier 2 has room");
    }

    @:test public static function sharesEqualFractionWithinATier():Void {
        new TestTraceRecorder("JustifierCompressionTest").section("sharesEqualFractionWithinATier");
        var p = new Justifier().compress(4, [
            new ShrinkOpportunity(0, 2, 2, ShrinkChannel.TrailingGlue),
            new ShrinkOpportunity(1, 2, 6, ShrinkChannel.TrailingGlue)
        ]);
        TracedAssertions.assertEqualsFloatTolerance(1, JustifierCompressionTestSupport.shrinkOf(p, 0), .0001);
        TracedAssertions.assertEqualsFloatTolerance(3, JustifierCompressionTestSupport.shrinkOf(p, 1), .0001);
        TracedAssertions.assertEqualsFloatTolerance(0, p.unfilledSurplus, .0001);
    }

    @:test public static function reportsUnfilledWhenCapacityExhausted():Void {
        new TestTraceRecorder("JustifierCompressionTest").section("reportsUnfilledWhenCapacityExhausted");
        var p = new Justifier().compress(5, [
            new ShrinkOpportunity(0, 1, 1, ShrinkChannel.TrailingGlue),
            new ShrinkOpportunity(1, 2, 1, ShrinkChannel.TrailingGlue)
        ]);
        TracedAssertions.assertEqualsFloatTolerance(3, p.unfilledSurplus, .0001);
        TracedAssertions.assertEquals(2, p.allocations.length);
    }

    @:test public static function zeroSurplusIsNoOp():Void {
        new TestTraceRecorder("JustifierCompressionTest").section("zeroSurplusIsNoOp");
        var p = new Justifier().compress(0, [new ShrinkOpportunity(0, 1, 5, ShrinkChannel.TrailingGlue)]);
        TracedAssertions.assertTrue(p.allocations.length == 0);
        TracedAssertions.assertEqualsFloatTolerance(0, p.unfilledSurplus, .0001);
    }

    @:test public static function nanSurplusEmitsNoAllocations():Void {
        new TestTraceRecorder("JustifierCompressionTest").section("nanSurplusEmitsNoAllocations");
        final justifier = new Justifier();
        final plan = justifier.compress(Math.NaN, [new ShrinkOpportunity(0, 1, 5.0, ShrinkChannel.TrailingGlue)]);
        TracedAssertions.assertTrue(plan.allocations.length == 0);
        TracedAssertions.assertTrue(Math.isNaN(plan.unfilledSurplus));
    }
}
