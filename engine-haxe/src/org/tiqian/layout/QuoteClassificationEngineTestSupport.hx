package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.core.RoleOverrideInfo;
import org.tiqian.core.PunctuationDecisionInfo;
import std.UString;
import org.tiqian.clreq.*;
import org.tiqian.font.FontRole;
import org.tiqian.shaping.TextShaper.ITextShaper;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.shaping.TextShaper.ExplainableStubTextShaper;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import std.SortedSet;

class QuoteClassificationEngineTestSupport {
    public static function begin(name:String):TestTraceRecorder {
        var t = new TestTraceRecorder("QuoteClassificationEngineTest");
        t.section(name);
        return t;
    }

    public static function arm():TestTraceRecorder {
        return new TestTraceRecorder("QuoteClassificationEngineTest");
    }

    public static function input(text:String, width:Float):LayoutInput
        return new LayoutInput(new TiqianTextContent(text), null, new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(width));

    public static function layout(text:String, width:Float, ?engine:ExplainableStubParagraphLayoutEngine):LayoutResult
        return (engine == null ? new ExplainableStubParagraphLayoutEngine() : engine).layout(input(text, width));

    public static function set(values:Array<Int>):SortedSet<Int> {
        var b = SortedSet.builder();
        for (v in values)
            b.put(v);
        return b.build();
    }

    public static function indices(text:String):Array<Int> {
        var r:Array<Int> = [];
        for (i in 0...text.length)
            if (isCurlyQuoteForTest(text.substring(i, i + 1)))
                r.push(i);
        return r;
    }

    public static function roleAt(result:LayoutResult, index:Int):String {
        for (i in 0...result.debug.fontDecisions.length) {
            var d = result.debug.fontDecisions[i];
            if (index >= d.range.start && index < d.range.end)
                return d.role;
        }
        return "";
    }

    public static function isCurlyQuoteForTest(ch:String):Bool
        return ch == "\u2018" || ch == "\u2019" || ch == "\u201C" || ch == "\u201D";

    public static function lastIndex(text:String, mark:String):Int {
        var result = -1;
        var start = 0;
        while (true) {
            var next = text.indexOf(mark, start);
            if (next < 0)
                return result;
            result = next;
            start = next + 1;
        }
    }

    public static function renderRoleMap(map:std.SortedMap<Int, String>):String {
        var out = "";
        for (i in 0...map.size()) {
            if (i > 0)
                out += ", ";
            out += "" + map.keyAt(i) + "='" + map.valueAt(i) + "'";
        }
        return "{" + out + "}";
    }

    public static function internal(text:String, source:String, role:String, ?section:String):Void {
        var t = section == null ? arm() : begin(section);
        var r = layout(text, 320);
        var a:Array<RoleOverrideInfo> = [];
        for (i in 0...r.debug.roleOverrides.length) {
            var d = r.debug.roleOverrides[i];
            if (d.sourceText == "“" || d.sourceText == "”")
                a.push(d);
        }
        TracedAssertions.assertEquals(2, a.length);
        var all = true;
        for (i in 0...a.length) {
            all = all && a[i].overriddenRole == role && a[i].source == source;
        }
        TracedAssertions.assertTrue(all);
    }

    public static function fullWidthTest():Void {
        var t = begin("requestsFullWidthCjkQuotesAndSynthesizesTheCellWhenTheFontStaysProportional");
        var e = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, new ProportionalQuoteTextShaper());
        var r = e.layout(input("中“文”中", 320));
        var o:Null<Cluster> = null;
        var c:Null<Cluster> = null;
        for (i in 0...r.clusters.length) {
            var x = r.clusters[i];
            if (x.text == "“")
                o = x;
            if (x.text == "”")
                c = x;
        }
        TracedAssertions.assertEqualsFloat(16, o.advance);
        TracedAssertions.assertEqualsFloat(16, c.advance);
        TracedAssertions.assertEqualsFloat(10, o.glyphInlineShift);
        TracedAssertions.assertEqualsFloat(0, c.glyphInlineShift);
        var a:Null<PunctuationDecisionInfo> = null;
        var b:Null<PunctuationDecisionInfo> = null;
        for (i in 0...r.debug.punctuationDecisions.length) {
            var x = r.debug.punctuationDecisions[i];
            if (x.char == "“")
                a = x;
            if (x.char == "”")
                b = x;
        }
        TracedAssertions.assertEqualsFloat(10, a.advanceExpansion);
        TracedAssertions.assertEqualsString("UnderwidthPunctuationFullWidthBoxPlacement", a.glyphPlacementReason);
        TracedAssertions.assertEqualsNullableString(null, b.glyphPlacementReason);
        TracedAssertions.assertEqualsString("InkBoundsFittedBodyCompression", a.geometrySource);
        TracedAssertions.assertEqualsString("InkBoundsFittedBodyCompression", b.geometrySource);
        var p = LayoutQueries.positionedClusters(r);
        var po:PositionedCluster = null;
        var pc:PositionedCluster = null;
        for (i in 0...p.length) {
            var x = p[i];
            if (x.range.start == o.range.start && x.range.end == o.range.end)
                po = x;
            if (x.range.start == c.range.start && x.range.end == c.range.end)
                pc = x;
        }
        TracedAssertions.assertEqualsFloat(po.left + 10, po.drawX);
        TracedAssertions.assertEqualsFloat(pc.left, pc.drawX);
        var q = e.layout(input("“文", 320));
        TracedAssertions.assertEqualsFloat(8, q.clusters[0].advance);
        var qp = LayoutQueries.positionedClusters(q);
        TracedAssertions.assertEqualsFloat(2, qp[0].drawX);
        TracedAssertions.assertEqualsFloat(8, qp[1].left);
    }

    public static function lineReason(r:LineEndReason):String {
        var x:String = "ParagraphEnd";
        switch (r) {
            case AutoWrap:
                x = "AutoWrap";
            case MandatoryBreak:
                x = "MandatoryBreak";
            case ParagraphEnd:
                x = "ParagraphEnd";
        }
        return x;
    }

    public static function startsWith(text:String, range:TextRange, mark:String):Bool {
        var x = UString.slice(text, range.start, range.end);
        var r = false;
        if (x.indexOf(mark) == 0)
            r = true;
        return r;
    }

    public static function endsWith(text:String, range:TextRange, mark:String):Bool {
        var x = UString.slice(text, range.start, range.end);
        return x.lastIndexOf(mark) == x.length - 1;
    }
}

class ProportionalQuoteTextShaper implements ITextShaper {
    private final delegate:ExplainableStubTextShaper;

    public function new()
        delegate = new ExplainableStubTextShaper();

    public function shape(input:ShapingInput):ShapingResult {
        final result = delegate.shape(input);
        if (input.displayText != "\u201C" && input.displayText != "\u201D")
            return result;
        org.tiqian.test.trace.TracedAssertions.assertEqualsStringArray(["fwid=1"], input.openTypeFeatures);
        var clusters:Array<Cluster> = [];
        for (i in 0...result.clusters.length) {
            var c = result.clusters[i];
            clusters.push(new Cluster(c.range, c.text, c.fontKey, 6.0, c.displayText, c.baselineShift, c.leadingLayoutAdvance, c.glyphInlineShift));
        }
        var runs:Array<GlyphRun> = [];
        for (ri in 0...result.glyphRuns.length) {
            var run = result.glyphRuns[ri];
            var gs:Array<Glyph> = [];
            for (gi in 0...run.glyphs.length) {
                var g = run.glyphs[gi];
                gs.push(new Glyph(g.id, g.clusterRange, 6.0, g.x, g.y, g.renderFontKey, new Rect(1, -10, 5, 0), g.haltAdvance, g.haltPlacementX));
            }
            var features:Array<String> = [];
            for (fi in 0...run.openTypeFeatures.length)
                features.push(run.openTypeFeatures[fi]);
            runs.push(new GlyphRun(run.range, run.fontKey, gs, 6.0, features));
        }
        var decisions:Array<ShapingDecisionInfo> = [];
        for (i in 0...result.decisions.length) {
            var d = result.decisions[i];
            decisions.push(new ShapingDecisionInfo(d.range, d.sourceText, d.displayText, d.fontKey, d.glyphCount, 6.0, d.source, d.reason,
                d.glyphsWithoutInkBounds, d.missingGlyphs, d.resolvedFace, d.script, d.language, d.strategy, d.featureEvidence, d.capabilityIssue));
        }
        return new ShapingResult(clusters, runs, decisions);
    }
}
