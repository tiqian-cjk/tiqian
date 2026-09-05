package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.IntRange;
import org.tiqian.core.TextRange;
import org.tiqian.layout.LineOptimization.RepairOption;
import org.tiqian.layout.LineOptimization.RepairCandidate;
import org.tiqian.layout.LineOptimization.PushInAllocation;
import org.tiqian.layout.LineBreaker.GreedyLineBreaker;
import org.tiqian.layout.KinsokuRule;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedSet;

/**
 * Haxe port of Kotlin GreedyLineBreakerTest.kt. Every test opens its golden
 * trace section through GreedyLineBreakerTestSupport.start and asserts the
 * same values in the same order as the Kotlin original.
 */
class GreedyLineBreakerTest {
    @:test public static function emptyInputProducesNoLines():Void {
        GreedyLineBreakerTestSupport.start("emptyInputProducesNoLines");
        final solution = new GreedyLineBreaker().breakLines([], [], 100);
        TracedAssertions.assertEquals(0, solution.lines.length);
    }

    @:test public static function singleClusterFitsOnOneLine():Void {
        GreedyLineBreakerTestSupport.start("singleClusterFitsOnOneLine");
        final clusters = [GreedyLineBreakerTestSupport.cluster(0, 1, "\u4E2D", 16)];
        final solution = new GreedyLineBreaker().breakLines(clusters, clusters, 64);
        TracedAssertions.assertEquals(1, solution.lines.length);
        final line = solution.lines[0];
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 0), line.clusterRange);
        TracedAssertions.assertEqualsRendered("TextRange(start=0, end=1)", GreedyLineBreakerTestSupport.textRange(line.sourceRange));
        TracedAssertions.assertEqualsFloat(16, line.naturalWidth);
        TracedAssertions.assertEqualsFloat(16, line.adjustedWidth);
    }

    @:test public static function fillsLineUntilOverflowThenStartsNewLine():Void {
        GreedyLineBreakerTestSupport.start("fillsLineUntilOverflowThenStartsNewLine");
        final clusters = GreedyLineBreakerTestSupport.clustersX(5);
        final solution = new GreedyLineBreaker().breakLines(clusters, clusters, 48);
        TracedAssertions.assertEquals(2, solution.lines.length);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 2), solution.lines[0].clusterRange);
        TracedAssertions.assertEqualsFloat(48, solution.lines[0].adjustedWidth);
        TracedAssertions.assertEqualsIntRange(new IntRange(3, 4), solution.lines[1].clusterRange);
        TracedAssertions.assertEqualsFloat(32, solution.lines[1].adjustedWidth);
    }

    @:test public static function naturalAndAdjustedWidthsTrackIndependently():Void {
        GreedyLineBreakerTestSupport.start("naturalAndAdjustedWidthsTrackIndependently");
        final natural = [
            GreedyLineBreakerTestSupport.cluster(0, 1, "\uFF0C", 16),
            GreedyLineBreakerTestSupport.cluster(1, 2, "\u3002", 16)
        ];
        final adjusted = [
            GreedyLineBreakerTestSupport.cluster(0, 1, "\uFF0C", 16),
            GreedyLineBreakerTestSupport.cluster(1, 2, "\u3002", 12)
        ];
        final solution = new GreedyLineBreaker().breakLines(natural, adjusted, 64);
        final line = solution.lines[0];
        TracedAssertions.assertEqualsFloat(32, line.naturalWidth);
        TracedAssertions.assertEqualsFloat(28, line.adjustedWidth);
    }

    @:test public static function clusterWiderThanMaxWidthGetsOwnLineRatherThanInfiniteLoop():Void {
        GreedyLineBreakerTestSupport.start("clusterWiderThanMaxWidthGetsOwnLineRatherThanInfiniteLoop");
        final clusters = [
            GreedyLineBreakerTestSupport.cluster(0, 1, "\u4E2D", 16),
            GreedyLineBreakerTestSupport.cluster(1, 8, "English", 112)
        ];
        final solution = new GreedyLineBreaker().breakLines(clusters, clusters, 80);
        TracedAssertions.assertEquals(2, solution.lines.length);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 0), solution.lines[0].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(1, 1), solution.lines[1].clusterRange);
        TracedAssertions.assertEqualsFloat(112, solution.lines[1].adjustedWidth);
    }

    @:test public static function kinsokuCarryPreviousMovesPrevClusterToNextLine():Void {
        GreedyLineBreakerTestSupport.start("kinsokuCarryPreviousMovesPrevClusterToNextLine");
        final clusters = [
            GreedyLineBreakerTestSupport.cluster(0, 1, "a", 16),
            GreedyLineBreakerTestSupport.cluster(1, 2, "b", 16),
            GreedyLineBreakerTestSupport.cluster(2, 3, "c", 16),
            GreedyLineBreakerTestSupport.cluster(3, 4, "\u3002", 16)
        ];
        final solution = new GreedyLineBreaker().breakLines(clusters, clusters, 48);
        TracedAssertions.assertEquals(2, solution.lines.length);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 1), solution.lines[0].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(2, 3), solution.lines[1].clusterRange);
        TracedAssertions.assertEqualsFloat(32, solution.lines[0].adjustedWidth);
        TracedAssertions.assertEqualsFloat(32, solution.lines[1].adjustedWidth);
        final repair = solution.lines[1].repair;
        TracedAssertions.assertEqualsRendered("true", GreedyLineBreakerTestSupport.repairIs(repair, "CarryPrevious"));
        TracedAssertions.assertEqualsFloat(10, solution.totalBadness);
    }

    @:test public static function kinsokuPushesForbiddenPunctuationIntoPreviousLineWhenGlueCapacityCoversOverflow():Void {
        GreedyLineBreakerTestSupport.start("kinsokuPushesForbiddenPunctuationIntoPreviousLineWhenGlueCapacityCoversOverflow");
        final clusters = [
            GreedyLineBreakerTestSupport.cluster(0, 1, "a", 16),
            GreedyLineBreakerTestSupport.cluster(1, 2, "b", 16),
            GreedyLineBreakerTestSupport.cluster(2, 3, "c", 16),
            GreedyLineBreakerTestSupport.cluster(3, 4, "\u3002", 16)
        ];
        final solution = new GreedyLineBreaker().breakLines(clusters, clusters, 60, [new ShrinkOpportunity(3, 6, 4, ShrinkChannel.TrailingGlue)]);
        TracedAssertions.assertEquals(1, solution.lines.length);
        final line = solution.lines[0];
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 3), line.clusterRange);
        TracedAssertions.assertEqualsFloat(64, line.naturalWidth);
        TracedAssertions.assertEqualsFloat(60, line.adjustedWidth);
        final repair = line.repair;
        TracedAssertions.assertEqualsRendered("true", GreedyLineBreakerTestSupport.repairIs(repair, "PushIn"));
        TracedAssertions.assertEquals(3, GreedyLineBreakerTestSupport.pushInOffenderClusterIndex(repair));
        TracedAssertions.assertEqualsFloat(4, GreedyLineBreakerTestSupport.pushInTotalShrink(repair));
        TracedAssertions.assertEqualsFloat(4, GreedyLineBreakerTestSupport.pushInTotalAvailableCapacity(repair));
        TracedAssertions.assertEqualsIntArray([3],
            GreedyLineBreakerTestSupport.allocationClusterIndices(GreedyLineBreakerTestSupport.pushInAllocations(repair)));
        TracedAssertions.assertEqualsFloat(4, GreedyLineBreakerTestSupport.pushInAllocations(repair)[0].shrink);
        TracedAssertions.assertEqualsFloat(4, GreedyLineBreakerTestSupport.pushInAllocations(repair)[0].availableCapacity);
        TracedAssertions.assertEquals(1, line.repairCandidates.length);
        TracedAssertions.assertEqualsString("PushIn", line.repairCandidates[0].kind);
        TracedAssertions.assertEqualsRendered("true", line.repairCandidates[0].accepted ? "true" : "false");
        TracedAssertions.assertEqualsFloat(2, solution.totalBadness);
    }

    @:test public static function kinsokuCarriesPreviousWhenPushInCapacityCannotCoverOverflow():Void {
        GreedyLineBreakerTestSupport.start("kinsokuCarriesPreviousWhenPushInCapacityCannotCoverOverflow");
        final clusters = [
            GreedyLineBreakerTestSupport.cluster(0, 1, "a", 16),
            GreedyLineBreakerTestSupport.cluster(1, 2, "b", 16),
            GreedyLineBreakerTestSupport.cluster(2, 3, "c", 16),
            GreedyLineBreakerTestSupport.cluster(3, 4, "\u3002", 16)
        ];
        final solution = new GreedyLineBreaker().breakLines(clusters, clusters, 59, [new ShrinkOpportunity(3, 6, 4, ShrinkChannel.TrailingGlue)]);
        TracedAssertions.assertEquals(2, solution.lines.length);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 1), solution.lines[0].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(2, 3), solution.lines[1].clusterRange);
        TracedAssertions.assertEqualsRendered("true", GreedyLineBreakerTestSupport.repairIs(solution.lines[1].repair, "CarryPrevious"));
        TracedAssertions.assertEquals(2, solution.lines[1].repairCandidates.length);
        TracedAssertions.assertEqualsString("PushIn", solution.lines[1].repairCandidates[0].kind);
        TracedAssertions.assertEqualsRendered("false", solution.lines[1].repairCandidates[0].accepted ? "true" : "false");
        TracedAssertions.assertEqualsString("insufficient-capacity", solution.lines[1].repairCandidates[0].rejectionReason);
        TracedAssertions.assertEqualsString("CarryPrevious", solution.lines[1].repairCandidates[1].kind);
        TracedAssertions.assertEqualsRendered("true", solution.lines[1].repairCandidates[1].accepted ? "true" : "false");
    }

    @:test public static function kinsokuRejectsCarryPreviousWhenCarriedLineWouldOverflow():Void {
        GreedyLineBreakerTestSupport.start("kinsokuRejectsCarryPreviousWhenCarriedLineWouldOverflow");
        final clusters = [
            GreedyLineBreakerTestSupport.cluster(0, 1, "a", 16),
            GreedyLineBreakerTestSupport.cluster(1, 2, "b", 16),
            GreedyLineBreakerTestSupport.cluster(2, 3, "c", 16),
            GreedyLineBreakerTestSupport.cluster(3, 4, "d", 16),
            GreedyLineBreakerTestSupport.cluster(4, 5, "\u3002", 16),
            GreedyLineBreakerTestSupport.cluster(5, 6, "e", 16),
            GreedyLineBreakerTestSupport.cluster(6, 7, "f", 16),
            GreedyLineBreakerTestSupport.cluster(7, 8, "g", 16)
        ];
        final solution = new GreedyLineBreaker().breakLines(clusters, clusters, 64);
        TracedAssertions.assertEquals(2, solution.lines.length);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 3), solution.lines[0].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(4, 7), solution.lines[1].clusterRange);
        TracedAssertions.assertEqualsFloat(64, solution.lines[1].adjustedWidth);
        TracedAssertions.assertEqualsRendered("true", GreedyLineBreakerTestSupport.repairIs(solution.lines[1].repair, "LeaveRagged"));
        TracedAssertions.assertEquals(3, solution.lines[1].repairCandidates.length);
        TracedAssertions.assertEqualsString("PushIn", solution.lines[1].repairCandidates[0].kind);
        TracedAssertions.assertEqualsRendered("false", solution.lines[1].repairCandidates[0].accepted ? "true" : "false");
        TracedAssertions.assertEqualsString("insufficient-capacity", solution.lines[1].repairCandidates[0].rejectionReason);
        TracedAssertions.assertEqualsString("CarryPrevious", solution.lines[1].repairCandidates[1].kind);
        TracedAssertions.assertEqualsRendered("false", solution.lines[1].repairCandidates[1].accepted ? "true" : "false");
        TracedAssertions.assertEqualsString("carry-overflows", solution.lines[1].repairCandidates[1].rejectionReason);
        TracedAssertions.assertEqualsNullableInt(3, solution.lines[1].repairCandidates[1].carriedClusterIndex);
        TracedAssertions.assertEqualsString("LeaveRagged", solution.lines[1].repairCandidates[2].kind);
        TracedAssertions.assertEqualsRendered("true", solution.lines[1].repairCandidates[2].accepted ? "true" : "false");
        TracedAssertions.assertEqualsFloat(20, solution.totalBadness);
    }

    @:test public static function kinsokuLeaveRaggedWhenPrevLineIsSingleCluster():Void {
        GreedyLineBreakerTestSupport.start("kinsokuLeaveRaggedWhenPrevLineIsSingleCluster");
        final clusters = [
            GreedyLineBreakerTestSupport.cluster(0, 7, "English", 112),
            GreedyLineBreakerTestSupport.cluster(7, 8, "\u3002", 16)
        ];
        final solution = new GreedyLineBreaker().breakLines(clusters, clusters, 64);
        TracedAssertions.assertEquals(2, solution.lines.length);
        final repair = solution.lines[1].repair;
        TracedAssertions.assertEqualsRendered("true", GreedyLineBreakerTestSupport.repairIs(repair, "LeaveRagged"));
        TracedAssertions.assertEqualsFloat(20, solution.totalBadness);
    }

    @:test public static function customKinsokuRuleOverridesDefault():Void {
        GreedyLineBreakerTestSupport.start("customKinsokuRuleOverridesDefault");
        final breaker = new GreedyLineBreaker(new NeverForbiddingKinsokuRule());
        final clusters = [
            GreedyLineBreakerTestSupport.cluster(0, 1, "a", 16),
            GreedyLineBreakerTestSupport.cluster(1, 2, "b", 16),
            GreedyLineBreakerTestSupport.cluster(2, 3, "c", 16),
            GreedyLineBreakerTestSupport.cluster(3, 4, "\u3002", 16)
        ];
        final solution = breaker.breakLines(clusters, clusters, 48);
        TracedAssertions.assertEquals(2, solution.lines.length);
        TracedAssertions.assertEqualsRendered("-", GreedyLineBreakerTestSupport.repairKind(solution.lines[1].repair));
        TracedAssertions.assertEqualsFloat(0, solution.totalBadness);
    }

    @:test public static function misalignedClusterListsThrow():Void {
        GreedyLineBreakerTestSupport.start("misalignedClusterListsThrow");
        final a = [
            GreedyLineBreakerTestSupport.cluster(0, 1, "\u4E2D", 16),
            GreedyLineBreakerTestSupport.cluster(1, 2, "\u6587", 16)
        ];
        final b = [GreedyLineBreakerTestSupport.cluster(0, 1, "\u4E2D", 16)];
        TracedAssertions.assertFailsWith(null, () -> {
            new GreedyLineBreaker().breakLines(a, b, 100);
        });
    }

    @:test public static function hangsPauseStopPastMeasureWhenEnabledAndPushInCannotFit():Void {
        GreedyLineBreakerTestSupport.start("hangsPauseStopPastMeasureWhenEnabledAndPushInCannotFit");
        final clusters = [
            GreedyLineBreakerTestSupport.cluster(0, 1, "a", 16),
            GreedyLineBreakerTestSupport.cluster(1, 2, "b", 16),
            GreedyLineBreakerTestSupport.cluster(2, 3, "c", 16),
            GreedyLineBreakerTestSupport.cluster(3, 4, "d", 16),
            GreedyLineBreakerTestSupport.cluster(4, 5, "\u3002", 16)
        ];
        final solution = new GreedyLineBreaker().breakLines(clusters, clusters, 64, null, null, null, GreedyLineBreakerTestSupport.setInts([4]));
        TracedAssertions.assertEquals(1, solution.lines.length);
        final line = solution.lines[0];
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 4), line.clusterRange);
        TracedAssertions.assertEqualsNullableInt(4, line.hangingClusterIndex);
        TracedAssertions.assertEqualsFloat(64, line.adjustedWidth);
        final repair = line.repair;
        TracedAssertions.assertEqualsRendered("true", GreedyLineBreakerTestSupport.repairIs(repair, "Hang"));
        TracedAssertions.assertEquals(4, GreedyLineBreakerTestSupport.hangOffenderClusterIndex(repair));
        var candidate:RepairCandidate = null;
        var ci = 0;
        while (ci < line.repairCandidates.length) {
            if (line.repairCandidates[ci].kind == "Hang") {
                candidate = line.repairCandidates[ci];
                break;
            }
            ci++;
        }
        TracedAssertions.assertEqualsRendered("true", candidate != null && candidate.accepted ? "true" : "false");
    }

    @:test public static function doesNotHangWhenDisabled():Void {
        GreedyLineBreakerTestSupport.start("doesNotHangWhenDisabled");
        final clusters = [
            GreedyLineBreakerTestSupport.cluster(0, 1, "a", 16),
            GreedyLineBreakerTestSupport.cluster(1, 2, "b", 16),
            GreedyLineBreakerTestSupport.cluster(2, 3, "c", 16),
            GreedyLineBreakerTestSupport.cluster(3, 4, "d", 16),
            GreedyLineBreakerTestSupport.cluster(4, 5, "\u3002", 16)
        ];
        final solution = new GreedyLineBreaker().breakLines(clusters, clusters, 64);
        TracedAssertions.assertEquals(2, solution.lines.length);
        TracedAssertions.assertEqualsNullableInt(null, solution.lines[0].hangingClusterIndex);
        TracedAssertions.assertEqualsRendered("true", GreedyLineBreakerTestSupport.repairIs(solution.lines[1].repair, "CarryPrevious"));
    }

    @:test public static function pushInStillPreferredOverHangWhenGlueCovers():Void {
        GreedyLineBreakerTestSupport.start("pushInStillPreferredOverHangWhenGlueCovers");
        final clusters = [
            GreedyLineBreakerTestSupport.cluster(0, 1, "a", 16),
            GreedyLineBreakerTestSupport.cluster(1, 2, "b", 16),
            GreedyLineBreakerTestSupport.cluster(2, 3, "c", 16),
            GreedyLineBreakerTestSupport.cluster(3, 4, "\u3002", 16)
        ];
        final solution = new GreedyLineBreaker().breakLines(clusters, clusters, 60, [new ShrinkOpportunity(3, 6, 8, ShrinkChannel.TrailingGlue)], null, null,
            GreedyLineBreakerTestSupport.setInts([3]));
        TracedAssertions.assertEquals(1, solution.lines.length);
        TracedAssertions.assertEqualsNullableInt(null, solution.lines[0].hangingClusterIndex);
        TracedAssertions.assertEqualsRendered("true", GreedyLineBreakerTestSupport.repairIs(solution.lines[0].repair, "PushIn"));
    }

    @:test public static function retreatsBreakSoLineDoesNotEndOnOpeningMark():Void {
        GreedyLineBreakerTestSupport.start("retreatsBreakSoLineDoesNotEndOnOpeningMark");
        final clusters = [
            GreedyLineBreakerTestSupport.cluster(0, 1, "\u4E2D", 16),
            GreedyLineBreakerTestSupport.cluster(1, 2, "\u4E2D", 16),
            GreedyLineBreakerTestSupport.cluster(2, 3, "\uFF08", 16),
            GreedyLineBreakerTestSupport.cluster(3, 4, "\u4E2D", 16),
            GreedyLineBreakerTestSupport.cluster(4, 5, "\u4E2D", 16)
        ];
        final solution = new GreedyLineBreaker().breakLines(clusters, clusters, 48, null, null, null, null, null, null,
            GreedyLineBreakerTestSupport.setInts([2]));
        TracedAssertions.assertEquals(2, solution.lines.length);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 1), solution.lines[0].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(2, 4), solution.lines[1].clusterRange);
        final repair = solution.lines[0].repair;
        TracedAssertions.assertEqualsRendered("true", GreedyLineBreakerTestSupport.repairIs(repair, "CarryNext"));
        TracedAssertions.assertEquals(2, GreedyLineBreakerTestSupport.carryNextMovedClusterIndex(repair));
    }

    @:test public static function keepsOpenerAtLineEndWhenItIsTheLineSoleCluster():Void {
        GreedyLineBreakerTestSupport.start("keepsOpenerAtLineEndWhenItIsTheLineSoleCluster");
        final clusters = [
            GreedyLineBreakerTestSupport.cluster(0, 1, "\uFF08", 16),
            GreedyLineBreakerTestSupport.cluster(1, 2, "\u4E2D", 16),
            GreedyLineBreakerTestSupport.cluster(2, 3, "\u4E2D", 16)
        ];
        final solution = new GreedyLineBreaker().breakLines(clusters, clusters, 16, null, null, null, null, null, null,
            GreedyLineBreakerTestSupport.setInts([0]));
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 0), solution.lines[0].clusterRange);
        TracedAssertions.assertEqualsRendered("-", GreedyLineBreakerTestSupport.repairKind(solution.lines[0].repair));
    }

    @:test public static function mandatoryBreakClosesLineAndPreservesTrailingEmptyLine():Void {
        GreedyLineBreakerTestSupport.start("mandatoryBreakClosesLineAndPreservesTrailingEmptyLine");
        final clusters = [
            GreedyLineBreakerTestSupport.cluster(0, 1, "\u4E2D", 16),
            GreedyLineBreakerTestSupport.cluster(1, 2, "\n", 0, "")
        ];
        final solution = new GreedyLineBreaker().breakLines(clusters, clusters, 160, null, null, null, null, null, null, null, null, null, null, null, null,
            null, null, GreedyLineBreakerTestSupport.setInts([1]));
        TracedAssertions.assertEquals(2, solution.lines.length);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 1), solution.lines[0].clusterRange);
        TracedAssertions.assertEqualsRendered("MandatoryBreak", Std.string(solution.lines[0].endReason));
        TracedAssertions.assertEqualsRendered("TextRange(start=2, end=2)", GreedyLineBreakerTestSupport.textRange(solution.lines[1].sourceRange));
        TracedAssertions.assertEqualsRendered("ParagraphEnd", Std.string(solution.lines[1].endReason));
    }

    @:test public static function mandatoryBreakBlocksKinsokuRepairAcrossBoundary():Void {
        GreedyLineBreakerTestSupport.start("mandatoryBreakBlocksKinsokuRepairAcrossBoundary");
        final clusters = [
            GreedyLineBreakerTestSupport.cluster(0, 1, "\u4E2D", 16),
            GreedyLineBreakerTestSupport.cluster(1, 2, "\n", 0, ""),
            GreedyLineBreakerTestSupport.cluster(2, 3, "\u3002", 16)
        ];
        final solution = new GreedyLineBreaker().breakLines(clusters, clusters, 160, null, null, null, null, null, null, null, null, null, null, null, null,
            null, null, GreedyLineBreakerTestSupport.setInts([1]));
        TracedAssertions.assertEquals(2, solution.lines.length);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 1), solution.lines[0].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(2, 2), solution.lines[1].clusterRange);
        TracedAssertions.assertEqualsRendered("-", GreedyLineBreakerTestSupport.repairKind(solution.lines[1].repair));
    }
}

class GreedyLineBreakerTestSupport {
    public static function cluster(start:Int, end:Int, text:String, advance:Float, ?displayText:Null<String>):Cluster
        return new Cluster(new TextRange(start, end), text, "test", advance, displayText);

    public static function clustersX(count:Int):Array<Cluster> {
        final out:Array<Cluster> = [];
        var i = 0;
        while (i < count) {
            out.push(cluster(i, i + 1, "x", 16));
            i++;
        }
        return out;
    }

    public static function setInts(values:Array<Int>):SortedSet<Int> {
        final b = SortedSet.builder();
        var i = 0;
        while (i < values.length) {
            b.put(values[i]);
            i++;
        }
        return b.build();
    }

    public static function repairIs(o:Null<RepairOption>, name:String):String
        return repairKind(o) == name ? "true" : "false";

    public static function repairKind(o:Null<RepairOption>):String {
        if (o == null)
            return "-";
        final v:RepairOption = o;
        return switch (v) {
            case PushIn(_, _, _, _, _, _): "PushIn";
            case Hang(_, _, _): "Hang";
            case CarryPrevious(_, _, _, _): "CarryPrevious";
            case CarryNext(_, _, _): "CarryNext";
            case LeaveRagged(_, _, _): "LeaveRagged";
        };
    }

    public static function pushInOffenderClusterIndex(o:Null<RepairOption>):Int {
        if (o == null)
            return -1;
        final v:RepairOption = o;
        return switch (v) {
            case PushIn(_, _, offenderClusterIndex, _, _, _): offenderClusterIndex;
            case Hang(_, _, _): -1;
            case CarryPrevious(_, _, _, _): -1;
            case CarryNext(_, _, _): -1;
            case LeaveRagged(_, _, _): -1;
        };
    }

    public static function pushInTotalShrink(o:Null<RepairOption>):Float {
        if (o == null)
            return -1;
        final v:RepairOption = o;
        return switch (v) {
            case PushIn(_, _, _, _, totalShrink, _): totalShrink;
            case Hang(_, _, _): -1;
            case CarryPrevious(_, _, _, _): -1;
            case CarryNext(_, _, _): -1;
            case LeaveRagged(_, _, _): -1;
        };
    }

    public static function pushInTotalAvailableCapacity(o:Null<RepairOption>):Float {
        if (o == null)
            return -1;
        final v:RepairOption = o;
        return switch (v) {
            case PushIn(_, _, _, _, _, totalAvailableCapacity): totalAvailableCapacity;
            case Hang(_, _, _): -1;
            case CarryPrevious(_, _, _, _): -1;
            case CarryNext(_, _, _): -1;
            case LeaveRagged(_, _, _): -1;
        };
    }

    public static function pushInAllocations(o:Null<RepairOption>):Array<PushInAllocation> {
        if (o == null)
            return [];
        final v:RepairOption = o;
        return switch (v) {
            case PushIn(_, _, _, allocations, _, _): allocations;
            case Hang(_, _, _): [];
            case CarryPrevious(_, _, _, _): [];
            case CarryNext(_, _, _): [];
            case LeaveRagged(_, _, _): [];
        };
    }

    public static function hangOffenderClusterIndex(o:Null<RepairOption>):Int {
        if (o == null)
            return -1;
        final v:RepairOption = o;
        return switch (v) {
            case Hang(_, _, offenderClusterIndex): offenderClusterIndex;
            case PushIn(_, _, _, _, _, _): -1;
            case CarryPrevious(_, _, _, _): -1;
            case CarryNext(_, _, _): -1;
            case LeaveRagged(_, _, _): -1;
        };
    }

    public static function carryNextMovedClusterIndex(o:Null<RepairOption>):Int {
        if (o == null)
            return -1;
        final v:RepairOption = o;
        return switch (v) {
            case CarryNext(_, _, movedClusterIndex): movedClusterIndex;
            case PushIn(_, _, _, _, _, _): -1;
            case Hang(_, _, _): -1;
            case CarryPrevious(_, _, _, _): -1;
            case LeaveRagged(_, _, _): -1;
        };
    }

    public static function allocationClusterIndices(allocations:Array<PushInAllocation>):Array<Int> {
        final out:Array<Int> = [];
        var i = 0;
        while (i < allocations.length) {
            out.push(allocations[i].clusterIndex);
            i++;
        }
        return out;
    }

    public static function textRange(r:TextRange):String
        return "TextRange(start=" + r.start + ", end=" + r.end + ")";

    public static function start(n:String):Void
        new TestTraceRecorder("GreedyLineBreakerTest").section(n);
}

class NeverForbiddingKinsokuRule implements KinsokuRule {
    public function new() {}

    public function forbiddenAtLineStart(cluster:Cluster):Bool
        return false;

    public function forbiddenAtLineEnd(cluster:Cluster):Bool
        return false;
}
