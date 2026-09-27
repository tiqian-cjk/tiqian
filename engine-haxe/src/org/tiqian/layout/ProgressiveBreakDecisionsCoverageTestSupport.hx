package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.TextRange;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedMap;
import std.SortedSet;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;

class ProgressiveBreakDecisionsCoverageTestSupport {
    public static function span():TextRange
        return new TextRange(0, 5);

    public static function c(i:Int, ?text:Null<String>, ?a:Null<Float>):Cluster
        return new Cluster(new TextRange(i, i + 1), text == null ? "中" : text, "test", a == null ? 16 : a, text == null ? "中" : text);

    public static function op(t:ProgressiveBreakTier, s:TextRange, ?cap:Null<Float>):ProgressiveBreakOpportunity
        return new ProgressiveBreakOpportunity(t, s, cap);

    public static function m(a:Array<Int>):SortedSet<Int> {
        final b = SortedSet.builder();
        var j = 0;
        while (j < a.length) {
            b.put(a[j]);
            j++;
        }
        return b.build();
    }

    public static function run(n:String, f:Void->Void):Void {
        new TestTraceRecorder("ProgressiveBreakDecisionsCoverageTest").section(n);
        f();
    }

    public static function hy(n:String, limit:Float, g:SortedSet<Int>, ?s:Null<SortedSet<Int>>, ?cap:Null<Float>):Int {
        var cs = [c(0), c(1), c(2), c(3)];
        return ProgressiveBreakDecisions.decideHyphenBreak(0, 3, cs, limit, m([3]), g, 8, s, cap);
    }

    public static function flush():Void {
        new TestTraceRecorder("ProgressiveBreakDecisionsCoverageTest").flush();
    }
}
