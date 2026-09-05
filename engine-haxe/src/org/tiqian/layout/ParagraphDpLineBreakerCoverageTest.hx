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

class ParagraphDpLineBreakerCoverageTest {
    static function rec(n:String):Void
        new TestTraceRecorder("ParagraphDpLineBreakerCoverageTest").section(n);

    static function solve(c:Array<Cluster>, width:Float, ?shrink:Array<ShrinkOpportunity>, ?hard:Array<Int>, ?push:Bool, ?ranges:UnbreakableRanges,
            ?progressive:SortedMap<Int, ProgressiveBreakOpportunity>, ?window:Int, ?cjk:Array<Int>):LineSolution
        return ParagraphDpLineBreakerTestSupport.solve(c, width, shrink, hard, push, ranges, progressive, window, cjk);

    static function han(n:Int, ?a:Float):Array<Cluster>
        return ParagraphDpLineBreakerTestSupport.han(n, a);

    static function latin():Array<Cluster>
        return ParagraphDpLineBreakerTestSupport.latin();

    static function opp(v:Array<Int>, spans:Array<TextRange>, tiers:Array<ProgressiveBreakTier>):SortedMap<Int, ProgressiveBreakOpportunity>
        return ParagraphDpLineBreakerTestSupport.opportunities(v, spans, tiers);

    static function pushInReasonStartsWith(repair:Null<RepairOption>, prefix:String):Bool {
        final r = ParagraphDpLineBreakerTestSupport.pushInReason(repair);
        return r != null && StringTools.startsWith(r, prefix);
    }

    public static function emptyClustersReturnAnEmptySolution():Void {
        rec("emptyClustersReturnAnEmptySolution");
        var s = solve([], 100);
        TracedAssertions.assertTrue(s.lines.length == 0, ParagraphDpLineBreakerTestSupport.linesString(s));
    }

    public static function mismatchedNaturalAndAdjustedSizesAreRejected():Void {
        rec("mismatchedNaturalAndAdjustedSizesAreRejected");
        var e = TracedAssertions.assertFailsWith(function() new ParagraphDpLineBreaker().breakLines(han(2), han(1), 100));
        TracedAssertions.assertTrue(e.message.indexOf("cluster-for-cluster") >= 0, e.message);
    }

    public static function negativeCandidateWindowIsRejected():Void {
        rec("negativeCandidateWindowIsRejected");
        var e = TracedAssertions.assertFailsWith(function() new ParagraphDpLineBreaker(-1).breakLines(han(2), han(2), 100));
        TracedAssertions.assertTrue(e.message.indexOf("non-negative") >= 0, e.message);
    }

    public static function shrinkPrefixSkipsNonPositiveAndOutOfRangeOpportunities():Void {
        rec("shrinkPrefixSkipsNonPositiveAndOutOfRangeOpportunities");
        var c = han(4);
        var s = solve(c, 100, [
            new ShrinkOpportunity(1, 2, 0, ShrinkChannel.RawAdvance),
            new ShrinkOpportunity(4, 2, 8, ShrinkChannel.RawAdvance),
            new ShrinkOpportunity(1, 2, 8, ShrinkChannel.RawAdvance)
        ]);
        TracedAssertions.assertEqualsInt(1, s.lines.length, ParagraphDpLineBreakerTestSupport.linesString(s));
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 3), s.lines[0].clusterRange);
    }

    public static function lineEndOnlyCapacityFeedsTheCompressedEdgeAtTheLineEnd():Void {
        rec("lineEndOnlyCapacityFeedsTheCompressedEdgeAtTheLineEnd");
        var c = han(4);
        var s = solve(c, 44, [new ShrinkOpportunity(2, 1, 4, ShrinkChannel.TrailingGlue, true)], null, true, null, null, null, [1]);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 2), s.lines[0].clusterRange, ParagraphDpLineBreakerTestSupport.linesString(s));
        TracedAssertions.assertTrue(pushInReasonStartsWith(s.lines[0].repair, "LineAdjustmentPushIn"), ParagraphDpLineBreakerTestSupport.repairsString(s));
    }

    public static function compressedEndsMayReachTheSegmentEnd():Void {
        rec("compressedEndsMayReachTheSegmentEnd");
        var s = solve(han(3), 44, [new ShrinkOpportunity(1, 2, 12, ShrinkChannel.RawAdvance)], null, true, null, null, null, [1]);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 2), s.lines[0].clusterRange, ParagraphDpLineBreakerTestSupport.linesString(s));
        TracedAssertions.assertTrue(pushInReasonStartsWith(s.lines[0].repair, "LineAdjustmentPushIn"), ParagraphDpLineBreakerTestSupport.repairsString(s));
        TracedAssertions.assertEqualsRendered("ParagraphEnd", Std.string(s.lines[s.lines.length - 1].endReason));
    }

    public static function compressedFinalMandatoryLineUsesTheCompressedCommitBranch():Void {
        rec("compressedFinalMandatoryLineUsesTheCompressedCommitBranch");
        var s = solve(han(4), 44, [new ShrinkOpportunity(2, 1, 4, ShrinkChannel.TrailingGlue, true)], [2], true);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 2), s.lines[0].clusterRange, ParagraphDpLineBreakerTestSupport.linesString(s));
        TracedAssertions.assertEqualsRendered("MandatoryBreak", Std.string(s.lines[0].endReason));
        TracedAssertions.assertTrue(pushInReasonStartsWith(s.lines[0].repair, "LineAdjustmentPushIn"), ParagraphDpLineBreakerTestSupport.repairsString(s));
    }

    public static function tierPromotionRoutesTheRepairReasonThroughThePromotionCode():Void {
        rec("tierPromotionRoutesTheRepairReasonThroughThePromotionCode");
        var c = latin();
        var span = new TextRange(0, 5);
        var s = solve(c, 80, [new ShrinkOpportunity(2, 2, 5, ShrinkChannel.RawAdvance)], null, true, null,
            opp([2, 3], [span, span], [ProgressiveBreakTier.Emergency, ProgressiveBreakTier.Whitespace]));
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 2), s.lines[0].clusterRange, ParagraphDpLineBreakerTestSupport.linesString(s));
        TracedAssertions.assertTrue(pushInReasonStartsWith(s.lines[0].repair, "ProgressiveTechnicalTierPromotion"),
            ParagraphDpLineBreakerTestSupport.repairsString(s));
    }

    public static function promotionCheckReturnsFalseWhenTheCandidateEndHasNoOpportunity():Void {
        rec("promotionCheckReturnsFalseWhenTheCandidateEndHasNoOpportunity");
        var c = latin();
        var s = solve(c, 80, [new ShrinkOpportunity(2, 2, 5, ShrinkChannel.RawAdvance)], null, true, null,
            opp([2], [new TextRange(0, 5)], [ProgressiveBreakTier.Emergency]));
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 1), s.lines[0].clusterRange, ParagraphDpLineBreakerTestSupport.linesString(s));
        TracedAssertions.assertTrue(s.lines[0].repair == null, ParagraphDpLineBreakerTestSupport.repairsString(s));
    }

    public static function mandatorySegmentFiltersTheControlBoundaryFromCandidates():Void {
        rec("mandatorySegmentFiltersTheControlBoundaryFromCandidates");
        var s = solve(han(6), 32, null, [2]);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 2), s.lines[0].clusterRange, ParagraphDpLineBreakerTestSupport.linesString(s));
        TracedAssertions.assertEqualsRendered("MandatoryBreak", Std.string(s.lines[0].endReason));
        TracedAssertions.assertEqualsInt(5, s.lines[s.lines.length - 1].clusterRange.end, ParagraphDpLineBreakerTestSupport.linesString(s));
    }

    public static function narrowWindowsDropEndsAtOrBelowTheLineStart():Void {
        rec("narrowWindowsDropEndsAtOrBelowTheLineStart");
        var s = solve(han(4), 20);
        TracedAssertions.assertEqualsInt(4, s.lines.length, ParagraphDpLineBreakerTestSupport.linesString(s));
        var all = true;
        for (l in s.lines)
            if (l.clusterRange.start != l.clusterRange.end)
                all = false;
        TracedAssertions.assertTrue(all, ParagraphDpLineBreakerTestSupport.rangesString(s));
    }

    public static function interfaceDefaultStrategyNameIsCustom():Void {
        rec("interfaceDefaultStrategyNameIsCustom");
        var b:LineBreaker = new CustomBreaker();
        TracedAssertions.assertEqualsString("custom", b.strategyName);
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
