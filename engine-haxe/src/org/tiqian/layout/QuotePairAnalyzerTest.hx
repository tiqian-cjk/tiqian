package org.tiqian.layout;

import org.tiqian.core.TextRange;
import org.tiqian.font.CjkFontRoleClassifier;
import org.tiqian.font.FontRole;
import org.tiqian.font.FontRoleContext;
import org.tiqian.layout.QuotePairAnalyzer.QuotePair;
import org.tiqian.layout.QuotePairAnalyzer.QuoteType;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class QuotePairAnalyzerTest {
    @:test public static function matchesDoubleQuotePair():Void {
        QuotePairAnalyzerTestSupport.rec("matchesDoubleQuotePair");
        var p = QuotePairAnalyzerTestSupport.a().analyze("\u4ED6\u8BF4\u201C\u4F60\u597D\u201D");
        TracedAssertions.assertEquals(1, p.length);
        TracedAssertions.assertEqualsQuotePair(new QuotePair(2, 5, QuoteType.Double), p[0]);
    }

    @:test public static function matchesSingleQuotePair():Void {
        QuotePairAnalyzerTestSupport.rec("matchesSingleQuotePair");
        var p = QuotePairAnalyzerTestSupport.a().analyze("\u4ED6\u8BF4\u2018\u4F60\u597D\u2019");
        TracedAssertions.assertEquals(1, p.length);
        TracedAssertions.assertEqualsQuotePair(new QuotePair(2, 5, QuoteType.Single), p[0]);
    }

    @:test public static function matchesNestedQuotePairs():Void {
        QuotePairAnalyzerTestSupport.rec("matchesNestedQuotePairs");
        var p = QuotePairAnalyzerTestSupport.a().analyze("\u4ED6\u8BF4\uFF1A\u201C\u5979\u8BF4\u2018\u4F60\u597D\u2019\u3002\u201D");
        TracedAssertions.assertEquals(2, p.length);
        var has6 = false;
        var has3 = false;
        var i = 0;
        while (i < p.length) {
            if (p[i].openIndex == 6)
                has6 = true;
            if (p[i].openIndex == 3)
                has3 = true;
            i++;
        }
        TracedAssertions.assertTrue(has6);
        TracedAssertions.assertTrue(has3);
    }

    @:test public static function unmatchedQuotesProduceNoPairs():Void {
        QuotePairAnalyzerTestSupport.rec("unmatchedQuotesProduceNoPairs");
        TracedAssertions.assertEquals(0, QuotePairAnalyzerTestSupport.a().analyze("it\u2019s").length);
    }

    @:test public static function contractionApostropheDoesNotCloseOuterSingleQuote():Void {
        QuotePairAnalyzerTestSupport.rec("contractionApostropheDoesNotCloseOuterSingleQuote");
        var t = "\u2018that\u2019s\u2019";
        TracedAssertions.assertEqualsQuotePairArray([new QuotePair(0, 7, QuoteType.Single)], QuotePairAnalyzerTestSupport.a().analyze(t));
    }

    @:test public static function contractionInsideCjkSingleQuotesKeepsApostropheLatin():Void {
        QuotePairAnalyzerTestSupport.rec("contractionInsideCjkSingleQuotesKeepsApostropheLatin");
        var t = "\u4E2D\u2018that\u2019s\u2019\u4E2D";
        var r = QuotePairAnalyzerTestSupport.a().classifyPairs(t, QuotePairAnalyzerTestSupport.a().analyze(t));
        var c = new CjkFontRoleClassifier();
        TracedAssertions.assertEqualsFontRole(FontRole.CjkPunctuation, r.get(1));
        TracedAssertions.assertEqualsFontRole(FontRole.CjkPunctuation, r.get(std.UString.count(t) - 2));
        TracedAssertions.assertEqualsFontRole(FontRole.LatinText, r.get(6));
        TracedAssertions.assertEqualsFontRole(FontRole.LatinText, c.classify(t, new TextRange(6, 7)));
    }

    @:test public static function inWordApostropheMatrixDoesNotConsumeOuterQuotePairs():Void {
        QuotePairAnalyzerTestSupport.rec("inWordApostropheMatrixDoesNotConsumeOuterQuotePairs");
        var words = [
            "that\u2019s",
            "l\u2019\u00E9t\u00E9",
            "rock\u2019n\u2019roll",
            "version2\u2019s",
            "\u03B1\u2019\u03B2",
            "\u0430\u2019\u0431",
            "e\u0301\u2019s"
        ];
        var i = 0;
        while (i < words.length) {
            var w = words[i];
            var d = QuotePairAnalyzerTestSupport.a().classifyQuoteRoles(w, []);
            TracedAssertions.assertTrue(QuotePairAnalyzerTestSupport.a().analyze(w).length == 0, w);
            var allLatin = true;
            var j = 0;
            while (j < d.length) {
                if (d[j].role != FontRole.LatinText)
                    allLatin = false;
                j++;
            }
            TracedAssertions.assertTrue(allLatin, w + ": " + QuotePairAnalyzerTestSupport.renderDecisions(d));
            var allSource = true;
            j = 0;
            while (j < d.length) {
                if (d[j].source != "NonCjkInWordApostrophe")
                    allSource = false;
                j++;
            }
            TracedAssertions.assertTrue(allSource, w + ": " + QuotePairAnalyzerTestSupport.renderDecisions(d));
            var q = "\u2018" + w + "\u2019";
            TracedAssertions.assertEqualsQuotePairArray([new QuotePair(0, q.length - 1, QuoteType.Single)], QuotePairAnalyzerTestSupport.a().analyze(q), q);
            var curly = 0;
            var k = 0;
            while (k < q.length) {
                var cq = q.charCodeAt(k);
                if (cq == 0x2018 || cq == 0x2019 || cq == 0x201C || cq == 0x201D)
                    curly++;
                k++;
            }
            var exp = "";
            var m = 0;
            while (m < curly) {
                exp += "L";
                m++;
            }
            TracedAssertions.assertEqualsString(exp, QuotePairAnalyzerTestSupport.sig(q, QuotePairAnalyzerTestSupport.a().classifyPairs(q, QuotePairAnalyzerTestSupport.a().analyze(q))), q);
            i++;
        }
    }

    @:test public static function unmatchedCurlyQuotesUseDirectionalContext():Void {
        QuotePairAnalyzerTestSupport.rec("unmatchedCurlyQuotesUseDirectionalContext");
        QuotePairAnalyzerTestSupport.role("leading elision at text start", "\u201990s", "L");
        QuotePairAnalyzerTestSupport.role("leading elision after CJK and Western space", "\u4E2D\u6587 \u201990s", "L");
        QuotePairAnalyzerTestSupport.role("trailing possessive", "James\u2019 book", "L");
        QuotePairAnalyzerTestSupport.role("truncated Latin opening quote", "\u201CHello", "L");
        QuotePairAnalyzerTestSupport.role("truncated Latin closing quote", "Hello\u201D", "L");
        QuotePairAnalyzerTestSupport.role("unspaced CJK opening quote", "\u4E2D\u6587\u201CHello", "C");
        QuotePairAnalyzerTestSupport.role("unmatched CJK closing quote", "\u4E2D\u6587\u201D", "C");
        QuotePairAnalyzerTestSupport.role("context-free quote", "\u201D", "C");
    }

    @:test public static function mismatchedNestingLeavesQuotesUnmatched():Void {
        QuotePairAnalyzerTestSupport.rec("mismatchedNestingLeavesQuotesUnmatched");
        TracedAssertions.assertEquals(0, QuotePairAnalyzerTestSupport.a().analyze("\u201Chello\u2019").length);
    }

    @:test public static function classifiesPairAsCjkWhenOuterContextIsCjk():Void
        QuotePairAnalyzerTestSupport.pairRole("classifiesPairAsCjkWhenOuterContextIsCjk", "\u4ED6\u8BF4\u201C\u4F60\u597D\u201D", [2, 5], FontRole.CjkPunctuation);

    @:test public static function classifiesPairAsLatinWhenOuterContextIsLatin():Void
        QuotePairAnalyzerTestSupport.pairRole("classifiesPairAsLatinWhenOuterContextIsLatin", "he said \u201Chello\u201D world", [8, 14], FontRole.LatinText);

    @:test public static function classifiesBothQuotesAsCjkForCjkQuotedLatinContent():Void
        QuotePairAnalyzerTestSupport.pairRole("classifiesBothQuotesAsCjkForCjkQuotedLatinContent", "\u4ED6\u8BF4\u201Chello\u201D", [2, 8], FontRole.CjkPunctuation);

    @:test public static function unspacedCjkQuotationOfLatinTextRemainsCjk():Void
        QuotePairAnalyzerTestSupport.pairRole("unspacedCjkQuotationOfLatinTextRemainsCjk", "\u4ED6\u8BF4\u2018hello\u2019", [2, 8], FontRole.CjkPunctuation);

    @:test public static function spacedCjkQuotedContentRemainsCjk():Void
        QuotePairAnalyzerTestSupport.pairRole("spacedCjkQuotedContentRemainsCjk", "\u4ED6\u8BF4 \u2018\u4F60\u597D\u2019", [3, 6], FontRole.CjkPunctuation);

    @:test public static function classifiesPairAsCjkAtTextBoundary():Void
        QuotePairAnalyzerTestSupport.pairRole("classifiesPairAsCjkAtTextBoundary", "\u201C\u4F60\u597D\u201D", [0, 3], FontRole.CjkPunctuation);

    @:test public static function classifiesTextStartLatinPairFromQuotedContent():Void
        QuotePairAnalyzerTestSupport.pairRole("classifiesTextStartLatinPairFromQuotedContent", "\u201CHello\u201D world", [0, 6], FontRole.LatinText);

    @:test public static function skipsAsciiPunctuationWhenResolvingContext():Void
        QuotePairAnalyzerTestSupport.pairRole("skipsAsciiPunctuationWhenResolvingContext", "English: \u201Chello\u201D", [9, 15], FontRole.LatinText);

    @:test public static function skipsNeutralDashWhenResolvingContext():Void
        QuotePairAnalyzerTestSupport.pairRole("skipsNeutralDashWhenResolvingContext", "English \u2014 \u201Chello\u201D", [10, 16], FontRole.LatinText);

    @:test public static function endOfTextQuotePairClassifiedByOuterContext():Void
        QuotePairAnalyzerTestSupport.pairRole("endOfTextQuotePairClassifiedByOuterContext", "he said \u201Chello\u201D", [8, 14], FontRole.LatinText);

    @:test public static function whitespaceDelimitedLatinQuotePairOverridesCjkOuterContext():Void {
        QuotePairAnalyzerTestSupport.rec("whitespaceDelimitedLatinQuotePairOverridesCjkOuterContext");
        var t = "\uFF08\u5982 \u2018O\u2019, \u2018Q\u2019\uFF09";
        var d = QuotePairAnalyzerTestSupport.decisions(t);
        var indexes = new Array<Int>();
        var j = 0;
        while (j < d.length) {
            indexes.push(d[j].index);
            j++;
        }
        TracedAssertions.assertEqualsIntArray([3, 5, 8, 10], indexes);
        TracedAssertions.assertTrue(d.length == 4, QuotePairAnalyzerTestSupport.renderDecisions(d));
        TracedAssertions.assertTrue(d[0].source == "DelimitedWesternQuotationRun", QuotePairAnalyzerTestSupport.renderDecisions(d));
    }

    @:test public static function adjacentQuotedListItemsDoNotUsePreviousItemContentAsOuterContext():Void {
        QuotePairAnalyzerTestSupport.rec("adjacentQuotedListItemsDoNotUsePreviousItemContentAsOuterContext");
        QuotePairAnalyzerTestSupport.role("CJK list item after mixed-script item",
            "\u4FBF\u5EF6\u4F38\u51FA\u4E86\u201C\u4E43\u5B50\u201D\u201C\u5927\u6CE2\u201D\u201C\u5927\u706F\u201D\u201C\u5927\u96F7\u201D\u201C\u5927\u624E\u201D\u201C\u5BF9A\u201D\u201C\u6CE2\u9738\u201D\u8FD9\u4E9B\u8BCD",
            "CCCCCCCCCCCCCC");
        QuotePairAnalyzerTestSupport.role("Latin list item after Latin item in CJK prose",
            "\u8FD9\u4E9B\u592A\u76F4\u767D\u4E86\u662F\u5427\uFF0C\n \u201C\u6B27\u6D3E\u201D\u201Cdouble\u201D\u201Cdouble may\u201D\u5462", "CCCCCC");
        var texts = [
            "\u4FBF\u5EF6\u4F38\u51FA\u4E86\u201C\u4E43\u5B50\u201D\u201C\u5927\u6CE2\u201D\u201C\u5927\u706F\u201D\u201C\u5927\u96F7\u201D\u201C\u5927\u624E\u201D\u201C\u5BF9A\u201D\u201C\u6CE2\u9738\u201D\u8FD9\u4E9B\u8BCD",
            "\u8FD9\u4E9B\u592A\u76F4\u767D\u4E86\u662F\u5427\uFF0C\n \u201C\u6B27\u6D3E\u201D\u201Cdouble\u201D\u201Cdouble may\u201D\u5462"
        ];
        var ti = 0;
        while (ti < texts.length) {
            var tt = texts[ti];
            var finalOpen = -1;
            var finalClose = -1;
            var p = 0;
            while (p < tt.length) {
                var ch = tt.charCodeAt(p);
                if (ch == 0x201C)
                    finalOpen = p;
                if (ch == 0x201D)
                    finalClose = p;
                p++;
            }
            var fd = QuotePairAnalyzerTestSupport.decisions(tt);
            var filtered = new Array<QuotePairAnalyzer.QuoteRoleDecision>();
            var fi = 0;
            while (fi < fd.length) {
                if (fd[fi].index == finalOpen || fd[fi].index == finalClose)
                    filtered.push(fd[fi]);
                fi++;
            }
            TracedAssertions.assertEquals(2, filtered.length, tt);
            var allSrc = true;
            var si = 0;
            while (si < filtered.length) {
                if (filtered[si].source != "PairedPunctuationOuterScriptContext")
                    allSrc = false;
                si++;
            }
            TracedAssertions.assertTrue(allSrc, tt + ": " + QuotePairAnalyzerTestSupport.renderDecisions(filtered));
            ti++;
        }
    }

    @:test public static function mixedChineseQuestionAtParagraphStartUsesParagraphLanguage():Void {
        QuotePairAnalyzerTestSupport.rec("mixedChineseQuestionAtParagraphStartUsesParagraphLanguage");
        var d = QuotePairAnalyzerTestSupport.decisions("\u201CJson\u662F\u8C01\uFF1F\u201D");
        TracedAssertions.assertEqualsIntArray([0, 8], [d[0].index, d[1].index]);
        TracedAssertions.assertTrue(d[0].role == FontRole.CjkPunctuation, QuotePairAnalyzerTestSupport.renderDecisions(d));
        TracedAssertions.assertTrue(d[0].source == "ParagraphLanguageQuoteContext", QuotePairAnalyzerTestSupport.renderDecisions(d));
    }

    @:test public static function explicitEnglishParagraphLanguageWinsForMixedQuotation():Void {
        QuotePairAnalyzerTestSupport.rec("explicitEnglishParagraphLanguageWinsForMixedQuotation");
        var t = "\u201CJson\u662F\u8C01\uFF1F\u201D";
        var d = QuotePairAnalyzerTestSupport.a().classifyQuoteRoles(t, QuotePairAnalyzerTestSupport.a().analyze(t), new FontRoleContext("en"));
        TracedAssertions.assertTrue(d[0].role == FontRole.LatinText, QuotePairAnalyzerTestSupport.renderDecisions(d));
        TracedAssertions.assertTrue(d[0].source == "ParagraphLanguageQuoteContext", QuotePairAnalyzerTestSupport.renderDecisions(d));
    }

    @:test public static function commonDigitsDoNotChooseTheQuoteRole():Void {
        QuotePairAnalyzerTestSupport.rec("commonDigitsDoNotChooseTheQuoteRole");
        var t = "\u201C2024\u201D";
        var d = QuotePairAnalyzerTestSupport.decisions(t);
        TracedAssertions.assertTrue(d[0].role == FontRole.CjkPunctuation, QuotePairAnalyzerTestSupport.renderDecisions(d));
        TracedAssertions.assertTrue(d[0].source == "ParagraphLanguageQuoteContext", QuotePairAnalyzerTestSupport.renderDecisions(d));
        var e = QuotePairAnalyzerTestSupport.a().classifyQuoteRoles(t, QuotePairAnalyzerTestSupport.a().analyze(t), new FontRoleContext("en"));
        TracedAssertions.assertTrue(e[0].role == FontRole.LatinText, QuotePairAnalyzerTestSupport.renderDecisions(e));
        TracedAssertions.assertTrue(e[0].source == "ParagraphLanguageQuoteContext", QuotePairAnalyzerTestSupport.renderDecisions(e));
    }

    @:test public static function nonLatinWesternScriptsParticipateAsStrongScriptEvidence():Void {
        QuotePairAnalyzerTestSupport.rec("nonLatinWesternScriptsParticipateAsStrongScriptEvidence");
        QuotePairAnalyzerTestSupport.role("standalone Cyrillic quotation", "\u201C\u041F\u0440\u0438\u0432\u0435\u0442\u201D", "LL");
        QuotePairAnalyzerTestSupport.role("mixed Greek and Chinese quotation", "\u201C\u03C0\u8C01\uFF1F\u201D", "CC");
        QuotePairAnalyzerTestSupport.role("CJK prose quoting Cyrillic", "\u4ED6\u8BF4\u201C\u041F\u0440\u0438\u0432\u0435\u0442\u201D", "CC");
    }

    @:test public static function numberedCjkQuotePrefixUsesQuotedContent():Void {
        QuotePairAnalyzerTestSupport.rec("numberedCjkQuotePrefixUsesQuotedContent");
        var t = "1.\u201C\u4F60\u77E5\u9053\u674E\u767D\u662F\u600E\u4E48\u6B7B\u7684\u5417\uFF1F\u201D";
        var d = QuotePairAnalyzerTestSupport.decisions(t);
        var role2:FontRole = FontRole.CjkPunctuation;
        var roleLast:FontRole = FontRole.CjkPunctuation;
        var src2:String = "";
        var i = 0;
        while (i < d.length) {
            if (d[i].index == 2) {
                role2 = d[i].role;
                src2 = d[i].source;
            }
            if (d[i].index == std.UString.count(t) - 1)
                roleLast = d[i].role;
            i++;
        }
        TracedAssertions.assertEqualsFontRole(FontRole.CjkPunctuation, role2);
        TracedAssertions.assertEqualsFontRole(FontRole.CjkPunctuation, roleLast);
        TracedAssertions.assertEqualsString("PairedPunctuationContentScriptContext", src2);
    }

    @:test public static function numberedLatinQuotePrefixStillUsesLatinContent():Void
        QuotePairAnalyzerTestSupport.pairRole("numberedLatinQuotePrefixStillUsesLatinContent", "1.\u201CHello\u201D", [2, 8], FontRole.LatinText);

    @:test public static function classifiesNestedPairsByOutermostContext():Void
        QuotePairAnalyzerTestSupport.pairRole("classifiesNestedPairsByOutermostContext", "\u4ED6\u8BF4\uFF1A\u201C\u5979\u8BF4\u2018\u4F60\u597D\u2019\u3002\u201D", [3, 11, 6, 9],
            FontRole.CjkPunctuation);

    @:test public static function classifiesLatinNestedQuotesByOuterContext():Void
        QuotePairAnalyzerTestSupport.pairRole("classifiesLatinNestedQuotesByOuterContext", "She said \u201Che said \u2018hello\u2019 today\u201D end", [9, 18, 24, 31], FontRole.LatinText);

    @:test public static function representativeQuoteContextMatrixRemainsStable():Void {
        QuotePairAnalyzerTestSupport.rec("representativeQuoteContextMatrixRemainsStable");
        var xs = [
            "Latin content at text start|\u201CHello\u201D|LL",
            "CJK content at text start|\u201C\u4F60\u597D\u201D|CC",
            "mixed Chinese question at text start|\u201CJson\u662F\u8C01\uFF1F\u201D|CC",
            "Cyrillic content at text start|\u201C\u041F\u0440\u0438\u0432\u0435\u0442\u201D|LL",
            "CJK prose quoting Latin|\u4ED6\u8BF4\u201Chello\u201D|CC",
            "Latin prose quoting CJK|He said \u201C\u4F60\u597D\u201D|LL",
            "spaced Western initials in CJK|\uFF08\u5982 \u2018O\u2019, \u2018Q\u2019\uFF09|LLLL",
            "spaced CJK quotation|\u4ED6\u8BF4 \u2018\u4F60\u597D\u2019|CC",
            "empty pair before Latin|\u201C\u201DEnglish|LL",
            "empty pair before CJK|\u201C\u201D\u4E2D\u6587|CC",
            "context-free empty pair|\u201C\u201D|CC",
            "numbered CJK quotation|1.\u201C\u4E2D\u6587\u201D|CC",
            "numbered Latin quotation|1.\u201CHello\u201D|LL",
            "mixed CJK outer Latin inner|\u4ED6\u8BF4\uFF1A\u201CShe said \u2018hello\u2019.\u201D|CLLC",
            "mixed Latin outer CJK inner|English \u201C\u4ED6\u8BF4\u2018\u4F60\u597D\u2019\u201D end|LCCL",
            "CJK outer with contraction|\u4E2D\u6587\u2018don\u2019t\u2019|CLC",
            "spaced Latin outer with contraction|\u4E2D\u6587 \u2018don\u2019t\u2019|LLL",
            "pair across mandatory break|\u4ED6\u8BF4\uFF1A\u201C\u7B2C\u4E00\u884C\n\u7B2C\u4E8C\u884C\u3002\u201D|CC",
            "tab-delimited Western quote|\uFF08\u5982\t\u2018O\u2019\uFF09|LL"
        ];
        var i = 0;
        while (i < xs.length) {
            var z = xs[i].split("|");
            QuotePairAnalyzerTestSupport.role(z[0], z[1], z[2]);
            i++;
        }
    }

    @:test public static function roleDecisionSourcesStayExplainableAcrossFallbackPaths():Void {
        QuotePairAnalyzerTestSupport.rec("roleDecisionSourcesStayExplainableAcrossFallbackPaths");
        var xs = [
            "\u201CHello\u201D",
            "\u201CJson\u662F\u8C01\uFF1F\u201D",
            "English\u2014\u201CHello\u201D",
            "\uFF08\u5982 \u2018O\u2019\uFF09",
            "1.\u201C\u4E2D\u6587\u201D",
            "\u201C\u201DEnglish",
            "\u201C\u201D",
            "that\u2019s",
            "\u4E2D\u6587 \u201990s",
            "James\u2019",
            "\u201990s",
            "\u201D"
        ];
        var i = 0;
        while (i < xs.length) {
            var d = QuotePairAnalyzerTestSupport.decisions(xs[i]);
            TracedAssertions.assertTrue(d.length > 0, xs[i]);
            TracedAssertions.assertTrue(d[0].source.length > 0, xs[i] + ": " + QuotePairAnalyzerTestSupport.renderDecisions(d));
            i++;
        }
    }

    public static function flushTestTrace():Void {
        TestTraceRecorder.flushClass("QuotePairAnalyzerTest");
    }

}
