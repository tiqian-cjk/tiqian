package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.IntRange;
import org.tiqian.core.LineEndReason;
import org.tiqian.core.TextRange;
import org.tiqian.layout.LineBreaker.LineBreakerLines;
import org.tiqian.layout.LineBreaker.LookaheadLineBreaker;
import org.tiqian.layout.LineOptimization.LineCandidate;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.UnbreakableRanges;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedMap;
import std.SortedSet;

class LineBreakerCoverage2Test {
    @:test public static function testLineBreakerStrategyNameDefault():Void {
        final testTrace = new TestTraceRecorder("LineBreakerCoverage2Test");
        testTrace.section("testLineBreakerStrategyNameDefault");
        final breaker:LineBreaker = new LineBreakerCoverage2TestCustomBreaker();
        TracedAssertions.assertEqualsString("custom", breaker.strategyName);
    }

    @:test public static function testLookaheadLineBreakerPreconditions():Void {
        final testTrace = new TestTraceRecorder("LineBreakerCoverage2Test");
        testTrace.section("testLookaheadLineBreakerPreconditions");
        final clusters = LineBreakerCoverage2TestSupport.hanClusters(2);
        TracedAssertions.assertFailsWith(null, function() {
            new LookaheadLineBreaker().breakLines(LineBreakerCoverage2TestSupport.hanClusters(1), clusters, 100.0);
        });
        TracedAssertions.assertFailsWith(null, function() {
            new LookaheadLineBreaker(-1).breakLines(clusters, clusters, 100.0);
        });
        TracedAssertions.assertFailsWith(null, function() {
            new LookaheadLineBreaker(null, -1).breakLines(clusters, clusters, 100.0);
        });
    }

    @:test public static function testLookaheadCandidateFilteringWithNonRenderingControlClusters():Void {
        final testTrace = new TestTraceRecorder("LineBreakerCoverage2Test");
        testTrace.section("testLookaheadCandidateFilteringWithNonRenderingControlClusters");
        final clusters = [
            LineBreakerCoverage2TestSupport.cluster(0, "\u200B", 0.0),
            LineBreakerCoverage2TestSupport.cluster(1, "A", 20.0),
            LineBreakerCoverage2TestSupport.cluster(2, "B", 20.0)
        ];
        final solution = new LookaheadLineBreaker(2).breakLines(clusters, clusters, 25.0, null, null, null, null, null, null, null, null, null, null, null,
            null, null, null, null, LineBreakerCoverage2TestSupport.ints([0]));
        TracedAssertions.assertTrue(solution.lines.length > 0);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 1), solution.lines[0].clusterRange);
    }

    @:test public static function testLookaheadHardBreakAtEndAndMiddle():Void {
        final testTrace = new TestTraceRecorder("LineBreakerCoverage2Test");
        testTrace.section("testLookaheadHardBreakAtEndAndMiddle");
        final endSolution = new LookaheadLineBreaker(1).breakLines(LineBreakerCoverage2TestSupport.hanClusters(2),
            LineBreakerCoverage2TestSupport.hanClusters(2), 20.0, null, null, null, null, null, null, null, null, null, null, null, null, null, null,
            LineBreakerCoverage2TestSupport.ints([1]));
        TracedAssertions.assertEqualsInt(2, endSolution.lines.length);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 1), endSolution.lines[0].clusterRange);
        TracedAssertions.assertEqualsEnum(LineEndReason.MandatoryBreak, endSolution.lines[0].endReason);
        TracedAssertions.assertEqualsIntRange(new IntRange(1, 0), endSolution.lines[1].clusterRange);
        TracedAssertions.assertEqualsEnum(LineEndReason.ParagraphEnd, endSolution.lines[1].endReason);

        final middleSolution = new LookaheadLineBreaker(1).breakLines(LineBreakerCoverage2TestSupport.hanClusters(3),
            LineBreakerCoverage2TestSupport.hanClusters(3), 20.0, null, null, null, null, null, null, null, null, null, null, null, null, null, null,
            LineBreakerCoverage2TestSupport.ints([0]));
        TracedAssertions.assertEqualsInt(3, middleSolution.lines.length);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 0), middleSolution.lines[0].clusterRange);
        TracedAssertions.assertEqualsEnum(LineEndReason.MandatoryBreak, middleSolution.lines[0].endReason);

        final oversized = [
            LineBreakerCoverage2TestSupport.cluster(0, "A", 50.0),
            LineBreakerCoverage2TestSupport.cluster(1, "B", 10.0)
        ];
        final oversizedSolution = new LookaheadLineBreaker(1).breakLines(oversized, oversized, 20.0, null, null, null, null, null, null, null, null, null,
            null, null, null, null, null, LineBreakerCoverage2TestSupport.ints([0]));
        TracedAssertions.assertEqualsInt(2, oversizedSolution.lines.length);
    }

    @:test public static function testLineCandidateEndsWithProgressiveBreak():Void {
        final testTrace = new TestTraceRecorder("LineBreakerCoverage2Test");
        testTrace.section("testLineCandidateEndsWithProgressiveBreak");
        final c = new LineCandidate(new IntRange(0, 1), new TextRange(0, 2), 32.0, 32.0, LineEndReason.AutoWrap);
        final opp = new ProgressiveBreakOpportunity(ProgressiveBreakTier.Syllable, new TextRange(0, 4));
        TracedAssertions.assertTrue(LineBreakerLines.endsWithProgressiveBreak(c, LineBreakerCoverage2TestSupport.oppMap([2], [opp])));
        final paragraphEnd = new LineCandidate(c.clusterRange, c.sourceRange, c.naturalWidth, c.adjustedWidth, LineEndReason.ParagraphEnd, c.repair,
            c.repairCandidates, c.hangingClusterIndices);
        TracedAssertions.assertFalse(LineBreakerLines.endsWithProgressiveBreak(paragraphEnd, LineBreakerCoverage2TestSupport.oppMap([2], [opp])));
        final emptyRange = new LineCandidate(new IntRange(1, 0), c.sourceRange, c.naturalWidth, c.adjustedWidth, c.endReason, c.repair, c.repairCandidates,
            c.hangingClusterIndices);
        TracedAssertions.assertFalse(LineBreakerLines.endsWithProgressiveBreak(emptyRange, LineBreakerCoverage2TestSupport.oppMap([2], [opp])));
        TracedAssertions.assertFalse(LineBreakerLines.endsWithProgressiveBreak(c, SortedMap.builder().build()));
    }

    @:test public static function testLineGapCount():Void {
        final testTrace = new TestTraceRecorder("LineBreakerCoverage2Test");
        testTrace.section("testLineGapCount");
        TracedAssertions.assertEqualsInt(0, LineBreakerLines.lineGapCount(new IntRange(1, 0), LineBreakerCoverage2TestSupport.ints([0, 1])));
        TracedAssertions.assertEqualsInt(1, LineBreakerLines.lineGapCount(new IntRange(0, 2), LineBreakerCoverage2TestSupport.ints([1])));
        TracedAssertions.assertEqualsInt(0, LineBreakerLines.lineGapCount(new IntRange(0, 2), LineBreakerCoverage2TestSupport.ints([2])));
    }

    @:test public static function testRebuildLineEmptyRangeThrows():Void {
        final testTrace = new TestTraceRecorder("LineBreakerCoverage2Test");
        testTrace.section("testRebuildLineEmptyRangeThrows");
        final clusters = LineBreakerCoverage2TestSupport.hanClusters(2);
        TracedAssertions.assertFailsWith(null, function() LineBreakerLines.rebuildLine(new IntRange(1, 0), clusters, clusters));
    }

    @:test public static function testFindGreedyEndDefaultArgs():Void {
        final testTrace = new TestTraceRecorder("LineBreakerCoverage2Test");
        testTrace.section("testFindGreedyEndDefaultArgs");
        TracedAssertions.assertEqualsInt(2, LineBreakerLines.findGreedyEnd(LineBreakerCoverage2TestSupport.hanClusters(5, 10.0), 0, 25.0));
    }

    @:test public static function testLookaheadOrphanAndSyntheticHyphenRuns():Void {
        final testTrace = new TestTraceRecorder("LineBreakerCoverage2Test");
        testTrace.section("testLookaheadOrphanAndSyntheticHyphenRuns");
        final clusters = LineBreakerCoverage2TestSupport.hanClusters(4, 20.0);
        final solution = new LookaheadLineBreaker(null,
            2).breakLines(clusters, clusters, 25.0, null, null, null, null, null, null, null, LineBreakerCoverage2TestSupport.ints([1, 2, 3]));
        TracedAssertions.assertEqualsInt(4, solution.lines.length);
    }
}

class LineBreakerCoverage2TestCustomBreaker implements LineBreaker {
    public function new() {}

    public var strategyName(get, never):String;

    function get_strategyName():String
        return "custom";

    public function breakLines(n:Array<Cluster>, a:Array<Cluster>, maxWidth:Float, ?s:Array<ShrinkOpportunity>, ?u:UnbreakableRanges, ?i:Float,
            ?h:SortedSet<Int>, ?e:Array<IntRange>, ?fs:Null<SortedSet<Int>>, ?fe:SortedSet<Int>, ?hy:SortedSet<Int>, ?cj:SortedSet<Int>, ?mc:Float,
            ?sw:SortedSet<Int>, ?sc:Float, ?p:Bool, ?bias:Float, ?hb:SortedSet<Int>, ?nc:SortedSet<Int>,
            ?pr:SortedMap<Int, ProgressiveBreakOpportunity>):LineOptimization.LineSolution {
        return new LineOptimization.LineSolution([]);
    }
}

class LineBreakerCoverage2TestSupport {
    public static function cluster(index:Int, text:String = "中", advance:Float = 16.0):Cluster
        return new Cluster(new TextRange(index, index + 1), text, "test", advance);

    public static function hanClusters(count:Int, advance:Float = 16.0):Array<Cluster> {
        final result:Array<Cluster> = [];
        for (i in 0...count)
            result.push(cluster(i, "中", advance));
        return result;
    }

    public static function ints(values:Array<Int>):SortedSet<Int> {
        final b = SortedSet.builder();
        for (v in values)
            b.put(v);
        return b.build();
    }

    public static function oppMap(keys:Array<Int>, opps:Array<ProgressiveBreakOpportunity>):SortedMap<Int, ProgressiveBreakOpportunity> {
        final b = SortedMap.builder();
        for (i in 0...keys.length)
            b.put(keys[i], opps[i]);
        return b.build();
    }
}
