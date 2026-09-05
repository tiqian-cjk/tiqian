package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.test.trace.*;
import org.tiqian.layout.LineAdjustmentStageJfTestSupport.DashBoundsShaper;
import org.tiqian.shaping.TextShaper.ITextShaper;

class LineAdjustmentStageJfTest {
    @:test public static function dashInkCenteringWithShapedBounds():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageJfTest");
        t.section("dashInkCenteringWithShapedBounds");
        final r = LineAdjustmentStageJfTestSupport.layout("中——中", 200, null, false, new DashBoundsShaper(false));
        final x = r.glyphRuns[0].glyphs.length > 1 ? r.glyphRuns[0].glyphs[1].x : r.glyphRuns[0].glyphs[0].x;
        TracedAssertions.assertEqualsFloat(1, x);
    }

    @:test public static function dashInkCenteringWithWideBoundsReturnsSameGlyph():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageJfTest");
        t.section("dashInkCenteringWithWideBoundsReturnsSameGlyph");
        final r = LineAdjustmentStageJfTestSupport.layout("中——中", 200, null, false, new DashBoundsShaper(true));
        final x = r.glyphRuns[0].glyphs.length > 1 ? r.glyphRuns[0].glyphs[1].x : r.glyphRuns[0].glyphs[0].x;
        TracedAssertions.assertEqualsFloat(0, x);
    }

    @:test public static function hyphenSqueezeConsumesPairedLeadingAndTrailingGlueUnderTaiwanProfile():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageJfTest");
        t.section("hyphenSqueezeConsumesPairedLeadingAndTrailingGlueUnderTaiwanProfile");
        final r = LineAdjustmentStageJfTestSupport.layout("中文，文internationalization", 112, null, true, null, ClreqProfile.TaiwanHorizontal);
        var a = 0.0;
        for (i in 0...r.clusters.length)
            if (r.clusters[i].text == "，") {
                a = r.clusters[i].advance;
                break;
            }
        TracedAssertions.assertTrue(a < 16, "Comma advance should have shrunk: " + a);
    }

    @:test public static function inlineObjectSeparatorSpaceTrimEdge():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageJfTest");
        t.section("inlineObjectSeparatorSpaceTrimEdge");
        final o = [new InlineObjectSpan(new TextRange(1, 2), 16, 12, 12)];
        final r = LineAdjustmentStageJfTestSupport.layout("中\uFFFC ，文文", 34, o);
        TracedAssertions.assertTrue(r.lines.length > 1);
    }

    @:test public static function inlineObjectWithZeroDiscardableAdvance():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageJfTest");
        t.section("inlineObjectWithZeroDiscardableAdvance");
        final o = [
            new InlineObjectSpan(new TextRange(1, 2), 24, 12, 12, null, new InlineObjectBoundaryAdjustment(null, null, null, 0, null))
        ];
        final r = LineAdjustmentStageJfTestSupport.layout("甲\uFFFC乙丙丁戊", 48, o);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 1), r.lines[0].clusterRange);
    }
}
