package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.font.FontRole;
import org.tiqian.font.FontPolicy.FontDecision;
import org.tiqian.font.FontPolicy.FontCandidate;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.LineBreakPlanningStage.ParagraphLayoutPrep;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class LineBreakPlanningStageCoverage2Test {
    @:test public static function testAdjustableInlineBoundaryRightClustersNoStretchBoundaries():Void {
        final t = new TestTraceRecorder("LineBreakPlanningStageCoverage2Test");
        t.section("testAdjustableInlineBoundaryRightClustersNoStretchBoundaries");
        final p = LineBreakPlanningStageCoverage2TestSupport.prep("中文字符排版");
        final r = LineBreakPlanningStageCoverage2TestSupport.plan(LineBreakPlanningStageCoverage2TestSupport.withPrep(p, null, null, null, null, null,
            LineBreakPlanningStageCoverage2TestSupport.setUniform(), LineBreakPlanningStageCoverage2TestSupport.mapAtom()));
        TracedAssertions.assertTrue(r.lineSolution.lines.length > 0);
    }

    @:test public static function testAsciiPointMarkKinsokuLineStart():Void {
        final t = new TestTraceRecorder("LineBreakPlanningStageCoverage2Test");
        t.section("testAsciiPointMarkKinsokuLineStart");
        TracedAssertions.assertTrue(LineBreakPlanningStageCoverage2TestSupport.layout("hello, world", 50).lines.length > 0);
    }

    @:test public static function testClusterCrossesFontDecisionThrows():Void {
        final t = new TestTraceRecorder("LineBreakPlanningStageCoverage2Test");
        t.section("testClusterCrossesFontDecisionThrows");
        final p = LineBreakPlanningStageCoverage2TestSupport.prep("abcdef");
        final c = new Cluster(new TextRange(0, 5), "abcde", "test", 50);
        final d = new FontDecision(new TextRange(0, 3), new FontCandidate("test", "test", FontRole.LatinText), FontRole.LatinText, "test");
        final e = TracedAssertions.assertFailsWith(null,
            () -> LineBreakPlanningStageCoverage2TestSupport.plan(LineBreakPlanningStageCoverage2TestSupport.withPrep(p, [c], [c], [d])));
        TracedAssertions.assertTrue(e.message.indexOf("crosses font decision") >= 0, e.message);
    }

    @:test public static function testEmergencyTrackingBoundaryWhitespaceAndEmpty():Void {
        final t = new TestTraceRecorder("LineBreakPlanningStageCoverage2Test");
        t.section("testEmergencyTrackingBoundaryWhitespaceAndEmpty");
        final p = LineBreakPlanningStageCoverage2TestSupport.prep("ab");
        final cs = [
            new Cluster(new TextRange(0, 0), "", "test", 0),
            new Cluster(new TextRange(0, 1), "a", "test", 10),
            new Cluster(new TextRange(1, 1), "", "test", 0),
            new Cluster(new TextRange(1, 2), "b", "test", 10)
        ];
        final e = new EmergencyTrackingEligibilityDecisionInfo(new TextRange(0, 2), "ab", "reason");
        TracedAssertions.assertTrue(LineBreakPlanningStageCoverage2TestSupport.plan(LineBreakPlanningStageCoverage2TestSupport.withPrep(p, cs, cs, null, null,
            [e]))
            .lineSolution.lines.length > 0);
    }

    @:test public static function testEmergencyTrackingEligibilityDecisionsBranches():Void {
        final t = new TestTraceRecorder("LineBreakPlanningStageCoverage2Test");
        t.section("testEmergencyTrackingEligibilityDecisionsBranches");
        final p = LineBreakPlanningStageCoverage2TestSupport.prep("中文字符");
        final es = [
            new EmergencyTrackingEligibilityDecisionInfo(new TextRange(100, 200), "unmapped", "reason"),
            new EmergencyTrackingEligibilityDecisionInfo(new TextRange(0, 4), "中文字符", "validReason"),
            new EmergencyTrackingEligibilityDecisionInfo(new TextRange(0, 4), "中文字符", "duplicateReason")
        ];
        TracedAssertions.assertTrue(LineBreakPlanningStageCoverage2TestSupport.plan(LineBreakPlanningStageCoverage2TestSupport.withPrep(p, null, null, null,
            null, es))
            .lineSolution.lines.length > 0);
    }

    @:test public static function testFontDecisionWithNoMatchingClustersUsesTextSubstring():Void {
        final t = new TestTraceRecorder("LineBreakPlanningStageCoverage2Test");
        t.section("testFontDecisionWithNoMatchingClustersUsesTextSubstring");
        final p = LineBreakPlanningStageCoverage2TestSupport.prep("abcdef");
        final d = new FontDecision(new TextRange(4, 6), new FontCandidate("test", "test", FontRole.LatinText), FontRole.LatinText, "test");
        final c = new Cluster(new TextRange(0, 2), "ab", "test", 20);
        final r = LineBreakPlanningStageCoverage2TestSupport.plan(LineBreakPlanningStageCoverage2TestSupport.withPrep(p, [c], [c], [d]));
        TracedAssertions.assertEquals(1, r.metricDecisions.length);
        TracedAssertions.assertEqualsString("ef", r.metricDecisions[0].request.faceSelectionText);
    }

    @:test public static function testInlineObjectKinsokuLineStart():Void {
        final t = new TestTraceRecorder("LineBreakPlanningStageCoverage2Test");
        t.section("testInlineObjectKinsokuLineStart");
        TracedAssertions.assertTrue(LineBreakPlanningStageCoverage2TestSupport.layout("\uFFFChello", 50, [new InlineObjectSpan(new TextRange(0, 1), 16, 8, 8)])
            .lines.length > 0);
    }

    @:test public static function testProgressiveBreakOffsetsUnmappedClusterIndex():Void {
        final t = new TestTraceRecorder("LineBreakPlanningStageCoverage2Test");
        t.section("testProgressiveBreakOffsetsUnmappedClusterIndex");
        final p = LineBreakPlanningStageCoverage2TestSupport.prep("abc");
        final r = LineBreakPlanningStageCoverage2TestSupport.plan(LineBreakPlanningStageCoverage2TestSupport.withPrep(p, null, null, null,
            LineBreakPlanningStageCoverage2TestSupport.mapOpp()));
        TracedAssertions.assertTrue(r.progressiveBreakOpportunities.size() == 0);
    }
}
