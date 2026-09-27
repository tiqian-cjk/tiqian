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
import org.tiqian.test.trace.TestTraceRecorder;

class ParagraphDpLineBreakerCoverage2Test {
    @:test public static function testShrinkOpportunitiesNegativeAndOutOfRange():Void {
        ParagraphDpLineBreakerCoverage2TestSupport.rec("testShrinkOpportunitiesNegativeAndOutOfRange");
        var c = ParagraphDpLineBreakerCoverage2TestSupport.han(3);
        var s = ParagraphDpLineBreakerCoverage2TestSupport.solve(c, 100, [
            new ShrinkOpportunity(-1, 1, 10, ShrinkChannel.RawAdvance),
            new ShrinkOpportunity(0, 1, -5, ShrinkChannel.RawAdvance),
            new ShrinkOpportunity(5, 1, 10, ShrinkChannel.RawAdvance),
            new ShrinkOpportunity(1, 1, 4, ShrinkChannel.RawAdvance),
            new ShrinkOpportunity(2, 1, 4, ShrinkChannel.TrailingGlue, true)
        ]);
        TracedAssertions.assertEqualsInt(1, s.lines.length);
    }

    @:test public static function testCandidateWindowBoundsCompressionEdges():Void {
        ParagraphDpLineBreakerCoverage2TestSupport.rec("testCandidateWindowBoundsCompressionEdges");
        var c = ParagraphDpLineBreakerCoverage2TestSupport.han(4, 20);
        var s = ParagraphDpLineBreakerCoverage2TestSupport.solve(c, 25, [
            new ShrinkOpportunity(0, 1, 10, ShrinkChannel.RawAdvance),
            new ShrinkOpportunity(1, 1, 10, ShrinkChannel.RawAdvance),
            new ShrinkOpportunity(2, 1, 10, ShrinkChannel.RawAdvance)
        ], null, true, null, null, 1);
        TracedAssertions.assertTrue(s.lines.length > 0);
    }

    @:test public static function testProgressiveTierPromotionBranches():Void {
        ParagraphDpLineBreakerCoverage2TestSupport.rec("testProgressiveTierPromotionBranches");
        var c = ParagraphDpLineBreakerCoverage2TestSupport.latin();
        var span = new TextRange(0, 5);
        var other = new TextRange(1, 3);
        var a = ParagraphDpLineBreakerCoverage2TestSupport.solve(c, 80, [new ShrinkOpportunity(2, 2, 5, ShrinkChannel.RawAdvance)], null, true, null,
            ParagraphDpLineBreakerCoverage2TestSupport.opp([2, 3], [span, span], [ProgressiveBreakTier.Whitespace, ProgressiveBreakTier.Emergency]));
        TracedAssertions.assertTrue(a.lines.length > 0);
        var b = ParagraphDpLineBreakerCoverage2TestSupport.solve(c, 80, [new ShrinkOpportunity(2, 2, 5, ShrinkChannel.RawAdvance)], null, true, null,
            ParagraphDpLineBreakerCoverage2TestSupport.opp([2, 3], [span, other], [ProgressiveBreakTier.Emergency, ProgressiveBreakTier.Whitespace]));
        TracedAssertions.assertTrue(b.lines.length > 0);
        var d = ParagraphDpLineBreakerCoverage2TestSupport.solve(c, 80, [new ShrinkOpportunity(2, 2, 5, ShrinkChannel.RawAdvance)], null, true, null,
            ParagraphDpLineBreakerCoverage2TestSupport.opp([2, 3], [span, span], [ProgressiveBreakTier.Emergency, ProgressiveBreakTier.Whitespace]), 4);
        TracedAssertions.assertTrue(d.lines.length > 0);
    }

    @:test public static function testCommitSegmentOriginalBreakNotNullResultingBreakNull():Void {
        ParagraphDpLineBreakerCoverage2TestSupport.rec("testCommitSegmentOriginalBreakNotNullResultingBreakNull");
        var c = ParagraphDpLineBreakerCoverage2TestSupport.latin();
        var s = ParagraphDpLineBreakerCoverage2TestSupport.solve(c, 80, [new ShrinkOpportunity(2, 2, 5, ShrinkChannel.RawAdvance)], null, true, null,
            ParagraphDpLineBreakerCoverage2TestSupport.opp([2], [new TextRange(0, 5)], [ProgressiveBreakTier.Whitespace]));
        TracedAssertions.assertTrue(s.lines.length > 0);
    }

    @:test public static function testTierPreferredPoolEmptyFallback():Void {
        ParagraphDpLineBreakerCoverage2TestSupport.rec("testTierPreferredPoolEmptyFallback");
        var s = ParagraphDpLineBreakerCoverage2TestSupport.solve(ParagraphDpLineBreakerCoverage2TestSupport.han(4, 20), 30, null, null, null, new UnbreakableRanges([new IntRange(0, 3)]));
        TracedAssertions.assertTrue(s.lines.length > 0);
    }

    @:test public static function testHardBreakAfterClustersInDpCommit():Void {
        ParagraphDpLineBreakerCoverage2TestSupport.rec("testHardBreakAfterClustersInDpCommit");
        var s = ParagraphDpLineBreakerCoverage2TestSupport.solve(ParagraphDpLineBreakerCoverage2TestSupport.han(4, 20), 50, null, [1]);
        TracedAssertions.assertEqualsInt(2, s.lines.length);
        TracedAssertions.assertEqualsEnum(LineEndReason.MandatoryBreak, s.lines[0].endReason);
        TracedAssertions.assertEqualsEnum(LineEndReason.ParagraphEnd, s.lines[1].endReason);
    }

    @:test public static function testCandidateEndsWindowBelowLineStart():Void {
        ParagraphDpLineBreakerCoverage2TestSupport.rec("testCandidateEndsWindowBelowLineStart");
        var s = ParagraphDpLineBreakerCoverage2TestSupport.solve(ParagraphDpLineBreakerCoverage2TestSupport.han(3, 20), 25, null, null, null, null, null, 5);
        TracedAssertions.assertEqualsInt(3, s.lines.length);
    }

    public static function flushTestTrace():Void {
        TestTraceRecorder.flushClass("ParagraphDpLineBreakerCoverage2Test");
    }

}
