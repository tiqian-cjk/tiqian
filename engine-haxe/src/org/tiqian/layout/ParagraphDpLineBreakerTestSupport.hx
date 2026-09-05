package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.TextRange;
import org.tiqian.core.IntRange;
import std.SortedSet;
import std.SortedMap;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.UnbreakableRanges;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.LineOptimization.LineSolution;
import org.tiqian.layout.LineOptimization.LineCandidate;
import org.tiqian.layout.LineOptimization.RepairOption;
import org.tiqian.layout.LineOptimization.RepairOptions;
import org.tiqian.test.trace.TracedAssertions;

class ParagraphDpLineBreakerTestSupport {
    public static function cluster(i:Int, ?text:String, ?advance:Float):Cluster
        return new Cluster(new TextRange(i, i + 1), text == null ? "中" : text, "test", advance == null ? 16.0 : advance);

    public static function han(n:Int, ?advance:Float):Array<Cluster> {
        var a = [];
        for (i in 0...n)
            a.push(cluster(i, "中", advance));
        return a;
    }

    public static function latin():Array<Cluster>
        return [
            cluster(0, "a", 30),
            cluster(1, "/", 30),
            cluster(2, "b", 25),
            cluster(3, "c", 30),
            cluster(4, "d", 30)
        ];

    public static function ints(v:Array<Int>):SortedSet<Int> {
        var b = SortedSet.builder();
        for (x in v)
            b.put(x);
        return b.build();
    }

    public static function opportunities(v:Array<Int>, spans:Array<TextRange>, tiers:Array<ProgressiveBreakTier>):SortedMap<Int, ProgressiveBreakOpportunity> {
        var b = SortedMap.builder();
        for (i in 0...v.length)
            b.put(v[i], new ProgressiveBreakOpportunity(tiers[i], spans[i]));
        return b.build();
    }

    // Engine-direct call semantics, mirroring the LineBreaker interface
    // defaults: cjk boundaries empty, per-gap stretch cap infinite,
    // forbidden line starts null.
    public static function solve(c:Array<Cluster>, width:Float, ?shrink:Array<ShrinkOpportunity>, ?hard:Array<Int>, ?push:Bool, ?ranges:UnbreakableRanges,
            ?progressive:SortedMap<Int, ProgressiveBreakOpportunity>, ?window:Int, ?cjk:Array<Int>, ?maxStretch:Null<Float>,
            ?forbidStart:Array<Int>):LineSolution {
        var x = new ParagraphDpLineBreaker(window == null ? 8 : window);
        return x.breakLines(c, c, width, shrink, ranges, null, null, null, forbidStart == null ? null : ints(forbidStart), null, null,
            ints(cjk == null ? [] : cjk), maxStretch == null ? Math.POSITIVE_INFINITY : maxStretch, null, null, push, null, ints(hard == null ? [] : hard),
            null, progressive);
    }

    // Mirrors the breakLines helper in ParagraphDpLineBreakerTest.kt: every
    // interior cluster boundary counts as a CJK gap and the per-gap stretch
    // cap is 8.
    public static function solveTestDefaults(c:Array<Cluster>, width:Float, ?shrink:Array<ShrinkOpportunity>, ?hard:Array<Int>, ?push:Bool,
            ?ranges:UnbreakableRanges, ?progressive:SortedMap<Int, ProgressiveBreakOpportunity>, ?forbidStart:Array<Int>):LineSolution {
        var boundaries:Array<Int> = [];
        for (i in 1...c.length)
            boundaries.push(i);
        return solve(c, width, shrink, hard, push, ranges, progressive, null, boundaries, 8.0, forbidStart);
    }

    public static function tiles(s:LineSolution, n:Int):Void {
        var e = 0;
        for (l in s.lines)
            if (l.clusterRange.start <= l.clusterRange.end) {
                TracedAssertions.assertEqualsInt(e, l.clusterRange.start, "lines must tile clusters in order");
                e = l.clusterRange.end + 1;
            }
        TracedAssertions.assertEqualsInt(n, e, "lines must cover every cluster");
    }

    public static function repairsString(s:LineSolution):String {
        var parts:Array<String> = [];
        for (l in s.lines)
            parts.push(renderRepair(l.repair));
        return "[" + parts.join(", ") + "]";
    }

    public static function renderRepair(r:Null<RepairOption>):String
        return r == null ? "null" : Std.string(r);

    public static function linesString(s:LineSolution):String {
        var parts:Array<String> = [];
        for (l in s.lines)
            parts.push(Std.string(l));
        return "[" + parts.join(", ") + "]";
    }

    public static function pushInReason(r:Null<RepairOption>):Null<String> {
        return r == null ? null : RepairOptions.pushInReasonOf(r);
    }

    public static function rangesString(s:LineSolution):String {
        var parts:Array<String> = [];
        for (l in s.lines)
            parts.push(l.clusterRange.start + ".." + l.clusterRange.end);
        return "[" + parts.join(", ") + "]";
    }
}
