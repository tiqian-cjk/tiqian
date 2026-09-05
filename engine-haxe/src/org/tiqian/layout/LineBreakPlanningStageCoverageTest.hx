package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.test.trace.*;
import std.UString;

class LineBreakPlanningStageCoverageTest {
    @:test public static function pushOutFirstTakesFewerFillPushInsThanPushInFirst():Void {
        final t = new TestTraceRecorder("LineBreakPlanningStageCoverageTest");
        t.section("pushOutFirstTakesFewerFillPushInsThanPushInFirst");
        final text = "咖啡（coffee）在十七世纪经威尼斯传入欧洲。最初它被当作药物出售，价格高得吓人，真正让它流行起来的是随后遍地开花的咖啡馆——读报、辩论、下棋、写作——城市生活忽然多出一个公共客厅。意大利人做出了 espresso，维也纳人往杯里加奶油，土耳其人坚持连渣同煮……每座城市都相信自己手里那一杯才是正统。有人说：「先有咖啡馆，后有启蒙运动」。这话说得夸张，但也不算太离谱。";
        final a = LineBreakPlanningStageCoverageTestSupport.layoutWithDefaultStyle(text, 320, LineAdjustmentStrategy.PushInFirst);
        final b = LineBreakPlanningStageCoverageTestSupport.layoutWithDefaultStyle(text, 320, LineAdjustmentStrategy.PushOutFirst);
        TracedAssertions.assertTrue(LineBreakPlanningStageCoverageTestSupport.fillPushInCount(a) > 0,
            LineBreakPlanningStageCoverageTestSupport.renderDecisions(a));
        TracedAssertions.assertTrue(LineBreakPlanningStageCoverageTestSupport.fillPushInCount(b) <= LineBreakPlanningStageCoverageTestSupport.fillPushInCount(a),
            "PushOutFirst "
            + LineBreakPlanningStageCoverageTestSupport.fillPushInCount(b)
            + " vs PushInFirst "
            + LineBreakPlanningStageCoverageTestSupport.fillPushInCount(a));
        TracedAssertions.assertTrue(b.lines.length >= a.lines.length, "PushOutFirst " + b.lines.length + " vs PushInFirst " + a.lines.length);
    }

    @:test public static function explicitZeroLineHeightKeepsTheControlParagraphAtZeroHeight():Void {
        final t = new TestTraceRecorder("LineBreakPlanningStageCoverageTest");
        t.section("explicitZeroLineHeightKeepsTheControlParagraphAtZeroHeight");
        final r = LineBreakPlanningStageCoverageTestSupport.layout("\n", 100, null, 0);
        TracedAssertions.assertEquals(2, r.lines.length, LineBreakPlanningStageCoverageTestSupport.renderLines(r.lines));
        TracedAssertions.assertEqualsFloat(0, r.size.height, Std.string(r.size.height));
    }

    @:test public static function emergencyBoundaryEligibilitySkipsZeroWidthAndMandatoryControls():Void {
        final t = new TestTraceRecorder("LineBreakPlanningStageCoverageTest");
        t.section("emergencyBoundaryEligibilitySkipsZeroWidthAndMandatoryControls");
        var s = "ab\u200Bcd";
        var r = LineBreakPlanningStageCoverageTestSupport.layout(s, 200, null, null, [
            new LineBreakSpan(new TextRange(0, std.UString.count(s)), LineBreakPolicy.ProgressiveTechnical)
        ]);
        TracedAssertions.assertEquals(1, r.lines.length, LineBreakPlanningStageCoverageTestSupport.renderLines(r.lines));
        r = LineBreakPlanningStageCoverageTestSupport.layout("aa\nbb", 200, null, null,
            [new LineBreakSpan(new TextRange(0, 5), LineBreakPolicy.ProgressiveTechnical)]);
        TracedAssertions.assertEquals(2, r.lines.length, LineBreakPlanningStageCoverageTestSupport.renderLines(r.lines));
    }

    @:test public static function emergencyBoundaryEligibilitySkipsInlineObjectBoundaries():Void {
        final t = new TestTraceRecorder("LineBreakPlanningStageCoverageTest");
        t.section("emergencyBoundaryEligibilitySkipsInlineObjectBoundaries");
        final r = LineBreakPlanningStageCoverageTestSupport.layout("a\uFFFCb", 200, null, null,
            [new LineBreakSpan(new TextRange(0, 3), LineBreakPolicy.ProgressiveTechnical)], [new InlineObjectSpan(new TextRange(1, 2), 16, 8, 8)]);
        TracedAssertions.assertEquals(1, r.lines.length, LineBreakPlanningStageCoverageTestSupport.renderLines(r.lines));
        TracedAssertions.assertTrue(r.lines[0].clusterRange.start == 0);
    }

    @:test public static function dashAndSolidusBoundariesInsideTechnicalSpansNeverStretch():Void {
        final t = new TestTraceRecorder("LineBreakPlanningStageCoverageTest");
        t.section("dashAndSolidusBoundariesInsideTechnicalSpansNeverStretch");
        for (s in ["a\u2014b\u2014c", "a/b/c", "a\u2026b"]) {
            final r = LineBreakPlanningStageCoverageTestSupport.layout(s, 24, null, null, [
                new LineBreakSpan(new TextRange(0, std.UString.count(s)), LineBreakPolicy.ProgressiveTechnical)
            ]);
            TracedAssertions.assertTrue(r.lines.length > 0, s + ": " + LineBreakPlanningStageCoverageTestSupport.renderLines(r.lines));
            var ok = true;
            for (i in 0...r.debug.justificationDecisions.length)
                for (j in 0...r.debug.justificationDecisions[i].allocations.length) {
                    final x = r.debug.justificationDecisions[i].allocations[j];
                    if (x.kind == "EmergencyGraphemeTracking" && x.delta > 0)
                        ok = false;
                }
            TracedAssertions.assertTrue(ok, s + ": " + LineBreakPlanningStageCoverageTestSupport.renderJustification(r.debug.justificationDecisions));
        }
    }

    @:test public static function overlappingTechnicalSpansKeepTheFirstBoundaryReason():Void {
        final t = new TestTraceRecorder("LineBreakPlanningStageCoverageTest");
        t.section("overlappingTechnicalSpansKeepTheFirstBoundaryReason");
        final r = LineBreakPlanningStageCoverageTestSupport.layout("aabbcc", 200, null, null, [
            new LineBreakSpan(new TextRange(0, 4), LineBreakPolicy.ProgressiveTechnical),
            new LineBreakSpan(new TextRange(2, 6), LineBreakPolicy.ProgressiveTechnical)
        ]);
        TracedAssertions.assertEquals(1, r.lines.length, LineBreakPlanningStageCoverageTestSupport.renderLines(r.lines));
    }
}
