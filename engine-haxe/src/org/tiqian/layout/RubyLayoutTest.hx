package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class RubyLayoutTest {
    @:test public static function rubyDoesNotChangeLineBoxAndCentresOverBase():Void {
        var t = new TestTraceRecorder("RubyLayoutTest");
        t.section("rubyDoesNotChangeLineBoxAndCentresOverBase");
        var plain = RubyLayoutTestSupport.layout([]);
        var ruby = RubyLayoutTestSupport.layout([new RubySpan(new TextRange(0, 1), "zh\u014Dng")]);
        TracedAssertions.assertEqualsFloatTolerance(plain.lines[0].top, ruby.lines[0].top, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(plain.lines[0].baseline, ruby.lines[0].baseline, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(plain.lines[0].bottom, ruby.lines[0].bottom, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(plain.size.height, ruby.size.height, 0.001);
        var lineHeightDecision = ruby.debug.rubyLineHeightDecision;
        TracedAssertions.assertEqualsString("PerLine", lineHeightDecision.mode);
        TracedAssertions.assertEqualsFloatTolerance(0, lineHeightDecision.maxExtra, 0.001);
        var allZero = true;
        for (i in 0...lineHeightDecision.lineExtras.length)
            if (lineHeightDecision.lineExtras[i] != 0)
                allZero = false;
        TracedAssertions.assertTrue(allZero);
        TracedAssertions.assertTrue(lineHeightDecision.expandedLineIndices.length == 0);
        TracedAssertions.assertEqualsString("ExistingInterlineSpaceFitsRuby", lineHeightDecision.reason);
        var decisions = ruby.debug.rubyDecisions;
        TracedAssertions.assertEquals(1, decisions.length);
        TracedAssertions.assertEqualsString("zh\u014Dng", decisions[0].text);
        var firstAdvance = ruby.clusters[0].advance;
        TracedAssertions.assertTrue(decisions[0].centerX >= 0 && decisions[0].centerX <= firstAdvance,
            "centre " + decisions[0].centerX + " within \u4E2D's span");
        TracedAssertions.assertTrue(decisions[0].baselineY < ruby.lines[0].baseline, "ruby baseline above base baseline");
        TracedAssertions.assertEqualsFloatTolerance(ruby.lines[0].baseline - 16 * 0.88, decisions[0].baselineY + decisions[0].fontSize * 0.2, 0.001);
        TracedAssertions.assertEquals(500, decisions[0].fontWeight, "ruby defaults one weight step heavier than base");
    }

    @:test public static function rubyOnOneLineKeepsTheWholeBaselineGridStable():Void {
        var t = new TestTraceRecorder("RubyLayoutTest");
        t.section("rubyOnOneLineKeepsTheWholeBaselineGridStable");
        var plain = RubyLayoutTestSupport.layoutEight([]);
        var annotated = RubyLayoutTestSupport.layoutEight([new RubySpan(new TextRange(4, 5), "w\u00F9")]);
        TracedAssertions.assertEquals(plain.lines.length, annotated.lines.length);
        TracedAssertions.assertEqualsFloatTolerance(plain.size.height, annotated.size.height, 0.001);
        for (i in 0...plain.lines.length) {
            var plainLine = plain.lines[i];
            var annotatedLine = annotated.lines[i];
            TracedAssertions.assertEqualsFloatTolerance(plainLine.top, annotatedLine.top, 0.001);
            TracedAssertions.assertEqualsFloatTolerance(plainLine.baseline, annotatedLine.baseline, 0.001);
            TracedAssertions.assertEqualsFloatTolerance(plainLine.bottom, annotatedLine.bottom, 0.001);
        }
        TracedAssertions.assertEqualsFloatTolerance(24, annotated.lines[1].baseline - annotated.lines[0].baseline, 0.001);
    }

    @:test public static function tightLineHeightRaisesOnlyTheAnnotatedLineByDefault():Void {
        var t = new TestTraceRecorder("RubyLayoutTest");
        t.section("tightLineHeightRaisesOnlyTheAnnotatedLineByDefault");
        var plain = RubyLayoutTestSupport.layoutTwelve([]);
        var annotated = RubyLayoutTestSupport.layoutTwelve([new RubySpan(new TextRange(4, 5), "w\u00F9")]);
        TracedAssertions.assertEquals(3, annotated.lines.length);
        TracedAssertions.assertEqualsFloatTolerance(plain.size.height + 6, annotated.size.height, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(18, annotated.lines[0].bottom - annotated.lines[0].top, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(24, annotated.lines[1].bottom - annotated.lines[1].top, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(18, annotated.lines[2].bottom - annotated.lines[2].top, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(24, annotated.lines[1].baseline - annotated.lines[0].baseline, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(18, annotated.lines[2].baseline - annotated.lines[1].baseline, 0.001);
        var decision = annotated.debug.rubyLineHeightDecision;
        TracedAssertions.assertEqualsString("PerLine", decision.mode);
        TracedAssertions.assertEqualsFloatTolerance(6, decision.maxExtra, 0.001);
        RubyLayoutTestSupport.assertFloatListEquals([0, 6, 0], decision.lineExtras);
        TracedAssertions.assertEqualsIntArray([1], decision.expandedLineIndices);
    }

    @:test public static function uniformModeAddsTheSameDeficitToEveryLine():Void {
        var t = new TestTraceRecorder("RubyLayoutTest");
        t.section("uniformModeAddsTheSameDeficitToEveryLine");
        var result = RubyLayoutTestSupport.layoutUniform([new RubySpan(new TextRange(4, 5), "w\u00F9")]);
        TracedAssertions.assertEquals(3, result.lines.length);
        for (i in 0...result.lines.length) {
            var line = result.lines[i];
            TracedAssertions.assertEqualsFloatTolerance(24, line.bottom - line.top, 0.001);
        }
        TracedAssertions.assertEqualsFloatTolerance(24, result.lines[1].baseline - result.lines[0].baseline, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(24, result.lines[2].baseline - result.lines[1].baseline, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(72, result.size.height, 0.001);
        var decision = result.debug.rubyLineHeightDecision;
        TracedAssertions.assertEqualsString("UniformParagraph", decision.mode);
        TracedAssertions.assertEqualsFloatTolerance(6, decision.maxExtra, 0.001);
        RubyLayoutTestSupport.assertFloatListEquals([6, 6, 6], decision.lineExtras);
        TracedAssertions.assertEqualsIntArray([0, 1, 2], decision.expandedLineIndices);
    }

    @:test public static function rubyVerticalGeometryUsesLatinMetricsNotReadingInk():Void {
        var t = new TestTraceRecorder("RubyLayoutTest");
        t.section("rubyVerticalGeometryUsesLatinMetricsNotReadingInk");
        var shallowInk = RubyLayoutTestSupport.layoutContradictory("he");
        var extremeInk = RubyLayoutTestSupport.layoutContradictory("pg");
        var shallowDecision = shallowInk.debug.rubyDecisions[0];
        var extremeDecision = extremeInk.debug.rubyDecisions[0];
        TracedAssertions.assertEqualsFloatTolerance(shallowInk.size.height, extremeInk.size.height, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(shallowInk.lines[0].top, extremeInk.lines[0].top, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(shallowInk.lines[0].baseline, extremeInk.lines[0].baseline, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(shallowInk.lines[0].bottom, extremeInk.lines[0].bottom, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(shallowDecision.baselineY, extremeDecision.baselineY, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(shallowDecision.ascent, extremeDecision.ascent, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(shallowDecision.descent, extremeDecision.descent, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(shallowInk.debug.rubyLineHeightDecision.rubyExtent, extremeInk.debug.rubyLineHeightDecision.rubyExtent,
            0.001);
    }

    @:test public static function noRubyIsUnchanged():Void {
        var t = new TestTraceRecorder("RubyLayoutTest");
        t.section("noRubyIsUnchanged");
        var plain = RubyLayoutTestSupport.layout([]);
        TracedAssertions.assertTrue(plain.debug.rubyDecisions.length == 0);
    }

    @:test public static function wideAdjacentReadingsSpreadButNarrowDoNot():Void {
        var t = new TestTraceRecorder("RubyLayoutTest");
        t.section("wideAdjacentReadingsSpreadButNarrowDoNot");
        var plain = RubyLayoutTestSupport.totalWidth(["", "", "", ""]);
        var narrow = RubyLayoutTestSupport.totalWidth(["y\u012B", "r\u00E9n", "y\u012B", "r\u00E9n"]);
        var wide = RubyLayoutTestSupport.totalWidth(["zhu\u0101ng", "chu\u00E1ng", "shu\u0101ng", "gu\u0101ng"]);
        TracedAssertions.assertTrue(narrow >= plain, "spread never shrinks the line (" + narrow + " vs " + plain + ")");
        TracedAssertions.assertTrue(wide > narrow, "wider readings spread more (" + wide + " vs " + narrow + ")");
    }
}
