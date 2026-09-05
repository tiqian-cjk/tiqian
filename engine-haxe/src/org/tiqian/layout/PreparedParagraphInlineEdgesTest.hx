package org.tiqian.layout;

import org.tiqian.core.Ic;
import org.tiqian.core.InlineBoxSpan;
import org.tiqian.core.LayoutConstraints;
import org.tiqian.core.LayoutInput;
import org.tiqian.core.LayoutResult;
import org.tiqian.core.ParagraphStyle;
import org.tiqian.core.TextRange;
import org.tiqian.core.TiqianTextContent;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.PreparedParagraph.PreparedParagraphFns;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class PreparedParagraphInlineEdgesTest {
    public static function contentWithoutInlineBoxesOmitsInlineEdgesArray():Void {
        final t = new TestTraceRecorder("PreparedParagraphInlineEdgesTest");
        t.section("contentWithoutInlineBoxesOmitsInlineEdgesArray");
        final result:LayoutResult = new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent("中文正文"), null,
            new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(320)));
        final json = PreparedParagraphFns.toPreparedParagraphJson(result, true);
        TracedAssertions.assertFalse(json.indexOf("\"inlineEdges\":") >= 0, "no boxes, no edges: " + json);
    }

    public static function endOnlyInlineBoxEmitsEdgeWithoutInlineStartField():Void {
        final t = new TestTraceRecorder("PreparedParagraphInlineEdgesTest");
        t.section("endOnlyInlineBoxEmitsEdgeWithoutInlineStartField");
        final result:LayoutResult = new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent("中文正文"), null,
            new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(320), null, null, null, [new InlineBoxSpan(new TextRange(0, 2), 0, 4)]));
        final json = PreparedParagraphFns.toPreparedParagraphJson(result, true);
        final edgesAt = json.indexOf("\"inlineEdges\":[");
        TracedAssertions.assertTrue(edgesAt >= 0, "inlineEdges array missing: " + json);
        final entry = json.substring(edgesAt);
        TracedAssertions.assertTrue(entry.indexOf("\"offset\":2") >= 0, "edge offset (box end) missing: " + entry);
        TracedAssertions.assertTrue(entry.indexOf("\"inlineEnd\":4") >= 0, "inlineEnd field missing: " + entry);
        TracedAssertions.assertFalse(entry.indexOf("\"inlineStart\":") >= 0, "inlineStart must be absent for an end-only box: " + entry);
    }
}
