package org.tiqian.layout;

import org.tiqian.clreq.KinsokuLevel;
import org.tiqian.core.*;
import org.tiqian.font.FontRole;
import org.tiqian.layout.LineBreaker.GreedyLineBreaker;
import org.tiqian.test.trace.*;

class UnicodePunctuationBoundaryTest {
    @:test public static function westernBracketsTouchingCjkExposeAllFourStretchBoundaries():Void {
        final t = new TestTraceRecorder("UnicodePunctuationBoundaryTest");
        t.section("westernBracketsTouchingCjkExposeAllFourStretchBoundaries");
        final text = "育(中文)后";
        final c = UnicodePunctuationBoundaryTestSupport.clusters(text);
        final roles = [
            FontRole.CjkText,
            FontRole.LatinText,
            FontRole.CjkText,
            FontRole.CjkText,
            FontRole.LatinText,
            FontRole.CjkText
        ];
        TracedAssertions.assertEqualsIntSet(UnicodePunctuationBoundaryTestSupport.setInts([0, 1, 3, 4]),
            UnicodePunctuationBoundaryResolver.resolveWesternBracketCjkInterCharBoundaries(text, c, roles));
        final w = "A(B)C";
        TracedAssertions.assertEqualsIntSet(UnicodePunctuationBoundaryTestSupport.setInts([]),
            UnicodePunctuationBoundaryResolver.resolveWesternBracketCjkInterCharBoundaries(w, UnicodePunctuationBoundaryTestSupport.clusters(w, true),
                UnicodePunctuationBoundaryTestSupport.roles(w, true)));
    }

    @:test public static function westernClosingPunctuationCannotBeginAnAutomaticLine():Void {
        final t = new TestTraceRecorder("UnicodePunctuationBoundaryTest");
        t.section("westernClosingPunctuationCannotBeginAnAutomaticLine");
        for (mi in 0...9) {
            final mark = UnicodePunctuationBoundaryTestSupport.markClosing(mi);
            for (bi in 0...UnicodePunctuationBoundaryTestSupport.breakers().length) {
                final b = UnicodePunctuationBoundaryTestSupport.breakers()[bi];
                final text = "中文" + mark + "文";
                final r = UnicodePunctuationBoundaryTestSupport.layout(text, 32, b.breaker, KinsokuLevel.None);
                final ls = UnicodePunctuationBoundaryTestSupport.lines(r, text);
                var ok = true;
                for (x in ls)
                    if (StringTools.startsWith(x, mark))
                        ok = false;
                TracedAssertions.assertTrue(ok, b.label + " placed '" + mark + "' at line start: [" + ls.join(", ") + "]");
                var d = false;
                for (xi in 0...r.debug.contextualKinsokuDecisions.length) {
                    final x = r.debug.contextualKinsokuDecisions[xi];
                    if (x.sourceText == mark
                        && x.forbiddenPosition == "LineStart"
                        && StringTools.startsWith(x.reason, "Uax14WesternPunctuationBoundary:"))
                        d = true;
                }
                TracedAssertions.assertTrue(d, b.label + " '" + mark + "' decisions=" + r.debug.contextualKinsokuDecisions);
            }
        }
    }

    @:test public static function westernOpeningBracketsCannotEndAnAutomaticLine():Void {
        final t = new TestTraceRecorder("UnicodePunctuationBoundaryTest");
        t.section("westernOpeningBracketsCannotEndAnAutomaticLine");
        for (mi in 0...3) {
            final mark = UnicodePunctuationBoundaryTestSupport.markOpening(mi);
            for (bi in 0...UnicodePunctuationBoundaryTestSupport.breakers().length) {
                final b = UnicodePunctuationBoundaryTestSupport.breakers()[bi];
                final text = "ABCD" + mark + "E";
                final r = UnicodePunctuationBoundaryTestSupport.layout(text, 40, b.breaker);
                var ok = true;
                for (x in UnicodePunctuationBoundaryTestSupport.lines(r, text))
                    if (StringTools.endsWith(x, mark))
                        ok = false;
                TracedAssertions.assertTrue(ok,
                    b.label
                    + " placed '"
                    + mark
                    + "' at line end: ["
                    + UnicodePunctuationBoundaryTestSupport.lines(r, text).join(", ")
                    + "]");
                var d = false;
                for (xi in 0...r.debug.contextualKinsokuDecisions.length) {
                    final x = r.debug.contextualKinsokuDecisions[xi];
                    if (x.sourceText == mark && x.forbiddenPosition == "LineEnd" && x.reason == "Uax14WesternPunctuationBoundary:LB14")
                        d = true;
                }
                TracedAssertions.assertTrue(d, b.label + " '" + mark + "' decisions=" + r.debug.contextualKinsokuDecisions);
            }
        }
    }

    @:test public static function unmatchedWesternCurlyDoubleQuotesRetainTheirDirection():Void {
        final t = new TestTraceRecorder("UnicodePunctuationBoundaryTest");
        t.section("unmatchedWesternCurlyDoubleQuotesRetainTheirDirection");
        for (bi in 0...UnicodePunctuationBoundaryTestSupport.breakers().length) {
            final b = UnicodePunctuationBoundaryTestSupport.breakers()[bi];
            final a = "ABCD”E";
            final r = UnicodePunctuationBoundaryTestSupport.layout(a, 32, b.breaker);
            var ok = true;
            for (x in UnicodePunctuationBoundaryTestSupport.lines(r, a))
                if (StringTools.startsWith(x, "”"))
                    ok = false;
            TracedAssertions.assertTrue(ok, b.label + " closing lines=[" + UnicodePunctuationBoundaryTestSupport.lines(r, a).join(", ") + "]");
            TracedAssertions.assertEqualsString("Uax14WesternPunctuationBoundary:LB19", UnicodePunctuationBoundaryTestSupport.findReason(r, "”", "LineStart"));
            final q = "ABCD“E";
            final z = UnicodePunctuationBoundaryTestSupport.layout(q, 40, b.breaker);
            ok = true;
            for (x in UnicodePunctuationBoundaryTestSupport.lines(z, q))
                if (StringTools.endsWith(x, "“"))
                    ok = false;
            TracedAssertions.assertTrue(ok, b.label + " opening lines=[" + UnicodePunctuationBoundaryTestSupport.lines(z, q).join(", ") + "]");
            TracedAssertions.assertEqualsString("Uax14WesternPunctuationBoundary:LB19", UnicodePunctuationBoundaryTestSupport.findReason(z, "“", "LineEnd"));
        }
    }

    @:test public static function unmatchedElisionApostropheBindsForwardInsteadOfBeingGuessedAsACloser():Void {
        final t = new TestTraceRecorder("UnicodePunctuationBoundaryTest");
        t.section("unmatchedElisionApostropheBindsForwardInsteadOfBeingGuessedAsACloser");
        final r = UnicodePunctuationBoundaryTestSupport.layout("AB ’90s", 16, new GreedyLineBreaker());
        var start = false;
        for (xi in 0...r.debug.contextualKinsokuDecisions.length) {
            final x = r.debug.contextualKinsokuDecisions[xi];
            if (x.sourceText == "’" && x.forbiddenPosition == "LineStart")
                start = true;
        }
        TracedAssertions.assertTrue(!start);
        TracedAssertions.assertEqualsString("Uax14WesternPunctuationBoundary:LB19", UnicodePunctuationBoundaryTestSupport.findReason(r, "’", "LineEnd"));
    }

    @:test public static function westernBaselineSurvivesClreqKinsokuNone():Void {
        final t = new TestTraceRecorder("UnicodePunctuationBoundaryTest");
        t.section("westernBaselineSurvivesClreqKinsokuNone");
        final r = UnicodePunctuationBoundaryTestSupport.layout("ABCD)E", 32, new GreedyLineBreaker(), KinsokuLevel.None);
        TracedAssertions.assertEqualsString("Uax14WesternPunctuationBoundary:LB13", UnicodePunctuationBoundaryTestSupport.findReason(r, ")", "LineStart"));
    }

    @:test public static function bracketBoundariesRemainProtectedAcrossWesternSpaces():Void {
        final t = new TestTraceRecorder("UnicodePunctuationBoundaryTest");
        t.section("bracketBoundariesRemainProtectedAcrossWesternSpaces");
        for (bi in 0...UnicodePunctuationBoundaryTestSupport.breakers().length) {
            final b = UnicodePunctuationBoundaryTestSupport.breakers()[bi];
            for (wi in 0...9) {
                final width = 48 + wi * 4;
                {
                    final o = "ABCD(  EFGH";
                    var ok = true;
                    for (x in UnicodePunctuationBoundaryTestSupport.lines(UnicodePunctuationBoundaryTestSupport.layout(o, width, b.breaker), o))
                        if (StringTools.endsWith(x, "("))
                            ok = false;
                    TracedAssertions.assertTrue(ok,
                        b.label
                        + " width="
                        + width
                        + " left an opener before trailing spaces: ["
                        + UnicodePunctuationBoundaryTestSupport.lines(UnicodePunctuationBoundaryTestSupport.layout(o, width, b.breaker), o).join(", ")
                        + "]");
                    final c = "ABCD  )EFGH";
                    ok = true;
                    for (x in UnicodePunctuationBoundaryTestSupport.lines(UnicodePunctuationBoundaryTestSupport.layout(c, width, b.breaker), c))
                        if (StringTools.startsWith(x, ")"))
                            ok = false;
                    TracedAssertions.assertTrue(ok,
                        b.label
                        + " width="
                        + width
                        + " left a closer after leading spaces: ["
                        + UnicodePunctuationBoundaryTestSupport.lines(UnicodePunctuationBoundaryTestSupport.layout(c, width, b.breaker), c).join(", ")
                        + "]");
                }
            }
        }
    }

    @:test public static function pairedLatinCurlyQuotesKeepTheirContentAcrossBothLineEdges():Void {
        final t = new TestTraceRecorder("UnicodePunctuationBoundaryTest");
        t.section("pairedLatinCurlyQuotesKeepTheirContentAcrossBothLineEdges");
        for (bi in 0...UnicodePunctuationBoundaryTestSupport.breakers().length) {
            final b = UnicodePunctuationBoundaryTestSupport.breakers()[bi];
            final a = "“ABCD”E";
            final r = UnicodePunctuationBoundaryTestSupport.layout(a, 40, b.breaker);
            var ok = true;
            for (x in UnicodePunctuationBoundaryTestSupport.lines(r, a))
                if (StringTools.startsWith(x, "”"))
                    ok = false;
            TracedAssertions.assertTrue(ok, b.label + " closing lines=[" + UnicodePunctuationBoundaryTestSupport.lines(r, a).join(", ") + "]");
            TracedAssertions.assertEqualsString("Uax14WesternPunctuationBoundary:PairedClosingQuote",
                UnicodePunctuationBoundaryTestSupport.findReason(r, "”", "LineStart"));
            final q = "ABCD“E”";
            final z = UnicodePunctuationBoundaryTestSupport.layout(q, 40, b.breaker);
            ok = true;
            for (x in UnicodePunctuationBoundaryTestSupport.lines(z, q))
                if (StringTools.endsWith(x, "“"))
                    ok = false;
            TracedAssertions.assertTrue(ok, b.label + " opening lines=[" + UnicodePunctuationBoundaryTestSupport.lines(z, q).join(", ") + "]");
            TracedAssertions.assertEqualsString("Uax14WesternPunctuationBoundary:PairedOpeningQuote",
                UnicodePunctuationBoundaryTestSupport.findReason(z, "“", "LineEnd"));
        }
    }
}
