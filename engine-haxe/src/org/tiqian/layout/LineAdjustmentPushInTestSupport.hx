package org.tiqian.layout;

import org.tiqian.clreq.*;
import org.tiqian.core.*;
import org.tiqian.layout.LineOptimization.LineCandidate;
import org.tiqian.layout.LineOptimization.PushInAllocation;
import org.tiqian.layout.LineOptimization.RepairOption;
import org.tiqian.layout.LineOptimization.RepairOptions;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;
import org.tiqian.layout.ProgressiveBreakDecisions.UnbreakableRanges;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.LineBreaker.LookaheadLineBreaker;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import std.SortedSet;
import std.SortedMap;

class LineAdjustmentPushInTestSupport {
    public static function cluster(i:Int, text:String, advance:Float):Cluster
        return new Cluster(new TextRange(i, i + 1), text, "test", advance);

    public static function ints(a:Array<Int>):SortedSet<Int> {
        var b = SortedSet.builder();
        for (x in a)
            b.put(x);
        return b.build();
    }

    public static function line(r:IntRange, cs:Array<Cluster>):LineCandidate {
        var w = 0.0;
        for (i in r.start...r.end + 1)
            w += cs[i].advance;
        return new LineCandidate(r, new TextRange(r.start, r.end + 1), w, w);
    }

    public static function emptyRanges():UnbreakableRanges
        return new UnbreakableRanges([]);

    public static function emptyProgressive():SortedMap<Int, ProgressiveBreakOpportunity> {
        return SortedMap.builder().build();
    }

    public static function baseClusters():Array<Cluster>
        return [
            LineAdjustmentPushInTestSupport.cluster(0, "甲", 30), LineAdjustmentPushInTestSupport.cluster(1, "乙", 30),
            LineAdjustmentPushInTestSupport.cluster(2, "丙", 20), LineAdjustmentPushInTestSupport.cluster(3, "丁", 20),
            LineAdjustmentPushInTestSupport.cluster(4, "戊", 20), LineAdjustmentPushInTestSupport.cluster(5, "己", 20)
        ];

    public static function forbiddenHeadStartClusters():Array<Cluster>
        return [
            LineAdjustmentPushInTestSupport.cluster(0, "甲", 30),
            LineAdjustmentPushInTestSupport.cluster(1, "乙", 30),
            LineAdjustmentPushInTestSupport.cluster(2, "势", 20),
            LineAdjustmentPushInTestSupport.cluster(3, "。", 10),
            LineAdjustmentPushInTestSupport.cluster(4, "后", 50)
        ];

    public static function forbiddenHeadEndClusters():Array<Cluster>
        return [
            LineAdjustmentPushInTestSupport.cluster(0, "甲", 30),
            LineAdjustmentPushInTestSupport.cluster(1, "乙", 30),
            LineAdjustmentPushInTestSupport.cluster(2, "「", 10),
            LineAdjustmentPushInTestSupport.cluster(3, "安", 20),
            LineAdjustmentPushInTestSupport.cluster(4, "装", 20)
        ];

    public static function technicalClusters():Array<Cluster>
        return [
            LineAdjustmentPushInTestSupport.cluster(0, "a", 20),
            LineAdjustmentPushInTestSupport.cluster(1, " ", 20),
            LineAdjustmentPushInTestSupport.cluster(2, "R", 30),
            LineAdjustmentPushInTestSupport.cluster(3, "e", 15),
            LineAdjustmentPushInTestSupport.cluster(4, "l", 15)
        ];

    public static function fill(cs:Array<Cluster>, width:Float, ?shrink:Array<ShrinkOpportunity>, ?starts:Array<Int>, ?ends:Array<Int>,
            ?progressive:SortedMap<Int, ProgressiveBreakOpportunity>, ?splitAt:Int):Array<LineCandidate> {
        final split = splitAt == null ? 1 : splitAt;
        final a = [
            LineAdjustmentPushInTestSupport.line(new IntRange(0, split), cs),
            LineAdjustmentPushInTestSupport.line(new IntRange(split + 1, cs.length - 1), cs)
        ];
        var gapsArr = [];
        for (i in 0...(cs.length - 1))
            gapsArr.push(i);
        return LineRepair.applyFillPushIn(a, cs, cs, width, shrink == null ? [] : shrink, 0, 1000000,
            starts == null ? null : LineAdjustmentPushInTestSupport.ints(starts), LineAdjustmentPushInTestSupport.ints(ends == null ? [] : ends),
            LineAdjustmentPushInTestSupport.emptyRanges(), 2, LineAdjustmentPushInTestSupport.ints(gapsArr), progressive);
    }

    public static function repairTotalShrink(o:Null<RepairOption>):Float {
        if (o == null)
            return -1;
        final v:RepairOption = o;
        return switch (v) {
            case PushIn(_, _, _, _, totalShrink, _): totalShrink;
            case Hang(_, _, _): -1;
            case CarryPrevious(_, _, _, _): -1;
            case CarryNext(_, _, _): -1;
            case LeaveRagged(_, _, _): -1;
        };
    }

    public static function repairOffenderIndex(o:Null<RepairOption>):Int {
        if (o == null)
            return -1;
        final v:RepairOption = o;
        return switch (v) {
            case PushIn(_, _, offenderIndex, _, _, _): offenderIndex;
            case Hang(_, _, _): -1;
            case CarryPrevious(_, _, _, _): -1;
            case CarryNext(_, _, _): -1;
            case LeaveRagged(_, _, _): -1;
        };
    }

    public static function repairAllocations(o:Null<RepairOption>):Array<PushInAllocation> {
        if (o == null)
            return [];
        final v:RepairOption = o;
        return switch (v) {
            case PushIn(_, _, _, allocations, _, _): allocations;
            case Hang(_, _, _): [];
            case CarryPrevious(_, _, _, _): [];
            case CarryNext(_, _, _): [];
            case LeaveRagged(_, _, _): [];
        };
    }

    public static function repairReason(o:Null<RepairOption>):String {
        if (o == null)
            return "";
        final v:RepairOption = o;
        return switch (v) {
            case PushIn(_, reason, _, _, _, _): reason;
            case Hang(_, reason, _): reason;
            case CarryPrevious(_, reason, _, _): reason;
            case CarryNext(_, reason, _): reason;
            case LeaveRagged(_, reason, _): reason;
        };
    }

    public static final fixtureText:String = "咖啡（coffee）在十七世纪经威尼斯传入欧洲。最初它被当作药物出售，价格高得吓人，真正让它流行起来的是随后遍地开花的咖啡馆——读报、辩论、下棋、写作——城市生活忽然多出一个公共客厅。意大利人做出了 espresso，维也纳人往杯里加奶油，土耳其人坚持连渣同煮……每座城市都相信自己手里那一杯才是正统。有人说：「先有咖啡馆，后有启蒙运动」。这话说得夸张，但也不算太离谱。";

    public static function layout(strategy:LineAdjustmentStrategy):LayoutResult {
        final resolver = new PushInClreqResolver(strategy);
        final engine = new ExplainableStubParagraphLayoutEngine(null, null, resolver, null, null, null, null, null, new LookaheadLineBreaker());
        return engine.layout(new LayoutInput(new TiqianTextContent(fixtureText), null, null, new LayoutConstraints(320.0)));
    }

    public static function fillPushInCount(r:LayoutResult):Int {
        var count = 0;
        for (i in 0...r.debug.lineDecisions.length) {
            final d = r.debug.lineDecisions[i];
            if (d.repairDecision != null && d.repairDecision.reasonCode == "LineAdjustmentPushIn") {
                count++;
            }
        }
        return count;
    }
}

class PushInClreqResolver implements ClreqProfileResolver {
    final strategy:LineAdjustmentStrategy;

    public function new(strategy:LineAdjustmentStrategy)
        this.strategy = strategy;

    public function resolve(profileId:LayoutProfileId):ClreqProfile {
        final base = ClreqProfile.MainlandHorizontal;
        return new ClreqProfile(base.id, base.strictness, base.region, base.punctuationGlyphPolicy, null, base.autoSpace, base.gluePlacement,
            new AdjustmentStylePolicy(null, null, null, strategy), base.kinsokuMode, base.punctuationWidth);
    }
}
