package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.*;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;
import org.tiqian.layout.ProgressiveBreakDecisions.UnbreakableRanges;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.LineOptimization.LineSolution;
import org.tiqian.layout.LineOptimization.RepairOption;
import org.tiqian.layout.LineOptimization.RepairOptions;
import std.SortedMap;
import org.tiqian.test.trace.TestTraceRecorder;

class ParagraphDpLineBreakerCoverageTest {
    @:test public static function emptyClustersReturnAnEmptySolution():Void {
        ParagraphDpLineBreakerCoverageTestSupport.rec("emptyClustersReturnAnEmptySolution");
        var s = ParagraphDpLineBreakerCoverageTestSupport.solve([], 100);
        TracedAssertions.assertTrue(s.lines.length == 0, ParagraphDpLineBreakerTestSupport.linesString(s));
    }

    @:test public static function mismatchedNaturalAndAdjustedSizesAreRejected():Void {
        ParagraphDpLineBreakerCoverageTestSupport.rec("mismatchedNaturalAndAdjustedSizesAreRejected");
        var e = TracedAssertions.assertFailsWith(function() new ParagraphDpLineBreaker().breakLines(ParagraphDpLineBreakerCoverageTestSupport.han(2), ParagraphDpLineBreakerCoverageTestSupport.han(1), 100));
        TracedAssertions.assertTrue(e.message.indexOf("cluster-for-cluster") >= 0, e.message);
    }

    @:test public static function negativeCandidateWindowIsRejected():Void {
        ParagraphDpLineBreakerCoverageTestSupport.rec("negativeCandidateWindowIsRejected");
        var e = TracedAssertions.assertFailsWith(function() new ParagraphDpLineBreaker(-1).breakLines(ParagraphDpLineBreakerCoverageTestSupport.han(2), ParagraphDpLineBreakerCoverageTestSupport.han(2), 100));
        TracedAssertions.assertTrue(e.message.indexOf("non-negative") >= 0, e.message);
    }

    @:test public static function shrinkPrefixSkipsNonPositiveAndOutOfRangeOpportunities():Void {
        ParagraphDpLineBreakerCoverageTestSupport.rec("shrinkPrefixSkipsNonPositiveAndOutOfRangeOpportunities");
        var c = ParagraphDpLineBreakerCoverageTestSupport.han(4);
        var s = ParagraphDpLineBreakerCoverageTestSupport.solve(c, 100, [
            new ShrinkOpportunity(1, 2, 0, ShrinkChannel.RawAdvance),
            new ShrinkOpportunity(4, 2, 8, ShrinkChannel.RawAdvance),
            new ShrinkOpportunity(1, 2, 8, ShrinkChannel.RawAdvance)
        ]);
        TracedAssertions.assertEqualsInt(1, s.lines.length, ParagraphDpLineBreakerTestSupport.linesString(s));
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 3), s.lines[0].clusterRange);
    }

    @:test public static function lineEndOnlyCapacityFeedsTheCompressedEdgeAtTheLineEnd():Void {
        ParagraphDpLineBreakerCoverageTestSupport.rec("lineEndOnlyCapacityFeedsTheCompressedEdgeAtTheLineEnd");
        var c = ParagraphDpLineBreakerCoverageTestSupport.han(4);
        var s = ParagraphDpLineBreakerCoverageTestSupport.solve(c, 44, [new ShrinkOpportunity(2, 1, 4, ShrinkChannel.TrailingGlue, true)], null, true, null, null, null, [1]);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 2), s.lines[0].clusterRange, ParagraphDpLineBreakerTestSupport.linesString(s));
        TracedAssertions.assertTrue(ParagraphDpLineBreakerCoverageTestSupport.pushInReasonStartsWith(s.lines[0].repair, "LineAdjustmentPushIn"), ParagraphDpLineBreakerTestSupport.repairsString(s));
    }

    @:test public static function compressedEndsMayReachTheSegmentEnd():Void {
        ParagraphDpLineBreakerCoverageTestSupport.rec("compressedEndsMayReachTheSegmentEnd");
        var s = ParagraphDpLineBreakerCoverageTestSupport.solve(ParagraphDpLineBreakerCoverageTestSupport.han(3), 44, [new ShrinkOpportunity(1, 2, 12, ShrinkChannel.RawAdvance)], null, true, null, null, null, [1]);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 2), s.lines[0].clusterRange, ParagraphDpLineBreakerTestSupport.linesString(s));
        TracedAssertions.assertTrue(ParagraphDpLineBreakerCoverageTestSupport.pushInReasonStartsWith(s.lines[0].repair, "LineAdjustmentPushIn"), ParagraphDpLineBreakerTestSupport.repairsString(s));
        TracedAssertions.assertEqualsRendered("ParagraphEnd", Std.string(s.lines[s.lines.length - 1].endReason));
    }

    @:test public static function compressedFinalMandatoryLineUsesTheCompressedCommitBranch():Void {
        ParagraphDpLineBreakerCoverageTestSupport.rec("compressedFinalMandatoryLineUsesTheCompressedCommitBranch");
        var s = ParagraphDpLineBreakerCoverageTestSupport.solve(ParagraphDpLineBreakerCoverageTestSupport.han(4), 44, [new ShrinkOpportunity(2, 1, 4, ShrinkChannel.TrailingGlue, true)], [2], true);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 2), s.lines[0].clusterRange, ParagraphDpLineBreakerTestSupport.linesString(s));
        TracedAssertions.assertEqualsRendered("MandatoryBreak", Std.string(s.lines[0].endReason));
        TracedAssertions.assertTrue(ParagraphDpLineBreakerCoverageTestSupport.pushInReasonStartsWith(s.lines[0].repair, "LineAdjustmentPushIn"), ParagraphDpLineBreakerTestSupport.repairsString(s));
    }

    @:test public static function tierPromotionRoutesTheRepairReasonThroughThePromotionCode():Void {
        ParagraphDpLineBreakerCoverageTestSupport.rec("tierPromotionRoutesTheRepairReasonThroughThePromotionCode");
        var c = ParagraphDpLineBreakerCoverageTestSupport.latin();
        var span = new TextRange(0, 5);
        var s = ParagraphDpLineBreakerCoverageTestSupport.solve(c, 80, [new ShrinkOpportunity(2, 2, 5, ShrinkChannel.RawAdvance)], null, true, null,
            ParagraphDpLineBreakerCoverageTestSupport.opp([2, 3], [span, span], [ProgressiveBreakTier.Emergency, ProgressiveBreakTier.Whitespace]));
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 2), s.lines[0].clusterRange, ParagraphDpLineBreakerTestSupport.linesString(s));
        TracedAssertions.assertTrue(ParagraphDpLineBreakerCoverageTestSupport.pushInReasonStartsWith(s.lines[0].repair, "ProgressiveTechnicalTierPromotion"),
            ParagraphDpLineBreakerTestSupport.repairsString(s));
    }

    @:test public static function promotionCheckReturnsFalseWhenTheCandidateEndHasNoOpportunity():Void {
        ParagraphDpLineBreakerCoverageTestSupport.rec("promotionCheckReturnsFalseWhenTheCandidateEndHasNoOpportunity");
        var c = ParagraphDpLineBreakerCoverageTestSupport.latin();
        var s = ParagraphDpLineBreakerCoverageTestSupport.solve(c, 80, [new ShrinkOpportunity(2, 2, 5, ShrinkChannel.RawAdvance)], null, true, null,
            ParagraphDpLineBreakerCoverageTestSupport.opp([2], [new TextRange(0, 5)], [ProgressiveBreakTier.Emergency]));
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 1), s.lines[0].clusterRange, ParagraphDpLineBreakerTestSupport.linesString(s));
        TracedAssertions.assertTrue(s.lines[0].repair == null, ParagraphDpLineBreakerTestSupport.repairsString(s));
    }

    @:test public static function mandatorySegmentFiltersTheControlBoundaryFromCandidates():Void {
        ParagraphDpLineBreakerCoverageTestSupport.rec("mandatorySegmentFiltersTheControlBoundaryFromCandidates");
        var s = ParagraphDpLineBreakerCoverageTestSupport.solve(ParagraphDpLineBreakerCoverageTestSupport.han(6), 32, null, [2]);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 2), s.lines[0].clusterRange, ParagraphDpLineBreakerTestSupport.linesString(s));
        TracedAssertions.assertEqualsRendered("MandatoryBreak", Std.string(s.lines[0].endReason));
        TracedAssertions.assertEqualsInt(5, s.lines[s.lines.length - 1].clusterRange.end, ParagraphDpLineBreakerTestSupport.linesString(s));
    }

    @:test public static function narrowWindowsDropEndsAtOrBelowTheLineStart():Void {
        ParagraphDpLineBreakerCoverageTestSupport.rec("narrowWindowsDropEndsAtOrBelowTheLineStart");
        var s = ParagraphDpLineBreakerCoverageTestSupport.solve(ParagraphDpLineBreakerCoverageTestSupport.han(4), 20);
        TracedAssertions.assertEqualsInt(4, s.lines.length, ParagraphDpLineBreakerTestSupport.linesString(s));
        var all = true;
        for (l in s.lines)
            if (l.clusterRange.start != l.clusterRange.end)
                all = false;
        TracedAssertions.assertTrue(all, ParagraphDpLineBreakerTestSupport.rangesString(s));
    }

    @:test public static function interfaceDefaultStrategyNameIsCustom():Void {
        ParagraphDpLineBreakerCoverageTestSupport.rec("interfaceDefaultStrategyNameIsCustom");
        var b:LineBreaker = new CustomBreaker();
        TracedAssertions.assertEqualsString("custom", b.strategyName);
    }

    public static function flushTestTrace():Void {
        TestTraceRecorder.flushClass("ParagraphDpLineBreakerCoverageTest");
    }

}

class CustomBreaker implements LineBreaker {
    public var strategyName(get, never):String;

    function get_strategyName():String
        return "custom";

    public function new() {}

    public function breakLines(n:Array<Cluster>, a:Array<Cluster>, w:Float, ?s:Array<ShrinkOpportunity>, ?u:UnbreakableRanges, ?i:Float,
            ?h:std.SortedSet<Int>, ?e:Array<IntRange>, ?fs:Null<std.SortedSet<Int>>, ?fe:std.SortedSet<Int>, ?hy:std.SortedSet<Int>, ?cj:std.SortedSet<Int>,
            ?mc:Float, ?sw:std.SortedSet<Int>, ?sc:Float, ?p:Bool, ?bias:Float, ?hb:std.SortedSet<Int>, ?nc:std.SortedSet<Int>,
            ?pr:SortedMap<Int, ProgressiveBreakOpportunity>):LineSolution
        return new LineSolution([]);
}
