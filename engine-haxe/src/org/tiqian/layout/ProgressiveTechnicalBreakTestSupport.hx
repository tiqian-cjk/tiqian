package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.TextRange;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import std.SortedMap;

class ProgressiveTechnicalBreakTestSupport {
    public static function cluster(index:Int, text:String, advance:Float):Cluster
        return new Cluster(new TextRange(index, index + 1), text, "test", advance, text);

    public static function opportunityMap(keys:Array<Int>, values:Array<ProgressiveBreakOpportunity>):SortedMap<Int, ProgressiveBreakOpportunity> {
        final b = SortedMap.builder();
        for (i in 0...keys.length)
            b.put(keys[i], values[i]);
        return b.build();
    }
}
