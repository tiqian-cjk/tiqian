package org.tiqian.layout;

import org.tiqian.core.IntRange;
import org.tiqian.core.Cluster;
import org.tiqian.core.TextRange;
import org.tiqian.core.TiqianIllegalArgumentException;
import org.tiqian.layout.LineOptimization.RepairOptions;
import org.tiqian.layout.LineOptimization.RepairCandidate;
import org.tiqian.layout.LineBreaker.GreedyLineBreaker;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;
import org.tiqian.layout.ProgressiveBreakDecisions.UnbreakableRanges;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import org.tiqian.test.trace.TestTraceRender;

class PushInLineWideCapacityTest {
    @:test public static function pushInAggregatesShrinkFromMultiplePrecedingClusters():Void {
        final t = new TestTraceRecorder("PushInLineWideCapacityTest");
        t.section("pushInAggregatesShrinkFromMultiplePrecedingClusters");
        final c:Array<Cluster> = [];
        for (i in 0...5)
            c.push(PushInLineWideCapacityTestSupport.cluster(i, i + 1, "中", 16));
        c.push(PushInLineWideCapacityTestSupport.cluster(5, 6, "、", 16));
        for (i in 0...4)
            c.push(PushInLineWideCapacityTestSupport.cluster(6 + i, 7 + i, "文", 16));
        c.push(PushInLineWideCapacityTestSupport.cluster(10, 11, "。", 16));
        final s = new GreedyLineBreaker().breakLines(c, c, 160, [
            new ShrinkOpportunity(5, 6, 8, ShrinkChannel.TrailingGlue),
            new ShrinkOpportunity(10, 6, 8, ShrinkChannel.TrailingGlue)
        ]);
        final l = s.lines[0];
        TracedAssertions.assertEqualsInt(1, s.lines.length);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 10), l.clusterRange);
        TracedAssertions.assertEqualsFloat(160, l.adjustedWidth);
        TracedAssertions.assertNotNullRendered(l.repair != null,
            l.repair == null ? "null" : TestTraceRender.cap(PushInLineWideCapacityTestSupport.pushInString(l.repair)));
        TracedAssertions.assertTrue(PushInLineWideCapacityTestSupport.isPushIn(l.repair));
        TracedAssertions.assertEqualsInt(10, PushInLineWideCapacityTestSupport.pushInOffenderClusterIndex(l.repair));
        TracedAssertions.assertEqualsFloat(16, PushInLineWideCapacityTestSupport.pushInTotalShrink(l.repair));
        TracedAssertions.assertEqualsFloat(16, PushInLineWideCapacityTestSupport.pushInTotalAvailableCapacity(l.repair));
        final indexesM1:Array<Int> = [];
        for (a in PushInLineWideCapacityTestSupport.pushInAllocations(l.repair))
            indexesM1.push(a.clusterIndex);
        TracedAssertions.assertEqualsIntArray([10, 5], indexesM1);
        TracedAssertions.assertEqualsFloat(8, PushInLineWideCapacityTestSupport.pushInAllocations(l.repair)[0].shrink);
        TracedAssertions.assertEqualsFloat(8, PushInLineWideCapacityTestSupport.pushInAllocations(l.repair)[1].shrink);
    }

    @:test public static function pushInRejectsWhenLineWideCapacityStillInsufficient():Void {
        final t = new TestTraceRecorder("PushInLineWideCapacityTest");
        t.section("pushInRejectsWhenLineWideCapacityStillInsufficient");
        final c = [
            for (i in 0...11)
                PushInLineWideCapacityTestSupport.cluster(i, i + 1, i == 5 ? "、" : i == 10 ? "。" : "文", 16)
        ];
        final s = new GreedyLineBreaker().breakLines(c, c, 160, [new ShrinkOpportunity(5, 6, 4, ShrinkChannel.TrailingGlue)]);
        TracedAssertions.assertEqualsInt(2, s.lines.length);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 8), s.lines[0].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(9, 10), s.lines[1].clusterRange);
        TracedAssertions.assertTrue(PushInLineWideCapacityTestSupport.isCarryPrevious(s.lines[1].repair));
        var p:Null<RepairCandidate> = null;
        for (cand in s.lines[1].repairCandidates)
            if (cand.kind == "PushIn") {
                p = cand;
                break;
            }
        TracedAssertions.assertNotNullRendered(p != null, p == null ? "null" : TestTraceRender.cap(Std.string(p)));
        TracedAssertions.assertEqualsBool(false, p.accepted);
        TracedAssertions.assertEqualsString("insufficient-capacity", p.rejectionReason);
        TracedAssertions.assertEqualsFloat(4, p.availableCapacity);
        TracedAssertions.assertEqualsFloat(16, p.requiredShrink);
    }

    @:test public static function pushInOffenderOnlyCapacityStillWorksBackCompat():Void {
        final t = new TestTraceRecorder("PushInLineWideCapacityTest");
        t.section("pushInOffenderOnlyCapacityStillWorksBackCompat");
        final c = [
            PushInLineWideCapacityTestSupport.cluster(0, 1, "中", 16),
            PushInLineWideCapacityTestSupport.cluster(1, 2, "文", 16),
            PushInLineWideCapacityTestSupport.cluster(2, 3, "中", 16),
            PushInLineWideCapacityTestSupport.cluster(3, 4, "。", 16)
        ];
        final s = new GreedyLineBreaker().breakLines(c, c, 60, [new ShrinkOpportunity(3, 6, 4, ShrinkChannel.TrailingGlue)]);
        TracedAssertions.assertEqualsInt(1, s.lines.length);
        TracedAssertions.assertTrue(PushInLineWideCapacityTestSupport.isPushIn(s.lines[0].repair));
        final indexesM3:Array<Int> = [];
        for (a in PushInLineWideCapacityTestSupport.pushInAllocations(s.lines[0].repair))
            indexesM3.push(a.clusterIndex);
        TracedAssertions.assertEqualsIntArray([3], indexesM3);
        TracedAssertions.assertEqualsFloat(4, PushInLineWideCapacityTestSupport.pushInTotalShrink(s.lines[0].repair));
    }

    @:test public static function pushInMergesOffenderThatFitsAfterChainedRepairs():Void {
        final t = new TestTraceRecorder("PushInLineWideCapacityTest");
        t.section("pushInMergesOffenderThatFitsAfterChainedRepairs");
        final c = [
            for (i in 0...10)
                PushInLineWideCapacityTestSupport.cluster(i, i + 1, i == 3 ? "」" : i == 4 ? "。" : i == 8 ? "、" : "中", 16)
        ];
        final s = new GreedyLineBreaker().breakLines(c, c, 64, [
            new ShrinkOpportunity(3, 6, 8, ShrinkChannel.TrailingGlue),
            new ShrinkOpportunity(4, 6, 8, ShrinkChannel.TrailingGlue),
            new ShrinkOpportunity(8, 6, 8, ShrinkChannel.TrailingGlue)
        ]);
        TracedAssertions.assertEqualsInt(3, s.lines.length);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 4), s.lines[0].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(5, 8), s.lines[1].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(9, 9), s.lines[2].clusterRange);
        for (line in s.lines) {
            final first = c[line.clusterRange.start].text;
            TracedAssertions.assertTrue(first == "中", "line starts with forbidden '" + first + "'");
        }
        TracedAssertions.assertTrue(PushInLineWideCapacityTestSupport.isPushIn(s.lines[1].repair));
        TracedAssertions.assertEqualsFloat(0, PushInLineWideCapacityTestSupport.pushInTotalShrink(s.lines[1].repair));
        TracedAssertions.assertTrue(RepairOptions.reason(s.lines[1].repair).indexOf("fits-no-shrink") >= 0);
        TracedAssertions.assertEqualsFloat(64, s.lines[1].adjustedWidth);
    }

    @:test public static function carryPreviousRefusesToSplitUnbreakableSpan():Void {
        final t = new TestTraceRecorder("PushInLineWideCapacityTest");
        t.section("carryPreviousRefusesToSplitUnbreakableSpan");
        final c = [
            PushInLineWideCapacityTestSupport.cluster(0, 1, "中", 16),
            PushInLineWideCapacityTestSupport.cluster(1, 2, "中", 16),
            PushInLineWideCapacityTestSupport.cluster(2, 3, "王", 16),
            PushInLineWideCapacityTestSupport.cluster(3, 4, "小", 16),
            PushInLineWideCapacityTestSupport.cluster(4, 5, "明", 16),
            PushInLineWideCapacityTestSupport.cluster(5, 6, "。", 16)
        ];
        final s = new GreedyLineBreaker().breakLines(c, c, 80, [new ShrinkOpportunity(5, 6, 8, ShrinkChannel.TrailingGlue)],
            new UnbreakableRanges([new IntRange(2, 4)]));
        TracedAssertions.assertEqualsInt(2, s.lines.length);
        TracedAssertions.assertTrue(PushInLineWideCapacityTestSupport.isLeaveRagged(s.lines[1].repair));
        final reason = RepairOptions.reason(s.lines[1].repair);
        TracedAssertions.assertTrue(reason.substr(reason.length - "carry-would-split-mourning-span".length) == "carry-would-split-mourning-span");
        var carry:Null<RepairCandidate> = null;
        for (cand in s.lines[1].repairCandidates)
            if (cand.kind == "CarryPrevious") {
                carry = cand;
                break;
            }
        if (carry == null)
            throw new TiqianIllegalArgumentException(Message("CarryPrevious candidate not found"));
        TracedAssertions.assertEqualsString("carry-would-split-mourning-span", carry.rejectionReason);
    }
}
