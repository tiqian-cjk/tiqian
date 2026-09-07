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
    private static function rec(name:String):Void
        new TestTraceRecorder("QuotePairAnalyzerTest").section(name);

    private static function a():QuotePairAnalyzer
        return new QuotePairAnalyzer();

    private static function sig(text:String, roles:std.SortedMap<Int, FontRole>):String {
        var out = "";
        var i = 0;
        while (i < text.length) {
            var c = text.charCodeAt(i);
            if (c == 0x2018 || c == 0x2019 || c == 0x201C || c == 0x201D) {
                var r = roles.get(i);
                out += r == FontRole.LatinText ? "L" : r == FontRole.CjkPunctuation ? "C" : "?";
            }
            i++;
        }
        return out;
    }

    private static function role(label:String, text:String, expected:String):Void {
        TracedAssertions.assertEqualsString(expected, sig(text, a().classifyPairs(text, a().analyze(text))), label);
    }

    private static function decisions(text:String):Array<QuotePairAnalyzer.QuoteRoleDecision>
        return a().classifyQuoteRoles(text, a().analyze(text));

    private static function renderDecisions(values:Array<QuotePairAnalyzer.QuoteRoleDecision>):String {
        var out = "[";
        var i = 0;
        while (i < values.length) {
            if (i > 0)
                out += ", ";
            out += values[i].toString();
            i++;
        }
        return out + "]";
    }

    public static function matchesDoubleQuotePair():Void {
        rec("matchesDoubleQuotePair");
        var p = a().analyze("\u4ED6\u8BF4\u201C\u4F60\u597D\u201D");
        TracedAssertions.assertEquals(1, p.length);
        TracedAssertions.assertEqualsQuotePair(new QuotePair(2, 5, QuoteType.Double), p[0]);
    }

    public static function matchesSingleQuotePair():Void {
        rec("matchesSingleQuotePair");
        var p = a().analyze("\u4ED6\u8BF4\u2018\u4F60\u597D\u2019");
        TracedAssertions.assertEquals(1, p.length);
        TracedAssertions.assertEqualsQuotePair(new QuotePair(2, 5, QuoteType.Single), p[0]);
    }

    public static function matchesNestedQuotePairs():Void {
        rec("matchesNestedQuotePairs");
        var p = a().analyze("\u4ED6\u8BF4\uFF1A\u201C\u5979\u8BF4\u2018\u4F60\u597D\u2019\u3002\u201D");
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

    public static function unmatchedQuotesProduceNoPairs():Void {
        rec("unmatchedQuotesProduceNoPairs");
        TracedAssertions.assertEquals(0, a().analyze("it\u2019s").length);
    }

    public static function contractionApostropheDoesNotCloseOuterSingleQuote():Void {
        rec("contractionApostropheDoesNotCloseOuterSingleQuote");
        var t = "\u2018that\u2019s\u2019";
        TracedAssertions.assertEqualsQuotePairArray([new QuotePair(0, 7, QuoteType.Single)], a().analyze(t));
    }

    public static function contractionInsideCjkSingleQuotesKeepsApostropheLatin():Void {
        rec("contractionInsideCjkSingleQuotesKeepsApostropheLatin");
        var t = "\u4E2D\u2018that\u2019s\u2019\u4E2D";
        var r = a().classifyPairs(t, a().analyze(t));
        var c = new CjkFontRoleClassifier();
        TracedAssertions.assertEqualsFontRole(FontRole.CjkPunctuation, r.get(1));
        TracedAssertions.assertEqualsFontRole(FontRole.CjkPunctuation, r.get(std.UString.count(t) - 2));
        TracedAssertions.assertEqualsFontRole(FontRole.LatinText, r.get(6));
        TracedAssertions.assertEqualsFontRole(FontRole.LatinText, c.classify(t, new TextRange(6, 7)));
    }

    public static function inWordApostropheMatrixDoesNotConsumeOuterQuotePairs():Void {
        rec("inWordApostropheMatrixDoesNotConsumeOuterQuotePairs");
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
            var d = a().classifyQuoteRoles(w, []);
            TracedAssertions.assertTrue(a().analyze(w).length == 0, w);
            var allLatin = true;
            var j = 0;
            while (j < d.length) {
                if (d[j].role != FontRole.LatinText)
                    allLatin = false;
                j++;
            }
            TracedAssertions.assertTrue(allLatin, w + ": " + renderDecisions(d));
            var allSource = true;
            j = 0;
            while (j < d.length) {
                if (d[j].source != "NonCjkInWordApostrophe")
                    allSource = false;
                j++;
            }
            TracedAssertions.assertTrue(allSource, w + ": " + renderDecisions(d));
            var q = "\u2018" + w + "\u2019";
            TracedAssertions.assertEqualsQuotePairArray([new QuotePair(0, q.length - 1, QuoteType.Single)], a().analyze(q), q);
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
            TracedAssertions.assertEqualsString(exp, sig(q, a().classifyPairs(q, a().analyze(q))), q);
            i++;
        }
    }

    public static function unmatchedCurlyQuotesUseDirectionalContext():Void {
        rec("unmatchedCurlyQuotesUseDirectionalContext");
        role("leading elision at text start", "\u201990s", "L");
        role("leading elision after CJK and Western space", "\u4E2D\u6587 \u201990s", "L");
        role("trailing possessive", "James\u2019 book", "L");
        role("truncated Latin opening quote", "\u201CHello", "L");
        role("truncated Latin closing quote", "Hello\u201D", "L");
        role("unspaced CJK opening quote", "\u4E2D\u6587\u201CHello", "C");
        role("unmatched CJK closing quote", "\u4E2D\u6587\u201D", "C");
        role("context-free quote", "\u201D", "C");
    }

    public static function mismatchedNestingLeavesQuotesUnmatched():Void {
        rec("mismatchedNestingLeavesQuotesUnmatched");
        TracedAssertions.assertEquals(0, a().analyze("\u201Chello\u2019").length);
    }

    private static function pairRole(name:String, text:String, indexes:Array<Int>, expected:FontRole):Void {
        rec(name);
        var r = a().classifyPairs(text, a().analyze(text));
        var i = 0;
        while (i < indexes.length) {
            TracedAssertions.assertEqualsFontRole(expected, r.get(indexes[i]));
            i++;
        }
    }

    public static function classifiesPairAsCjkWhenOuterContextIsCjk():Void
        pairRole("classifiesPairAsCjkWhenOuterContextIsCjk", "\u4ED6\u8BF4\u201C\u4F60\u597D\u201D", [2, 5], FontRole.CjkPunctuation);

    public static function classifiesPairAsLatinWhenOuterContextIsLatin():Void
        pairRole("classifiesPairAsLatinWhenOuterContextIsLatin", "he said \u201Chello\u201D world", [8, 14], FontRole.LatinText);

    public static function classifiesBothQuotesAsCjkForCjkQuotedLatinContent():Void
        pairRole("classifiesBothQuotesAsCjkForCjkQuotedLatinContent", "\u4ED6\u8BF4\u201Chello\u201D", [2, 8], FontRole.CjkPunctuation);

    public static function unspacedCjkQuotationOfLatinTextRemainsCjk():Void
        pairRole("unspacedCjkQuotationOfLatinTextRemainsCjk", "\u4ED6\u8BF4\u2018hello\u2019", [2, 8], FontRole.CjkPunctuation);

    public static function spacedCjkQuotedContentRemainsCjk():Void
        pairRole("spacedCjkQuotedContentRemainsCjk", "\u4ED6\u8BF4 \u2018\u4F60\u597D\u2019", [3, 6], FontRole.CjkPunctuation);

    public static function classifiesPairAsCjkAtTextBoundary():Void
        pairRole("classifiesPairAsCjkAtTextBoundary", "\u201C\u4F60\u597D\u201D", [0, 3], FontRole.CjkPunctuation);

    public static function classifiesTextStartLatinPairFromQuotedContent():Void
        pairRole("classifiesTextStartLatinPairFromQuotedContent", "\u201CHello\u201D world", [0, 6], FontRole.LatinText);

    public static function skipsAsciiPunctuationWhenResolvingContext():Void
        pairRole("skipsAsciiPunctuationWhenResolvingContext", "English: \u201Chello\u201D", [9, 15], FontRole.LatinText);

    public static function skipsNeutralDashWhenResolvingContext():Void
        pairRole("skipsNeutralDashWhenResolvingContext", "English \u2014 \u201Chello\u201D", [10, 16], FontRole.LatinText);

    public static function endOfTextQuotePairClassifiedByOuterContext():Void
        pairRole("endOfTextQuotePairClassifiedByOuterContext", "he said \u201Chello\u201D", [8, 14], FontRole.LatinText);

    public static function whitespaceDelimitedLatinQuotePairOverridesCjkOuterContext():Void {
        rec("whitespaceDelimitedLatinQuotePairOverridesCjkOuterContext");
        var t = "\uFF08\u5982 \u2018O\u2019, \u2018Q\u2019\uFF09";
        var d = decisions(t);
        var indexes = new Array<Int>();
        var j = 0;
        while (j < d.length) {
            indexes.push(d[j].index);
            j++;
        }
        TracedAssertions.assertEqualsIntArray([3, 5, 8, 10], indexes);
        TracedAssertions.assertTrue(d.length == 4, renderDecisions(d));
        TracedAssertions.assertTrue(d[0].source == "DelimitedWesternQuotationRun", renderDecisions(d));
    }

    public static function adjacentQuotedListItemsDoNotUsePreviousItemContentAsOuterContext():Void {
        rec("adjacentQuotedListItemsDoNotUsePreviousItemContentAsOuterContext");
        role("CJK list item after mixed-script item",
            "\u4FBF\u5EF6\u4F38\u51FA\u4E86\u201C\u4E43\u5B50\u201D\u201C\u5927\u6CE2\u201D\u201C\u5927\u706F\u201D\u201C\u5927\u96F7\u201D\u201C\u5927\u624E\u201D\u201C\u5BF9A\u201D\u201C\u6CE2\u9738\u201D\u8FD9\u4E9B\u8BCD",
            "CCCCCCCCCCCCCC");
        role("Latin list item after Latin item in CJK prose",
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
            var fd = decisions(tt);
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
            TracedAssertions.assertTrue(allSrc, tt + ": " + renderDecisions(filtered));
            ti++;
        }
    }

    public static function mixedChineseQuestionAtParagraphStartUsesParagraphLanguage():Void {
        rec("mixedChineseQuestionAtParagraphStartUsesParagraphLanguage");
        var d = decisions("\u201CJson\u662F\u8C01\uFF1F\u201D");
        TracedAssertions.assertEqualsIntArray([0, 8], [d[0].index, d[1].index]);
        TracedAssertions.assertTrue(d[0].role == FontRole.CjkPunctuation, renderDecisions(d));
        TracedAssertions.assertTrue(d[0].source == "ParagraphLanguageQuoteContext", renderDecisions(d));
    }

    public static function explicitEnglishParagraphLanguageWinsForMixedQuotation():Void {
        rec("explicitEnglishParagraphLanguageWinsForMixedQuotation");
        var t = "\u201CJson\u662F\u8C01\uFF1F\u201D";
        var d = a().classifyQuoteRoles(t, a().analyze(t), new FontRoleContext("en"));
        TracedAssertions.assertTrue(d[0].role == FontRole.LatinText, renderDecisions(d));
        TracedAssertions.assertTrue(d[0].source == "ParagraphLanguageQuoteContext", renderDecisions(d));
    }

    public static function commonDigitsDoNotChooseTheQuoteRole():Void {
        rec("commonDigitsDoNotChooseTheQuoteRole");
        var t = "\u201C2024\u201D";
        var d = decisions(t);
        TracedAssertions.assertTrue(d[0].role == FontRole.CjkPunctuation, renderDecisions(d));
        TracedAssertions.assertTrue(d[0].source == "ParagraphLanguageQuoteContext", renderDecisions(d));
        var e = a().classifyQuoteRoles(t, a().analyze(t), new FontRoleContext("en"));
        TracedAssertions.assertTrue(e[0].role == FontRole.LatinText, renderDecisions(e));
        TracedAssertions.assertTrue(e[0].source == "ParagraphLanguageQuoteContext", renderDecisions(e));
    }

    public static function nonLatinWesternScriptsParticipateAsStrongScriptEvidence():Void {
        rec("nonLatinWesternScriptsParticipateAsStrongScriptEvidence");
        role("standalone Cyrillic quotation", "\u201C\u041F\u0440\u0438\u0432\u0435\u0442\u201D", "LL");
        role("mixed Greek and Chinese quotation", "\u201C\u03C0\u8C01\uFF1F\u201D", "CC");
        role("CJK prose quoting Cyrillic", "\u4ED6\u8BF4\u201C\u041F\u0440\u0438\u0432\u0435\u0442\u201D", "CC");
    }

    public static function numberedCjkQuotePrefixUsesQuotedContent():Void {
        rec("numberedCjkQuotePrefixUsesQuotedContent");
        var t = "1.\u201C\u4F60\u77E5\u9053\u674E\u767D\u662F\u600E\u4E48\u6B7B\u7684\u5417\uFF1F\u201D";
        var d = decisions(t);
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

    public static function numberedLatinQuotePrefixStillUsesLatinContent():Void
        pairRole("numberedLatinQuotePrefixStillUsesLatinContent", "1.\u201CHello\u201D", [2, 8], FontRole.LatinText);

    public static function classifiesNestedPairsByOutermostContext():Void
        pairRole("classifiesNestedPairsByOutermostContext", "\u4ED6\u8BF4\uFF1A\u201C\u5979\u8BF4\u2018\u4F60\u597D\u2019\u3002\u201D", [3, 11, 6, 9],
            FontRole.CjkPunctuation);

    public static function classifiesLatinNestedQuotesByOuterContext():Void
        pairRole("classifiesLatinNestedQuotesByOuterContext", "She said \u201Che said \u2018hello\u2019 today\u201D end", [9, 18, 24, 31], FontRole.LatinText);

    public static function representativeQuoteContextMatrixRemainsStable():Void {
        rec("representativeQuoteContextMatrixRemainsStable");
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
            role(z[0], z[1], z[2]);
            i++;
        }
    }

    public static function roleDecisionSourcesStayExplainableAcrossFallbackPaths():Void {
        rec("roleDecisionSourcesStayExplainableAcrossFallbackPaths");
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
            var d = decisions(xs[i]);
            TracedAssertions.assertTrue(d.length > 0, xs[i]);
            TracedAssertions.assertTrue(d[0].source.length > 0, xs[i] + ": " + renderDecisions(d));
            i++;
        }
    }
}
