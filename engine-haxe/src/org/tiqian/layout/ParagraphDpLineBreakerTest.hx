package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.*;
import org.tiqian.layout.LineOptimization.LineCandidate;
import org.tiqian.layout.LineOptimization.RepairOption;
import org.tiqian.layout.LineOptimization.RepairOptions;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;
import org.tiqian.layout.ProgressiveBreakDecisions.UnbreakableRanges;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;

class ParagraphDpLineBreakerTest {
    static function rec(n:String):Void
        new TestTraceRecorder("ParagraphDpLineBreakerTest").section(n);

    static function c(i:Int, t:String, a:Float):Cluster
        return ParagraphDpLineBreakerTestSupport.cluster(i, t, a);

    public static function compressedSameTierBoundaryIsNotReportedAsPromotion():Void {
        rec("compressedSameTierBoundaryIsNotReportedAsPromotion");
        var cs = [c(0, "a", 30), c(1, "/", 30), c(2, "b", 25), c(3, "c", 30), c(4, "d", 30)];
        var s = ParagraphDpLineBreakerTestSupport.solve(cs, 80, [new ShrinkOpportunity(2, 2, 5, ShrinkChannel.RawAdvance)], null, true, null,
            ParagraphDpLineBreakerTestSupport.opportunities([2, 3], [new TextRange(0, 5), new TextRange(0, 5)],
                [ProgressiveBreakTier.Emergency, ProgressiveBreakTier.Emergency]),
            null, [], 8.0);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 2), s.lines[0].clusterRange);
        TracedAssertions.assertTrue(s.lines[0].repair != null
            && StringTools.startsWith(RepairOptions.reason(s.lines[0].repair), "LineAdjustmentPushIn"));
    }

    public static function tilesAllClustersInOrder():Void {
        rec("tilesAllClustersInOrder");
        var s = ParagraphDpLineBreakerTestSupport.solveTestDefaults(ParagraphDpLineBreakerTestSupport.han(23), 100);
        ParagraphDpLineBreakerTestSupport.tiles(s, 23);
        TracedAssertions.assertEqualsRendered("ParagraphEnd", Std.string(s.lines[s.lines.length - 1].endReason));
    }

    public static function singleLineWhenEverythingFits():Void {
        rec("singleLineWhenEverythingFits");
        var s = ParagraphDpLineBreakerTestSupport.solveTestDefaults(ParagraphDpLineBreakerTestSupport.han(4), 400);
        TracedAssertions.assertEqualsInt(1, s.lines.length);
        TracedAssertions.assertEqualsRendered("ParagraphEnd", Std.string(s.lines[0].endReason));
    }

    public static function mandatoryBreakBindsControlToPreviousLine():Void {
        rec("mandatoryBreakBindsControlToPreviousLine");
        var cs = [c(0, "中", 16), c(1, "中", 16), c(2, "\n", 0), c(3, "中", 16), c(4, "中", 16)];
        var s = ParagraphDpLineBreakerTestSupport.solveTestDefaults(cs, 200, null, [2]);
        ParagraphDpLineBreakerTestSupport.tiles(s, 5);
        TracedAssertions.assertEqualsInt(2, s.lines.length);
        TracedAssertions.assertEqualsRendered("MandatoryBreak", Std.string(s.lines[0].endReason));
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 2), s.lines[0].clusterRange);
        TracedAssertions.assertEqualsRendered("ParagraphEnd", Std.string(s.lines[1].endReason));
    }

    public static function trailingMandatoryBreakEmitsParagraphEndLine():Void {
        rec("trailingMandatoryBreakEmitsParagraphEndLine");
        var s = ParagraphDpLineBreakerTestSupport.solveTestDefaults([c(0, "中", 16), c(1, "\n", 0)], 200, null, [1]);
        TracedAssertions.assertEqualsRendered("MandatoryBreak", Std.string(s.lines[0].endReason));
        TracedAssertions.assertEqualsRendered("ParagraphEnd", Std.string(s.lines[s.lines.length - 1].endReason));
        TracedAssertions.assertTrue(s.lines[s.lines.length - 1].clusterRange.start > s.lines[s.lines.length - 1].clusterRange.end);
    }

    public static function neverBreaksInsideUnbreakableRange():Void {
        rec("neverBreaksInsideUnbreakableRange");
        var s = ParagraphDpLineBreakerTestSupport.solveTestDefaults(ParagraphDpLineBreakerTestSupport.han(10), 64, null, null, null,
            new UnbreakableRanges([new IntRange(3, 6)]));
        ParagraphDpLineBreakerTestSupport.tiles(s, 10);
        for (l in s.lines)
            if (l.clusterRange.start <= l.clusterRange.end)
                TracedAssertions.assertTrue(!(l.clusterRange.start >= 4 && l.clusterRange.start <= 6),
                    "break inside unbreakable range: "
                    + l.clusterRange.start
                    + ".."
                    + l.clusterRange.end);
    }

    public static function kinsokuAvoidanceRoutesAroundForbiddenLineStart():Void {
        rec("kinsokuAvoidanceRoutesAroundForbiddenLineStart");
        var cs = ParagraphDpLineBreakerTestSupport.han(7);
        cs[6] = c(6, "。", 16);
        var s = ParagraphDpLineBreakerTestSupport.solveTestDefaults(cs, 48, null, null, null, null, null, [6]);
        ParagraphDpLineBreakerTestSupport.tiles(s, 7);
        for (l in s.lines)
            if (l.clusterRange.start <= l.clusterRange.end)
                TracedAssertions.assertTrue(l.clusterRange.start != 6 || l.repair != null, "。 must not start a line without a recorded repair");
    }

    public static function compressionEdgeRecordsPushInRepair():Void {
        rec("compressionEdgeRecordsPushInRepair");
        var cs = ParagraphDpLineBreakerTestSupport.han(7);
        cs[3] = c(3, "，", 16);
        var s = ParagraphDpLineBreakerTestSupport.solveTestDefaults(cs, 56, [new ShrinkOpportunity(3, 5, 8, ShrinkChannel.TrailingGlue)], null, true);
        ParagraphDpLineBreakerTestSupport.tiles(s, 7);
        var compressed:Null<LineCandidate> = null;
        for (l in s.lines) {
            if (compressed == null && ParagraphDpLineBreakerTestSupport.pushInReason(l.repair) != null)
                compressed = l;
        }
        if (compressed == null) {
            TracedAssertions.assertTrue(false, "expected a PushIn-compressed line, got " + ParagraphDpLineBreakerTestSupport.repairsString(s));
            return;
        }
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 3), compressed.clusterRange);
        TracedAssertions.assertTrue(compressed.adjustedWidth <= 56.0 + 0.01, "compressed line must fit the measure");
        TracedAssertions.assertTrue(StringTools.startsWith(ParagraphDpLineBreakerTestSupport.pushInReason(compressed.repair), "LineAdjustmentPushIn"),
            "compression must be recorded as the fill-pass reason code");
    }

    public static function compressionDisabledWithoutPushInFlag():Void {
        rec("compressionDisabledWithoutPushInFlag");
        var cs = ParagraphDpLineBreakerTestSupport.han(5);
        cs[3] = c(3, "，", 16);
        var s = ParagraphDpLineBreakerTestSupport.solveTestDefaults(cs, 56, [new ShrinkOpportunity(3, 5, 8, ShrinkChannel.TrailingGlue)], null, false);
        ParagraphDpLineBreakerTestSupport.tiles(s, 5);
        var none = true;
        for (l in s.lines) {
            var r = ParagraphDpLineBreakerTestSupport.pushInReason(l.repair);
            if (r != null && StringTools.startsWith(r, "LineAdjustmentPushIn"))
                none = false;
        }
        TracedAssertions.assertTrue(none, "PushOutOnly must not produce fill push-ins");
    }

    public static function overWideSingleClusterStillProgresses():Void {
        rec("overWideSingleClusterStillProgresses");
        var s = ParagraphDpLineBreakerTestSupport.solveTestDefaults([c(0, "中", 16), c(1, "Ｗ", 300), c(2, "中", 16)], 48);
        ParagraphDpLineBreakerTestSupport.tiles(s, 3);
    }
}
