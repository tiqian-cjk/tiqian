package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.LineBreaker.GreedyLineBreaker;
import org.tiqian.layout.LineBreaker.LookaheadLineBreaker;
import org.tiqian.layout.ParagraphDpLineBreaker.ParagraphDpLineBreaker;
import org.tiqian.layout.PreparedParagraph.PreparedParagraphFns;
import StringTools;

class PreparedParagraphRenderEvidenceTest {
    @:test public static function plainParagraphEvidenceIsAppendOnly():Void {
        final t = new TestTraceRecorder("PreparedParagraphRenderEvidenceTest");
        t.section("plainParagraphEvidenceIsAppendOnly");
        final a = PreparedParagraphRenderEvidenceTestSupport.layout(new LayoutInput(new TiqianTextContent("中文段落纯文本测试"), null, null,
            new LayoutConstraints(200)));
        final ap = PreparedParagraphRenderEvidenceTestSupport.plain(a);
        final ae = PreparedParagraphRenderEvidenceTestSupport.evidence(a);
        TracedAssertions.assertTrue(StringTools.startsWith(ae, ap.substr(0, ap.length - 1)));
        final r = PreparedParagraphRenderEvidenceTestSupport.layout(new LayoutInput(new TiqianTextContent("中文段落，含标点与替换破折号——测试。"), null, null,
            new LayoutConstraints(200)));
        final p = PreparedParagraphRenderEvidenceTestSupport.plain(r);
        final e = PreparedParagraphRenderEvidenceTestSupport.evidence(r);
        TracedAssertions.assertFalse(p.indexOf("\"fontSize\"") >= 0);
        TracedAssertions.assertFalse(p.indexOf("\"rubyDecisions\"") >= 0);
        TracedAssertions.assertFalse(p.indexOf("\"dashStrategy\"") >= 0);
        TracedAssertions.assertTrue(e.indexOf("\"schema\":1,") >= 0);
        TracedAssertions.assertTrue(e.indexOf("\"fontSize\":") >= 0);
        TracedAssertions.assertTrue(e.indexOf("\"overlayWidth\":") >= 0);
    }

    @:test public static function pinyinRubyEmitsRubyDecisions():Void {
        final t = new TestTraceRecorder("PreparedParagraphRenderEvidenceTest");
        t.section("pinyinRubyEmitsRubyDecisions");
        final r = PreparedParagraphRenderEvidenceTestSupport.layout(new LayoutInput(new TiqianTextContent("北京是首都。"), null, null, new LayoutConstraints(200),
            null, null, [new RubySpan(new TextRange(0, 2), "Běijīng")], null));
        final p = PreparedParagraphRenderEvidenceTestSupport.plain(r);
        final e = PreparedParagraphRenderEvidenceTestSupport.evidence(r);
        TracedAssertions.assertFalse(p.indexOf("rubyDecisions") >= 0);
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"rubyDecisions\":[", "missing rubyDecisions");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"baseRangeStart\":0", "baseRangeStart");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"baseRangeEnd\":2", "baseRangeEnd");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"text\":\"Běijīng\"", "text");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"centerX\":", "centerX");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"baselineY\":", "baselineY");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"fontSize\":", "fontSize");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"ascent\":", "ascent");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"fontWeight\":500", "fontWeight");
    }

    @:test public static function bopomofoRubyEmitsBopomofoDecisions():Void {
        final t = new TestTraceRecorder("PreparedParagraphRenderEvidenceTest");
        t.section("bopomofoRubyEmitsBopomofoDecisions");
        final r = PreparedParagraphRenderEvidenceTestSupport.layout(new LayoutInput(new TiqianTextContent("好文。"), null, null, new LayoutConstraints(200),
            null, null, [new RubySpan(new TextRange(0, 1), "ㄏㄠˇ", RubyKind.Bopomofo)], null));
        final p = PreparedParagraphRenderEvidenceTestSupport.plain(r);
        final e = PreparedParagraphRenderEvidenceTestSupport.evidence(r);
        TracedAssertions.assertFalse(p.indexOf("bopomofoDecisions") >= 0);
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"bopomofoDecisions\":[", "bopomofo");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"placements\":[", "placements");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"role\":\"", "role");
        TracedAssertions.assertFalse(e.indexOf("\"rubyDecisions\"") >= 0);
    }

    @:test public static function decorationsEmitSegmentsDotsAndRanges():Void {
        final t = new TestTraceRecorder("PreparedParagraphRenderEvidenceTest");
        t.section("decorationsEmitSegmentsDotsAndRanges");
        final r = PreparedParagraphRenderEvidenceTestSupport.layout(new LayoutInput(new TiqianTextContent("鲁迅的小说在中国现代文学里很重要。"), null, null,
            new LayoutConstraints(200), null, [
                new DecorationSpan(new TextRange(0, 2), DecorationKind.ProperNoun),
                new DecorationSpan(new TextRange(3, 5), DecorationKind.BookTitle),
                new DecorationSpan(new TextRange(6, 9), DecorationKind.Emphasis)
            ], null, null));
        final p = PreparedParagraphRenderEvidenceTestSupport.plain(r);
        final e = PreparedParagraphRenderEvidenceTestSupport.evidence(r);
        TracedAssertions.assertFalse(p.indexOf("decorationSegments") >= 0);
        TracedAssertions.assertFalse(p.indexOf("emphasisDots") >= 0);
        TracedAssertions.assertFalse(p.indexOf("emphasisRanges") >= 0);
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"decorationSegments\":[", "segments");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"kind\":\"ProperNoun\"", "kind");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"kind\":\"BookTitle\"", "kind");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"sourceRangeStart\":0", "range");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"emphasisRanges\":[[6,9]]", "ranges");
        if (e.indexOf("\"emphasisDots\"") >= 0) {
            PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"anchorX\":", "anchor");
            PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"dotDiameter\":", "diameter");
        }
    }

    @:test public static function styleDeltaEmitsPerCellStyleBlock():Void {
        final t = new TestTraceRecorder("PreparedParagraphRenderEvidenceTest");
        t.section("styleDeltaEmitsPerCellStyleBlock");
        final r = PreparedParagraphRenderEvidenceTestSupport.layout(new LayoutInput(new TiqianTextContent("普通字与小字混排的段落。",
            [new TextSpan(new TextRange(4, 6), new TextStyle(12, null, 700))]), null, null, new LayoutConstraints(200)));
        final p = PreparedParagraphRenderEvidenceTestSupport.plain(r);
        final e = PreparedParagraphRenderEvidenceTestSupport.evidence(r);
        TracedAssertions.assertFalse(p.indexOf("\"style\":{") >= 0);
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"style\":{\"fontSize\":", "style");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"fontWeight\":700", "weight");
    }

    @:test public static function inlineBoxesEmitInlineEdges():Void {
        final t = new TestTraceRecorder("PreparedParagraphRenderEvidenceTest");
        t.section("inlineBoxesEmitInlineEdges");
        final r = PreparedParagraphRenderEvidenceTestSupport.layout(new LayoutInput(new TiqianTextContent("文字与边距。"), null, null, new LayoutConstraints(200),
            null, null, null, [new InlineBoxSpan(new TextRange(0, 1), 2, 3)]));
        final p = PreparedParagraphRenderEvidenceTestSupport.plain(r);
        final e = PreparedParagraphRenderEvidenceTestSupport.evidence(r);
        TracedAssertions.assertFalse(p.indexOf("inlineEdges") >= 0);
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"inlineEdges\":[", "edges");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"offset\":0", "offset");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"offset\":1", "offset");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"inlineStart\":2", "start");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"inlineEnd\":3", "end");
    }
}
