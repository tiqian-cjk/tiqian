package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.TextRange;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedMap;
import std.SortedSet;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;

class ProgressiveBreakDecisionsCoverageTest {
    static function span():TextRange
        return new TextRange(0, 5);

    static function c(i:Int, ?text:Null<String>, ?a:Null<Float>):Cluster
        return new Cluster(new TextRange(i, i + 1), text == null ? "中" : text, "test", a == null ? 16 : a, text == null ? "中" : text);

    static function op(t:ProgressiveBreakTier, s:TextRange, ?cap:Null<Float>):ProgressiveBreakOpportunity
        return new ProgressiveBreakOpportunity(t, s, cap);

    static function m(a:Array<Int>):SortedSet<Int> {
        final b = SortedSet.builder();
        var j = 0;
        while (j < a.length) {
            b.put(a[j]);
            j++;
        }
        return b.build();
    }

    static function run(n:String, f:Void->Void):Void {
        new TestTraceRecorder("ProgressiveBreakDecisionsCoverageTest").section(n);
        f();
    }

    public static function defaultsAdmitTheCleanTierWithoutGeometryInputs():Void
        run("defaultsAdmitTheCleanTierWithoutGeometryInputs", function() {
            final bo = SortedMap.builder();
            bo.put(1, op(ProgressiveBreakTier.Whitespace, span()));
            bo.put(2, op(ProgressiveBreakTier.Emergency, span()));
            final o = bo.build();
            TracedAssertions.assertEqualsInt(1, ProgressiveBreakDecisions.decideProgressiveBreak(0, 2, o));
            TracedAssertions.assertTrue(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 2, 3, o));
        });

    public static function lineStartAtTheOverflowBoundaryScansAnEmptyRange():Void
        run("lineStartAtTheOverflowBoundaryScansAnEmptyRange", function() {
            final bo = SortedMap.builder();
            bo.put(2, op(ProgressiveBreakTier.Emergency, span()));
            final o = bo.build();
            TracedAssertions.assertEqualsInt(2, ProgressiveBreakDecisions.decideProgressiveBreak(2, 2, o));
        });

    public static function twoSameTierBoundariesPickTheRightmost():Void
        run("twoSameTierBoundariesPickTheRightmost", function() {
            final bo = SortedMap.builder();
            bo.put(2, op(ProgressiveBreakTier.Whitespace, span()));
            bo.put(4, op(ProgressiveBreakTier.Whitespace, span()));
            final o = bo.build();
            TracedAssertions.assertEqualsInt(4, ProgressiveBreakDecisions.decideProgressiveBreak(0, 4, o, [c(0), c(1), c(2), c(3), c(4)], 64, null, 8));
        });

    public static function visiblyLooseCleanTiersFallThroughToEmergency():Void
        run("visiblyLooseCleanTiersFallThroughToEmergency", function() {
            final bo = SortedMap.builder();
            bo.put(2, op(ProgressiveBreakTier.Whitespace, span()));
            bo.put(4, op(ProgressiveBreakTier.Emergency, span()));
            final o = bo.build();
            TracedAssertions.assertEqualsInt(4, ProgressiveBreakDecisions.decideProgressiveBreak(0, 4, o, [c(0), c(1), c(2), c(3), c(4)], 200, null, 8));
        });

    public static function aLeftwardEmergencyBoundaryKeepsTheBestCleanTier():Void
        run("aLeftwardEmergencyBoundaryKeepsTheBestCleanTier", function() {
            final bo = SortedMap.builder();
            bo.put(2, op(ProgressiveBreakTier.Emergency, span()));
            bo.put(4, op(ProgressiveBreakTier.Whitespace, span()));
            final o = bo.build();
            TracedAssertions.assertEqualsInt(4, ProgressiveBreakDecisions.decideProgressiveBreak(0, 4, o, [c(0), c(1), c(2), c(3), c(4)], 200, null, 8));
        });

    public static function spanEdgeAndWhitespaceClustersDoNotCountAsTechnicalUnits():Void
        run("spanEdgeAndWhitespaceClustersDoNotCountAsTechnicalUnits", function() {
            final bo = SortedMap.builder();
            var s = new TextRange(1, 4);
            bo.put(2, op(ProgressiveBreakTier.Whitespace, s));
            bo.put(3, op(ProgressiveBreakTier.Emergency, s));
            final o = bo.build();
            TracedAssertions.assertEqualsInt(3,
                ProgressiveBreakDecisions.decideProgressiveBreak(0, 3, o, [c(0), c(1, " "), c(2, "a"), c(3, "b")], 200, null, 8));
        });

    public static function singleTechnicalUnitFallsBackToTheCjkGapDensity():Void
        run("singleTechnicalUnitFallsBackToTheCjkGapDensity", function() {
            final bo = SortedMap.builder();
            var s = new TextRange(0, 1);
            bo.put(1, op(ProgressiveBreakTier.Whitespace, s));
            bo.put(2, op(ProgressiveBreakTier.Emergency, s));
            final o = bo.build();
            TracedAssertions.assertEqualsInt(2, ProgressiveBreakDecisions.decideProgressiveBreak(0, 2, o, [c(0, "a"), c(1, "b"), c(2, "c")], 200, m([1]), 8));
        });

    public static function candidateOutsideTheClusterListIsAllowed():Void
        run("candidateOutsideTheClusterListIsAllowed", function() {
            final bo = SortedMap.builder();
            bo.put(1, op(ProgressiveBreakTier.Emergency, span()));
            final o = bo.build();
            TracedAssertions.assertTrue(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 1, 5, o, [c(0)]));
        });

    public static function candidatesOutsideTheActiveSpanAreAllowed():Void
        run("candidatesOutsideTheActiveSpanAreAllowed", function() {
            var cs = [c(0), c(1), c(2), c(3)];
            var a = new TextRange(5, 10);
            final bo = SortedMap.builder();
            bo.put(1, op(ProgressiveBreakTier.Emergency, a));
            final o = bo.build();
            TracedAssertions.assertTrue(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 1, 2, o, cs));
            final bt = SortedMap.builder();
            bt.put(1, op(ProgressiveBreakTier.Emergency, new TextRange(0, 2)));
            final t = bt.build();
            TracedAssertions.assertTrue(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 1, 2, t, cs));
            final bz = SortedMap.builder();
            bz.put(1, op(ProgressiveBreakTier.Emergency, new TextRange(0, 4)));
            final z = bz.build();
            TracedAssertions.assertFalse(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 1, 2, z, cs));
        });

    public static function candidatesOfADifferentSpanAreAllowed():Void
        run("candidatesOfADifferentSpanAreAllowed", function() {
            final bo = SortedMap.builder();
            bo.put(1, op(ProgressiveBreakTier.Emergency, new TextRange(0, 2)));
            bo.put(3, op(ProgressiveBreakTier.Whitespace, new TextRange(2, 6)));
            final o = bo.build();
            TracedAssertions.assertTrue(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 1, 3, o));
        });

    public static function sameTierPastTheRawGreedyIsAllowedAndWorseTiersAreNot():Void
        run("sameTierPastTheRawGreedyIsAllowedAndWorseTiersAreNot", function() {
            final bo = SortedMap.builder();
            bo.put(2, op(ProgressiveBreakTier.Whitespace, span()));
            bo.put(3, op(ProgressiveBreakTier.Whitespace, span()));
            bo.put(4, op(ProgressiveBreakTier.Emergency, span()));
            final o = bo.build();
            TracedAssertions.assertTrue(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 2, 3, o));
            TracedAssertions.assertFalse(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 2, 4, o));
        });

    public static function candidatesBeforeTheRawGreedyMustMatchTheSelectedBoundary():Void
        run("candidatesBeforeTheRawGreedyMustMatchTheSelectedBoundary", function() {
            final bo = SortedMap.builder();
            bo.put(1, op(ProgressiveBreakTier.Whitespace, span()));
            bo.put(2, op(ProgressiveBreakTier.Whitespace, span()));
            bo.put(3, op(ProgressiveBreakTier.Emergency, span()));
            final o = bo.build();
            TracedAssertions.assertTrue(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 3, 2, o));
            TracedAssertions.assertFalse(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 3, 1, o));
        });

    static function hy(n:String, limit:Float, g:SortedSet<Int>, ?s:Null<SortedSet<Int>>, ?cap:Null<Float>):Int {
        var cs = [c(0), c(1), c(2), c(3)];
        return ProgressiveBreakDecisions.decideHyphenBreak(0, 3, cs, limit, m([3]), g, 8, s, cap);
    }

    public static function hyphenBreakReturnsOverflowAtPlainWordBoundaries():Void
        run("hyphenBreakReturnsOverflowAtPlainWordBoundaries", function() {
            TracedAssertions.assertEqualsInt(1, ProgressiveBreakDecisions.decideHyphenBreak(0, 1, [c(0), c(1), c(2)], 16, m([]), m([]), 8));
        });

    public static function overLongWordsMustHyphenateFromTheLineStart():Void
        run("overLongWordsMustHyphenateFromTheLineStart", function() {
            TracedAssertions.assertEqualsInt(2, ProgressiveBreakDecisions.decideHyphenBreak(0, 2, [c(0), c(1), c(2)], 48, m([0, 1, 2]), m([]), 8));
        });

    public static function aFittingWholeWordBreaksThere():Void
        run("aFittingWholeWordBreaksThere", function() {
            TracedAssertions.assertEqualsInt(1, ProgressiveBreakDecisions.decideHyphenBreak(0, 2, [c(0), c(1), c(2)], 16, m([2]), m([]), 8));
        });

    public static function sinoWesternGapsAbsorbingTheDeficitKeepTheWholeWord():Void
        run("sinoWesternGapsAbsorbingTheDeficitKeepTheWholeWord", function() {
            TracedAssertions.assertEqualsInt(2, hy("x", 40, m([1]), m([1]), 8));
        });

    public static function gaplessOrTooLooseLinesHyphenateInstead():Void
        run("gaplessOrTooLooseLinesHyphenateInstead", function() {
            TracedAssertions.assertEqualsInt(3, hy("x", 60, m([2])));
            TracedAssertions.assertEqualsInt(3, hy("x", 100, m([1])));
            TracedAssertions.assertEqualsInt(2, ProgressiveBreakDecisions.decideHyphenBreak(0, 3, [c(0), c(1), c(2), c(3)], 36, m([3]), m([1]), 8));
        });

    public static function flush():Void {
        new TestTraceRecorder("ProgressiveBreakDecisionsCoverageTest").flush();
    }
}
