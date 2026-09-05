package org.tiqian.layout;

import org.tiqian.core.TextRange;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class ProgressiveTechnicalBreakTest {
    @:test public static function sourceWhitespaceCapacityKeepsStructuralTierAheadOfSyllable():Void {
        final t = new TestTraceRecorder("ProgressiveTechnicalBreakTest");
        t.section("sourceWhitespaceCapacityKeepsStructuralTierAheadOfSyllable");
        final span = new TextRange(0, 6);
        final c = [
            ProgressiveTechnicalBreakTestSupport.cluster(0, "a", 20),
            ProgressiveTechnicalBreakTestSupport.cluster(1, " ", 4),
            ProgressiveTechnicalBreakTestSupport.cluster(2, "b", 28),
            ProgressiveTechnicalBreakTestSupport.cluster(3, "/", 28),
            ProgressiveTechnicalBreakTestSupport.cluster(4, "c", 2),
            ProgressiveTechnicalBreakTestSupport.cluster(5, "d", 20)
        ];
        final o = ProgressiveTechnicalBreakTestSupport.opportunityMap([2, 4, 5], [
            new ProgressiveBreakOpportunity(ProgressiveBreakTier.Whitespace, span, 4),
            new ProgressiveBreakOpportunity(ProgressiveBreakTier.Structural, span),
            new ProgressiveBreakOpportunity(ProgressiveBreakTier.Syllable, span)
        ]);
        TracedAssertions.assertEqualsInt(4, ProgressiveBreakDecisions.decideProgressiveBreak(0, 5, o, c, 84, null, 8));
    }

    @:test public static function lookaheadMayNotReplaceSelectedEmergencyBoundaryWithEarlierSameTierCut():Void {
        final t = new TestTraceRecorder("ProgressiveTechnicalBreakTest");
        t.section("lookaheadMayNotReplaceSelectedEmergencyBoundaryWithEarlierSameTierCut");
        final span = new TextRange(0, 5);
        final c = [
            for (i in 0...5)
                ProgressiveTechnicalBreakTestSupport.cluster(i, String.fromCharCode(97 + i), 20)
        ];
        final o = ProgressiveTechnicalBreakTestSupport.opportunityMap([3, 4], [
            new ProgressiveBreakOpportunity(ProgressiveBreakTier.Emergency, span),
            new ProgressiveBreakOpportunity(ProgressiveBreakTier.Emergency, span)
        ]);
        TracedAssertions.assertFalse(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 4, 3, o, c, 90, null, 8));
        TracedAssertions.assertTrue(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 4, 4, o, c, 90, null, 8));
    }
}
