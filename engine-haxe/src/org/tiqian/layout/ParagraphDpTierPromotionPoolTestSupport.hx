package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.TextRange;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;
import org.tiqian.layout.ProgressiveBreakDecisions.UnbreakableRanges;
import org.tiqian.layout.LineOptimization.RepairOption;
import org.tiqian.layout.LineOptimization.RepairOptions;
import std.SortedMap;

class ParagraphDpTierPromotionPoolTestSupport {
    public static function cluster(index:Int, text:String, advance:Float):Cluster
        return new Cluster(new TextRange(index, index + 1), text, "test", advance, text);

    public static function hanClusters(n:Int):Array<Cluster>
        return [for (i in 0...n) cluster(i, "中", 16)];

    public static function latinClusters():Array<Cluster>
        return [
            cluster(0, "a", 30),
            cluster(1, "/", 30),
            cluster(2, "b", 25),
            cluster(3, "c", 30),
            cluster(4, "d", 30)
        ];

    public static function opp(keys:Array<Int>, values:Array<ProgressiveBreakOpportunity>):SortedMap<Int, ProgressiveBreakOpportunity> {
        final b = SortedMap.builder();
        for (i in 0...keys.length)
            b.put(keys[i], values[i]);
        return b.build();
    }

    public static function repairReason(r:Null<RepairOption>):String
        return r == null ? "" : RepairOptions.reason(r);
}
