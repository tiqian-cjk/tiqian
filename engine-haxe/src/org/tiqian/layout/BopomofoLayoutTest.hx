package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import org.tiqian.test.trace.TestTraceRender;

class BopomofoLayoutTest {
    @:test public static function symbolsAndToneRightOfBase():Void {
        final t = new TestTraceRecorder("BopomofoLayoutTest");
        t.section("symbolsAndToneRightOfBase");
        final r = BopomofoLayoutTestSupport.layout([
            new RubySpan(new TextRange(0, 1), "ㄓㄨㄥ", null, RubyKind.Bopomofo),
            new RubySpan(new TextRange(1, 2), "ㄔㄤˊ", null, RubyKind.Bopomofo)
        ]);
        final z = r.debug.bopomofoDecisions;
        if (z.length < 2) {
            TracedAssertions.assertEqualsInt(2, z.length);
            return;
        }
        final a = z[0];
        final b = z[1];
        var symbolsA = 0;
        var toneA = 0;
        var right = true;
        final lefts = [];
        for (p in a.placements) {
            if (p.role == BopomofoGlyphRole.Symbol)
                symbolsA++;
            if (p.role == BopomofoGlyphRole.Tone)
                toneA++;
            if (p.left < 15.9)
                right = false;
            lefts.push(TestTraceRender.renderFloat(p.left));
        }
        var symbolsB = 0;
        var toneB = 0;
        for (p in b.placements) {
            if (p.role == BopomofoGlyphRole.Symbol)
                symbolsB++;
            if (p.role == BopomofoGlyphRole.Tone)
                toneB++;
        }
        TracedAssertions.assertEqualsInt(2, z.length);
        TracedAssertions.assertEqualsInt(700, a.fontWeight, "bopomofo defaults three weight steps heavier than base");
        TracedAssertions.assertEqualsInt(3, symbolsA);
        TracedAssertions.assertTrue(toneA == 0);
        TracedAssertions.assertTrue(right, "symbols right of base: [" + lefts.join(", ") + "]");
        TracedAssertions.assertEqualsInt(2, symbolsB);
        TracedAssertions.assertEqualsInt(1, toneB);
    }

    @:test public static function annotatedBaseReservesHalfEmOnly():Void {
        final t = new TestTraceRecorder("BopomofoLayoutTest");
        t.section("annotatedBaseReservesHalfEmOnly");
        final plain = BopomofoLayoutTestSupport.plain();
        final r = BopomofoLayoutTestSupport.layout([new RubySpan(new TextRange(0, 1), "ㄓㄨㄥ", null, RubyKind.Bopomofo)]);
        TracedAssertions.assertTrue(r.clusters[0].advance > plain.clusters[0].advance,
            "bopomofo reserves advance on annotated base (" + r.clusters[0].advance + " vs " + plain.clusters[0].advance + ")");
        TracedAssertions.assertEqualsFloat(plain.clusters[1].advance, r.clusters[1].advance, "current v1 does not reserve the unannotated adjacent char");
    }

    @:test public static function fontWeightFollowsAnnotatedBasePlusThreeSteps():Void {
        final t = new TestTraceRecorder("BopomofoLayoutTest");
        t.section("fontWeightFollowsAnnotatedBasePlusThreeSteps");
        final r = BopomofoLayoutTestSupport.layout([
            new RubySpan(new TextRange(0, 1), "ㄓㄨㄥ", null, RubyKind.Bopomofo),
            new RubySpan(new TextRange(1, 2), "ㄨㄣˊ", null, RubyKind.Bopomofo)
        ], [
            new TextSpan(new TextRange(0, 1), new TextStyle(null, null, null, 500)),
            new TextSpan(new TextRange(1, 2), new TextStyle(null, null, null, 700))
        ]);
        TracedAssertions.assertEqualsInt(800, r.debug.bopomofoDecisions[0].fontWeight);
        TracedAssertions.assertEqualsInt(900, r.debug.bopomofoDecisions[1].fontWeight, "bopomofo weight clamps at 900");
    }

    @:test public static function decisionKeepsSourceReadingForCopy():Void {
        final t = new TestTraceRecorder("BopomofoLayoutTest");
        t.section("decisionKeepsSourceReadingForCopy");
        final r = BopomofoLayoutTestSupport.layout([new RubySpan(new TextRange(0, 1), "˙ㄉㄜ", null, RubyKind.Bopomofo)]);
        final d = r.debug.bopomofoDecisions;
        if (d.length == 0) {
            TracedAssertions.assertEqualsString("˙ㄉㄜ", r.input.rubySpans[0].text);
            return;
        }
        final decision = d[0];
        final texts = [];
        for (p in decision.placements)
            texts.push(p.text);
        TracedAssertions.assertEqualsString("˙ㄉㄜ", decision.text);
        TracedAssertions.assertEqualsStringArray(["˙", "ㄉ", "ㄜ"], texts);
        TracedAssertions.assertEqualsEnum(BopomofoGlyphRole.Neutral, decision.placements[0].role);
    }

    @:test public static function annotationLocaleDoesNotReplaceSimplifiedBaseLocale():Void {
        final t = new TestTraceRecorder("BopomofoLayoutTest");
        t.section("annotationLocaleDoesNotReplaceSimplifiedBaseLocale");
        final r = BopomofoLayoutTestSupport.layout([new RubySpan(new TextRange(0, 1), "ㄓㄨㄥ", null, RubyKind.Bopomofo)]);
        TracedAssertions.assertEqualsString("zh-Hans", r.input.textStyle.locale);
        if (r.debug.bopomofoDecisions.length == 0) {
            TracedAssertions.assertEqualsInt(1, r.debug.bopomofoDecisions.length);
            return;
        }
        TracedAssertions.assertEqualsString("zh-TW", r.debug.bopomofoDecisions[0].locale);
    }
}
