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
    @:test public static function defaultsAdmitTheCleanTierWithoutGeometryInputs():Void
        ProgressiveBreakDecisionsCoverageTestSupport.run("defaultsAdmitTheCleanTierWithoutGeometryInputs", function() {
            final bo = SortedMap.builder();
            bo.put(1, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Whitespace, ProgressiveBreakDecisionsCoverageTestSupport.span()));
            bo.put(2, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Emergency, ProgressiveBreakDecisionsCoverageTestSupport.span()));
            final o = bo.build();
            TracedAssertions.assertEqualsInt(1, ProgressiveBreakDecisions.decideProgressiveBreak(0, 2, o));
            TracedAssertions.assertTrue(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 2, 3, o));
        });

    @:test public static function lineStartAtTheOverflowBoundaryScansAnEmptyRange():Void
        ProgressiveBreakDecisionsCoverageTestSupport.run("lineStartAtTheOverflowBoundaryScansAnEmptyRange", function() {
            final bo = SortedMap.builder();
            bo.put(2, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Emergency, ProgressiveBreakDecisionsCoverageTestSupport.span()));
            final o = bo.build();
            TracedAssertions.assertEqualsInt(2, ProgressiveBreakDecisions.decideProgressiveBreak(2, 2, o));
        });

    @:test public static function twoSameTierBoundariesPickTheRightmost():Void
        ProgressiveBreakDecisionsCoverageTestSupport.run("twoSameTierBoundariesPickTheRightmost", function() {
            final bo = SortedMap.builder();
            bo.put(2, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Whitespace, ProgressiveBreakDecisionsCoverageTestSupport.span()));
            bo.put(4, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Whitespace, ProgressiveBreakDecisionsCoverageTestSupport.span()));
            final o = bo.build();
            TracedAssertions.assertEqualsInt(4, ProgressiveBreakDecisions.decideProgressiveBreak(0, 4, o, [ProgressiveBreakDecisionsCoverageTestSupport.c(0), ProgressiveBreakDecisionsCoverageTestSupport.c(1), ProgressiveBreakDecisionsCoverageTestSupport.c(2), ProgressiveBreakDecisionsCoverageTestSupport.c(3), ProgressiveBreakDecisionsCoverageTestSupport.c(4)], 64, null, 8));
        });

    @:test public static function visiblyLooseCleanTiersFallThroughToEmergency():Void
        ProgressiveBreakDecisionsCoverageTestSupport.run("visiblyLooseCleanTiersFallThroughToEmergency", function() {
            final bo = SortedMap.builder();
            bo.put(2, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Whitespace, ProgressiveBreakDecisionsCoverageTestSupport.span()));
            bo.put(4, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Emergency, ProgressiveBreakDecisionsCoverageTestSupport.span()));
            final o = bo.build();
            TracedAssertions.assertEqualsInt(4, ProgressiveBreakDecisions.decideProgressiveBreak(0, 4, o, [ProgressiveBreakDecisionsCoverageTestSupport.c(0), ProgressiveBreakDecisionsCoverageTestSupport.c(1), ProgressiveBreakDecisionsCoverageTestSupport.c(2), ProgressiveBreakDecisionsCoverageTestSupport.c(3), ProgressiveBreakDecisionsCoverageTestSupport.c(4)], 200, null, 8));
        });

    @:test public static function aLeftwardEmergencyBoundaryKeepsTheBestCleanTier():Void
        ProgressiveBreakDecisionsCoverageTestSupport.run("aLeftwardEmergencyBoundaryKeepsTheBestCleanTier", function() {
            final bo = SortedMap.builder();
            bo.put(2, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Emergency, ProgressiveBreakDecisionsCoverageTestSupport.span()));
            bo.put(4, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Whitespace, ProgressiveBreakDecisionsCoverageTestSupport.span()));
            final o = bo.build();
            TracedAssertions.assertEqualsInt(4, ProgressiveBreakDecisions.decideProgressiveBreak(0, 4, o, [ProgressiveBreakDecisionsCoverageTestSupport.c(0), ProgressiveBreakDecisionsCoverageTestSupport.c(1), ProgressiveBreakDecisionsCoverageTestSupport.c(2), ProgressiveBreakDecisionsCoverageTestSupport.c(3), ProgressiveBreakDecisionsCoverageTestSupport.c(4)], 200, null, 8));
        });

    @:test public static function spanEdgeAndWhitespaceClustersDoNotCountAsTechnicalUnits():Void
        ProgressiveBreakDecisionsCoverageTestSupport.run("spanEdgeAndWhitespaceClustersDoNotCountAsTechnicalUnits", function() {
            final bo = SortedMap.builder();
            var s = new TextRange(1, 4);
            bo.put(2, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Whitespace, s));
            bo.put(3, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Emergency, s));
            final o = bo.build();
            TracedAssertions.assertEqualsInt(3,
                ProgressiveBreakDecisions.decideProgressiveBreak(0, 3, o, [ProgressiveBreakDecisionsCoverageTestSupport.c(0), ProgressiveBreakDecisionsCoverageTestSupport.c(1, " "), ProgressiveBreakDecisionsCoverageTestSupport.c(2, "a"), ProgressiveBreakDecisionsCoverageTestSupport.c(3, "b")], 200, null, 8));
        });

    @:test public static function singleTechnicalUnitFallsBackToTheCjkGapDensity():Void
        ProgressiveBreakDecisionsCoverageTestSupport.run("singleTechnicalUnitFallsBackToTheCjkGapDensity", function() {
            final bo = SortedMap.builder();
            var s = new TextRange(0, 1);
            bo.put(1, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Whitespace, s));
            bo.put(2, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Emergency, s));
            final o = bo.build();
            TracedAssertions.assertEqualsInt(2, ProgressiveBreakDecisions.decideProgressiveBreak(0, 2, o, [ProgressiveBreakDecisionsCoverageTestSupport.c(0, "a"), ProgressiveBreakDecisionsCoverageTestSupport.c(1, "b"), ProgressiveBreakDecisionsCoverageTestSupport.c(2, "c")], 200, ProgressiveBreakDecisionsCoverageTestSupport.m([1]), 8));
        });

    @:test public static function candidateOutsideTheClusterListIsAllowed():Void
        ProgressiveBreakDecisionsCoverageTestSupport.run("candidateOutsideTheClusterListIsAllowed", function() {
            final bo = SortedMap.builder();
            bo.put(1, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Emergency, ProgressiveBreakDecisionsCoverageTestSupport.span()));
            final o = bo.build();
            TracedAssertions.assertTrue(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 1, 5, o, [ProgressiveBreakDecisionsCoverageTestSupport.c(0)]));
        });

    @:test public static function candidatesOutsideTheActiveSpanAreAllowed():Void
        ProgressiveBreakDecisionsCoverageTestSupport.run("candidatesOutsideTheActiveSpanAreAllowed", function() {
            var cs = [ProgressiveBreakDecisionsCoverageTestSupport.c(0), ProgressiveBreakDecisionsCoverageTestSupport.c(1), ProgressiveBreakDecisionsCoverageTestSupport.c(2), ProgressiveBreakDecisionsCoverageTestSupport.c(3)];
            var a = new TextRange(5, 10);
            final bo = SortedMap.builder();
            bo.put(1, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Emergency, a));
            final o = bo.build();
            TracedAssertions.assertTrue(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 1, 2, o, cs));
            final bt = SortedMap.builder();
            bt.put(1, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Emergency, new TextRange(0, 2)));
            final t = bt.build();
            TracedAssertions.assertTrue(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 1, 2, t, cs));
            final bz = SortedMap.builder();
            bz.put(1, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Emergency, new TextRange(0, 4)));
            final z = bz.build();
            TracedAssertions.assertFalse(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 1, 2, z, cs));
        });

    @:test public static function candidatesOfADifferentSpanAreAllowed():Void
        ProgressiveBreakDecisionsCoverageTestSupport.run("candidatesOfADifferentSpanAreAllowed", function() {
            final bo = SortedMap.builder();
            bo.put(1, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Emergency, new TextRange(0, 2)));
            bo.put(3, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Whitespace, new TextRange(2, 6)));
            final o = bo.build();
            TracedAssertions.assertTrue(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 1, 3, o));
        });

    @:test public static function sameTierPastTheRawGreedyIsAllowedAndWorseTiersAreNot():Void
        ProgressiveBreakDecisionsCoverageTestSupport.run("sameTierPastTheRawGreedyIsAllowedAndWorseTiersAreNot", function() {
            final bo = SortedMap.builder();
            bo.put(2, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Whitespace, ProgressiveBreakDecisionsCoverageTestSupport.span()));
            bo.put(3, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Whitespace, ProgressiveBreakDecisionsCoverageTestSupport.span()));
            bo.put(4, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Emergency, ProgressiveBreakDecisionsCoverageTestSupport.span()));
            final o = bo.build();
            TracedAssertions.assertTrue(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 2, 3, o));
            TracedAssertions.assertFalse(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 2, 4, o));
        });

    @:test public static function candidatesBeforeTheRawGreedyMustMatchTheSelectedBoundary():Void
        ProgressiveBreakDecisionsCoverageTestSupport.run("candidatesBeforeTheRawGreedyMustMatchTheSelectedBoundary", function() {
            final bo = SortedMap.builder();
            bo.put(1, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Whitespace, ProgressiveBreakDecisionsCoverageTestSupport.span()));
            bo.put(2, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Whitespace, ProgressiveBreakDecisionsCoverageTestSupport.span()));
            bo.put(3, ProgressiveBreakDecisionsCoverageTestSupport.op(ProgressiveBreakTier.Emergency, ProgressiveBreakDecisionsCoverageTestSupport.span()));
            final o = bo.build();
            TracedAssertions.assertTrue(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 3, 2, o));
            TracedAssertions.assertFalse(ProgressiveBreakDecisions.progressiveCandidateAllowed(0, 3, 1, o));
        });

    @:test public static function hyphenBreakReturnsOverflowAtPlainWordBoundaries():Void
        ProgressiveBreakDecisionsCoverageTestSupport.run("hyphenBreakReturnsOverflowAtPlainWordBoundaries", function() {
            TracedAssertions.assertEqualsInt(1, ProgressiveBreakDecisions.decideHyphenBreak(0, 1, [ProgressiveBreakDecisionsCoverageTestSupport.c(0), ProgressiveBreakDecisionsCoverageTestSupport.c(1), ProgressiveBreakDecisionsCoverageTestSupport.c(2)], 16, ProgressiveBreakDecisionsCoverageTestSupport.m([]), ProgressiveBreakDecisionsCoverageTestSupport.m([]), 8));
        });

    @:test public static function overLongWordsMustHyphenateFromTheLineStart():Void
        ProgressiveBreakDecisionsCoverageTestSupport.run("overLongWordsMustHyphenateFromTheLineStart", function() {
            TracedAssertions.assertEqualsInt(2, ProgressiveBreakDecisions.decideHyphenBreak(0, 2, [ProgressiveBreakDecisionsCoverageTestSupport.c(0), ProgressiveBreakDecisionsCoverageTestSupport.c(1), ProgressiveBreakDecisionsCoverageTestSupport.c(2)], 48, ProgressiveBreakDecisionsCoverageTestSupport.m([0, 1, 2]), ProgressiveBreakDecisionsCoverageTestSupport.m([]), 8));
        });

    @:test public static function aFittingWholeWordBreaksThere():Void
        ProgressiveBreakDecisionsCoverageTestSupport.run("aFittingWholeWordBreaksThere", function() {
            TracedAssertions.assertEqualsInt(1, ProgressiveBreakDecisions.decideHyphenBreak(0, 2, [ProgressiveBreakDecisionsCoverageTestSupport.c(0), ProgressiveBreakDecisionsCoverageTestSupport.c(1), ProgressiveBreakDecisionsCoverageTestSupport.c(2)], 16, ProgressiveBreakDecisionsCoverageTestSupport.m([2]), ProgressiveBreakDecisionsCoverageTestSupport.m([]), 8));
        });

    @:test public static function sinoWesternGapsAbsorbingTheDeficitKeepTheWholeWord():Void
        ProgressiveBreakDecisionsCoverageTestSupport.run("sinoWesternGapsAbsorbingTheDeficitKeepTheWholeWord", function() {
            TracedAssertions.assertEqualsInt(2, ProgressiveBreakDecisionsCoverageTestSupport.hy("x", 40, ProgressiveBreakDecisionsCoverageTestSupport.m([1]), ProgressiveBreakDecisionsCoverageTestSupport.m([1]), 8));
        });

    @:test public static function gaplessOrTooLooseLinesHyphenateInstead():Void
        ProgressiveBreakDecisionsCoverageTestSupport.run("gaplessOrTooLooseLinesHyphenateInstead", function() {
            TracedAssertions.assertEqualsInt(3, ProgressiveBreakDecisionsCoverageTestSupport.hy("x", 60, ProgressiveBreakDecisionsCoverageTestSupport.m([2])));
            TracedAssertions.assertEqualsInt(3, ProgressiveBreakDecisionsCoverageTestSupport.hy("x", 100, ProgressiveBreakDecisionsCoverageTestSupport.m([1])));
            TracedAssertions.assertEqualsInt(2, ProgressiveBreakDecisions.decideHyphenBreak(0, 3, [ProgressiveBreakDecisionsCoverageTestSupport.c(0), ProgressiveBreakDecisionsCoverageTestSupport.c(1), ProgressiveBreakDecisionsCoverageTestSupport.c(2), ProgressiveBreakDecisionsCoverageTestSupport.c(3)], 36, ProgressiveBreakDecisionsCoverageTestSupport.m([3]), ProgressiveBreakDecisionsCoverageTestSupport.m([1]), 8));
        });

    public static function flushTestTrace():Void {
        TestTraceRecorder.flushClass("ProgressiveBreakDecisionsCoverageTest");
    }

}
