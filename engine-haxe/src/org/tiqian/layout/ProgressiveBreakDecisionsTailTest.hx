package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.TextRange;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedMap;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;

class ProgressiveBreakDecisionsTailTest {
    static function c(i:Int):Cluster
        return new Cluster(new TextRange(i, i + 1), "中", "test", 16, "中");

    static function o():SortedMap<Int, ProgressiveBreakOpportunity> {
        final b = SortedMap.builder();
        var s = new TextRange(0, 5);
        b.put(2, new ProgressiveBreakOpportunity(ProgressiveBreakTier.Whitespace, s));
        b.put(4, new ProgressiveBreakOpportunity(ProgressiveBreakTier.Emergency, s));
        return b.build();
    }

    static function t(n:String, f:Void->Void):Void {
        new TestTraceRecorder("ProgressiveBreakDecisionsTailTest").section(n);
        f();
    }

    public static function infiniteLineLimitWithClustersAdmitsTheCleanestTier():Void
        t("infiniteLineLimitWithClustersAdmitsTheCleanestTier", function() {
            final cs = [c(0), c(1), c(2), c(3), c(4)];
            TracedAssertions.assertEqualsInt(2, ProgressiveBreakDecisions.decideProgressiveBreak(0, 4, o(), cs));
        });

    public static function infiniteStretchCeilingWithFiniteLineLimitAdmitsTheCleanestTier():Void
        t("infiniteStretchCeilingWithFiniteLineLimitAdmitsTheCleanestTier", function() {
            final cs = [c(0), c(1), c(2), c(3), c(4)];
            TracedAssertions.assertEqualsInt(2, ProgressiveBreakDecisions.decideProgressiveBreak(0, 4, o(), cs, 200));
        });

    public static function flush():Void
        new TestTraceRecorder("ProgressiveBreakDecisionsTailTest").flush();
}
