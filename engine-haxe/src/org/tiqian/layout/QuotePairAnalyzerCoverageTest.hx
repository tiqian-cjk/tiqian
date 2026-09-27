package org.tiqian.layout;

import org.tiqian.layout.QuotePairAnalyzer.QuotePairAwareFontRoleClassifier;
import org.tiqian.core.TextRange;
import org.tiqian.font.CjkFontRoleClassifier;
import org.tiqian.font.FontRole;
import org.tiqian.font.FontRoleContext;
import org.tiqian.layout.QuotePairAnalyzer.QuoteType;
import org.tiqian.test.TestHelpers;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class QuotePairAnalyzerCoverageTest {
    @:test public static function deprecatedClassifyPairsWithFontRoleClassifierDelegates():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("deprecatedClassifyPairsWithFontRoleClassifierDelegates");
        var t = "\u4ED6\u8BF4\u201C\u4F60\u597D\u201D";
        TracedAssertions.assertEqualsFontRole(FontRole.CjkPunctuation, QuotePairAnalyzerCoverageTestSupport.a().classifyPairsWithClassifier(t, QuotePairAnalyzerCoverageTestSupport.a().analyze(t), new CjkFontRoleClassifier()).get(2));
    }

    @:test public static function deprecatedClassifyQuoteRolesWithFontRoleClassifierDelegates():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("deprecatedClassifyQuoteRolesWithFontRoleClassifierDelegates");
        var t = "\u4ED6\u8BF4\u201C\u4F60\u597D\u201D";
        TracedAssertions.assertTrue(QuotePairAnalyzerCoverageTestSupport.a().classifyQuoteRolesWithClassifier(t, QuotePairAnalyzerCoverageTestSupport.a().analyze(t), new CjkFontRoleClassifier()).length > 0);
    }

    @:test public static function codePointBeforeSurrogatePairReturnsSupplementary():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("codePointBeforeSurrogatePairReturnsSupplementary");
        TracedAssertions.assertEquals(0, QuotePairAnalyzerCoverageTestSupport.a().analyze(TestHelpers.surrogateText([0xD83D, 0xDE00, 0x2019])).length);
    }

    @:test public static function codePointAtOrNullSurrogatePairReturnsSupplementary():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("codePointAtOrNullSurrogatePairReturnsSupplementary");
        QuotePairAnalyzerCoverageTestSupport.nonEmpty(TestHelpers.surrogateText([0x2019, 0xD83D, 0xDE00]));
    }

    @:test public static function codePointAtOrNullNonSurrogateReturnsSelf():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("codePointAtOrNullNonSurrogateReturnsSelf");
        TracedAssertions.assertTrue(QuotePairAnalyzerCoverageTestSupport.a().classifyQuoteRoles("abc", []).length == 0);
    }

    @:test public static function codePointBeforeReturnsNullAtStart():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("codePointBeforeReturnsNullAtStart");
        QuotePairAnalyzerCoverageTestSupport.nonEmpty("\u2019");
    }

    @:test public static function codePointBeforeReturnsSupplementaryForSurrogatePair():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("codePointBeforeReturnsSupplementaryForSurrogatePair");
        QuotePairAnalyzerCoverageTestSupport.nonEmpty(TestHelpers.surrogateText([0xD83D, 0xDE00, 0x2019]));
    }

    @:test public static function quotePairAwareFontRoleClassifierUsesOverride():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("quotePairAwareFontRoleClassifierUsesOverride");
        var b = std.SortedMap.builder();
        b.put(2, FontRole.LatinText);
        var c = new QuotePairAwareFontRoleClassifier(new CjkFontRoleClassifier(), b.build());
        TracedAssertions.assertEqualsFontRole(FontRole.LatinText, c.classify("ab", new TextRange(0, 2), new FontRoleContext()));
    }

    @:test public static function quotePairAwareFontRoleClassifierDelegatesWhenNoOverride():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("quotePairAwareFontRoleClassifierDelegatesWhenNoOverride");
        var b = std.SortedMap.builder();
        var c = new CjkFontRoleClassifier();
        var w = new QuotePairAwareFontRoleClassifier(c, b.build());
        TracedAssertions.assertEqualsFontRole(c.classify("ab", new TextRange(0, 2), new FontRoleContext()),
            w.classify("ab", new TextRange(0, 2), new FontRoleContext()));
    }

    @:test public static function doubleQuoteCloseWithEmptyStackIgnores():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("doubleQuoteCloseWithEmptyStackIgnores");
        TracedAssertions.assertEquals(0, QuotePairAnalyzerCoverageTestSupport.a().analyze("\u201D").length);
    }

    @:test public static function singleQuoteCloseWithEmptyStackIgnores():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("singleQuoteCloseWithEmptyStackIgnores");
        TracedAssertions.assertEquals(0, QuotePairAnalyzerCoverageTestSupport.a().analyze("\u2019").length);
    }

    @:test public static function inWordApostropheAfterSupplementaryDoesNotClose():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("inWordApostropheAfterSupplementaryDoesNotClose");
        QuotePairAnalyzerCoverageTestSupport.nonEmpty(TestHelpers.surrogateText([0xD83D, 0xDE00, 0x2019, 0x78]));
    }

    @:test public static function codePointAtOrNullWithSupplementaryAfterQuote():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("codePointAtOrNullWithSupplementaryAfterQuote");
        QuotePairAnalyzerCoverageTestSupport.nonEmpty(TestHelpers.surrogateText([0x61, 0x2019, 0xD83D, 0xDE00]));
    }

    @:test public static function codePointBeforeWithHighSurrogateBeforeQuote():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("codePointBeforeWithHighSurrogateBeforeQuote");
        QuotePairAnalyzerCoverageTestSupport.nonEmpty(TestHelpers.surrogateText([0xD83D, 0xDE00, 0x2019]));
    }

    @:test(except = ["swift", "rust"]) public static function codePointBeforeWithLowSurrogateAtStart():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("codePointBeforeWithLowSurrogateAtStart");
        QuotePairAnalyzerCoverageTestSupport.failLow(TestHelpers.surrogateText([0xDC00, 0x2019]));
    }

    @:test(except = ["swift", "rust"]) public static function codePointBeforeWithLowSurrogateAfterNonHighSurrogate():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("codePointBeforeWithLowSurrogateAfterNonHighSurrogate");
        QuotePairAnalyzerCoverageTestSupport.failLow(TestHelpers.surrogateText([0x61, 0xDC00, 0x2019]));
    }

    @:test public static function codePointAtOrNullWithIndexOutOfRange():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("codePointAtOrNullWithIndexOutOfRange");
        QuotePairAnalyzerCoverageTestSupport.nonEmpty("a\u2019");
    }

    @:test(except = ["swift", "rust"]) public static function codePointAtOrNullWithHighSurrogateAtEnd():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("codePointAtOrNullWithHighSurrogateAtEnd");
        QuotePairAnalyzerCoverageTestSupport.failLow(TestHelpers.surrogateText([0x2019, 0xD800]));
    }

    @:test(except = ["swift", "rust"]) public static function codePointAtOrNullWithHighSurrogateFollowedByNonLowSurrogate():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("codePointAtOrNullWithHighSurrogateFollowedByNonLowSurrogate");
        QuotePairAnalyzerCoverageTestSupport.failLow(TestHelpers.surrogateText([0x2019, 0xD800, 0x61]));
    }

    @:test public static function analyzeWithDoubleQuoteOpen():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("analyzeWithDoubleQuoteOpen");
        TracedAssertions.assertEquals(0, QuotePairAnalyzerCoverageTestSupport.a().analyze("\u201Cabc").length);
    }

    @:test public static function codePointAtOrNullHighSurrogateNotInRangeReturnsHigh():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("codePointAtOrNullHighSurrogateNotInRangeReturnsHigh");
        QuotePairAnalyzerCoverageTestSupport.nonEmpty("x\u2019a");
    }

    @:test(except = ["swift", "rust"]) public static function codePointBeforeLowInRangeIndexGe2HighNotInRange():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("codePointBeforeLowInRangeIndexGe2HighNotInRange");
        QuotePairAnalyzerCoverageTestSupport.failLow(TestHelpers.surrogateText([0x61, 0xDC00, 0x2019]));
    }

    @:test public static function singleQuotePairMatch():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("singleQuotePairMatch");
        var p = QuotePairAnalyzerCoverageTestSupport.a().analyze("\u2018\u2019");
        TracedAssertions.assertEquals(1, p.length);
        TracedAssertions.assertEqualsQuoteType(QuoteType.Single, p[0].quoteType);
    }

    @:test(except = ["swift", "rust"]) public static function codePointAtOrNullLoneHighSurrogateAfterQuote():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("codePointAtOrNullLoneHighSurrogateAfterQuote");
        QuotePairAnalyzerCoverageTestSupport.failLow(TestHelpers.surrogateText([0x61, 0x2019, 0xD800, 0x61]));
    }

    @:test(except = ["swift", "rust"]) public static function codePointAtOrNullHighSurrogateAtStringEnd():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("codePointAtOrNullHighSurrogateAtStringEnd");
        QuotePairAnalyzerCoverageTestSupport.failLow(TestHelpers.surrogateText([0x61, 0x2019, 0xD800]));
    }

    @:test public static function analyzeWithAllQuoteTypes():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("analyzeWithAllQuoteTypes");
        TracedAssertions.assertEquals(2, QuotePairAnalyzerCoverageTestSupport.a().analyze("\u201C\u2018abc\u2019\u201D").length);
    }

    @:test public static function codePointBeforeNonSurrogateBmpChar():Void {
        QuotePairAnalyzerCoverageTestSupport.rec("codePointBeforeNonSurrogateBmpChar");
        QuotePairAnalyzerCoverageTestSupport.nonEmpty("A\u2019");
    }

    public static function flushTestTrace():Void {
        TestTraceRecorder.flushClass("QuotePairAnalyzerCoverageTest");
    }

}
