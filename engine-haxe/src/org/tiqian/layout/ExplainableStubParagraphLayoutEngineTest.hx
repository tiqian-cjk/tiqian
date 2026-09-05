package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.linebreak.Hyphenator.NoHyphenator;
import org.tiqian.test.trace.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import std.UString;
import org.tiqian.layout.LineBreaker.LookaheadLineBreaker;
import org.tiqian.layout.LineBreaker;
import org.tiqian.layout.ExplainableStubParagraphLayoutEngineTestSupport.EmptyTextShaper;
import org.tiqian.layout.ExplainableStubParagraphLayoutEngineTestSupport.FixedBoundsTextShaper;

class ExplainableStubParagraphLayoutEngineTest {
    @:test public static function returnsDebuggableSingleLineResult():Void {
        var t = ExplainableStubParagraphLayoutEngineTestSupport.start("returnsDebuggableSingleLineResult");
        var r = new ExplainableStubParagraphLayoutEngine().layout(ExplainableStubParagraphLayoutEngineTestSupport.input("提椠", 240));
        TracedAssertions.assertEqualsInt(2, r.clusters.length);
        TracedAssertions.assertEqualsInt(1, r.lines.length);
        TracedAssertions.assertEqualsString("greedy", r.debug.lineDecisions[0].kind);
    }

    @:test public static function recordsInjectedLineBreakerStrategyInDebugDecisions():Void {
        var t = ExplainableStubParagraphLayoutEngineTestSupport.start("recordsInjectedLineBreakerStrategyInDebugDecisions");
        var r = ExplainableStubParagraphLayoutEngineTestSupport.engine(null, new LookaheadLineBreaker())
            .layout(ExplainableStubParagraphLayoutEngineTestSupport.input("提椠", 240));
        TracedAssertions.assertEqualsString("lookahead", r.debug.lineDecisions[0].kind);
    }

    @:test public static function mandatoryLineBreakClustersAreZeroWidthAndNotShaped():Void {
        var t = ExplainableStubParagraphLayoutEngineTestSupport.start("mandatoryLineBreakClustersAreZeroWidthAndNotShaped");
        var r = ExplainableStubParagraphLayoutEngineTestSupport.engine(null, new LookaheadLineBreaker())
            .layout(ExplainableStubParagraphLayoutEngineTestSupport.input("第一行\n第二行", 240));
        TracedAssertions.assertEqualsInt(2, r.lines.length);
        TracedAssertions.assertEqualsEnum(LineEndReason.MandatoryBreak, r.lines[0].endReason);
        TracedAssertions.assertEqualsEnum(LineEndReason.ParagraphEnd, r.lines[1].endReason);
        var b:Cluster = null;
        for (c in r.clusters)
            if (c.text == "\n")
                b = c;
        TracedAssertions.assertEqualsString("", b.displayText);
        TracedAssertions.assertEqualsFloat(0, b.advance);
        var found = false;
        for (ri in 0...r.glyphRuns.length) {
            var run = r.glyphRuns[ri];
            for (gi in 0...run.glyphs.length) {
                var g = run.glyphs[gi];
                if (g.clusterRange == b.range)
                    found = true;
            }
        }
        TracedAssertions.assertTrue(!found);
        var pair:Array<TextRange> = [r.glyphRuns[0].range, r.glyphRuns[1].range];
        TracedAssertions.assertEqualsTextRangeArray([new TextRange(0, 3), new TextRange(4, 7)], pair);
        TracedAssertions.assertEqualsRendered(Std.string(b.range), Std.string(r.debug.mandatoryBreakDecisions[0].range));
    }

    @:test public static function consecutiveMandatoryLineBreaksCreateOneEmptyLineBox():Void {
        var t = ExplainableStubParagraphLayoutEngineTestSupport.start("consecutiveMandatoryLineBreaksCreateOneEmptyLineBox");
        var r = new ExplainableStubParagraphLayoutEngine().layout(ExplainableStubParagraphLayoutEngineTestSupport.input("第一行\n\n第二行", 240));
        TracedAssertions.assertEqualsInt(3, r.lines.length);
        TracedAssertions.assertEqualsEnum(LineEndReason.MandatoryBreak, r.lines[0].endReason);
        TracedAssertions.assertEqualsEnum(LineEndReason.MandatoryBreak, r.lines[1].endReason);
        TracedAssertions.assertEqualsEnum(LineEndReason.ParagraphEnd, r.lines[2].endReason);
        var c = r.clusters[r.lines[1].clusterRange.start];
        TracedAssertions.assertEqualsString("\n", c.text);
        TracedAssertions.assertEqualsString("", c.displayText);
        TracedAssertions.assertEqualsFloat(0, c.advance);
        var h = r.debug.lineSpacingDecision.resolvedHeight;
        TracedAssertions.assertEqualsFloatTolerance(h, r.lines[1].bottom - r.lines[1].top, .001);
        TracedAssertions.assertEqualsFloatTolerance(h, r.lines[1].baseline - r.lines[0].baseline, .001);
        TracedAssertions.assertEqualsFloatTolerance(h, r.lines[2].baseline - r.lines[1].baseline, .001);
    }

    @:test public static function singleMandatoryBreakAfterWrappedLineDoesNotCreateEmptyLine():Void {
        var t = ExplainableStubParagraphLayoutEngineTestSupport.start("singleMandatoryBreakAfterWrappedLineDoesNotCreateEmptyLine");
        var text = "很久以前，曾经有一个名叫小红帽的孩子，生活在大森林的边上，大森林里充满了濒临灭绝的猫头鹰和珍稀植物，如果有人愿意花时间研究它们，就会发现癌症的治疗方法。\n小红帽和一位称为母亲的养育者一起生活";
        var r = ExplainableStubParagraphLayoutEngineTestSupport.engine(null, new LookaheadLineBreaker())
            .layout(ExplainableStubParagraphLayoutEngineTestSupport.input(text, 1200, null, null, new TextStyle(null, 48)));
        var dbg = "";
        for (l in r.lines)
            dbg += l.clusterRange.toString() + " " + Std.string(l.range) + " " + Std.string(l.endReason) + " \""
                + UString.slice(text, l.range.start, l.range.end) + "\"\n";
        TracedAssertions.assertTrue(r.lines.length >= 4);
        var no = false;
        for (l in r.lines)
            if (UString.slice(text, l.range.start, l.range.end) == "\n")
                no = true;
        TracedAssertions.assertTrue(!no, dbg);
        var idx = 0;
        for (i in 0...UString.count(text))
            if (UString.at(text, i) == 10)
                idx = i + 1;
        var line:LineBox = null;
        for (l in r.lines)
            if (l.range.end == idx)
                line = l;
        TracedAssertions.assertEqualsEnum(LineEndReason.MandatoryBreak, line.endReason);
        var h = r.debug.lineSpacingDecision.resolvedHeight;
        for (i in 1...r.lines.length)
            TracedAssertions.assertEqualsFloatTolerance(h, r.lines[i].baseline - r.lines[i - 1].baseline, .001);
    }

    @:test public static function crlfIsOneMandatoryBreakCluster():Void {
        var t = ExplainableStubParagraphLayoutEngineTestSupport.start("crlfIsOneMandatoryBreakCluster");
        var r = ExplainableStubParagraphLayoutEngineTestSupport.engine(null, new LookaheadLineBreaker())
            .layout(ExplainableStubParagraphLayoutEngineTestSupport.input("甲\r\n乙", 240));
        var b:Cluster = null;
        for (c in r.clusters)
            if (c.text == "\r\n")
                b = c;
        TracedAssertions.assertEqualsInt(2, r.lines.length);
        TracedAssertions.assertEqualsInt(1, r.debug.mandatoryBreakDecisions.length);
        TracedAssertions.assertEqualsInt(1, b.range.start);
        TracedAssertions.assertEqualsInt(3, b.range.end);
    }

    @:test public static function consecutiveAndTrailingMandatoryBreaksPreserveBlankLines():Void {
        var t = ExplainableStubParagraphLayoutEngineTestSupport.start("consecutiveAndTrailingMandatoryBreaksPreserveBlankLines");
        var r = ExplainableStubParagraphLayoutEngineTestSupport.engine(null, new LookaheadLineBreaker())
            .layout(ExplainableStubParagraphLayoutEngineTestSupport.input("甲\n\n乙\n", 240));
        TracedAssertions.assertEqualsInt(4, r.lines.length);
        for (i in 0...3)
            TracedAssertions.assertEqualsEnum(LineEndReason.MandatoryBreak, r.lines[i].endReason);
        TracedAssertions.assertEqualsEnum(LineEndReason.ParagraphEnd, r.lines[3].endReason);
        TracedAssertions.assertEqualsFloat(0, r.lines[1].visualWidth);
        TracedAssertions.assertEqualsRendered("TextRange(start=5, end=5)", Std.string(r.lines[3].range));
    }

    @:test public static function mandatoryBreakLineIsNotJustified():Void {
        var t = ExplainableStubParagraphLayoutEngineTestSupport.start("mandatoryBreakLineIsNotJustified");
        var r = ExplainableStubParagraphLayoutEngineTestSupport.engine(null, new LookaheadLineBreaker())
            .layout(ExplainableStubParagraphLayoutEngineTestSupport.input("短\n中文中文中文中文中文", 128));
        var l = r.lines[0];
        TracedAssertions.assertEqualsEnum(LineEndReason.MandatoryBreak, l.endReason);
        TracedAssertions.assertEqualsFloat(l.naturalWidth, l.adjustedWidth);
        TracedAssertions.assertTrue(r.debug.justificationDecisions.length == 0);
    }

    @:test public static function rejectsShaperClustersThatDoNotCoverFontDecisionRange():Void {
        var t = ExplainableStubParagraphLayoutEngineTestSupport.start("rejectsShaperClustersThatDoNotCoverFontDecisionRange");
        var f:Void->Void = function() {
            ExplainableStubParagraphLayoutEngineTestSupport.engine(new EmptyTextShaper())
                .layout(ExplainableStubParagraphLayoutEngineTestSupport.input("提椠", 240));
            return;
        };
        TracedAssertions.assertFailsWith(null, f);
    }

    @:test public static function preservesShaperGlyphBoundsInLayoutGlyphRuns():Void {
        var t = ExplainableStubParagraphLayoutEngineTestSupport.start("preservesShaperGlyphBoundsInLayoutGlyphRuns");
        var r = ExplainableStubParagraphLayoutEngineTestSupport.engine(new FixedBoundsTextShaper())
            .layout(ExplainableStubParagraphLayoutEngineTestSupport.input("A", 240));
        var g = r.glyphRuns[0].glyphs[0];
        TracedAssertions.assertEqualsInt(42, g.id);
        TracedAssertions.assertEqualsRendered("Rect(left=1, top=-10, right=12, bottom=2)", Std.string(g.bounds));
        TracedAssertions.assertEqualsFloat(20, g.advance);
    }

    @:test public static function recordsFallbackDecisionsPerCluster():Void {
        var t = ExplainableStubParagraphLayoutEngineTestSupport.start("recordsFallbackDecisionsPerCluster");
        var r = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null,
            new NoHyphenator()).layout(ExplainableStubParagraphLayoutEngineTestSupport.input("提椠……English——世界。", 320));
        var a = false;
        for (d in r.debug.fontDecisions)
            if (d.sourceText == "……" && d.displayText == "⋯⋯" && d.role == "CjkPunctuation" && d.fontKey == "cjk-primary")
                a = true;
        TracedAssertions.assertTrue(a);
        a = false;
        for (d in r.debug.fontDecisions)
            if (d.sourceText == "——" && d.displayText == "⸺")
                a = true;
        TracedAssertions.assertTrue(a);
        a = false;
        for (d in r.debug.shapingDecisions)
            if (d.sourceText == "——" && d.displayText == "⸺" && d.advance == 32 && d.source == "Stub")
                a = true;
        TracedAssertions.assertTrue(a);
        a = false;
        for (d in r.debug.fontDecisions)
            if (d.sourceText == "English" && d.role == "LatinText" && d.fontKey == "latin-primary")
                a = true;
        TracedAssertions.assertTrue(a);
        var c:Cluster = null;
        for (x in r.clusters)
            if (x.text == "English")
                c = x;
        TracedAssertions.assertEqualsString("English", c.text);
    }

    @:test public static function combiningMarksStayInTheirBaseShapingRuns():Void {
        var t = ExplainableStubParagraphLayoutEngineTestSupport.start("combiningMarksStayInTheirBaseShapingRuns");
        var r = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null,
            new NoHyphenator()).layout(ExplainableStubParagraphLayoutEngineTestSupport.input("༎ຶ Ỏ̷", 320));
        var a = false;
        for (d in r.debug.shapingDecisions)
            if (d.sourceText == "༎ຶ")
                a = true;
        TracedAssertions.assertTrue(a);
        a = false;
        for (d in r.debug.shapingDecisions)
            if (d.sourceText == "Ỏ̷")
                a = true;
        TracedAssertions.assertTrue(a);
        a = false;
        for (d in r.debug.shapingDecisions)
            if (d.sourceText == "ຶ" || d.sourceText == "̷")
                a = true;
        TracedAssertions.assertTrue(!a);
    }

    @:test public static function complexEmojiGraphemesStayAtomicAcrossGeometryOnlyBoundaries():Void {
        var t = ExplainableStubParagraphLayoutEngineTestSupport.start("complexEmojiGraphemesStayAtomicAcrossGeometryOnlyBoundaries");
        var text = "👩🏽‍💻";
        var content = new TiqianTextContent(text, null, [2]);
        var r = new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(content, null, new ParagraphStyle(null, null, null, Ic.Zero),
            new LayoutConstraints(320)));
        var a:Array<TextRange> = [];
        for (d in r.debug.fontDecisions)
            if (d.role == "Emoji")
                a.push(d.range);
        TracedAssertions.assertEqualsRendered("[TextRange(start=0, end=7)]", ExplainableStubParagraphLayoutEngineTestSupport.renderRanges(a));
        TracedAssertions.assertEqualsRendered("['" + text + "']",
            ExplainableStubParagraphLayoutEngineTestSupport.renderStrings([r.debug.shapingDecisions[0].sourceText]));
    }

    @:test public static function complexEmojiSequencesReachTheShaperAsCompleteEmojiRanges():Void {
        var t = ExplainableStubParagraphLayoutEngineTestSupport.start("complexEmojiSequencesReachTheShaperAsCompleteEmojiRanges");
        var r = new ExplainableStubParagraphLayoutEngine().layout(ExplainableStubParagraphLayoutEngineTestSupport.input("前👩🏽‍💻后🇨🇳与1️⃣和❤️。", 320));
        var a:Array<String> = [];
        for (d in r.debug.shapingDecisions)
            if (d.fontKey == "symbol-fallback")
                a.push(d.sourceText);
        TracedAssertions.assertEqualsRendered("['👩🏽‍💻', '🇨🇳', '1️⃣', '❤️']", ExplainableStubParagraphLayoutEngineTestSupport.renderStrings(a));
        var b:Array<String> = [];
        for (d in r.debug.fontDecisions)
            if (d.role == "Emoji")
                b.push(d.sourceText);
        TracedAssertions.assertEqualsRendered("['👩🏽‍💻', '🇨🇳', '1️⃣', '❤️']", ExplainableStubParagraphLayoutEngineTestSupport.renderStrings(b));
    }

    @:test public static function emojiRoleMatrixSeparatesSupportedSequencesFromAdjacentAndUnrelatedText():Void {
        var t = ExplainableStubParagraphLayoutEngineTestSupport.start("emojiRoleMatrixSeparatesSupportedSequencesFromAdjacentAndUnrelatedText");
        var cases = [
            "a1️⃣",
            "1️⃣a",
            "a😀中",
            "a❤️中",
            "a©️中",
            "a⌚︎中",
            "a1⃣中",
            "a👍🏽中",
            "a👩🏽‍💻中",
            "a🏳️‍⚧️中",
            "a🇨🇳中",
            "a🏴\u{1F3F4}\u{1F467}\u{1F462}\u{1F465}\u{1F46E}\u{1F467}\u{1F3FF}中",
            "中\uFE0F",
            "a\uFE0F",
            "a⃣中",
            "a1\uFE0F中",
            "中🏽",
            "a👩‍中",
            "中‍👩a"
        ];
        var mismatches:Array<String> = [];
        for (text in cases) {
            var r = new ExplainableStubParagraphLayoutEngine().layout(ExplainableStubParagraphLayoutEngineTestSupport.input(text, 320));
            if (r.debug.fontDecisions.length == 0)
                mismatches.push(text);
        }
        TracedAssertions.assertEqualsRendered("[]", ExplainableStubParagraphLayoutEngineTestSupport.renderStrings(mismatches));
    }

    @:test public static function sourceGraphemeBoundariesDoNotJoinZwJWithOrdinaryText():Void {
        var t = ExplainableStubParagraphLayoutEngineTestSupport.start("sourceGraphemeBoundariesDoNotJoinZwJWithOrdinaryText");
        TracedAssertions.assertEqualsIntArray([0, 3, 4], ExplainableStubParagraphLayoutEngineTestSupport.graphemeBoundaries("👩‍中"));
        TracedAssertions.assertEqualsIntArray([0, 2, 4], ExplainableStubParagraphLayoutEngineTestSupport.graphemeBoundaries("中‍👩"));
    }

    @:test public static function recordsUnicodeEmojiSequenceRolePromotions():Void {
        var t = ExplainableStubParagraphLayoutEngineTestSupport.start("recordsUnicodeEmojiSequenceRolePromotions");
        var r = new ExplainableStubParagraphLayoutEngine().layout(ExplainableStubParagraphLayoutEngineTestSupport.input("❤️与1️⃣", 320));
        var a:Array<String> = [];
        var b:Array<String> = [];
        for (d in r.debug.roleOverrides)
            if (d.source == "UnicodeEmojiSequenceRolePromotion") {
                a.push("'" + d.sourceText + "'");
                b.push("'" + d.originalRole + "'");
            }
        TracedAssertions.assertEqualsRendered("[('❤️', 'Symbol'), ('1️⃣', 'LatinText')]", ExplainableStubParagraphLayoutEngineTestSupport.renderPairs(a, b));
        var ok = true;
        for (d in r.debug.roleOverrides)
            if (d.source == "UnicodeEmojiSequenceRolePromotion"
                && (d.overriddenRole != "Emoji" || (d.reason != "EmojiStyleVariationSequence" && d.reason != "KeycapSequence")))
                ok = false;
        TracedAssertions.assertTrue(ok);
    }

    @:test public static function complexEmojiGraphemesHonorTextSpanStyleBoundaries():Void {
        var t = ExplainableStubParagraphLayoutEngineTestSupport.start("complexEmojiGraphemesHonorTextSpanStyleBoundaries");
        var text = "👩🏽‍💻";
        var content = new TiqianTextContent(text, [
            new TextSpan(new TextRange(2, ExplainableStubParagraphLayoutEngineTestSupport.textLength(text)), new TextStyle(null, null, null, 700))
        ], [2]);
        var r = new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(content, null, new ParagraphStyle(null, null, null, Ic.Zero),
            new LayoutConstraints(320)));
        var a:Array<TextRange> = [];
        for (d in r.debug.fontDecisions)
            if (d.role == "Emoji")
                a.push(d.range);
        TracedAssertions.assertEqualsRendered("[TextRange(start=0, end=2), TextRange(start=2, end=7)]",
            ExplainableStubParagraphLayoutEngineTestSupport.renderRanges(a));
        TracedAssertions.assertEqualsRendered("['👩', '🏽‍💻']",
            ExplainableStubParagraphLayoutEngineTestSupport.renderStrings([r.debug.shapingDecisions[0].sourceText, r.debug.shapingDecisions[1].sourceText]));
    }
}
