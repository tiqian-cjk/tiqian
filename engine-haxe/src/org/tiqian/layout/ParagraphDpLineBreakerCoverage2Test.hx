package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.*;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;
import org.tiqian.layout.ProgressiveBreakDecisions.UnbreakableRanges;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.LineOptimization.LineSolution;
import std.SortedMap;

class ParagraphDpLineBreakerCoverage2Test {
    static function rec(n:String):Void
        new TestTraceRecorder("ParagraphDpLineBreakerCoverage2Test").section(n);

    static function solve(c:Array<Cluster>, width:Float, ?shrink:Array<ShrinkOpportunity>, ?hard:Array<Int>, ?push:Bool, ?ranges:UnbreakableRanges,
            ?progressive:SortedMap<Int, ProgressiveBreakOpportunity>, ?window:Int):LineSolution
        return ParagraphDpLineBreakerTestSupport.solve(c, width, shrink, hard, push, ranges, progressive, window);

    static function han(n:Int, ?a:Float):Array<Cluster>
        return ParagraphDpLineBreakerTestSupport.han(n, a);

    static function latin():Array<Cluster>
        return ParagraphDpLineBreakerTestSupport.latin();

    static function opp(v:Array<Int>, spans:Array<TextRange>, tiers:Array<ProgressiveBreakTier>):SortedMap<Int, ProgressiveBreakOpportunity>
        return ParagraphDpLineBreakerTestSupport.opportunities(v, spans, tiers);

    public static function testShrinkOpportunitiesNegativeAndOutOfRange():Void {
        rec("testShrinkOpportunitiesNegativeAndOutOfRange");
        var c = han(3);
        var s = solve(c, 100, [
            new ShrinkOpportunity(-1, 1, 10, ShrinkChannel.RawAdvance),
            new ShrinkOpportunity(0, 1, -5, ShrinkChannel.RawAdvance),
            new ShrinkOpportunity(5, 1, 10, ShrinkChannel.RawAdvance),
            new ShrinkOpportunity(1, 1, 4, ShrinkChannel.RawAdvance),
            new ShrinkOpportunity(2, 1, 4, ShrinkChannel.TrailingGlue, true)
        ]);
        TracedAssertions.assertEqualsInt(1, s.lines.length);
    }

    public static function testCandidateWindowBoundsCompressionEdges():Void {
        rec("testCandidateWindowBoundsCompressionEdges");
        var c = han(4, 20);
        var s = solve(c, 25, [
            new ShrinkOpportunity(0, 1, 10, ShrinkChannel.RawAdvance),
            new ShrinkOpportunity(1, 1, 10, ShrinkChannel.RawAdvance),
            new ShrinkOpportunity(2, 1, 10, ShrinkChannel.RawAdvance)
        ], null, true, null, null, 1);
        TracedAssertions.assertTrue(s.lines.length > 0);
    }

    public static function testProgressiveTierPromotionBranches():Void {
        rec("testProgressiveTierPromotionBranches");
        var c = latin();
        var span = new TextRange(0, 5);
        var other = new TextRange(1, 3);
        var a = solve(c, 80, [new ShrinkOpportunity(2, 2, 5, ShrinkChannel.RawAdvance)], null, true, null,
            opp([2, 3], [span, span], [ProgressiveBreakTier.Whitespace, ProgressiveBreakTier.Emergency]));
        TracedAssertions.assertTrue(a.lines.length > 0);
        var b = solve(c, 80, [new ShrinkOpportunity(2, 2, 5, ShrinkChannel.RawAdvance)], null, true, null,
            opp([2, 3], [span, other], [ProgressiveBreakTier.Emergency, ProgressiveBreakTier.Whitespace]));
        TracedAssertions.assertTrue(b.lines.length > 0);
        var d = solve(c, 80, [new ShrinkOpportunity(2, 2, 5, ShrinkChannel.RawAdvance)], null, true, null,
            opp([2, 3], [span, span], [ProgressiveBreakTier.Emergency, ProgressiveBreakTier.Whitespace]), 4);
        TracedAssertions.assertTrue(d.lines.length > 0);
    }

    public static function testCommitSegmentOriginalBreakNotNullResultingBreakNull():Void {
        rec("testCommitSegmentOriginalBreakNotNullResultingBreakNull");
        var c = latin();
        var s = solve(c, 80, [new ShrinkOpportunity(2, 2, 5, ShrinkChannel.RawAdvance)], null, true, null,
            opp([2], [new TextRange(0, 5)], [ProgressiveBreakTier.Whitespace]));
        TracedAssertions.assertTrue(s.lines.length > 0);
    }

    public static function testTierPreferredPoolEmptyFallback():Void {
        rec("testTierPreferredPoolEmptyFallback");
        var s = solve(han(4, 20), 30, null, null, null, new UnbreakableRanges([new IntRange(0, 3)]));
        TracedAssertions.assertTrue(s.lines.length > 0);
    }

    public static function testHardBreakAfterClustersInDpCommit():Void {
        rec("testHardBreakAfterClustersInDpCommit");
        var s = solve(han(4, 20), 50, null, [1]);
        TracedAssertions.assertEqualsInt(2, s.lines.length);
        TracedAssertions.assertEqualsEnum(LineEndReason.MandatoryBreak, s.lines[0].endReason);
        TracedAssertions.assertEqualsEnum(LineEndReason.ParagraphEnd, s.lines[1].endReason);
    }

    public static function testCandidateEndsWindowBelowLineStart():Void {
        rec("testCandidateEndsWindowBelowLineStart");
        var s = solve(han(3, 20), 25, null, null, null, null, null, 5);
        TracedAssertions.assertEqualsInt(3, s.lines.length);
    }
}
