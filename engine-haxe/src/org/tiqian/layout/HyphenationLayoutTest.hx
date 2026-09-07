package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.test.trace.*;
import org.tiqian.linebreak.Hyphenator;
import org.tiqian.linebreak.Hyphenator.NoHyphenator;
import org.tiqian.linebreak.EnglishHyphenation;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;

class HyphenationLayoutTest {
    @:test public static function fittingWordHyphenatesOnlyWhenAHyphenatorIsInjected():Void {
        final t = new TestTraceRecorder("HyphenationLayoutTest");
        t.section("fittingWordHyphenatesOnlyWhenAHyphenatorIsInjected");
        final n = HyphenationLayoutTestSupport.layoutWith(new NoHyphenator(), "中文中 coffee", 112);
        final h = HyphenationLayoutTestSupport.layoutWith(EnglishHyphenation.enUs(), "中文中 coffee", 112);
        var nc = false;
        var nh = true;
        var hc = false;
        var cof = false;
        var fee = false;
        var hh = false;
        for (i in 0...n.clusters.length)
            if (n.clusters[i].text == "coffee")
                nc = true;
        for (i in 0...n.lines.length)
            if (n.lines[i].hyphenAdvance > 0)
                nh = false;
        for (i in 0...h.clusters.length) {
            if (h.clusters[i].text == "coffee")
                hc = true;
            if (h.clusters[i].text == "cof")
                cof = true;
            if (h.clusters[i].text == "fee")
                fee = true;
        }
        for (i in 0...h.lines.length)
            if (h.lines[i].hyphenAdvance > 0)
                hh = true;
        TracedAssertions.assertTrue(nc);
        TracedAssertions.assertTrue(nh);
        TracedAssertions.assertTrue(!hc);
        TracedAssertions.assertTrue(cof);
        TracedAssertions.assertTrue(fee);
        TracedAssertions.assertTrue(hh, "no line hyphenated");
    }

    @:test public static function hyphenIsReservedWithinTheMeasureNotHungPastIt():Void {
        final t = new TestTraceRecorder("HyphenationLayoutTest");
        t.section("hyphenIsReservedWithinTheMeasureNotHungPastIt");
        final h = HyphenationLayoutTestSupport.layoutWith(EnglishHyphenation.enUs(), "请运行 internationalization 命令", 160);
        var line:LineBox = h.lines[0];
        for (i in 0...h.lines.length)
            if (h.lines[i].hyphenAdvance > 0) {
                line = h.lines[i];
                break;
            }
        TracedAssertions.assertTrue(line.indent
            + line.visualWidth
            + line.hyphenAdvance <= 160 + 0.01,
            "hyphen hung past the measure: "
            + (line.indent + line.visualWidth + line.hyphenAdvance));
    }

    @:test public static function hyphenationIsOnByDefault():Void {
        final t = new TestTraceRecorder("HyphenationLayoutTest");
        t.section("hyphenationIsOnByDefault");
        final r:LayoutResult = new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent("中文中 coffee"), null,
            new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(112)));
        var cof = false;
        var fee = false;
        var hy = false;
        for (i in 0...r.clusters.length) {
            if (r.clusters[i].text == "cof")
                cof = true;
            if (r.clusters[i].text == "fee")
                fee = true;
        }
        for (i in 0...r.lines.length)
            if (r.lines[i].hyphenAdvance > 0)
                hy = true;
        TracedAssertions.assertTrue(cof);
        TracedAssertions.assertTrue(fee);
        TracedAssertions.assertTrue(hy);
    }

    @:test public static function hyphenationIsSkippedWhenStretchingCjkStaysTight():Void {
        final t = new TestTraceRecorder("HyphenationLayoutTest");
        t.section("hyphenationIsSkippedWhenStretchingCjkStaysTight");
        final r:LayoutResult = new ExplainableStubParagraphLayoutEngine(null, null,
            HyphenationLayoutTestSupport.pushOutResolver()).layout(new LayoutInput(new TiqianTextContent("中文中文中文中文 coffee"), null,
                new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(180)));
        var hy = false;
        for (i in 0...r.lines.length)
            if (r.lines[i].hyphenAdvance > 0)
                hy = true;
        TracedAssertions.assertTrue(!hy, "should not hyphenate when tight");
    }

    @:test public static function reservedHyphenSqueezesPunctuationGlueToPullItIn():Void {
        final t = new TestTraceRecorder("HyphenationLayoutTest");
        t.section("reservedHyphenSqueezesPunctuationGlueToPullItIn");
        final r = HyphenationLayoutTestSupport.layoutWith(EnglishHyphenation.enUs(), "中文，internationalization", 128);
        var c:Cluster = r.clusters[0];
        for (i in 0...r.clusters.length)
            if (r.clusters[i].text == "，")
                c = r.clusters[i];
        TracedAssertions.assertTrue(c.advance < 16, "comma glue not compressed for the hyphen: " + c.advance);
    }

    @:test public static function syllableSplitMatchesTheHyphenatorExactly():Void {
        final t = new TestTraceRecorder("HyphenationLayoutTest");
        t.section("syllableSplitMatchesTheHyphenatorExactly");
        final word = "internationalization";
        final r = HyphenationLayoutTestSupport.layoutWith(EnglishHyphenation.enUs(), HyphenationLayoutTestSupport.TEXT, 160);
        final parts:Array<String> = [];
        for (i in 0...r.clusters.length)
            if (r.clusters[i].text != "" && HyphenationLayoutTestSupport.isLatin(r.clusters[i].text))
                parts.push(r.clusters[i].text);
        TracedAssertions.assertEqualsString(HyphenationLayoutTestSupport.rebuild(word, EnglishHyphenation.enUs().hyphenate(word)), parts.join("-"));
    }
}
