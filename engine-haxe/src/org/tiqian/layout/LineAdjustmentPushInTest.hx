package org.tiqian.layout;

import org.tiqian.clreq.*;
import org.tiqian.core.*;
import org.tiqian.test.trace.*;
import org.tiqian.layout.LineOptimization.LineCandidate;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;
import org.tiqian.layout.ProgressiveBreakDecisions.UnbreakableRanges;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import std.SortedSet;
import std.SortedMap;

class LineAdjustmentPushInTest {
    @:test public static function fillPushInCompressesSourceSpaceToPromoteEmergencyBreakToSyllable():Void {
        final t = new TestTraceRecorder("LineAdjustmentPushInTest");
        t.section("fillPushInCompressesSourceSpaceToPromoteEmergencyBreakToSyllable");
        final c = LineAdjustmentPushInTestSupport.technicalClusters();
        final techRange = new TextRange(0, 5);
        final prog = SortedMap.builder();
        prog.put(1, new ProgressiveBreakOpportunity(ProgressiveBreakTier.Structural, techRange));
        prog.put(3, new ProgressiveBreakOpportunity(ProgressiveBreakTier.Emergency, techRange));
        prog.put(4, new ProgressiveBreakOpportunity(ProgressiveBreakTier.Syllable, techRange));
        final s = LineAdjustmentPushInTestSupport.fill(c, 80, [new ShrinkOpportunity(1, 2, 10, ShrinkChannel.RawAdvance)], null, null, prog.build(), 2);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 3), s[0].clusterRange);
        TracedAssertions.assertEqualsFloat(80, s[0].adjustedWidth);
        TracedAssertions.assertEqualsIntRange(new IntRange(4, 4), s[1].clusterRange);
        TracedAssertions.assertEqualsFloat(5, LineAdjustmentPushInTestSupport.repairTotalShrink(s[0].repair));
        final allocs = LineAdjustmentPushInTestSupport.repairAllocations(s[0].repair);
        TracedAssertions.assertEqualsInt(1, allocs[0].clusterIndex);
        TracedAssertions.assertEqualsFloat(5, allocs[0].shrink);
        TracedAssertions.assertTrue(StringTools.startsWith(LineAdjustmentPushInTestSupport.repairReason(s[0].repair), "ProgressiveTechnicalTierPromotion"));
    }

    @:test public static function fillPushInCrossesIntermediateCleanerBoundaryToRefillAtSelectedTier():Void {
        final t = new TestTraceRecorder("LineAdjustmentPushInTest");
        t.section("fillPushInCrossesIntermediateCleanerBoundaryToRefillAtSelectedTier");
        final c = LineAdjustmentPushInTestSupport.technicalClusters();
        final techRange = new TextRange(0, 5);
        final prog = SortedMap.builder();
        prog.put(3, new ProgressiveBreakOpportunity(ProgressiveBreakTier.Emergency, techRange));
        prog.put(4, new ProgressiveBreakOpportunity(ProgressiveBreakTier.Syllable, techRange));
        prog.put(5, new ProgressiveBreakOpportunity(ProgressiveBreakTier.Emergency, techRange));
        final s = LineAdjustmentPushInTestSupport.fill(c, 100, null, null, null, prog.build(), 2);
        TracedAssertions.assertEqualsInt(1, s.length);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 4), s[0].clusterRange);
        TracedAssertions.assertEqualsFloat(100, s[0].adjustedWidth);
        TracedAssertions.assertTrue(StringTools.startsWith(LineAdjustmentPushInTestSupport.repairReason(s[0].repair), "LineAdjustmentPushIn"));
    }

    @:test public static function fillPushInDoesNotPromoteEmergencyBreakWhenCleanerBoundaryStillLeavesDeficit():Void {
        final t = new TestTraceRecorder("LineAdjustmentPushInTest");
        t.section("fillPushInDoesNotPromoteEmergencyBreakWhenCleanerBoundaryStillLeavesDeficit");
        final c = LineAdjustmentPushInTestSupport.technicalClusters();
        final techRange = new TextRange(0, 5);
        final prog = SortedMap.builder();
        prog.put(3, new ProgressiveBreakOpportunity(ProgressiveBreakTier.Emergency, techRange));
        prog.put(4, new ProgressiveBreakOpportunity(ProgressiveBreakTier.Syllable, techRange));
        final s = LineAdjustmentPushInTestSupport.fill(c, 100, null, null, null, prog.build(), 2);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 2), s[0].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(3, 4), s[1].clusterRange);
        TracedAssertions.assertEqualsNullableRepairOption(null, s[0].repair);
    }

    @:test public static function fillPushInExtendsPastForbiddenLineEndHead():Void {
        final t = new TestTraceRecorder("LineAdjustmentPushInTest");
        t.section("fillPushInExtendsPastForbiddenLineEndHead");
        final c = LineAdjustmentPushInTestSupport.forbiddenHeadEndClusters();
        final s = LineAdjustmentPushInTestSupport.fill(c, 100, null, null, [2]);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 3), s[0].clusterRange);
        TracedAssertions.assertEqualsFloat(90, s[0].adjustedWidth);
        TracedAssertions.assertEqualsIntRange(new IntRange(4, 4), s[1].clusterRange);
        TracedAssertions.assertEqualsInt(3, LineAdjustmentPushInTestSupport.repairOffenderIndex(s[0].repair));
        TracedAssertions.assertEqualsFloat(0, LineAdjustmentPushInTestSupport.repairTotalShrink(s[0].repair));
    }

    @:test public static function fillPushInPullsMinimalGroupToAvoidForbiddenNextHead():Void {
        final t = new TestTraceRecorder("LineAdjustmentPushInTest");
        t.section("fillPushInPullsMinimalGroupToAvoidForbiddenNextHead");
        final c = LineAdjustmentPushInTestSupport.forbiddenHeadStartClusters();
        final s = LineAdjustmentPushInTestSupport.fill(c, 100, null, [3]);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 3), s[0].clusterRange);
        TracedAssertions.assertEqualsFloat(90, s[0].adjustedWidth);
        TracedAssertions.assertEqualsIntRange(new IntRange(4, 4), s[1].clusterRange);
        TracedAssertions.assertEqualsInt(3, LineAdjustmentPushInTestSupport.repairOffenderIndex(s[0].repair));
        TracedAssertions.assertEqualsFloat(0, LineAdjustmentPushInTestSupport.repairTotalShrink(s[0].repair));
    }

    @:test public static function noShrinkFillPushInCanContinueUntilTheLineIsNoLongerLoose():Void {
        final t = new TestTraceRecorder("LineAdjustmentPushInTest");
        t.section("noShrinkFillPushInCanContinueUntilTheLineIsNoLongerLoose");
        final c = LineAdjustmentPushInTestSupport.baseClusters();
        final s = LineAdjustmentPushInTestSupport.fill(c, 100);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 3), s[0].clusterRange);
        TracedAssertions.assertEqualsFloat(100, s[0].adjustedWidth);
        TracedAssertions.assertEqualsIntRange(new IntRange(4, 5), s[1].clusterRange);
        TracedAssertions.assertEqualsFloat(0, LineAdjustmentPushInTestSupport.repairTotalShrink(s[0].repair));
    }

    @:test public static function pushInFirstCompressesSomeBoundariesPushOutOnlyNone():Void {
        final t = new TestTraceRecorder("LineAdjustmentPushInTest");
        t.section("pushInFirstCompressesSomeBoundariesPushOutOnlyNone");
        final auto = LineAdjustmentPushInTestSupport.layout(LineAdjustmentStrategy.PushInFirst);
        final pushOut = LineAdjustmentPushInTestSupport.layout(LineAdjustmentStrategy.PushOutOnly);
        TracedAssertions.assertEqualsInt(0, LineAdjustmentPushInTestSupport.fillPushInCount(pushOut), "PushOutOnly must never fill-push-in");
        TracedAssertions.assertTrue(LineAdjustmentPushInTestSupport.fillPushInCount(auto) > 0, "PushInFirst should compress at least one boundary");
        TracedAssertions.assertTrue(auto.lines.length <= pushOut.lines.length,
            "PushInFirst ("
            + auto.lines.length
            + ") should not need more lines than PushOutOnly ("
            + pushOut.lines.length
            + ")");
    }

    @:test public static function pushInFirstDoesNotCompressEveryLine():Void {
        final t = new TestTraceRecorder("LineAdjustmentPushInTest");
        t.section("pushInFirstDoesNotCompressEveryLine");
        final auto = LineAdjustmentPushInTestSupport.layout(LineAdjustmentStrategy.PushInFirst);
        TracedAssertions.assertTrue(LineAdjustmentPushInTestSupport.fillPushInCount(auto) < auto.lines.length,
            "not every line should be a fill-push-in ("
            + LineAdjustmentPushInTestSupport.fillPushInCount(auto)
            + "/"
            + auto.lines.length
            + ")");
    }
}
