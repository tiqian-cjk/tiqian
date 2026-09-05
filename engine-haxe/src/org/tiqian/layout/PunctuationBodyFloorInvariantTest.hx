package org.tiqian.layout;

import org.tiqian.core.Ic;
import org.tiqian.core.LayoutConstraints;
import org.tiqian.core.LayoutInput;
import org.tiqian.core.ParagraphStyle;
import org.tiqian.core.TiqianTextContent;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.test.trace.TestTraceRender;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.TestHelpers;
import org.tiqian.test.trace.TracedAssertions;

class PunctuationBodyFloorInvariantTest {
    @:test public static function punctuationNeverResolvesBelowItsBodyWidth():Void {
        final t = new TestTraceRecorder("PunctuationBodyFloorInvariantTest");
        t.section("punctuationNeverResolvesBelowItsBodyWidth");
        final fixtures = [
            "中文，中文。",
            "他说：“你好，世界。”！！",
            "中（中文）文中文中文中",
            "有人说：「先有咖啡馆，后有启蒙运动」。每座城市、每条街巷、每个清晨都有人在等一杯 espresso……这并不是巧合。",
            "读报、辩论、下棋、写作——城市生活忽然多出一个公共客厅。"
        ];
        final widths = [48.0, 64.0, 80.0, 100.0, 160.0, 320.0];
        final engine = new ExplainableStubParagraphLayoutEngine();
        for (text in fixtures)
            for (maxWidth in widths) {
                final result = engine.layout(new LayoutInput(new TiqianTextContent(text), null, new ParagraphStyle(null, null, null, Ic.Zero),
                    new LayoutConstraints(maxWidth)));
                for (i in 0...result.debug.geometryDecisions.length) {
                    final geometry = result.debug.geometryDecisions[i];
                    TracedAssertions.assertTrue(geometry.resolvedAdvance >= geometry.bodyWidth - 1e-3,
                        "Body floor violated for '"
                        + geometry.sourceText
                        + "' ("
                        + geometry.range.start
                        + "-"
                        + geometry.range.end
                        + ") in \""
                        + text
                        + "\" @maxWidth="
                        + maxWidth
                        + ": resolved="
                        + TestTraceRender.floatText(geometry.resolvedAdvance)
                        + " < body="
                        + TestTraceRender.floatText(geometry.bodyWidth));
                }
            }
    }
}
