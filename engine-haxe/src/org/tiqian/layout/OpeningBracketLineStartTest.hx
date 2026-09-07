package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class OpeningBracketLineStartTest {
    @:test public static function testOpeningBracketAtLineStartCompression():Void {
        final t = new TestTraceRecorder("OpeningBracketLineStartTest");
        t.section("testOpeningBracketAtLineStartCompression");
        final text = "这是第一行测试文字这是第一行测试\n（Shaping & Font Metrics）这是第二行文字\n（GPOS / GSUB 特性表查询）这是第三行文字";
        final result = new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent(text), null,
            new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(672.0)));
        TracedAssertions.assertEqualsInt(3, result.lines.length);
        final line1 = result.clusters[result.lines[1].clusterRange.start];
        final line2 = result.clusters[result.lines[2].clusterRange.start];
        TracedAssertions.assertEqualsString("（", line1.text);
        TracedAssertions.assertEqualsFloatTolerance(8.0, line1.advance, 0.01);
        TracedAssertions.assertEqualsString("（", line2.text);
        TracedAssertions.assertEqualsFloatTolerance(8.0, line2.advance, 0.01);
        var count = 0;
        var all = true;
        for (i in 0...result.debug.lineEdgeTrimDecisions.length) {
            final d = result.debug.lineEdgeTrimDecisions[i];
            if (d.reason == "LineStartHalfWidthPunctuation") {
                count++;
                if (!(d.side == "leading" && d.trimAmount == 8.0))
                    all = false;
            }
        }
        TracedAssertions.assertEqualsInt(2, count);
        TracedAssertions.assertTrue(all);
    }
}
