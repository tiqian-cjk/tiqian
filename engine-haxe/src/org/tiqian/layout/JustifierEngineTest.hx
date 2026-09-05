package org.tiqian.layout;

using std.RecordCopy;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.linebreak.Hyphenator.NoHyphenator;
import org.tiqian.shaping.TextShaper;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.test.trace.*;

class JustifierEngineTest {
    @:test public static function connectorBoundariesAvoidStretchUnderJustification():Void {
        var t = JustifierEngineTestSupport.start("connectorBoundariesAvoidStretchUnderJustification");
        var r = JustifierEngineTestSupport.engine()
            .layout(new LayoutInput(new TiqianTextContent("中～文中Example"), null, new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(80)));
        TracedAssertions.assertTrue(r.lines.length >= 2);
        var d = r.debug.justificationDecisions[0];
        TracedAssertions.assertEqualsFloat(0, d.deficitAfter);
        var a:Array<Int> = [];
        for (x in d.allocations)
            if (x.kind == "CjkInterChar")
                a.push(x.clusterRange.start);
        TracedAssertions.assertEqualsRendered("[2]", Std.string(a));
        TracedAssertions.assertEqualsFloat(16, d.allocations[0].delta);
    }

    @:test public static function inseparableNumberAndUnitBoundaryAvoidsStretchUnderJustification():Void {
        var t = JustifierEngineTestSupport.start("inseparableNumberAndUnitBoundaryAvoidsStretchUnderJustification");
        var text = "中文50℃中文中文中文Example";
        var nr = new TextRange(2, 4);
        var ur = new TextRange(4, 5);
        var r = JustifierEngineTestSupport.engine()
            .layout(new LayoutInput(new TiqianTextContent(text), null, new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false)),
                new LayoutConstraints(128)));
        var n:Cluster = null;
        var u:Cluster = null;
        for (c in r.clusters) {
            if (nr.start >= c.range.start && nr.end <= c.range.end)
                n = c;
            if (ur.start >= c.range.start && ur.end <= c.range.end)
                u = c;
        }
        TracedAssertions.assertTrue(n != u);
        var d = r.debug.justificationDecisions[0];
        var bad = false;
        for (a in d.allocations)
            if (a.clusterRange == n.range && (a.kind == "CjkLatinSpace" || a.kind == "CjkInterChar"))
                bad = true;
        TracedAssertions.assertTrue(!bad, "50|℃ must stay closed: " + JustifierEngineTestSupport.allocationsText(d.allocations));
        TracedAssertions.assertEqualsFloat(0, d.deficitAfter);
    }

    @:test public static function lastLineAlignmentPositionsTheLastLineViaIndent():Void {
        var t = JustifierEngineTestSupport.start("lastLineAlignmentPositionsTheLastLineViaIndent");
        function l(a:LastLineAlignment):LayoutResult
            return JustifierEngineTestSupport.engine()
                .layout(new LayoutInput(new TiqianTextContent("中文中文中文中文中"), null,
                    new ParagraphStyle(a, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(100)));
        var s = l(LastLineAlignment.Start);
        TracedAssertions.assertEqualsFloat(100, s.lines[0].visualWidth);
        TracedAssertions.assertEqualsFloat(0, s.lines[1].indent);
        var c = l(LastLineAlignment.Center);
        TracedAssertions.assertEqualsFloat(26, c.lines[1].indent);
        TracedAssertions.assertEqualsFloat(0, c.lines[0].indent);
        var x = l(LastLineAlignment.End);
        TracedAssertions.assertEqualsFloat(52, x.lines[1].indent);
    }

    @:test public static function mandatoryBreakLinesTakeLastLineAlignment():Void {
        var t = JustifierEngineTestSupport.start("mandatoryBreakLinesTakeLastLineAlignment");
        var r = JustifierEngineTestSupport.engine()
            .layout(new LayoutInput(new TiqianTextContent("中文中\n中文中文中文中"), null,
                new ParagraphStyle(LastLineAlignment.Center, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(100)));
        TracedAssertions.assertEqualsInt(3, r.lines.length);
        TracedAssertions.assertEqualsFloat(26, r.lines[0].indent);
        TracedAssertions.assertEqualsFloat(0, r.lines[1].indent);
        TracedAssertions.assertEqualsFloat(42, r.lines[2].indent);
    }

    @:test public static function lastLineIsNeverJustified():Void {
        var t = JustifierEngineTestSupport.start("lastLineIsNeverJustified");
        var r = JustifierEngineTestSupport.engine()
            .layout(new LayoutInput(new TiqianTextContent("中文中"), null, new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(80)));
        TracedAssertions.assertEqualsFloat(48, r.lines[0].adjustedWidth);
        TracedAssertions.assertEqualsFloat(48, r.lines[0].visualWidth);
        TracedAssertions.assertEqualsInt(0, r.debug.justificationDecisions.length);
    }

    @:test public static function latinGlyphPositionsSurviveAutospaceAndJustification():Void {
        var t = JustifierEngineTestSupport.start("latinGlyphPositionsSurviveAutospaceAndJustification");
        var r = JustifierEngineTestSupport.positioned()
            .layout(new LayoutInput(new TiqianTextContent("中AV中文"), null,
                new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(52)));
        var c:Cluster = null;
        for (x in r.clusters)
            if (x.text == "AV")
                c = x;
        TracedAssertions.assertTrue(c.advance > 10, "autospace/justification should widen the cluster as trailing layout space: " + Std.string(c));
        var ok = false;
        for (di in 0...r.debug.justificationDecisions.length) {
            var d = r.debug.justificationDecisions[di];
            for (ai in 0...d.allocations.length) {
                var al = d.allocations[ai];
                if (al.clusterRange == c.range && al.kind == "CjkLatinSpace")
                    ok = true;
            }
        }
        TracedAssertions.assertTrue(ok, "the test must exercise a justify delta on the Latin cluster");
        var xs:Array<Float> = [];
        var adv:Array<Float> = [];
        for (ri in 0...r.glyphRuns.length) {
            var run = r.glyphRuns[ri];
            for (gi in 0...run.glyphs.length) {
                var g = run.glyphs[gi];
                if (g.clusterRange == c.range) {
                    xs.push(g.x);
                    adv.push(g.advance);
                }
            }
        }
        TracedAssertions.assertEqualsRendered("[0, 5]", "[" + xs.join(", ") + "]");
        TracedAssertions.assertEqualsRendered("[5, 5]", "[" + adv.join(", ") + "]");
    }

    @:test public static function justifiesNonLastLineUsingCjkInterCharGapsAsLastResort():Void {
        var t = JustifierEngineTestSupport.start("justifiesNonLastLineUsingCjkInterCharGapsAsLastResort");
        var r = JustifierEngineTestSupport.engine()
            .layout(new LayoutInput(new TiqianTextContent("中文中文中文"), null, new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(80)));
        TracedAssertions.assertEqualsInt(2, r.lines.length);
        TracedAssertions.assertEqualsFloat(80, r.lines[0].adjustedWidth);
        TracedAssertions.assertEqualsFloat(80, r.lines[0].visualWidth);
        TracedAssertions.assertEqualsFloat(16, r.lines[1].adjustedWidth);
        TracedAssertions.assertEqualsFloat(16, r.lines[1].visualWidth);
        TracedAssertions.assertEqualsInt(0, r.debug.justificationDecisions.length);
    }

    @:test public static function usesPunctuationGlueFirstWhenDeficitMatchesCompression():Void {
        var t = JustifierEngineTestSupport.start("usesPunctuationGlueFirstWhenDeficitMatchesCompression");
        var r = JustifierEngineTestSupport.engine()
            .layout(new LayoutInput(new TiqianTextContent("中，。文"), null, new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(64)));
        TracedAssertions.assertEqualsInt(1, r.lines.length);
        TracedAssertions.assertEqualsInt(0, r.debug.justificationDecisions.length);
    }

    @:test public static function justifyDistributesDeficitAcrossPriorityChain():Void {
        var t = JustifierEngineTestSupport.start("justifyDistributesDeficitAcrossPriorityChain");
        var r = JustifierEngineTestSupport.engine()
            .layout(new LayoutInput(new TiqianTextContent("中」。文中文中文中"), null, new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(80)));
        TracedAssertions.assertTrue(r.lines.length >= 2);
        var d = r.debug.justificationDecisions[0];
        TracedAssertions.assertEqualsFloat(8, d.deficitBefore);
        TracedAssertions.assertEqualsFloat(0, d.deficitAfter);
        TracedAssertions.assertEqualsInt(4, d.allocations.length);
        var kinds = true;
        var deltas = true;
        for (a in d.allocations) {
            if (a.kind != "CjkInterChar")
                kinds = false;
            if (a.delta != 2)
                deltas = false;
        }
        TracedAssertions.assertTrue(kinds);
        TracedAssertions.assertTrue(deltas);
        var starts:Array<Int> = [];
        for (a in d.allocations)
            starts.push(a.clusterRange.start);
        TracedAssertions.assertEqualsIntArray([0, 1, 2, 3], starts);
        TracedAssertions.assertEqualsFloat(80, r.lines[0].visualWidth);
        var g:ClusterGeometryDecisionInfo = null;
        for (x in r.debug.geometryDecisions)
            if (x.sourceText == "」")
                g = x;
        TracedAssertions.assertEqualsFloat(8, g.trailingGlueConsumed);
        TracedAssertions.assertEqualsFloat(2, g.justificationDelta);
        TracedAssertions.assertEqualsFloat(10, g.resolvedAdvance);
    }

    @:test public static function cjkInterCharActsAsLastResortWhenPunctGlueExhausted():Void {
        var t = JustifierEngineTestSupport.start("cjkInterCharActsAsLastResortWhenPunctGlueExhausted");
        var r = JustifierEngineTestSupport.engine()
            .layout(new LayoutInput(new TiqianTextContent("中文中文中文中文中文中文"), null,
                new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(100)));
        TracedAssertions.assertEqualsInt(2, r.lines.length);
        var d = r.debug.justificationDecisions[0];
        TracedAssertions.assertEqualsFloat(4, d.deficitBefore);
        TracedAssertions.assertEqualsFloat(0, d.deficitAfter);
        var kinds = true;
        for (a in d.allocations)
            if (a.kind != "CjkInterChar")
                kinds = false;
        TracedAssertions.assertTrue(kinds);
        TracedAssertions.assertEqualsInt(5, d.allocations.length);
        for (a in d.allocations)
            TracedAssertions.assertEqualsFloat(.8, a.delta);
        TracedAssertions.assertEqualsFloat(100, r.lines[0].visualWidth);
    }

    @:test public static function uniformTrackingIncludesBracketInnerSides():Void {
        var t = JustifierEngineTestSupport.start("uniformTrackingIncludesBracketInnerSides");
        var r = JustifierEngineTestSupport.engine()
            .layout(new LayoutInput(new TiqianTextContent("中（中文）文中文中文中"), null,
                new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(100)));
        TracedAssertions.assertEqualsInt(2, r.lines.length);
        var d = r.debug.justificationDecisions[0];
        TracedAssertions.assertEqualsFloat(0, d.deficitAfter);
        var starts:Array<Int> = [];
        for (a in d.allocations)
            starts.push(a.clusterRange.start);
        TracedAssertions.assertEqualsIntArray([0, 1, 2, 3, 4], starts);
        var kinds = true;
        for (a in d.allocations)
            if (a.kind != "CjkInterChar")
                kinds = false;
        TracedAssertions.assertTrue(kinds);
        for (a in d.allocations)
            TracedAssertions.assertEqualsFloatTolerance(.8, a.delta, .01);
    }

    @:test public static function bracketWesternInteriorStretchesInTierThreeNotTierTwo():Void {
        var t = JustifierEngineTestSupport.start("bracketWesternInteriorStretchesInTierThreeNotTierTwo");
        var r = JustifierEngineTestSupport.engine()
            .layout(new LayoutInput(new TiqianTextContent("中文（Hello）中文中文"), null,
                new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(170)));
        TracedAssertions.assertEqualsInt(2, r.lines.length);
        var d = r.debug.justificationDecisions[0];
        var latin = false;
        var left = false;
        var right = false;
        for (a in d.allocations) {
            if (a.kind == "CjkLatinSpace")
                latin = true;
            if (a.kind == "CjkInterChar" && a.clusterRange.start == 2)
                left = true;
            if (a.kind == "CjkInterChar" && a.clusterRange.start == 3)
                right = true;
        }
        TracedAssertions.assertTrue(!latin);
        TracedAssertions.assertTrue(left);
        TracedAssertions.assertTrue(right);
    }

    @:test public static function dashBoundariesDoNotReceiveUniformTracking():Void {
        var t = JustifierEngineTestSupport.start("dashBoundariesDoNotReceiveUniformTracking");
        var r = JustifierEngineTestSupport.engine()
            .layout(new LayoutInput(new TiqianTextContent("在所谓中文语境下——不如说中文"), null,
                new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(180)));
        TracedAssertions.assertTrue(r.lines.length >= 2);
        var dash:Cluster = null;
        for (c in r.clusters)
            if (c.text == "——")
                dash = c;
        var before:Cluster = null;
        for (i in 1...r.clusters.length)
            if (r.clusters[i].range == dash.range)
                before = r.clusters[i - 1];
        var d = r.debug.justificationDecisions[0];
        var badBefore = false;
        var badAfter = false;
        for (a in d.allocations) {
            if (a.kind == "CjkInterChar" && a.clusterRange == before.range)
                badBefore = true;
            if (a.kind == "CjkInterChar" && a.clusterRange == dash.range)
                badAfter = true;
        }
        TracedAssertions.assertTrue(!badBefore, "boundary before dash must stay closed: " + JustifierEngineTestSupport.allocationsText(d.allocations));
        TracedAssertions.assertTrue(!badAfter, "boundary after dash must stay closed: " + JustifierEngineTestSupport.allocationsText(d.allocations));
    }

    @:test public static function typedSinoWesternSpacesStretchInTierTwo():Void {
        var t = JustifierEngineTestSupport.start("typedSinoWesternSpacesStretchInTierTwo");
        var r = JustifierEngineTestSupport.engine()
            .layout(new LayoutInput(new TiqianTextContent("中文 Hello 中文中文中文"), null, new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(180)));
        TracedAssertions.assertTrue(r.lines.length >= 2);
        var d = r.debug.justificationDecisions[0];
        var a:Array<JustificationAllocationInfo> = [];
        for (x in d.allocations)
            if (x.kind == "CjkLatinSpace")
                a.push(x);
        TracedAssertions.assertEqualsInt(2, a.length);
        var spaced = true;
        for (ai in 0...a.length) {
            var x = a[ai];
            var c:Cluster = null;
            for (yi in 0...r.clusters.length) {
                var y = r.clusters[yi];
                if (y.range.start == x.clusterRange.start)
                    c = y;
            }
            if (c.text != " ")
                spaced = false;
        }
        TracedAssertions.assertTrue(spaced, "every 中西 stretch lands on a typed space cluster, not a boundary");
        TracedAssertions.assertTrue(a[0].delta == a[1].delta, "同时、同等量");
    }

    @:test public static function punctuationToWesternBoundaryStretchesInTierThree():Void {
        var t = JustifierEngineTestSupport.start("punctuationToWesternBoundaryStretchesInTierThree");
        var r = JustifierEngineTestSupport.engine()
            .layout(new LayoutInput(new TiqianTextContent("你好「World」你好你好你"), null,
                new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(140)));
        var ok = false;
        for (ai in 0...r.debug.justificationDecisions[0].allocations.length) {
            var al = r.debug.justificationDecisions[0].allocations[ai];
            var c:Cluster = null;
            for (xi in 0...r.clusters.length) {
                var x = r.clusters[xi];
                if (x.range.start == al.clusterRange.start)
                    c = x;
            }
            if (al.kind == "CjkInterChar" && c.text == "「")
                ok = true;
        }
        TracedAssertions.assertTrue(ok, "标点↔西文 boundary must stretch in tier ③");
    }

    @:test public static function lineEdgeSinoWesternSpaceStaysCollapsed():Void {
        var t = JustifierEngineTestSupport.start("lineEdgeSinoWesternSpaceStaysCollapsed");
        var r = JustifierEngineTestSupport.engine()
            .layout(new LayoutInput(new TiqianTextContent("中文中文 word 中文中"), null, new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(80)));
        for (i in 0...r.lines.length - 1) {
            var edge:Cluster = null;
            for (c in r.clusters)
                if (c.range.start < r.lines[i].range.end)
                    edge = c;
            if (edge.text == " ")
                TracedAssertions.assertEqualsFloat(0, edge.advance, "line-edge sino-western space must stay collapsed");
        }
    }
}
