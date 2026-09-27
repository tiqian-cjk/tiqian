package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.TextRange;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedMap;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;

class ProgressiveBreakDecisionsTailTest {
    @:test public static function infiniteLineLimitWithClustersAdmitsTheCleanestTier():Void
        ProgressiveBreakDecisionsTailTestSupport.t("infiniteLineLimitWithClustersAdmitsTheCleanestTier", function() {
            final cs = [ProgressiveBreakDecisionsTailTestSupport.c(0), ProgressiveBreakDecisionsTailTestSupport.c(1), ProgressiveBreakDecisionsTailTestSupport.c(2), ProgressiveBreakDecisionsTailTestSupport.c(3), ProgressiveBreakDecisionsTailTestSupport.c(4)];
            TracedAssertions.assertEqualsInt(2, ProgressiveBreakDecisions.decideProgressiveBreak(0, 4, ProgressiveBreakDecisionsTailTestSupport.o(), cs));
        });

    @:test public static function infiniteStretchCeilingWithFiniteLineLimitAdmitsTheCleanestTier():Void
        ProgressiveBreakDecisionsTailTestSupport.t("infiniteStretchCeilingWithFiniteLineLimitAdmitsTheCleanestTier", function() {
            final cs = [ProgressiveBreakDecisionsTailTestSupport.c(0), ProgressiveBreakDecisionsTailTestSupport.c(1), ProgressiveBreakDecisionsTailTestSupport.c(2), ProgressiveBreakDecisionsTailTestSupport.c(3), ProgressiveBreakDecisionsTailTestSupport.c(4)];
            TracedAssertions.assertEqualsInt(2, ProgressiveBreakDecisions.decideProgressiveBreak(0, 4, ProgressiveBreakDecisionsTailTestSupport.o(), cs, 200));
        });

    public static function flushTestTrace():Void {
        TestTraceRecorder.flushClass("ProgressiveBreakDecisionsTailTest");
    }

}
