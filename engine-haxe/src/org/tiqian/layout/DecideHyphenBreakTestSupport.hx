package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.TextRange;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedSet;

class DecideHyphenBreakTestSupport {
    public static function c(i:Int, a:Float):Cluster
        return new Cluster(new TextRange(i, i + 1), "x", "k", a);

    public static function cs():Array<Cluster>
        return [c(0, 16), c(1, 16), c(2, 32), c(3, 32), c(4, 32)];

    public static function m(a:Array<Int>):SortedSet<Int> {
        final b = SortedSet.builder();
        var j = 0;
        while (j < a.length) {
            b.put(a[j]);
            j++;
        }
        return b.build();
    }

    public static function flush():Void
        new TestTraceRecorder("DecideHyphenBreakTest").flush();
}
