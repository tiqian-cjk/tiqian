package org.tiqian.layout;

import org.tiqian.font.FontRole;
import org.tiqian.font.FontRoleContext;
import org.tiqian.layout.QuotePairAnalyzer.QuoteRoleDecision;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class ContextualQuoteRoleResolverNestedAndSurrogateSupport {
    public static function start(n:String):Void
        new TestTraceRecorder("ContextualQuoteRoleResolverNestedAndSurrogateTest").section(n);

    public static function decisions(text:String, ?locale:String):Array<QuoteRoleDecision> {
        final c = locale == null ? new FontRoleContext() : new FontRoleContext(locale);
        final a = new QuotePairAnalyzer();
        return a.classifyQuoteRoles(text, a.analyze(text), c);
    }

    public static function locate(ds:Array<QuoteRoleDecision>, i:Int):QuoteRoleDecision {
        var n = 0;
        while (n < ds.length) {
            if (ds[n].index == i)
                return ds[n];
            n++;
        }
        return ds[0];
    }

    public static function surrogateText(codes:Array<Int>):String {
        var s = "";
        var i = 0;
        while (i < codes.length) {
            s += String.fromCharCode(codes[i]);
            i++;
        }
        return s;
    }

    public static function assertIllegal(f:() -> Void):Void
        TracedAssertions.assertFailsWith(null, f);
}

class ContextualQuoteRoleResolverNestedAndSurrogateTest {
    @:test public static function nestedPairInsideNeutralEnclosingInheritsTheOuterQuotation():Void {
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.start("nestedPairInsideNeutralEnclosingInheritsTheOuterQuotation");
        final d = ContextualQuoteRoleResolverNestedAndSurrogateSupport.decisions("\u201C\u2014\u2018\u6587\u2019\u2014\u201D");
        final outer = ContextualQuoteRoleResolverNestedAndSurrogateSupport.locate(d, 0);
        final inner = ContextualQuoteRoleResolverNestedAndSurrogateSupport.locate(d, 2);
        TracedAssertions.assertEqualsString("PairedPunctuationEnclosingQuoteContext", inner.source);
        TracedAssertions.assertEqualsString("quote-pair-inherits-enclosing-quotation", inner.reason);
        TracedAssertions.assertEqualsFontRole(outer.role, inner.role);
        var has = false;
        var i = 0;
        while (i < d.length) {
            if (d[i].source == "DelimitedWesternQuotationRun")
                has = true;
            i++;
        }
        TracedAssertions.assertTrue(!has);
    }

    @:test public static function spaceBeforeUnmatchedQuoteWithCjkRightSkipsTheDelimitedRule():Void {
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.start("spaceBeforeUnmatchedQuoteWithCjkRightSkipsTheDelimitedRule");
        final d = ContextualQuoteRoleResolverNestedAndSurrogateSupport.decisions(" \u2019\u4E2D");
        final x = ContextualQuoteRoleResolverNestedAndSurrogateSupport.locate(d, 1);
        TracedAssertions.assertEqualsString("UnmatchedQuoteSurroundingScriptContext", x.source);
        TracedAssertions.assertEqualsFontRole(FontRole.CjkPunctuation, x.role);
    }

    @:test public static function leftwardScanFromALowSurrogateWalksEveryBacktrackArm():Void {
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.start("leftwardScanFromALowSurrogateWalksEveryBacktrackArm");
        final s = ContextualQuoteRoleResolverNestedAndSurrogateSupport.surrogateText;
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.assertIllegal(() ->
            ContextualQuoteRoleResolverNestedAndSurrogateSupport.decisions(s([0xDC00, 0x201C])));
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.assertIllegal(() ->
            ContextualQuoteRoleResolverNestedAndSurrogateSupport.decisions(s([0x61, 0xDC00, 0x201C])));
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.assertIllegal(() ->
            ContextualQuoteRoleResolverNestedAndSurrogateSupport.decisions(s([0x78, 0xDC00, 0xDC00, 0x201C])));
    }

    @:test public static function tabBeforeAWhollyWesternPairDelimitsLikeASpace():Void {
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.start("tabBeforeAWhollyWesternPairDelimitsLikeASpace");
        final x = ContextualQuoteRoleResolverNestedAndSurrogateSupport.locate(ContextualQuoteRoleResolverNestedAndSurrogateSupport.decisions("\t\u201Ca\u201D"),
            1);
        TracedAssertions.assertEqualsString("DelimitedWesternQuotationRun", x.source);
    }

    @:test public static function spaceBeforeAPairWithNonWesternContentSkipsTheDelimitedRule():Void {
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.start("spaceBeforeAPairWithNonWesternContentSkipsTheDelimitedRule");
        final x = ContextualQuoteRoleResolverNestedAndSurrogateSupport.locate(ContextualQuoteRoleResolverNestedAndSurrogateSupport.decisions(" \u201C\u4E2D\u201D"),
            1);
        TracedAssertions.assertEqualsString("PairedPunctuationContentScriptContext", x.source);
        TracedAssertions.assertEqualsFontRole(FontRole.CjkPunctuation, x.role);
    }

    @:test public static function spaceBeforeAMixedContentPairReportsMixedContent():Void {
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.start("spaceBeforeAMixedContentPairReportsMixedContent");
        final x = ContextualQuoteRoleResolverNestedAndSurrogateSupport.locate(ContextualQuoteRoleResolverNestedAndSurrogateSupport.decisions(" \u201Ca\u4E2D\u201D"),
            1);
        TracedAssertions.assertEqualsString("ParagraphLanguageQuoteContext", x.source);
        TracedAssertions.assertTrue(x.reason.indexOf("mixed-quoted-content") >= 0, x.reason);
    }

    @:test public static function mixedEnclosingLevelFallsBackToParagraphLanguage():Void {
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.start("mixedEnclosingLevelFallsBackToParagraphLanguage");
        final x = ContextualQuoteRoleResolverNestedAndSurrogateSupport.locate(ContextualQuoteRoleResolverNestedAndSurrogateSupport.decisions("a\u201C\u4E2D\u201D\u6587"),
            1);
        TracedAssertions.assertEqualsString("ParagraphLanguageQuoteContext", x.source);
        TracedAssertions.assertTrue(x.reason.indexOf("mixed-enclosing-level-script") >= 0, x.reason);
    }

    @:test public static function nonChineseLocaleResolvesNeutralContextToLatinText():Void {
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.start("nonChineseLocaleResolvesNeutralContextToLatinText");
        final d = ContextualQuoteRoleResolverNestedAndSurrogateSupport.decisions("\u2019", "en-US");
        final x = d[0];
        TracedAssertions.assertEqualsFontRole(FontRole.LatinText, x.role);
        TracedAssertions.assertTrue(x.reason.indexOf("paragraph-language=en-US") >= 0);
    }

    @:test public static function privateUseCharBeforeAQuoteFailsTheLowSurrogateRangeAbove():Void {
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.start("privateUseCharBeforeAQuoteFailsTheLowSurrogateRangeAbove");
        final x = ContextualQuoteRoleResolverNestedAndSurrogateSupport.locate(ContextualQuoteRoleResolverNestedAndSurrogateSupport.decisions("\uE000\u201C\u4E2D"),
            1);
        TracedAssertions.assertEqualsString("UnmatchedQuoteSurroundingScriptContext", x.source);
        TracedAssertions.assertEqualsFontRole(FontRole.CjkPunctuation, x.role);
    }

    @:test public static function highSurrogateAtTheContentEndHasNoRoomAndThrows():Void {
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.start("highSurrogateAtTheContentEndHasNoRoomAndThrows");
        final s = ContextualQuoteRoleResolverNestedAndSurrogateSupport.surrogateText;
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.assertIllegal(() ->
            ContextualQuoteRoleResolverNestedAndSurrogateSupport.decisions(s([0x201C, 0xD83D, 0x201D])));
    }

    @:test public static function siblingPairsInsideOneQuotationEachInheritTheOuterRole():Void {
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.start("siblingPairsInsideOneQuotationEachInheritTheOuterRole");
        final d = ContextualQuoteRoleResolverNestedAndSurrogateSupport.decisions("\u201C\u2018a\u2019\u2018b\u2019\u201D");
        final a = ContextualQuoteRoleResolverNestedAndSurrogateSupport.locate(d, 1);
        final b = ContextualQuoteRoleResolverNestedAndSurrogateSupport.locate(d, 4);
        TracedAssertions.assertEqualsString("PairedPunctuationEnclosingQuoteContext", a.source);
        TracedAssertions.assertEqualsString("PairedPunctuationEnclosingQuoteContext", b.source);
        TracedAssertions.assertEqualsFontRole(a.role, b.role);
    }

    @:test public static function plainFollowerOfAHighSurrogateCountsAsOneUnit():Void {
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.start("plainFollowerOfAHighSurrogateCountsAsOneUnit");
        final s = ContextualQuoteRoleResolverNestedAndSurrogateSupport.surrogateText;
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.assertIllegal(() ->
            ContextualQuoteRoleResolverNestedAndSurrogateSupport.decisions(s([0x201C, 0xD83D, 0x78, 0x201D])));
    }

    @:test public static function privateUseFollowerOfAHighSurrogateCountsAsOneUnit():Void {
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.start("privateUseFollowerOfAHighSurrogateCountsAsOneUnit");
        final s = ContextualQuoteRoleResolverNestedAndSurrogateSupport.surrogateText;
        ContextualQuoteRoleResolverNestedAndSurrogateSupport.assertIllegal(() ->
            ContextualQuoteRoleResolverNestedAndSurrogateSupport.decisions(s([0x201C, 0xD83D, 0xE000, 0x201D])));
    }
}
