package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.font.FontRole;
import org.tiqian.layout.PreparedParagraph.PreparedParagraphFns;
import org.tiqian.test.TestHelpers;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class PreparedParagraphPlanConstructionTestSupport {
    public static function line(r:TextRange, cr:IntRange, ?w:Null<Float>):LineBox {
        final x = w == null ? 26.0 : w;
        return new LineBox(r, cr, 20, 0, 24, x, x, x, null, null, null, null, null, new LineDebugInfo(null));
    }

    static function result(content:TiqianTextContent, clusters:Array<Cluster>, runs:Array<GlyphRun>, lines:Array<LineBox>, ?decorations:Array<DecorationSpan>,
            ?boxes:Array<InlineBoxSpan>, ?objects:Array<InlineObjectSpan>, ?debug:LayoutDebugInfo, ?width:Null<Float>, ?height:Null<Float>):LayoutResult {
        final w = width == null ? 480.0 : width;
        final h = height == null ? 24.0 : height;
        return new LayoutResult(new LayoutInput(content, new TextStyle(), null, new LayoutConstraints(w), null, decorations, null, boxes, objects),
            new Size(w, h), clusters, runs, lines, debug == null ? new LayoutDebugInfo(null) : debug);
    }

    static function one(text:String, ?font:String, ?advance:Null<Float>):LayoutResult {
        final a = advance == null ? 16.0 : advance;
        final f = font == null ? "cjk" : font;
        final r = new TextRange(0, text.length);
        return result(new TiqianTextContent(text), [new Cluster(r, text, f, a)], [new GlyphRun(r, f, [new Glyph(1, r, a)], a)],
            [line(r, new IntRange(0, 0), a)]);
    }

    public static function openTypeFeaturesAndRenderFontFamilyAttachPerCluster():LayoutResult {
        final r = new TextRange(0, 1);
        return result(new TiqianTextContent("汉"), [new Cluster(r, "汉", "cjk", 16)], [
            new GlyphRun(r, "cjk", [new Glyph(7, r, 16, null, null, "Noto Serif CJK")], 16, ["kern", "liga"])
        ], [line(r, new IntRange(0, 0))]);
    }

    public static function multiUnitClusterMarksShapingBoundary():LayoutResult {
        final r = new TextRange(0, 2);
        return result(new TiqianTextContent("AB"), [new Cluster(r, "AB", "latin", 18)], [new GlyphRun(r, "latin", [new Glyph(1, r, 18)], 18)],
            [line(r, new IntRange(0, 0))]);
    }

    public static function inlineObjectCellEmitsAdvanceOverride():LayoutResult {
        final a = new TextRange(0, 1);
        final b = new TextRange(1, 2);
        return result(new TiqianTextContent("汉图"), [new Cluster(a, "汉", "cjk", 16), new Cluster(b, "图", "inline", 10)], [
            new GlyphRun(a, "cjk", [new Glyph(1, a, 16)], 16),
            new GlyphRun(b, "inline", [new Glyph(2, b, 24)], 24)
        ], [line(new TextRange(0, 2), new IntRange(0, 1), 40)],
            null, null, [new InlineObjectSpan(b, 24, 12, 4)]);
    }

    public static function styleDeltaListsOnlyPaintFields():LayoutResult {
        final a = new TextRange(0, 1);
        final b = new TextRange(1, 2);
        final c = new TextRange(2, 3);
        final content = new TiqianTextContent("汉A字", [
            new TextSpan(a, new TextStyle(null, 20, null, 700, true)),
            new TextSpan(b, new TextStyle(["Kai"]))
        ]);
        return result(content, [
            new Cluster(a, "汉", "cjk", 16),
            new Cluster(b, "A", "latin", 10),
            new Cluster(c, "字", "cjk", 16)
        ], [
            new GlyphRun(a, "cjk", [new Glyph(1, a, 16)], 16),
            new GlyphRun(b, "latin", [new Glyph(2, b, 10)], 10),
            new GlyphRun(c, "cjk", [new Glyph(3, c, 16)], 16)
        ], [line(new TextRange(0, 3), new IntRange(0, 2), 42)]);
    }

    public static function dashClusterEmitsShapingEvidenceBlock():LayoutResult {
        final a = new TextRange(0, 1);
        final b = new TextRange(1, 3);
        final d = new ShapingDecisionInfo(b, "——", "——", "cjk", 2, 32, "ShapingStage", "dash-reason", null, null, "NotoSansCJK", null, "zh-Hans",
            "PairedEmDash");
        return result(new TiqianTextContent("汉——"), [new Cluster(a, "汉", "cjk", 16), new Cluster(b, "——", "cjk", 32)], [
            new GlyphRun(a, "cjk", [new Glyph(1, a, 16)], 16),
            new GlyphRun(b, "cjk", [new Glyph(9, b, 32, null, null, "Noto Sans CJK"), new Glyph(10, b, 0)], 32)
        ],
            [line(new TextRange(0, 3), new IntRange(0, 1), 48)], null, null, null, new LayoutDebugInfo(null, null, null, null, null, null, null, [d]));
    }

    public static function punctuationInkFloorAndLatinRoleMarkCells():LayoutResult {
        final a = new TextRange(0, 1);
        final b = new TextRange(1, 2);
        final c = new TextRange(2, 3);
        final ps = [
            new PunctuationDecisionInfo(a, "。", "PauseOrStop", 16, 16, 0, 0, "centre", null, null, 16, null, null, 6, true),
            new PunctuationDecisionInfo(b, "A", "Other", 10, 10, 0, 0, "centre", null, null, 10),
            new PunctuationDecisionInfo(c, "中", "Other", 16, 16, 0, 0, "centre", null, null, 16)
        ];
        final fd = [new FontDecisionInfo(b, "A", "A", "LatinText", "latin", "latin-run", "none")];
        return result(new TiqianTextContent("。A中"), [
            new Cluster(a, "。", "cjk", 16),
            new Cluster(b, "A", "latin", 10),
            new Cluster(c, "中", "cjk", 16)
        ], [
            new GlyphRun(a, "cjk", [new Glyph(1, a, 16)], 16),
            new GlyphRun(b, "latin", [new Glyph(2, b, 10)], 10),
            new GlyphRun(c, "cjk", [new Glyph(3, c, 16)], 16)
        ],
            [line(new TextRange(0, 3), new IntRange(0, 2), 42)], null, null, null, new LayoutDebugInfo(null, null, null, null, null, null, fd, null, ps));
    }

    public static function zeroWidthBreakClusterSurvivesEmptyDisplayText():LayoutResult {
        final a = new TextRange(0, 1);
        final b = new TextRange(1, 2);
        final c = new TextRange(2, 3);
        final z = new ShapingDecisionInfo(b, "​", "", "cjk", 0, 0, "ShapingStage", "no-shape", null, null, null, null, null, "ZeroWidthNoShape");
        return result(new TiqianTextContent("汉​字"), [
            new Cluster(a, "汉", "cjk", 16),
            new Cluster(b, "​", "cjk", 0, ""),
            new Cluster(c, "字", "cjk", 16)
        ], [
            new GlyphRun(a, "cjk", [new Glyph(1, a, 16)], 16),
            new GlyphRun(c, "cjk", [new Glyph(3, c, 16)], 16)
        ],
            [line(new TextRange(0, 3), new IntRange(0, 2), 32)], null, null, null,
            new LayoutDebugInfo(null, null, null, null, null, null, null, [z], null, null, null, null, null, null, null, null, null, null, null, null, null,
                null, null, null, null, null, [new ZeroWidthBreakDecisionInfo(b, "​", 1)]));
    }

    public static function paragraphEvidenceEmitsEverySection():LayoutResult {
        final a = new TextRange(0, 1);
        final b = new TextRange(1, 2);
        final ds = [
            new DecorationSpan(a, DecorationKind.Emphasis),
            new DecorationSpan(b, DecorationKind.Emphasis)
        ];
        final dec = [
            new DecorationDecisionInfo(a, "汉", "Emphasis", true, "dot-applied", 8, 22, 2),
            new DecorationDecisionInfo(b, "注", "Emphasis", true, "dot-without-size", 24, 22, 0),
            new DecorationDecisionInfo(b, "注", "Emphasis", false, "dot-skipped", 24, 22, 2)
        ];
        final seg = [
            new DecorationSegmentInfo(a, "ProperNoun", 0, 0, 20, 16, 22, false, false, "proper-noun"),
            new DecorationSegmentInfo(b, "BookTitle", 0, 16, 20, 32, 22, false, false, "book-title")
        ];
        final ruby = [
            new RubyDecisionInfo(a, "hàn", 0, 8, 2, 8, .5, 6, null, null, ["RubyKai", "RubyLatin"]),
            new RubyDecisionInfo(b, "zhù", 0, 24, 2, 8, 0)
        ];
        final bop = [
            new BopomofoDecisionInfo(b, "ㄓㄨˋ", 0, [
                new BopomofoGlyphPlacement("ㄓ", 1, 2, 4, 4, BopomofoGlyphRole.Symbol, [], 1, 6, 4),
                new BopomofoGlyphPlacement("ˋ", 2, 0, 2, 2, BopomofoGlyphRole.Tone, [], 2, 2, 2)
            ], ["BopomofoKai", "BopomofoLatin"]),
            new BopomofoDecisionInfo(a, "ㄏㄢˋ", 0, [
                new BopomofoGlyphPlacement("ㄏ", 0, 2, 4, 4, BopomofoGlyphRole.Symbol, [], 0, 6, 4)
            ])
        ];
        final debug = new LayoutDebugInfo(null, null, null, null, ruby, bop, null, null, null, null, null, null, null, null, dec, seg);
        return result(new TiqianTextContent("汉注"), [new Cluster(a, "汉", "cjk", 16), new Cluster(b, "注", "cjk", 16)], [
            new GlyphRun(new TextRange(0, 2), "cjk", [new Glyph(1, a, 16), new Glyph(2, b, 16)], 32)
        ], [line(new TextRange(0, 2), new IntRange(0, 1), 32)], ds, [
            new InlineBoxSpan(a, 2),
            new InlineBoxSpan(a, .5),
            new InlineBoxSpan(b, null, 3),
            new InlineBoxSpan(new TextRange(0, 2), null, 1.5)
        ], null, debug);
    }

    public static function negativeZeroAndExponentWidthsNormalize():LayoutResult {
        final r = one("汉");
        final l = line(new TextRange(0, 1), new IntRange(0, 0));
        final nl = new LineBox(l.range, l.clusterRange, l.baseline, l.top, l.bottom, l.naturalWidth, l.adjustedWidth, l.visualWidth,
            l.hangingPunctuationAdvance, -0.0, l.endReason, -0.0, null, l.debug);
        return result(new TiqianTextContent("汉"), [new Cluster(new TextRange(0, 1), "汉", "cjk", 16)], [
            new GlyphRun(new TextRange(0, 1), "cjk", [new Glyph(1, new TextRange(0, 1), 16)], 16)
        ], [nl], null, null, null, null, TestHelpers.f32Literal(1.0e21), -0.0);
    }

    public static function escapes():LayoutResult {
        final s = TestHelpers.surrogateText([34, 92, 8, 12, 10, 13, 9, 1]);
        final r = new TextRange(0, 8);
        return result(new TiqianTextContent(s), [new Cluster(r, s, "cjk", 8)], [new GlyphRun(r, "cjk", [new Glyph(1, r, 8)], 8)],
            [line(r, new IntRange(0, 0), 8)]);
    }

    public static function diagnostics():LayoutResult {
        final a = new TextRange(0, 1);
        final b = new TextRange(1, 2);
        final c = new TextRange(2, 3);
        final ds = [
            new ShapingDecisionInfo(a, "汉", "汉", "cjk", 1, 32, "ShapingStage", "capability-reason", null, null, null, null, null, null, null,
                "InvalidWebShapingAdvance"),
            new ShapingDecisionInfo(c, "臣", "臣", "cjk", 1, Math.POSITIVE_INFINITY, "ShapingStage", "infinite-capability", null, null, null, null, null, null,
                null, "MissingInkBoundsFallback"),
            new ShapingDecisionInfo(b, "零", "零", "cjk", 1, 0, "ShapingStage", "zero-advance"),
            new ShapingDecisionInfo(c, "臣", "臣", "cjk", 1, Math.NaN, "ShapingStage", "nan-advance"),
            new ShapingDecisionInfo(c, "臣", "臣", "cjk", 1, Math.POSITIVE_INFINITY, "ShapingStage", "infinite-advance")
        ];
        return result(new TiqianTextContent("汉零臣"), [
            new Cluster(a, "汉", "cjk", 32),
            new Cluster(b, "零", "cjk", 0),
            new Cluster(c, "臣", "cjk", 16)
        ], [
            new GlyphRun(a, "cjk", [new Glyph(1, a, 32)], 32),
            new GlyphRun(b, "cjk", [new Glyph(2, b, 0)], 0),
            new GlyphRun(c, "cjk", [new Glyph(3, c, 16)], 16)
        ],
            [line(new TextRange(0, 3), new IntRange(0, 2), 48)], null, null, null, new LayoutDebugInfo(null, null, null, null, null, null, null, ds));
    }

    static function begin(name:String):TestTraceRecorder {
        final t = new TestTraceRecorder("PreparedParagraphPlanConstructionTest");
        t.section(name);
        return t;
    }

    public static function runEvidence(name:String, r:LayoutResult):Void {
        final t = begin(name);
        final j = PreparedParagraphFns.toPreparedParagraphJson(r, true);
        TracedAssertions.assertTrue(j.indexOf("\"dashStrategy\":\"PairedEmDash\"") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"shapingLanguage\":\"zh-Hans\"") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"resolvedFace\":\"NotoSansCJK\"") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"glyphIds\":\"9,10\"") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"shapingEvidence\":\"dash-reason\"") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"naturalWidth\":32") >= 0, j);
    }

    public static function runPunctuation():Void {
        final t = begin("punctuationInkFloorAndLatinRoleMarkCells");
        final j = PreparedParagraphFns.toPreparedParagraphJson(punctuationInkFloorAndLatinRoleMarkCells(), true);
        TracedAssertions.assertTrue(j.indexOf("\"punctuationInkFloor\":6") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"punctuationBodyWidth\":16") >= 0, j);
        TracedAssertions.assertEquals(1, j.split("\"punctuationInkFloor\":").length - 1);
        TracedAssertions.assertTrue(j.indexOf("\"latin\":true") >= 0, j);
    }

    public static function runZeroWidth():Void {
        final t = begin("zeroWidthBreakClusterSurvivesEmptyDisplayText");
        final r = zeroWidthBreakClusterSurvivesEmptyDisplayText();
        final j = PreparedParagraphFns.toPreparedParagraphJson(r);
        TracedAssertions.assertTrue(j.indexOf("\"display\":\"\",\"drawX\":16") >= 0, j);
        TracedAssertions.assertEquals(3, j.split("\"source\":").length - 1);
        final e = PreparedParagraphFns.toPreparedParagraphJson(r, true);
        TracedAssertions.assertTrue(e.indexOf("\"dashStrategy\":\"ZeroWidthNoShape\"") >= 0, e);
        TracedAssertions.assertTrue(e.indexOf("\"shapingEvidence\":\"no-shape\"") >= 0, e);
        TracedAssertions.assertFalse(e.indexOf("shapingLanguage") >= 0, e);
        TracedAssertions.assertFalse(e.indexOf("resolvedFace") >= 0, e);
        TracedAssertions.assertFalse(e.indexOf("glyphIds") >= 0, e);
    }

    public static function runParagraphEvidence():Void {
        final t = begin("paragraphEvidenceEmitsEverySection");
        final j = PreparedParagraphFns.toPreparedParagraphJson(paragraphEvidenceEmitsEverySection(), true);
        TracedAssertions.assertTrue(j.indexOf("\"emphasisRanges\":[[0,1],[1,2]]") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"inlineEdges\":[{\"offset\":0,\"inlineStart\":2.5},{\"offset\":2,\"inlineEnd\":4.5}]") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"rubyDecisions\":[{\"baseRangeStart\":0") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"ascent\":6") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"fontFamilies\":[\"RubyKai\",\"RubyLatin\"]") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"bopomofoDecisions\":[{\"baseRangeStart\":1") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"role\":\"Symbol\"") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"role\":\"Tone\"") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"fontFamilies\":[\"BopomofoKai\",\"BopomofoLatin\"]") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"decorationSegments\":[{\"kind\":\"ProperNoun\"") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"kind\":\"BookTitle\"") >= 0, j);
        TracedAssertions.assertFalse(j.indexOf("Emphasis") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"emphasisDots\":[{\"clusterRangeStart\":0,\"anchorX\":8,\"anchorY\":22,\"dotDiameter\":2}]") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"fontSize\":16") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"overlayWidth\":480") >= 0, j);
    }

    public static function runNegativeZero():Void {
        final t = begin("negativeZeroAndExponentWidthsNormalize");
        final j = PreparedParagraphFns.toPreparedParagraphJson(negativeZeroAndExponentWidthsNormalize());
        TracedAssertions.assertTrue(j.indexOf("\"width\":1.0000000200408773e+21") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"height\":0") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"indent\":0") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("\"hyphenAdvance\":0") >= 0, j);
    }

    public static function runEscapes():Void {
        final t = begin("jsonStringEscapesQuotesBackslashesAndControlCharacters");
        final j = PreparedParagraphFns.toPreparedParagraphJson(escapes());
        final ss = ["\\\"", "\\\\", "\\b", "\\f", "\\n", "\\r", "\\t", "\\u0001"];
        for (i in 0...ss.length) {
            final s = ss[i];
            TracedAssertions.assertTrue(j.indexOf(s) >= 0, j);
        }
    }

    public static function runDiagnostics():Void {
        final t = begin("planWithDiagnosticsListsCapabilityIssuesAndAdvanceSuspects");
        final j = PreparedParagraphFns.toPlanWithDiagnosticsJson(diagnostics(), false, 0.5);
        final d = j.substr(j.indexOf("\"diagnostics\":"));
        for (s in [
            "\"name\":\"InvalidWebShapingAdvance\"",
            "\"reason\":\"capability-reason\"",
            "\"rangeStart\":0",
            "\"rangeEnd\":1",
            "\"displayText\":\"零\"",
            "\"advance\":\"0\"",
            "\"advance\":\"NaN\"",
            "\"advance\":\"Infinity\""
        ])
            TracedAssertions.assertTrue(d.indexOf(s) >= 0, j);
        TracedAssertions.assertFalse(d.indexOf("\"advance\":\"32\"") >= 0, j);
        TracedAssertions.assertTrue(j.indexOf("{\"plan\":\"") == 0, j.substr(0, 20));
    }
}
