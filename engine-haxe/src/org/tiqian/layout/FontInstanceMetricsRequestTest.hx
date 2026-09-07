package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.font.FontMetrics.FontMetricsRequest;
import org.tiqian.font.FontMetrics.FontMetricsResolver;
import org.tiqian.font.RawFontMetrics;
import org.tiqian.font.FontMetrics.StubFontMetricsResolver;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.font.FontRole;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class FontInstanceMetricsRequestTest {
    @:test public static function perSpanWeightAndItalicReachTheMetricsResolver():Void {
        final t = new TestTraceRecorder("FontInstanceMetricsRequestTest");
        t.section("perSpanWeightAndItalicReachTheMetricsResolver");
        final requests:Array<FontMetricsRequest> = [];
        final base = FontInstanceMetricsRequestTestSupport.baseStyle();
        FontInstanceMetricsRequestTestSupport.recordingEngine(requests).layout(new LayoutInput(new TiqianTextContent("中A", [
            new TextSpan(new TextRange(1, 2), new TextStyle(["Fixture Sans"], 18.0, null, 700, true))
        ]), base, null, new LayoutConstraints(180.0)));
        var cjk = false;
        var latin = false;
        for (r in requests) {
            if (r.role == FontRole.CjkText && r.fontWeight == 400 && !r.italic && r.faceSelectionText == "中")
                cjk = true;
            if (r.role == FontRole.LatinText && r.fontWeight == 700 && r.italic && r.faceSelectionText == "A")
                latin = true;
        }
        TracedAssertions.assertTrue(cjk);
        TracedAssertions.assertTrue(latin);
    }

    @:test public static function faceSelectionUsesTheDisplayTextThatWasActuallyShaped():Void {
        final t = new TestTraceRecorder("FontInstanceMetricsRequestTest");
        t.section("faceSelectionUsesTheDisplayTextThatWasActuallyShaped");
        final requests:Array<FontMetricsRequest> = [];
        FontInstanceMetricsRequestTestSupport.recordingEngine(requests)
            .layout(new LayoutInput(new TiqianTextContent("——"), new TextStyle(["Fixture Sans"], 18.0), null, new LayoutConstraints(180.0)));
        var found = false;
        for (r in requests)
            if (r.faceSelectionText == "⸺")
                found = true;
        TracedAssertions.assertTrue(found);
    }

    @:test public static function rubyMetricsUseTheSameItalicInstanceAsRubyShaping():Void {
        final t = new TestTraceRecorder("FontInstanceMetricsRequestTest");
        t.section("rubyMetricsUseTheSameItalicInstanceAsRubyShaping");
        final requests:Array<FontMetricsRequest> = [];
        FontInstanceMetricsRequestTestSupport.recordingEngine(requests)
            .layout(new LayoutInput(new TiqianTextContent("中"), new TextStyle(["Fixture Sans"], 18.0, null, 400, true), null, new LayoutConstraints(180.0),
                null, null, [new RubySpan(new TextRange(0, 1), "zhōng")], null, null));
        var found = false;
        for (r in requests)
            if (r.role == FontRole.LatinText && r.faceSelectionText == "zhōng" && r.italic)
                found = true;
        TracedAssertions.assertTrue(found);
    }
}
