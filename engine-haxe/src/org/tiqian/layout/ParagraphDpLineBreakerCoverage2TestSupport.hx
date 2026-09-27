package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.*;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;
import org.tiqian.layout.ProgressiveBreakDecisions.UnbreakableRanges;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.LineOptimization.LineSolution;
import std.SortedMap;
import org.tiqian.test.trace.TestTraceRecorder;

class ParagraphDpLineBreakerCoverage2TestSupport {
    public static function rec(n:String):Void
        new TestTraceRecorder("ParagraphDpLineBreakerCoverage2Test").section(n);

    public static function solve(c:Array<Cluster>, width:Float, ?shrink:Array<ShrinkOpportunity>, ?hard:Array<Int>, ?push:Bool, ?ranges:UnbreakableRanges,
            ?progressive:SortedMap<Int, ProgressiveBreakOpportunity>, ?window:Int):LineSolution
        return ParagraphDpLineBreakerTestSupport.solve(c, width, shrink, hard, push, ranges, progressive, window);

    public static function han(n:Int, ?a:Float):Array<Cluster>
        return ParagraphDpLineBreakerTestSupport.han(n, a);

    public static function latin():Array<Cluster>
        return ParagraphDpLineBreakerTestSupport.latin();

    public static function opp(v:Array<Int>, spans:Array<TextRange>, tiers:Array<ProgressiveBreakTier>):SortedMap<Int, ProgressiveBreakOpportunity>
        return ParagraphDpLineBreakerTestSupport.opportunities(v, spans, tiers);
}
