package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.*;
import org.tiqian.clreq.*;
import std.ReadOnlyArray;
import org.tiqian.layout.LineBreaker.GreedyLineBreaker;
import org.tiqian.layout.LineBreaker.LookaheadLineBreaker;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.linebreak.Hyphenator.NoHyphenator;

class AsciiPointMarkKinsokuTest {
    @:test public static function cjkAttachedAsciiPointMarksCannotStartWrappedLinesAndStayLatin():Void {
        final t = new TestTraceRecorder("AsciiPointMarkKinsokuTest");
        t.section("cjkAttachedAsciiPointMarksCannotStartWrappedLinesAndStayLatin");
        for (mi in 0...6) {
            final mark = [",", ".", ":", ";", "!", "?"][mi];
            for (b in AsciiPointMarkKinsokuTestSupport.breakers()) {
                final text = "中文中文" + mark + "中文";
                final r = AsciiPointMarkKinsokuTestSupport.layout(text, 64, b.breaker);
                final ls = AsciiPointMarkKinsokuTestSupport.lineTexts(r, text);
                var starts = false;
                for (i in 0...ls.length)
                    if (StringTools.startsWith(ls[i], mark))
                        starts = true;
                TracedAssertions.assertTrue(!starts, b.label + " placed '" + mark + "' at line start: " + AsciiPointMarkKinsokuTestSupport.renderStrings(ls));
                var p = AsciiPointMarkKinsokuTestSupport.clustersWithText(r, mark)[0];
                TracedAssertions.assertEqualsString("latin-primary", p.fontKey, b.label + " '" + mark + "' face");
                var f = AsciiPointMarkKinsokuTestSupport.fontDecision(r, p.range);
                TracedAssertions.assertEqualsString("LatinText", f.role, b.label + " '" + mark + "' role");
                TracedAssertions.assertTrue(!AsciiPointMarkKinsokuTestSupport.hasPunctuation(r, p.range),
                    b.label
                    + " '"
                    + mark
                    + "' must not enter CJK punctuation geometry");
                var c = AsciiPointMarkKinsokuTestSupport.contextual(r, p.range);
                TracedAssertions.assertEqualsString("LineStart", c.forbiddenPosition);
                TracedAssertions.assertEqualsString("AttachedAsciiPointMarkKinsoku", c.reason);
            }
        }
    }

    @:test public static function leadingPointMarkRunIsSplitFromFollowingLatinText():Void {
        final t = new TestTraceRecorder("AsciiPointMarkKinsokuTest");
        t.section("leadingPointMarkRunIsSplitFromFollowingLatinText");
        final text = "中文,anyway继续";
        for (b in AsciiPointMarkKinsokuTestSupport.breakers()) {
            final r = AsciiPointMarkKinsokuTestSupport.layout(text, 64, b.breaker);
            final ls = AsciiPointMarkKinsokuTestSupport.lineTexts(r, text);
            var st = false;
            for (i in 0...ls.length)
                if (StringTools.startsWith(ls[i], ","))
                    st = true;
            TracedAssertions.assertTrue(!st, b.label + " lines: " + AsciiPointMarkKinsokuTestSupport.renderStrings(ls));
            TracedAssertions.assertTrue(AsciiPointMarkKinsokuTestSupport.hasCluster(r, ","),
                b.label + " comma cluster: " + AsciiPointMarkKinsokuTestSupport.renderClusters(r.clusters));
            TracedAssertions.assertTrue(AsciiPointMarkKinsokuTestSupport.hasFontSource(r, "anyway"),
                b.label + " Latin decision: " + AsciiPointMarkKinsokuTestSupport.renderFonts(r.debug.fontDecisions));
            TracedAssertions.assertFalse(AsciiPointMarkKinsokuTestSupport.hasCluster(r, ",anyway"), b.label + " bound the word to the comma");
        }
    }

    @:test public static function LatinTokensAndAmbiguousAsciiCharactersKeepExistingSegmentation():Void {
        final t = new TestTraceRecorder("AsciiPointMarkKinsokuTest");
        t.section("LatinTokensAndAmbiguousAsciiCharactersKeepExistingSegmentation");
        final r = AsciiPointMarkKinsokuTestSupport.layout("foo,bar 1,234 50% \"quoted\"", 1000, new GreedyLineBreaker());
        for (x in ["foo,bar", "1,234", "50%", "\"quoted\""])
            TracedAssertions.assertTrue(AsciiPointMarkKinsokuTestSupport.hasCluster(r, x));
        var q = AsciiPointMarkKinsokuTestSupport.forbiddenFor(r, "\"quoted\"");
        TracedAssertions.assertEqualsStringArray(["LineStart", "LineEnd"], q);
    }

    @:test public static function pointMarkSplitFromAnOverlongLatinTokenStillCannotStartALine():Void {
        final t = new TestTraceRecorder("AsciiPointMarkKinsokuTest");
        t.section("pointMarkSplitFromAnOverlongLatinTokenStillCannotStartALine");
        for (w in [32.0, 36.0, 40.0, 48.0])
            for (b in AsciiPointMarkKinsokuTestSupport.breakers()) {
                final r = AsciiPointMarkKinsokuTestSupport.layout("anyway,你", w, b.breaker);
                var x = false;
                for (s in AsciiPointMarkKinsokuTestSupport.lineTexts(r, "anyway,你"))
                    if (StringTools.startsWith(s, ","))
                        x = true;
                TracedAssertions.assertTrue(!x,
                    b.label
                    + " width="
                    + w
                    + " lines: "
                    + AsciiPointMarkKinsokuTestSupport.renderStrings(AsciiPointMarkKinsokuTestSupport.lineTexts(r, "anyway,你")));
            }
    }

    @:test public static function pointMarkExposedByASecondStageLatinCutIsSplitFromItsSuffix():Void {
        final t = new TestTraceRecorder("AsciiPointMarkKinsokuTest");
        t.section("pointMarkExposedByASecondStageLatinCutIsSplitFromItsSuffix");
        for (b in AsciiPointMarkKinsokuTestSupport.breakers()) {
            final r = AsciiPointMarkKinsokuTestSupport.layout(".,A中", 32, b.breaker);
            var x = false;
            for (s in AsciiPointMarkKinsokuTestSupport.lineTexts(r, ".,A中"))
                if (StringTools.startsWith(s, ","))
                    x = true;
            TracedAssertions.assertTrue(!x,
                b.label + " lines: " + AsciiPointMarkKinsokuTestSupport.renderStrings(AsciiPointMarkKinsokuTestSupport.lineTexts(r, ".,A中")));
            TracedAssertions.assertEqualsString(".,", AsciiPointMarkKinsokuTestSupport.lineTexts(r, ".,A中")[0],
                b.label + " should keep the avoidable pair together");
            TracedAssertions.assertTrue(AsciiPointMarkKinsokuTestSupport.hasCluster(r, ","),
                b.label + " clusters: " + AsciiPointMarkKinsokuTestSupport.renderClusters(r.clusters));
            TracedAssertions.assertFalse(AsciiPointMarkKinsokuTestSupport.hasCluster(r, ",A"), b.label + " kept the post-cut suffix attached");
        }
    }

    @:test public static function impossibleMeasureHangsThePointMarkInsteadOfLeavingItAtLineStart():Void {
        final t = new TestTraceRecorder("AsciiPointMarkKinsokuTest");
        t.section("impossibleMeasureHangsThePointMarkInsteadOfLeavingItAtLineStart");
        for (w in [1.0, 8.0, 15.0, 23.0, 31.0])
            for (b in AsciiPointMarkKinsokuTestSupport.breakers()) {
                final r = AsciiPointMarkKinsokuTestSupport.layout("中,文", w, b.breaker);
                var x = false;
                for (s in AsciiPointMarkKinsokuTestSupport.lineTexts(r, "中,文"))
                    if (StringTools.startsWith(s, ","))
                        x = true;
                TracedAssertions.assertTrue(!x,
                    b.label
                    + " width="
                    + w
                    + " lines: "
                    + AsciiPointMarkKinsokuTestSupport.renderStrings(AsciiPointMarkKinsokuTestSupport.lineTexts(r, "中,文")));
                TracedAssertions.assertEqualsString("AttachedAsciiPointMarkImpossibleMeasureHang",
                    AsciiPointMarkKinsokuTestSupport.contextual(r, null).impossibleMeasureFallback, b.label
                    + " width="
                    + w
                    + " fallback");
                TracedAssertions.assertTrue(AsciiPointMarkKinsokuTestSupport.hasRepair(r, "Hang"),
                    b.label
                    + " width="
                    + w
                    + " repairs: "
                    + AsciiPointMarkKinsokuTestSupport.renderLineDecisions(r.debug.lineDecisions));
            }
    }

    @:test public static function firstLineIndentUsesTheSameImpossibleMeasureFallback():Void {
        final t = new TestTraceRecorder("AsciiPointMarkKinsokuTest");
        t.section("firstLineIndentUsesTheSameImpossibleMeasureFallback");
        for (b in AsciiPointMarkKinsokuTestSupport.breakers()) {
            final r = AsciiPointMarkKinsokuTestSupport.layoutWithoutExplicitIndent("中,文", 32, b.breaker);
            TracedAssertions.assertTrue(!StringTools.startsWith(AsciiPointMarkKinsokuTestSupport.lineTexts(r, "中,文")[0], ","),
                b.label + " lines: " + AsciiPointMarkKinsokuTestSupport.renderStrings(AsciiPointMarkKinsokuTestSupport.lineTexts(r, "中,文")));
            TracedAssertions.assertEqualsString("AttachedAsciiPointMarkImpossibleMeasureHang",
                AsciiPointMarkKinsokuTestSupport.contextual(r, null).impossibleMeasureFallback, b.label + " adaptive first-line indent");
        }
    }

    @:test public static function lineBreakGeometryIncludesBopomofoSpreadWhenChoosingTheFallback():Void {
        final t = new TestTraceRecorder("AsciiPointMarkKinsokuTest");
        t.section("lineBreakGeometryIncludesBopomofoSpreadWhenChoosingTheFallback");
        for (b in AsciiPointMarkKinsokuTestSupport.breakers()) {
            final r = AsciiPointMarkKinsokuTestSupport.layout("中,文", 32, b.breaker, null, null, null,
                [new RubySpan(new TextRange(0, 1), "ㄅ", RubyKind.Bopomofo)]);
            TracedAssertions.assertTrue(!StringTools.startsWith(AsciiPointMarkKinsokuTestSupport.lineTexts(r, "中,文")[0], ","),
                b.label + " lines: " + AsciiPointMarkKinsokuTestSupport.renderStrings(AsciiPointMarkKinsokuTestSupport.lineTexts(r, "中,文")));
            TracedAssertions.assertEqualsString("AttachedAsciiPointMarkImpossibleMeasureHang",
                AsciiPointMarkKinsokuTestSupport.contextual(r, null).impossibleMeasureFallback, b.label + " must use post-spread line-break geometry");
        }
    }

    @:test public static function styledPointMarkRunCanExtendOneImpossibleMeasureHang():Void {
        final t = new TestTraceRecorder("AsciiPointMarkKinsokuTest");
        t.section("styledPointMarkRunCanExtendOneImpossibleMeasureHang");
        for (b in AsciiPointMarkKinsokuTestSupport.breakers()) {
            final r = AsciiPointMarkKinsokuTestSupport.layout("中!,文", 15, b.breaker, null, null, null, null,
                [new TextSpan(new TextRange(2, 3), new TextStyle(null, null, null, 700))]);
            var x = false;
            for (s in AsciiPointMarkKinsokuTestSupport.lineTexts(r, "中!,文"))
                if (StringTools.startsWith(s, "!") || StringTools.startsWith(s, ","))
                    x = true;
            TracedAssertions.assertTrue(!x,
                b.label + " lines: " + AsciiPointMarkKinsokuTestSupport.renderStrings(AsciiPointMarkKinsokuTestSupport.lineTexts(r, "中!,文")));
            TracedAssertions.assertTrue(AsciiPointMarkKinsokuTestSupport.hasCluster(r, "!"), b.label + " exclamation cluster");
            TracedAssertions.assertTrue(AsciiPointMarkKinsokuTestSupport.hasCluster(r, ","), b.label + " comma cluster");
            var n = 0;
            for (i in 0...r.debug.contextualKinsokuDecisions.length)
                if (r.debug.contextualKinsokuDecisions[i].impossibleMeasureFallback == "AttachedAsciiPointMarkImpossibleMeasureHang")
                    n++;
            TracedAssertions.assertEqualsInt(2, n,
                b.label + " applied fallbacks: " + AsciiPointMarkKinsokuTestSupport.renderContextual(r.debug.contextualKinsokuDecisions));
            var hangingAdvance = 0.0;
            for (i in 0...r.lines.length)
                if (r.lines[i].hangingPunctuationAdvance > 0)
                    hangingAdvance = r.lines[i].hangingPunctuationAdvance;
            var expectedAdvance = 0.0;
            for (i in 0...r.clusters.length)
                if (r.clusters[i].text == "!" || r.clusters[i].text == ",")
                    expectedAdvance += r.clusters[i].advance;
            TracedAssertions.assertEqualsFloat(expectedAdvance, hangingAdvance, b.label + " run advance");
        }
    }

    @:test public static function contextualRunCanExtendAProfileHangOnlyWithinTheSameProtectedGroup():Void {
        final t = new TestTraceRecorder("AsciiPointMarkKinsokuTest");
        t.section("contextualRunCanExtendAProfileHangOnlyWithinTheSameProtectedGroup");
        for (b in AsciiPointMarkKinsokuTestSupport.breakers()) {
            final r = AsciiPointMarkKinsokuTestSupport.layout("中，,文", 15, b.breaker, null, HangingPunctuationStyle.PauseStops);
            var x = false;
            for (s in AsciiPointMarkKinsokuTestSupport.lineTexts(r, "中，,文"))
                if (StringTools.startsWith(s, ",") || StringTools.startsWith(s, "，"))
                    x = true;
            TracedAssertions.assertTrue(!x,
                b.label + " lines: " + AsciiPointMarkKinsokuTestSupport.renderStrings(AsciiPointMarkKinsokuTestSupport.lineTexts(r, "中，,文")));
            TracedAssertions.assertEqualsString("AttachedAsciiPointMarkImpossibleMeasureHang",
                AsciiPointMarkKinsokuTestSupport.contextual(r, null).impossibleMeasureFallback, b.label + " contextual extension");
        }
    }

    @:test public static function adjacentImpossibleGroupsDoNotShareHangProvenance():Void {
        final t = new TestTraceRecorder("AsciiPointMarkKinsokuTest");
        t.section("adjacentImpossibleGroupsDoNotShareHangProvenance");
        for (b in AsciiPointMarkKinsokuTestSupport.breakers()) {
            final r = AsciiPointMarkKinsokuTestSupport.layout("中!，?", 15, b.breaker, null, HangingPunctuationStyle.PauseStops);
            var n = 0;
            for (i in 0...r.lines.length)
                if (r.lines[i].hangingPunctuationAdvance > 0)
                    n++;
            TracedAssertions.assertEqualsInt(2, n,
                b.label + " must keep the adjacent protected groups separate: " + AsciiPointMarkKinsokuTestSupport.renderLines(r.lines));
            var x = false;
            for (s in AsciiPointMarkKinsokuTestSupport.lineTexts(r, "中!，?"))
                if (StringTools.startsWith(s, "!") || StringTools.startsWith(s, "?"))
                    x = true;
            TracedAssertions.assertTrue(!x,
                b.label + " lines: " + AsciiPointMarkKinsokuTestSupport.renderStrings(AsciiPointMarkKinsokuTestSupport.lineTexts(r, "中!，?")));
        }
    }

    @:test public static function compressedClosingAndPointMarkPairDoesNotReportAnUnusedHangFallback():Void {
        final t = new TestTraceRecorder("AsciiPointMarkKinsokuTest");
        t.section("compressedClosingAndPointMarkPairDoesNotReportAnUnusedHangFallback");
        for (b in AsciiPointMarkKinsokuTestSupport.breakers()) {
            final r = AsciiPointMarkKinsokuTestSupport.layout("）,文", 24, b.breaker, null, null, null, null, null, new LineLengthGrid(false));
            TracedAssertions.assertEqualsString("）,", AsciiPointMarkKinsokuTestSupport.lineTexts(r, "）,文")[0],
                b.label + " lines: " + AsciiPointMarkKinsokuTestSupport.renderStrings(AsciiPointMarkKinsokuTestSupport.lineTexts(r, "）,文")));
            TracedAssertions.assertTrue(!AsciiPointMarkKinsokuTestSupport.hasRepair(r, "Hang"),
                b.label + " repairs: " + AsciiPointMarkKinsokuTestSupport.renderLineDecisions(r.debug.lineDecisions));
            TracedAssertions.assertEqualsNullableString(null, AsciiPointMarkKinsokuTestSupport.contextual(r, null).impossibleMeasureFallback);
        }
    }

    @:test public static function kinsokuNoneDisablesClreqButKeepsTheUax14AsciiPointMarkBoundary():Void {
        final t = new TestTraceRecorder("AsciiPointMarkKinsokuTest");
        t.section("kinsokuNoneDisablesClreqButKeepsTheUax14AsciiPointMarkBoundary");
        for (b in AsciiPointMarkKinsokuTestSupport.breakers()) {
            final r = AsciiPointMarkKinsokuTestSupport.layout("中文中文,中文", 64, b.breaker, KinsokuLevel.None);
            var x = false;
            for (s in AsciiPointMarkKinsokuTestSupport.lineTexts(r, "中文中文,中文"))
                if (StringTools.startsWith(s, ","))
                    x = true;
            TracedAssertions.assertTrue(!x,
                b.label + " lines: " + AsciiPointMarkKinsokuTestSupport.renderStrings(AsciiPointMarkKinsokuTestSupport.lineTexts(r, "中文中文,中文")));
            TracedAssertions.assertEqualsString("Uax14WesternPunctuationBoundary:LB15d", AsciiPointMarkKinsokuTestSupport.contextualByText(r, ",").reason,
                b.label);
        }
    }

    @:test public static function authoredWhitespaceAndMandatoryBreakDoNotCreateContextualKinsoku():Void {
        final t = new TestTraceRecorder("AsciiPointMarkKinsokuTest");
        t.section("authoredWhitespaceAndMandatoryBreakDoNotCreateContextualKinsoku");
        for (text in ["中\n,文", ",中文"])
            for (b in AsciiPointMarkKinsokuTestSupport.breakers()) {
                final r = AsciiPointMarkKinsokuTestSupport.layout(text, 1000, b.breaker);
                TracedAssertions.assertTrue(r.debug.contextualKinsokuDecisions.length == 0,
                    b.label
                    + " text="
                    + StringTools.replace(text, "\n", "\\n")
                    + " decisions="
                    + AsciiPointMarkKinsokuTestSupport.renderContextual(r.debug.contextualKinsokuDecisions));
            }
        for (b in AsciiPointMarkKinsokuTestSupport.breakers()) {
            final r = AsciiPointMarkKinsokuTestSupport.layout("中 ,文", 1000, b.breaker);
            TracedAssertions.assertEqualsString("Uax14WesternPunctuationBoundary:LB15d", AsciiPointMarkKinsokuTestSupport.contextualByText(r, ",").reason,
                b.label);
        }
    }

    @:test public static function mandatoryBreakControlAfterAHungPointMarkStaysInTheTrailingSuffix():Void {
        final t = new TestTraceRecorder("AsciiPointMarkKinsokuTest");
        t.section("mandatoryBreakControlAfterAHungPointMarkStaysInTheTrailingSuffix");
        for (b in AsciiPointMarkKinsokuTestSupport.breakers()) {
            final r = AsciiPointMarkKinsokuTestSupport.layout("中,\n文", 15, b.breaker);
            var x = false;
            for (s in AsciiPointMarkKinsokuTestSupport.lineTexts(r, "中,\n文"))
                if (StringTools.startsWith(s, ","))
                    x = true;
            TracedAssertions.assertTrue(!x,
                b.label + " lines: " + AsciiPointMarkKinsokuTestSupport.renderStrings(AsciiPointMarkKinsokuTestSupport.lineTexts(r, "中,\n文")));
            TracedAssertions.assertEqualsString("AttachedAsciiPointMarkImpossibleMeasureHang",
                AsciiPointMarkKinsokuTestSupport.contextual(r, null).impossibleMeasureFallback);
        }
    }

    @:test public static function reportedRealWorldParagraphNeverWrapsDirectlyBeforeAnAsciiComma():Void {
        final t = new TestTraceRecorder("AsciiPointMarkKinsokuTest");
        t.section("reportedRealWorldParagraphNeverWrapsDirectlyBeforeAnAsciiComma");
        for (w in [36.0, 40.0, 160.0, 240.0, 320.0])
            for (b in AsciiPointMarkKinsokuTestSupport.breakers()) {
                final r = AsciiPointMarkKinsokuTestSupport.layout(AsciiPointMarkKinsokuTestSupport.REPORTED_PARAGRAPH, w, b.breaker);
                var x = false;
                for (s in AsciiPointMarkKinsokuTestSupport.lineTexts(r, AsciiPointMarkKinsokuTestSupport.REPORTED_PARAGRAPH))
                    if (StringTools.startsWith(s, ","))
                        x = true;
                TracedAssertions.assertTrue(!x,
                    b.label
                    + " width="
                    + w
                    + " still starts a line with comma:\n"
                    + AsciiPointMarkKinsokuTestSupport.joinLines(AsciiPointMarkKinsokuTestSupport.lineTexts(r,
                        AsciiPointMarkKinsokuTestSupport.REPORTED_PARAGRAPH)));
            }
    }
}
