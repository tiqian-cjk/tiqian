package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.layout.PreparedParagraph.PreparedParagraphFns;
import org.tiqian.test.TestHelpers;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class PreparedParagraphJfTest {
    @:test public static function dashShapingDecisionWithGlyphIds():Void {
        final t = new TestTraceRecorder("PreparedParagraphJfTest");
        t.section("dashShapingDecisionWithGlyphIds");
        final c = new TiqianTextContent("——");
        final r = new LayoutResult(new LayoutInput(c, null, null, new LayoutConstraints(200)), new Size(200, 24),
            [new Cluster(new TextRange(0, 2), "——", "k", 32)], [
                new GlyphRun(new TextRange(0, 2), "k", [new Glyph(42, new TextRange(0, 2), 32)], 32)
            ],
            [PreparedParagraphJfTestSupport.line(new TextRange(0, 2), new IntRange(0, 0), 32)], new LayoutDebugInfo(null, null, null, null, null, null, null, [
                new ShapingDecisionInfo(new TextRange(0, 2), "——", "——", "k", 1, 32, "test", "DashRule", null, null, "NotoSansCJK", null, "zh",
                    "DashTwoEmLigature")
            ], null));
        final json = PreparedParagraphFns.toPreparedParagraphJson(r, true);
        TracedAssertions.assertTrue(json.indexOf("\"glyphIds\":\"42\"") >= 0);
        TracedAssertions.assertTrue(json.indexOf("\"shapingLanguage\":\"zh\"") >= 0);
        TracedAssertions.assertTrue(json.indexOf("\"resolvedFace\":\"NotoSansCJK\"") >= 0);
    }

    @:test public static function ecmaJsonNumberEdgeCases():Void {
        final t = new TestTraceRecorder("PreparedParagraphJfTest");
        t.section("ecmaJsonNumberEdgeCases");
        TracedAssertions.assertTrue(PreparedParagraphFns.ecmaJsonNumber(TestHelpers.f32Bits(1)).length > 0);
        TracedAssertions.assertTrue(PreparedParagraphFns.ecmaJsonNumber(TestHelpers.f32Bits(0x007FFFFF)).length > 0);
        TracedAssertions.assertEqualsString("8.999999688540309e-17", PreparedParagraphFns.ecmaJsonNumber(TestHelpers.f32Literal(9.000000000000001e-17)));
        for (i in 1...2001) {
            PreparedParagraphFns.ecmaJsonNumber(TestHelpers.f32Literal(i * 1e-17));
            PreparedParagraphFns.ecmaJsonNumber(TestHelpers.f32Literal(i * 1e-15));
            PreparedParagraphFns.ecmaJsonNumber(TestHelpers.f32Literal(i * 1e-20));
        }
        for (shift in 1...61) {
            final v = TestHelpers.f32Literal(Math.pow(2, shift));
            TracedAssertions.assertTrue(PreparedParagraphFns.ecmaJsonNumber(v).length > 0);
            TracedAssertions.assertTrue(PreparedParagraphFns.ecmaJsonNumber(-v).length > 0);
            final inv = TestHelpers.f32Literal(1.0 / v);
            TracedAssertions.assertTrue(PreparedParagraphFns.ecmaJsonNumber(inv).length > 0);
            TracedAssertions.assertTrue(PreparedParagraphFns.ecmaJsonNumber(-inv).length > 0);
        }
        final edgeValues = [
            0.9999999999999999,
            0.09999999999999999,
            0.009999999999999999,
            9.999999999999999e-5,
            1.9999999999999998e-4,
            9.999999999999999e20,
            1.9999999999999999e20,
            1e-300,
            1e300,
            1.401298464324817e-45,
            3.4028234663852886e38,
            1.0e-302,
            5.960464477539063e-8,
            2.9802322387695312e-8
        ];
        for (raw in edgeValues) {
            final v = TestHelpers.f32Literal(raw);
            TracedAssertions.assertTrue(PreparedParagraphFns.ecmaJsonNumber(v).length > 0);
            TracedAssertions.assertTrue(PreparedParagraphFns.ecmaJsonNumber(-v).length > 0);
        }
    }

    @:test public static function inlineBoxEdgesAndEmphasisDotsFilter():Void {
        final t = new TestTraceRecorder("PreparedParagraphJfTest");
        t.section("inlineBoxEdgesAndEmphasisDotsFilter");
        final c = new TiqianTextContent("甲乙");
        final cs = [
            new Cluster(new TextRange(0, 1), "甲", "k", 16),
            new Cluster(new TextRange(1, 2), "乙", "k", 16)
        ];
        final debug = new LayoutDebugInfo(null, null, null, null, null, null, null, null, null, null, null, null, null, null, [
            new DecorationDecisionInfo(new TextRange(0, 1), "甲", "Emphasis", false, "test", null, null, 4),
            new DecorationDecisionInfo(new TextRange(0, 1), "甲", "ProperNoun", true, "test", null, null, 4),
            new DecorationDecisionInfo(new TextRange(0, 1), "甲", "Emphasis", true, "test", null, null, 0),
            new DecorationDecisionInfo(new TextRange(0, 1), "甲", "Emphasis", true, "test", 8, 20, 4)
        ]);
        final r = new LayoutResult(new LayoutInput(c, null, null, new LayoutConstraints(200), null, null, null, [
            new InlineBoxSpan(new TextRange(0, 1), 4, 0),
            new InlineBoxSpan(new TextRange(1, 2), 0, 6)
        ]), new Size(200, 24), cs, [
            new GlyphRun(new TextRange(0, 2), "k", [new Glyph(1, new TextRange(0, 1), 16), new Glyph(2, new TextRange(1, 2), 16)], 32)
        ],
            [PreparedParagraphJfTestSupport.line(new TextRange(0, 2), new IntRange(0, 1), 32)], debug);
        final json = PreparedParagraphFns.toPreparedParagraphJson(r, true);
        TracedAssertions.assertTrue(json.indexOf("\"inlineStart\":4") >= 0);
        TracedAssertions.assertTrue(json.indexOf("\"inlineEnd\":6") >= 0);
        TracedAssertions.assertTrue(json.indexOf("\"emphasisDots\":") >= 0);
    }

    @:test public static function styleAtAndStyleDeltasInPreparedParagraphJson():Void {
        final t = new TestTraceRecorder("PreparedParagraphJfTest");
        t.section("styleAtAndStyleDeltasInPreparedParagraphJson");
        final content = new TiqianTextContent("甲乙丙丁戊己", [
            new TextSpan(new TextRange(1, 3), new TextStyle(null, 20, null, 700, true)),
            new TextSpan(new TextRange(2, 4), new TextStyle(null, 16, null, 700, false)),
            new TextSpan(new TextRange(4, 5), new TextStyle(null, 16, null, 400, true))
        ]);
        final texts = ["甲", "乙", "丙", "丁", "戊", "己"];
        final clusters = [
            for (i in 0...6)
                new Cluster(new TextRange(i, i + 1), texts[i], "k", i == 1 ? 20 : 16)
        ];
        final glyphs = [for (i in 0...6) new Glyph(i + 1, new TextRange(i, i + 1), i == 1 ? 20 : 16)];
        final r = new LayoutResult(new LayoutInput(content, new TextStyle(), null, new LayoutConstraints(200)), new Size(200, 24), clusters,
            [new GlyphRun(new TextRange(0, 6), "k", glyphs, 100, ["liga", "dlig"])], [
                PreparedParagraphJfTestSupport.line(new TextRange(0, 6), new IntRange(0, 5), 100)
            ], new LayoutDebugInfo(null));
        final json = PreparedParagraphFns.toPreparedParagraphJson(r, true);
        TracedAssertions.assertTrue(json.indexOf("\"openTypeFeatures\":[\"liga\",\"dlig\"]") >= 0);
        TracedAssertions.assertTrue(json.indexOf("\"fontSize\":20") >= 0);
        TracedAssertions.assertTrue(json.indexOf("\"fontWeight\":700") >= 0);
        TracedAssertions.assertTrue(json.indexOf("\"italic\":true") >= 0);
    }
}
