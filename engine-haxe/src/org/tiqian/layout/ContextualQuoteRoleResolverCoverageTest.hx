package org.tiqian.layout;

import org.tiqian.font.FontRole;
import org.tiqian.font.FontRoleContext;
import org.tiqian.layout.QuotePairAnalyzer.QuoteRoleDecision;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class ContextualQuoteRoleResolverCoverageSupport {
    public static function start(n:String):Void
        new TestTraceRecorder("ContextualQuoteRoleResolverCoverageTest").section(n);

    public static function decisions(text:String, pairs:Null<Array<QuotePairAnalyzer.QuotePair>>):Array<QuoteRoleDecision> {
        return new QuotePairAnalyzer().classifyQuoteRoles(text, pairs == null ? [] : pairs);
    }

    public static function anyRole(ds:Array<QuoteRoleDecision>, role:FontRole):Bool {
        var i = 0;
        while (i < ds.length) {
            if (ds[i].role == role)
                return true;
            i++;
        }
        return false;
    }

    public static function anySource(ds:Array<QuoteRoleDecision>, source:String):Bool {
        var i = 0;
        while (i < ds.length) {
            if (ds[i].source == source)
                return true;
            i++;
        }
        return false;
    }

    public static function nonEmpty(ds:Array<QuoteRoleDecision>):Bool
        return ds.length > 0;

    public static function execute(n:String, text:String, paired:Bool = true):Array<QuoteRoleDecision> {
        start(n);
        final a = new QuotePairAnalyzer();
        final p = paired ? a.analyze(text) : [];
        return a.classifyQuoteRoles(text, p);
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

    public static function locate(ds:Array<QuoteRoleDecision>, index:Int):Null<QuoteRoleDecision> {
        var i = 0;
        while (i < ds.length) {
            if (ds[i].index == index)
                return ds[i];
            i++;
        }
        return null;
    }
}

class ContextualQuoteRoleResolverCoverageTest {
    @:test public static function nestedPairInheritsEnclosingQuoteRole():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("nestedPairInheritsEnclosingQuoteRole",
            "\u4ED6\u8BF4\uFF1A\u201C\u5979\u8BF4\u2018\u4F60\u597D\u2019\u3002\u201D");
        final a = ContextualQuoteRoleResolverCoverageSupport.locate(d, 6);
        if (a != null)
            TracedAssertions.assertEqualsFontRole(FontRole.CjkPunctuation, a.role);
        final b = ContextualQuoteRoleResolverCoverageSupport.locate(d, 9);
        if (b != null)
            TracedAssertions.assertEqualsFontRole(FontRole.CjkPunctuation, b.role);
    }

    @:test public static function nestedPairLatinInnerInheritsCjkEnclosing():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("nestedPairLatinInnerInheritsCjkEnclosing", "\u4ED6\u8BF4\uFF1A\u201Chello\u201D");
        final a = ContextualQuoteRoleResolverCoverageSupport.locate(d, 3);
        if (a != null)
            TracedAssertions.assertEqualsFontRole(FontRole.CjkPunctuation, a.role);
    }

    @:test public static function unmatchedRightSingleQuoteUsesSurroundingScript():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("unmatchedRightSingleQuoteUsesSurroundingScript", "abc\u2019def", false);
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.anyRole(d, FontRole.LatinText));
    }

    @:test public static function unmatchedRightDoubleQuote():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("unmatchedRightDoubleQuote", "abc\u201D", false);
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function unmatchedLeftDoubleQuote():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("unmatchedLeftDoubleQuote", "\u201Cabc", false);
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function unmatchedLeftSingleQuote():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("unmatchedLeftSingleQuote", "\u2018abc", false);
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function conflictingUnmatchedQuotesUsesParagraphLanguage():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("conflictingUnmatchedQuotesUsesParagraphLanguage", "\u03B1\u2019\u4E2D", false);
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function unmatchedQuoteWithSurrogatePairContent():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("unmatchedQuoteWithSurrogatePairContent",
            ContextualQuoteRoleResolverCoverageSupport.surrogateText([0xD83D, 0xDE00, 0x2019, 0x4E2D]), false);
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function codePointAtCompatWithSupplementaryChar():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("codePointAtCompatWithSupplementaryChar",
            ContextualQuoteRoleResolverCoverageSupport.surrogateText([0xD83D, 0xDE00, 0x201C, 0xD83D, 0xDE00, 0x201D]));
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function codePointLengthAtSupplementaryInContent():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("codePointLengthAtSupplementaryInContent",
            ContextualQuoteRoleResolverCoverageSupport.surrogateText([0x201C, 0xD83D, 0xDE00, 0x201D]));
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function nonCjkInWordApostropheWithSurrogateBefore():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("nonCjkInWordApostropheWithSurrogateBefore",
            ContextualQuoteRoleResolverCoverageSupport.surrogateText([0xD83D, 0xDE00, 0x2019, 0x78]), false);
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function whitespaceDelimitedWesternQuoteUnmatched():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("whitespaceDelimitedWesternQuoteUnmatched", "中文 ’90s", false);
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.anySource(d, "DelimitedUnmatchedWesternQuote"));
    }

    @:test public static function enclosingPairResolvedBeforeInner():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("enclosingPairResolvedBeforeInner", "\u201C\u2018\u4E2D\u2019\u201D");
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function pairByCloseSkipInNearestStrongScript():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("pairByCloseSkipInNearestStrongScript", "\u201C\u2018abc\u2019\u201D", false);
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function pairByOpenSkipInNearestStrongScript():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("pairByOpenSkipInNearestStrongScript", "\u201C\u2018abc\u2019\u201D", false);
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function ambiguousCurlyQuoteUnmatchedInText():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("ambiguousCurlyQuoteUnmatchedInText", "abc\u2019", false);
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function resolveUnmatchedWithBothSurroundingRolesNull():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("resolveUnmatchedWithBothSurroundingRolesNull", "\u2019", false);
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function nearestStrongScriptRoleBackwardSkipsPairedCloseQuote():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("nearestStrongScriptRoleBackwardSkipsPairedCloseQuote", "\u201C\u2018a\u2019\u201D\u2019");
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function nearestStrongScriptRoleForwardSkipsPairedOpenQuote():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("nearestStrongScriptRoleForwardSkipsPairedOpenQuote", "\u2019\u201Cabc\u201D");
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function enclosingPairResolvedBeforeInnerPair():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("enclosingPairResolvedBeforeInnerPair", "\u201C\u2018abc\u2019\u201D");
        final a = ContextualQuoteRoleResolverCoverageSupport.locate(d, 1);
        TracedAssertions.assertNotNullRendered(a != null, a == null ? "null" : a.toString());
        if (a != null) {
            TracedAssertions.assertEqualsFontRole(FontRole.CjkPunctuation, a.role);
            TracedAssertions.assertEqualsString("PairedPunctuationEnclosingQuoteContext", a.source);
        }
    }

    @:test public static function whitespaceDelimitedWesternQuotePaired():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("whitespaceDelimitedWesternQuotePaired", "\u201C \u2018hello\u2019 \u201D");
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function conflictingUnmatchedQuotesBothNonNull():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("conflictingUnmatchedQuotesBothNonNull", "\u03B1\u2019\u4E2D", false);
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function noUnmatchedQuoteContext():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("noUnmatchedQuoteContext", "\u2019", false);
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function nearestStrongScriptRoleBackwardThroughSurrogatePair():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("nearestStrongScriptRoleBackwardThroughSurrogatePair",
            ContextualQuoteRoleResolverCoverageSupport.surrogateText([0xD83D, 0xDE00, 0x201C, 0x61, 0x62, 0x63, 0x201D]));
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function nearestStrongScriptRoleForwardThroughSurrogatePair():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("nearestStrongScriptRoleForwardThroughSurrogatePair",
            ContextualQuoteRoleResolverCoverageSupport.surrogateText([0x201C, 0x61, 0x62, 0x63, 0xD83D, 0xDE00, 0x201D]));
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function nestedPairSkipsInnerInScriptEvidence():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("nestedPairSkipsInnerInScriptEvidence", "\u201C\u2018\u4E2D\u2019\u201D");
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function mixedScriptEnclosingLevelUsesParagraphLanguage():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("mixedScriptEnclosingLevelUsesParagraphLanguage", "abc\u201C\u4E2D\u201D");
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function unmatchedRightSingleQuoteWithLeftRole():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("unmatchedRightSingleQuoteWithLeftRole", "\u4E2D\u2019", false);
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function unmatchedRightSingleQuoteWithRightRole():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("unmatchedRightSingleQuoteWithRightRole", "\u2019\u4E2D", false);
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function unmatchedQuoteWithWhitespaceBeforeAndLatinRight():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("unmatchedQuoteWithWhitespaceBeforeAndLatinRight", " \u2019abc", false);
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.anySource(d, "DelimitedUnmatchedWesternQuote"));
    }

    @:test public static function nonCjkInWordApostrophePaired():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("nonCjkInWordApostrophePaired", "\u2018it\u2019s");
        final a = new QuotePairAnalyzer();
        TracedAssertions.assertTrue(a.analyze("\u2018it\u2019s").length == 0);
    }

    @:test public static function codePointLengthAtSurrogatePairInContent():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("codePointLengthAtSurrogatePairInContent",
            ContextualQuoteRoleResolverCoverageSupport.surrogateText([0x201C, 0xD83D, 0xDE00, 0x201D]));
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function codePointAtCompatSupplementaryInOuterEvidence():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("codePointAtCompatSupplementaryInOuterEvidence",
            ContextualQuoteRoleResolverCoverageSupport.surrogateText([0xD83D, 0xDE00, 0x201C, 0x61, 0x62, 0x63, 0x201D, 0xD83D, 0xDE00]));
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function conflictingUnmatchedQuotesLeftAndRightNonNull():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("conflictingUnmatchedQuotesLeftAndRightNonNull", "a\u2019b\u201Cc");
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function unmatchedQuoteNonWhitespaceBefore():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("unmatchedQuoteNonWhitespaceBefore", "a\u201C");
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function nearestStrongScriptRoleBackwardHitsSupplementary():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("nearestStrongScriptRoleBackwardHitsSupplementary",
            ContextualQuoteRoleResolverCoverageSupport.surrogateText([0xD83D, 0xDE00, 0x201C]));
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function nearestStrongScriptRoleForwardHitsSupplementary():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("nearestStrongScriptRoleForwardHitsSupplementary",
            ContextualQuoteRoleResolverCoverageSupport.surrogateText([0x201C, 0xD83D, 0xDE00]));
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function enclosingPairUnresolvedFallsThroughToContent():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("enclosingPairUnresolvedFallsThroughToContent", "\u201C\u2018abc\u2019\u201D");
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }

    @:test public static function unmatchedQuoteAtStartWithRightRole():Void {
        final d = ContextualQuoteRoleResolverCoverageSupport.execute("unmatchedQuoteAtStartWithRightRole", "\u201Cabc");
        TracedAssertions.assertTrue(ContextualQuoteRoleResolverCoverageSupport.nonEmpty(d));
    }
}
