package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.IntRange;
import org.tiqian.core.TextRange;
import org.tiqian.layout.LineOptimization.LineCandidate;
import org.tiqian.layout.LineOptimization.RepairOption;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;
import org.tiqian.layout.ProgressiveBreakDecisions.UnbreakableRanges;
import org.tiqian.layout.LineBreaker.LineBreakerLines;
import org.tiqian.layout.LineBreaker.GreedyLineBreaker;
import org.tiqian.layout.LineBreaker.LookaheadLineBreaker;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedSet;

class LookaheadLineBreakerTest {
    @:test public static function hangingTailIsExcludedFromFillDensityGeometry():Void {
        final testTrace = new TestTraceRecorder("LookaheadLineBreakerTest");
        testTrace.section("hangingTailIsExcludedFromFillDensityGeometry");
        final line = new LineCandidate(new IntRange(0, 2), new TextRange(0, 3), 48.0, 16.0, null, null, null, LookaheadLineBreakerTestSupport.ints([1, 2]));

        TracedAssertions.assertEqualsIntRange(new IntRange(0, 0), line.inMeasureClusterRange);
        TracedAssertions.assertEqualsInt(0, LineBreakerLines.lineGapCount(line.inMeasureClusterRange, LookaheadLineBreakerTestSupport.ints([1, 2])));
        TracedAssertions.assertEqualsFloat(0.0, LineBreakerLines.lineAdjustmentDensity(line, 48.0, false, LookaheadLineBreakerTestSupport.ints([1, 2])),
            "hung point-mark boundaries are not justification gaps");
    }

    @:test public static function hangingClustersMustBeAContiguousTrailingSuffix():Void {
        final testTrace = new TestTraceRecorder("LookaheadLineBreakerTest");
        testTrace.section("hangingClustersMustBeAContiguousTrailingSuffix");
        TracedAssertions.assertFailsWith(null, function() {
            new LineCandidate(new IntRange(0, 2), new TextRange(0, 3), 48.0, 32.0, null, null, null, LookaheadLineBreakerTestSupport.ints([1]));
        });
    }

    @:test public static function compatibilityHangingIndexSkipsATrailingMandatoryBreakControl():Void {
        final testTrace = new TestTraceRecorder("LookaheadLineBreakerTest");
        testTrace.section("compatibilityHangingIndexSkipsATrailingMandatoryBreakControl");
        final line = new LineCandidate(new IntRange(0, 2), new TextRange(0, 3), 32.0, 16.0, null, RepairOption.Hang(5, "test", 1), null,
            LookaheadLineBreakerTestSupport.ints([1, 2]));

        TracedAssertions.assertEqualsInt(1, line.hangingClusterIndex);
    }

    @:test public static function emptyInputProducesNoLines():Void {
        final testTrace = new TestTraceRecorder("LookaheadLineBreakerTest");
        testTrace.section("emptyInputProducesNoLines");
        final emptyClusters:Array<Cluster> = [];
        final solution = new LookaheadLineBreaker().breakLines(emptyClusters, emptyClusters, 100.0);
        TracedAssertions.assertEqualsInt(0, solution.lines.length);
    }

    @:test public static function lookaheadMatchesGreedyWhenShiftingEarlierGivesNoBenefit():Void {
        final testTrace = new TestTraceRecorder("LookaheadLineBreakerTest");
        testTrace.section("lookaheadMatchesGreedyWhenShiftingEarlierGivesNoBenefit");
        final clusters:Array<Cluster> = [];
        for (i in 0...6) {
            clusters.push(LookaheadLineBreakerTestSupport.cluster(i, i + 1, "x", 16.0));
        }
        final solution = new LookaheadLineBreaker().breakLines(clusters, clusters, 64.0);

        TracedAssertions.assertEqualsInt(2, solution.lines.length);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 3), solution.lines[0].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(4, 5), solution.lines[1].clusterRange);
        TracedAssertions.assertEqualsFloat(0.0, solution.totalBadness);
    }

    @:test public static function lookaheadShiftsBreakEarlierToAvoidKinsokuRepair():Void {
        final testTrace = new TestTraceRecorder("LookaheadLineBreakerTest");
        testTrace.section("lookaheadShiftsBreakEarlierToAvoidKinsokuRepair");
        final clusters = [
            LookaheadLineBreakerTestSupport.cluster(0, 1, "中", 16.0),
            LookaheadLineBreakerTestSupport.cluster(1, 2, "文", 16.0),
            LookaheadLineBreakerTestSupport.cluster(2, 3, "中", 16.0),
            LookaheadLineBreakerTestSupport.cluster(3, 4, "文", 16.0),
            LookaheadLineBreakerTestSupport.cluster(4, 5, "中", 16.0),
            LookaheadLineBreakerTestSupport.cluster(5, 6, "文", 16.0),
            LookaheadLineBreakerTestSupport.cluster(6, 7, "。", 16.0)
        ];

        final greedy = new GreedyLineBreaker().breakLines(clusters, clusters, 48.0);
        final lookahead = new LookaheadLineBreaker().breakLines(clusters, clusters, 48.0);

        // Greedy ends up with a CarryPrevious repair.
        TracedAssertions.assertEqualsInt(3, greedy.lines.length);
        TracedAssertions.assertEqualsBool(true, LookaheadLineBreakerTestSupport.isCarryPrevious(greedy.lines[2].repair));
        TracedAssertions.assertEqualsFloat(10.0, greedy.totalBadness);

        // Lookahead avoids the conflict entirely.
        TracedAssertions.assertEqualsInt(3, lookahead.lines.length);
        TracedAssertions.assertEqualsNullableRepairOption(null, lookahead.lines[0].repair);
        TracedAssertions.assertEqualsNullableRepairOption(null, lookahead.lines[1].repair);
        TracedAssertions.assertEqualsNullableRepairOption(null, lookahead.lines[2].repair);
        TracedAssertions.assertEqualsFloat(0.0, lookahead.totalBadness);

        // Concrete shape: 32 / 48 / 32 instead of greedy's 48 / 32 / 32.
        TracedAssertions.assertEqualsFloat(32.0, lookahead.lines[0].adjustedWidth);
        TracedAssertions.assertEqualsFloat(48.0, lookahead.lines[1].adjustedWidth);
        TracedAssertions.assertEqualsFloat(32.0, lookahead.lines[2].adjustedWidth);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 1), lookahead.lines[0].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(2, 4), lookahead.lines[1].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(5, 6), lookahead.lines[2].clusterRange);
    }

    @:test public static function lookaheadKeepsGreedyBreakWhenPushInGlueCoversRepair():Void {
        final testTrace = new TestTraceRecorder("LookaheadLineBreakerTest");
        testTrace.section("lookaheadKeepsGreedyBreakWhenPushInGlueCoversRepair");
        final clusters = [
            LookaheadLineBreakerTestSupport.cluster(0, 1, "中", 16.0),
            LookaheadLineBreakerTestSupport.cluster(1, 2, "文", 16.0),
            LookaheadLineBreakerTestSupport.cluster(2, 3, "中", 16.0),
            LookaheadLineBreakerTestSupport.cluster(3, 4, "。", 16.0)
        ];
        final solution = new LookaheadLineBreaker().breakLines(clusters, clusters, 60.0, [new ShrinkOpportunity(3, 6, 4.0, ShrinkChannel.TrailingGlue)]);

        TracedAssertions.assertEqualsInt(1, solution.lines.length);
        final line = solution.lines[0];
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 3), line.clusterRange);
        TracedAssertions.assertEqualsFloat(60.0, line.adjustedWidth);
        TracedAssertions.assertEqualsBool(true, LookaheadLineBreakerTestSupport.isPushIn(line.repair));
        TracedAssertions.assertEqualsFloat(2.0, solution.totalBadness);
    }

    @:test public static function lookaheadScoresFuturePushInBeforeChoosingEarlierBreak():Void {
        final testTrace = new TestTraceRecorder("LookaheadLineBreakerTest");
        testTrace.section("lookaheadScoresFuturePushInBeforeChoosingEarlierBreak");
        final clusters = [
            LookaheadLineBreakerTestSupport.cluster(0, 1, "中", 16.0),
            LookaheadLineBreakerTestSupport.cluster(1, 2, "文", 16.0),
            LookaheadLineBreakerTestSupport.cluster(2, 3, "中", 16.0),
            LookaheadLineBreakerTestSupport.cluster(3, 4, "文", 16.0),
            LookaheadLineBreakerTestSupport.cluster(4, 5, "中", 16.0),
            LookaheadLineBreakerTestSupport.cluster(5, 6, "文", 16.0),
            LookaheadLineBreakerTestSupport.cluster(6, 7, "。", 16.0)
        ];
        final solution = new LookaheadLineBreaker().breakLines(clusters, clusters, 60.0, [new ShrinkOpportunity(6, 6, 4.0, ShrinkChannel.TrailingGlue)]);

        TracedAssertions.assertEqualsInt(2, solution.lines.length);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 2), solution.lines[0].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(3, 6), solution.lines[1].clusterRange);
        TracedAssertions.assertEqualsFloat(60.0, solution.lines[1].adjustedWidth);
        TracedAssertions.assertEqualsBool(true, LookaheadLineBreakerTestSupport.isPushIn(solution.lines[1].repair));
        TracedAssertions.assertEqualsFloat(2.0, solution.totalBadness);
    }

    @:test public static function lookaheadFallsBackToGreedyWhenAlternativesAreWorse():Void {
        final testTrace = new TestTraceRecorder("LookaheadLineBreakerTest");
        testTrace.section("lookaheadFallsBackToGreedyWhenAlternativesAreWorse");
        final clusters:Array<Cluster> = [];
        for (i in 0...9) {
            clusters.push(LookaheadLineBreakerTestSupport.cluster(i, i + 1, "x", 16.0));
        }
        final solution = new LookaheadLineBreaker().breakLines(clusters, clusters, 64.0);

        TracedAssertions.assertEqualsInt(3, solution.lines.length);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 3), solution.lines[0].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(4, 7), solution.lines[1].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(8, 8), solution.lines[2].clusterRange);
    }

    @:test public static function lookaheadAvoidsConsecutiveSyntheticHyphenBreaks():Void {
        final testTrace = new TestTraceRecorder("LookaheadLineBreakerTest");
        testTrace.section("lookaheadAvoidsConsecutiveSyntheticHyphenBreaks");
        final clusters:Array<Cluster> = [];
        for (i in 0...8) {
            clusters.push(LookaheadLineBreakerTestSupport.cluster(i, i + 1, "x", 10.0));
        }

        final noPenalty = new LookaheadLineBreaker(null, null, null, null, null, null, null,
            0.0).breakLines(clusters, clusters, 30.0, null, null, null, null, null, null, null, LookaheadLineBreakerTestSupport.ints([3, 6]));
        final withPenalty = new LookaheadLineBreaker().breakLines(clusters, clusters, 30.0, null, null, null, null, null, null, null,
            LookaheadLineBreakerTestSupport.ints([3, 6]));

        // With no demerit, two perfectly full synthetic-hyphen lines win:
        // 0..2- / 3..5- / 6..7.
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 2), noPenalty.lines[0].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(3, 5), noPenalty.lines[1].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(6, 7), noPenalty.lines[2].clusterRange);

        // AvoidConsecutiveSyntheticHyphenBreaks pays a soft penalty on the
        // second generated hyphen, so one ragged line is cheaper here:
        // 0..1 / 2..4 / 5..7.
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 1), withPenalty.lines[0].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(2, 4), withPenalty.lines[1].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(5, 7), withPenalty.lines[2].clusterRange);
    }

    @:test public static function lookaheadScoresKinsokuRepairsWithUnbreakableRanges():Void {
        final testTrace = new TestTraceRecorder("LookaheadLineBreakerTest");
        testTrace.section("lookaheadScoresKinsokuRepairsWithUnbreakableRanges");
        final clusters = [
            LookaheadLineBreakerTestSupport.cluster(0, 1, "甲", 16.0),
            LookaheadLineBreakerTestSupport.cluster(1, 2, "乙", 16.0),
            LookaheadLineBreakerTestSupport.cluster(2, 3, "丙", 16.0),
            LookaheadLineBreakerTestSupport.cluster(3, 4, "丁", 16.0),
            LookaheadLineBreakerTestSupport.cluster(4, 5, "戊", 16.0),
            LookaheadLineBreakerTestSupport.cluster(5, 6, "己", 16.0),
            LookaheadLineBreakerTestSupport.cluster(6, 7, "庚", 16.0),
            LookaheadLineBreakerTestSupport.cluster(7, 8, "辛", 16.0),
            LookaheadLineBreakerTestSupport.cluster(8, 9, "。", 16.0)
        ];

        final solution = new LookaheadLineBreaker(2).breakLines(clusters, clusters, 64.0, null, new UnbreakableRanges([new IntRange(6, 7)]), null, null, null,
            LookaheadLineBreakerTestSupport.ints([8]), null, null, null, null, null, null, false);

        TracedAssertions.assertEqualsInt(3, solution.lines.length);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 1), solution.lines[0].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(2, 5), solution.lines[1].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(6, 8), solution.lines[2].clusterRange);
        TracedAssertions.assertEqualsNullableRepairOption(null, solution.lines[0].repair);
        TracedAssertions.assertEqualsNullableRepairOption(null, solution.lines[1].repair);
        TracedAssertions.assertEqualsNullableRepairOption(null, solution.lines[2].repair);
        TracedAssertions.assertEqualsFloat(0.0, solution.totalBadness);
    }

    @:test public static function windowZeroReducesLookaheadToGreedy():Void {
        final testTrace = new TestTraceRecorder("LookaheadLineBreakerTest");
        testTrace.section("windowZeroReducesLookaheadToGreedy");
        final clusters = [
            LookaheadLineBreakerTestSupport.cluster(0, 1, "中", 16.0),
            LookaheadLineBreakerTestSupport.cluster(1, 2, "文", 16.0),
            LookaheadLineBreakerTestSupport.cluster(2, 3, "中", 16.0),
            LookaheadLineBreakerTestSupport.cluster(3, 4, "文", 16.0),
            LookaheadLineBreakerTestSupport.cluster(4, 5, "中", 16.0),
            LookaheadLineBreakerTestSupport.cluster(5, 6, "文", 16.0),
            LookaheadLineBreakerTestSupport.cluster(6, 7, "。", 16.0)
        ];
        final solution = new LookaheadLineBreaker(0).breakLines(clusters, clusters, 48.0);

        // Same as greedy: CarryPrevious on last line.
        TracedAssertions.assertEqualsInt(3, solution.lines.length);
        TracedAssertions.assertEqualsBool(true, LookaheadLineBreakerTestSupport.isCarryPrevious(solution.lines[2].repair));
    }
}

class LookaheadLineBreakerTestSupport {
    public static function isCarryPrevious(repair:Null<RepairOption>):Bool {
        if (repair == null)
            return false;
        final r:RepairOption = repair;
        return switch (r) {
            case CarryPrevious(_, _, _, _): true;
            case PushIn(_, _, _, _, _, _): false;
            case Hang(_, _, _): false;
            case CarryNext(_, _, _): false;
            case LeaveRagged(_, _, _): false;
        };
    }

    public static function isPushIn(repair:Null<RepairOption>):Bool {
        if (repair == null)
            return false;
        final r:RepairOption = repair;
        return switch (r) {
            case PushIn(_, _, _, _, _, _): true;
            case CarryPrevious(_, _, _, _): false;
            case Hang(_, _, _): false;
            case CarryNext(_, _, _): false;
            case LeaveRagged(_, _, _): false;
        };
    }

    public static function cluster(start:Int, end:Int, text:String, advance:Float):Cluster {
        return new Cluster(new TextRange(start, end), text, "test", advance);
    }

    public static function ints(values:Array<Int>):SortedSet<Int> {
        final b = SortedSet.builder();
        for (v in values) {
            b.put(v);
        }
        return b.build();
    }
}
