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

    @:test public static function spacingCarrierAdvanceFollowsShapedSegments():Void {
        final t = new TestTraceRecorder("PreparedParagraphRenderEvidenceTest");
        t.section("spacingCarrierAdvanceFollowsShapedSegments");
        final unprobed = PreparedParagraphRenderEvidenceTestSupport.layout(new LayoutInput(new TiqianTextContent("中文 Latin words 混排段落测试。"), null,
            null, new LayoutConstraints(120)));
        TracedAssertions.assertEquals(0, unprobed.debug.spacingCarrierAdvanceDecisions.length, "the default engine skips the carrier probe");
        final r = PreparedParagraphRenderEvidenceTestSupport.layoutWithSpacingCarrierProbe(new LayoutInput(new TiqianTextContent("中文 Latin words 混排段落测试。"),
            null, null, new LayoutConstraints(120)));
        final records = r.debug.spacingCarrierAdvanceDecisions;
        TracedAssertions.assertTrue(records.length > 0, "carrier advance records");
        var previousEnd = 0;
        for (i in 0...records.length) {
            final record = records[i];
            TracedAssertions.assertTrue(record.range.start >= previousEnd, "records ordered without overlap");
            TracedAssertions.assertTrue(record.advance >= 0, "carrier advance non-negative");
            TracedAssertions.assertEqualsString("SpacingCarrierNoBreakSpaceAdvance", record.reason, "carrier reason");
            previousEnd = record.range.end;
        }
        final p = PreparedParagraphRenderEvidenceTestSupport.plain(r);
        final e = PreparedParagraphRenderEvidenceTestSupport.evidence(r);
        PreparedParagraphRenderEvidenceTestSupport.contains(p, "\"spacingCarrierAdvances\":[", "plain spacingCarrierAdvances");
        PreparedParagraphRenderEvidenceTestSupport.contains(e, "\"spacingCarrierAdvances\":[", "evidence spacingCarrierAdvances");
        final plan = PlanLowering.toPlan(r, true);
        TracedAssertions.assertEquals(records.length, plan.spacingCarrierAdvances.length, "plan carries every carrier record");
        TracedAssertions.assertEquals(records.length, PlanLowering.toPlan(r, false).spacingCarrierAdvances.length, "plain plan carries the carrier table");
        var latinCells = 0;
        for (li in 0...plan.lines.length) {
            for (ci in 0...plan.lines[li].cells.length) {
                final cell = plan.lines[li].cells[ci];
                if (!cell.latin)
                    continue;
                latinCells += 1;
                var covered = false;
                for (i in 0...records.length) {
                    if (records[i].range.start <= cell.rangeStart && cell.rangeEnd <= records[i].range.end)
                        covered = true;
                }
                TracedAssertions.assertTrue(covered, "latin cell " + cell.rangeStart + "-" + cell.rangeEnd + " has a carrier advance");
            }
        }
        TracedAssertions.assertTrue(latinCells > 0, "fixture has latin cells");
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
            null, null, [new RubySpan(new TextRange(0, 1), "ㄏㄠˇ", RubyKind.Bopomofo, "zh-TW")], null));
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

    public static function flushTestTrace():Void {
        TestTraceRecorder.flushClass("PreparedParagraphRenderEvidenceTest");
    }
}
