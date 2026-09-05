package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.core.TextRangeError.Message;
import org.tiqian.font.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.test.TestHelpers;

class ContextualDashEllipsisRoleResolverTestSupport {
    public static function role(r:FontRole):String
        return Type.enumConstructor(r);

    public static function fail(m:String):Void
        throw new TiqianIllegalArgumentException(Message(m));

    public static function one(r:ContextualDashEllipsisRoleResolver, s:String,
            c:Null<FontRoleContext> = null):ContextualDashEllipsisRoleResolver.DashEllipsisRoleDecision {
        var d = r.resolve(s, c);
        if (d.length != 1)
            ContextualDashEllipsisRoleResolverTestSupport.fail("expected one decision for " + s);
        return d[0];
    }

    public static function allRole(d:Array<ContextualDashEllipsisRoleResolver.DashEllipsisRoleDecision>, r:FontRole):Bool {
        for (i in 0...d.length)
            if (d[i].role != r)
                return false;
        return true;
    }

    public static function allSource(d:Array<ContextualDashEllipsisRoleResolver.DashEllipsisRoleDecision>, s:String):Bool {
        for (i in 0...d.length)
            if (d[i].source != s)
                return false;
        return true;
    }

    public static function allReason(d:Array<ContextualDashEllipsisRoleResolver.DashEllipsisRoleDecision>, p:String):Bool {
        for (i in 0...d.length)
            if (!StringTools.startsWith(d[i].reason, p))
                return false;
        return true;
    }

    public static function render(d:Array<ContextualDashEllipsisRoleResolver.DashEllipsisRoleDecision>):String {
        var a:Array<String> = [];
        for (i in 0...d.length)
            a.push(Type.enumConstructor(d[i].role) + ":" + d[i].source + ":" + d[i].reason);
        return "[" + a.join(", ") + "]";
    }

    public static function layout(text:String, ?locale:String, ?spans:Array<TextSpan>):LayoutResult {
        return new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent(text, spans == null ? [] : spans),
            new TextStyle(null, null, locale == null ? "zh-Hans" : locale), new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(1000.0)));
    }

    public static function fontAt(r:LayoutResult, index:Int):FontDecisionInfo {
        for (i in 0...r.debug.fontDecisions.length) {
            var d = r.debug.fontDecisions[i];
            if (index >= d.range.start && index < d.range.end)
                return d;
        }
        throw new TiqianIllegalArgumentException(Message("no font decision at index " + index));
    }
}

class ContextualDashEllipsisRoleResolverTest {
    @:test public static function resolvesBySurroundingScriptRatherThanMarkCount():Void {
        var r = new ContextualDashEllipsisRoleResolver();
        var cases = [
            ["English \u2014 next", "LatinText"],
            ["\u2014 English", "LatinText"],
            ["A\u2014\u2014B", "LatinText"],
            ["Wait\u2026what", "LatinText"],
            ["Wait\u2026\u2026what", "LatinText"],
            ["\u4E2D\u6587\u2014\u4E0B\u53E5", "CjkPunctuation"],
            ["\u4E2D\u6587\u2014\u2014\u4E0B\u53E5", "CjkPunctuation"],
            ["\u4E2D\u6587\u2014123", "CjkPunctuation"],
            ["123\u2014English", "LatinText"],
            ["\u4E2D\u6587\u2026\u2026", "CjkPunctuation"],
            ["\u7B49\u7B49\u2026\u771F\u7684", "CjkPunctuation"],
            ["\u7B49\u7B49\u2026\u2026\u771F\u7684", "CjkPunctuation"]
        ];
        for (x in cases) {
            var d = ContextualDashEllipsisRoleResolverTestSupport.one(r, x[0]);
            if (ContextualDashEllipsisRoleResolverTestSupport.role(d.role) != x[1] || d.source != "DashEllipsisSurroundingScriptContext")
                ContextualDashEllipsisRoleResolverTestSupport.fail("wrong role/source for " + x[0]);
        }
    }

    @:test public static function conflictingOrAbsentScriptFallsBackToParagraphLanguage():Void {
        var r = new ContextualDashEllipsisRoleResolver();
        for (x in [["zh-Hans", "CjkPunctuation"], ["en-US", "LatinText"]]) {
            var c = new FontRoleContext(x[0]);
            for (s in ["\u4E2D\u6587\u2014English", "\u2026"]) {
                var d = ContextualDashEllipsisRoleResolverTestSupport.one(r, s, c);
                if (ContextualDashEllipsisRoleResolverTestSupport.role(d.role) != x[1]
                    || d.source != "ParagraphLanguageDashEllipsisContext")
                    ContextualDashEllipsisRoleResolverTestSupport.fail("fallback " + x[0]);
            }
        }
    }

    @:test public static function decisionReasonNamesTheEvidenceShape():Void {
        var r = new ContextualDashEllipsisRoleResolver();
        if (!StringTools.startsWith(ContextualDashEllipsisRoleResolverTestSupport.one(r, "A\u2014B").reason, "matching-surrounding-script")
            || !StringTools.startsWith(ContextualDashEllipsisRoleResolverTestSupport.one(r, "\u4E2D\u6587\u2026\u2026").reason, "only-left-strong-script")
            || !StringTools.startsWith(ContextualDashEllipsisRoleResolverTestSupport.one(r, "\u2014 English").reason, "only-right-strong-script"))
            ContextualDashEllipsisRoleResolverTestSupport.fail("wrong evidence reason");
    }

    @:test public static function mandatoryBreakStopsContextSearch():Void {
        var d = ContextualDashEllipsisRoleResolverTestSupport.one(new ContextualDashEllipsisRoleResolver(), "\u2014\nEnglish", new FontRoleContext("zh-Hans"));
        if (d.role != CjkPunctuation
            || d.source != "ParagraphLanguageDashEllipsisContext"
            || !StringTools.startsWith(d.reason, "no-strong-script-context"))
            ContextualDashEllipsisRoleResolverTestSupport.fail("mandatory break did not stop search");
    }

    @:test public static function linearContextIndexPreservesSupplementaryScriptEvidence():Void {
        var a = TestHelpers.surrogateText([0xD840, 0xDC00]) + "\u2014123";
        var b = "123\u2014" + TestHelpers.surrogateText([0xD801, 0xDC00]);
        if (ContextualDashEllipsisRoleResolverTestSupport.one(new ContextualDashEllipsisRoleResolver(), a).role != CjkPunctuation
            || ContextualDashEllipsisRoleResolverTestSupport.one(new ContextualDashEllipsisRoleResolver(), b).role != LatinText)
            ContextualDashEllipsisRoleResolverTestSupport.fail("supplementary evidence");
    }

    @:test public static function resolvesManyNeutralSeparatedRunsFromOneParagraphIndex():Void {
        var s = "A";
        for (i in 0...2048)
            s += " \u2014 ";
        s += "B";
        var d = new ContextualDashEllipsisRoleResolver().resolve(s, new FontRoleContext("zh-Hans"));
        if (d.length != 2048 || !ContextualDashEllipsisRoleResolverTestSupport.allRole(d, LatinText))
            ContextualDashEllipsisRoleResolverTestSupport.fail("many runs");
    }

    @:test public static function pairsParentheticalDashesAcrossInsertedContent():Void {
        var d = new ContextualDashEllipsisRoleResolver()
            .resolve("\u4ED6\u5F7B\u591C\u60F3Jessica\u2014\u2014Jessica\u662F\u4ED6\u7684\u524D\u5973\u53CB\u2014\u2014\u7761\u4E0D\u7740\u89C9",
            new FontRoleContext("zh-Hans"));
        if (d.length != 2
            || !ContextualDashEllipsisRoleResolverTestSupport.allRole(d, CjkPunctuation)
            || !ContextualDashEllipsisRoleResolverTestSupport.allSource(d, "ParagraphLanguageDashEllipsisContext")
            || !ContextualDashEllipsisRoleResolverTestSupport.allReason(d, "parenthetical-pair-conflicting-outer-script"))
            ContextualDashEllipsisRoleResolverTestSupport.fail("parenthetical conflict: " + ContextualDashEllipsisRoleResolverTestSupport.render(d));
    }

    @:test public static function matchingOuterScriptResolvesTheParentheticalPairDirectly():Void {
        var d = new ContextualDashEllipsisRoleResolver().resolve("word\u2014\u2014and stuff\u2014\u2014word");
        if (d.length != 2
            || !ContextualDashEllipsisRoleResolverTestSupport.allRole(d, LatinText)
            || !ContextualDashEllipsisRoleResolverTestSupport.allSource(d, "ParentheticalDashPairContext"))
            ContextualDashEllipsisRoleResolverTestSupport.fail("matching pair");
    }

    @:test public static function punctuationBetweenRunsKeepsThemIndependent():Void {
        var d = new ContextualDashEllipsisRoleResolver().resolve("\u5730\u70B9\u2014\u2014\u5317\u4EAC\uFF0C\u65F6\u95F4\u2014\u2014\u660E\u5929",
            new FontRoleContext("zh-Hans"));
        if (d.length != 2
            || !ContextualDashEllipsisRoleResolverTestSupport.allRole(d, CjkPunctuation)
            || !ContextualDashEllipsisRoleResolverTestSupport.allSource(d, "DashEllipsisSurroundingScriptContext"))
            ContextualDashEllipsisRoleResolverTestSupport.fail("punctuation separation");
    }

    @:test public static function symbolBetweenRunsKeepsThemIndependent():Void {
        var d = new ContextualDashEllipsisRoleResolver().resolve("\u65F6\u4EF7\u2014\u2014$100\u2014\u2014\u5F88\u8D35", new FontRoleContext("zh-Hans"));
        if (d.length != 2 || !ContextualDashEllipsisRoleResolverTestSupport.allSource(d, "DashEllipsisSurroundingScriptContext"))
            ContextualDashEllipsisRoleResolverTestSupport.fail("symbol separation");
    }

    @:test public static function unequalRunLengthsDoNotPair():Void {
        var d = new ContextualDashEllipsisRoleResolver().resolve("\u60F3Jessica\u2014\u2014Jessica\u662F\u524D\u5973\u53CB\u2014\u7761\u4E0D\u7740",
            new FontRoleContext("zh-Hans"));
        if (d.length != 2 || d[0].role != LatinText || d[1].role != CjkPunctuation)
            ContextualDashEllipsisRoleResolverTestSupport.fail("unequal runs");
    }

    @:test public static function ellipsisRunsNeverPair():Void {
        var d = new ContextualDashEllipsisRoleResolver()
            .resolve("\u60F3Jessica\u2026\u2026Jessica\u662F\u4ED6\u7684\u524D\u5973\u53CB\u2026\u2026\u7761\u4E0D\u7740", new FontRoleContext("zh-Hans"));
        if (d.length != 2 || d[0].role != LatinText || d[1].role != CjkPunctuation)
            ContextualDashEllipsisRoleResolverTestSupport.fail("ellipsis pair");
    }

    @:test public static function mandatoryBreakBetweenRunsKeepsThemIndependent():Void {
        var d = new ContextualDashEllipsisRoleResolver().resolve("\u60F3Jessica\u2014\u2014Jessica\n\u662F\u524D\u5973\u53CB\u2014\u2014\u7761\u4E0D\u7740",
            new FontRoleContext("zh-Hans"));
        if (d.length != 2 || d[0].role != LatinText || d[1].role != CjkPunctuation)
            ContextualDashEllipsisRoleResolverTestSupport.fail("break pair");
    }

    @:test public static function westernContextKeepsDashAndEllipsisOnLatinFaceAndPreservesSourceDisplay():Void {
        var s = "English \u2014 next; ellipsis\u2026 / slash. A\u2014\u2014B; Wait\u2026\u2026what?";
        var r = ContextualDashEllipsisRoleResolverTestSupport.layout(s);
        for (i in 0...r.debug.fontDecisions.length) {
            var d = r.debug.fontDecisions[i];
            if (d.role != "LatinText" || d.sourceText != d.displayText)
                ContextualDashEllipsisRoleResolverTestSupport.fail("western layout");
        }
    }

    @:test public static function cjkContextKeepsClreqDisplaySubstitutionIndependentOfMarkCount():Void {
        var s = "\u4E2D\u2014\u6587\uFF0C\u7B49\u2026\u771F\uFF1B\u4E2D\u6587\u2014\u2014\u4E0B\u53E5\uFF0C\u7701\u7565\u53F7\u2026\u2026\u3002";
        var r = ContextualDashEllipsisRoleResolverTestSupport.layout(s);
        var n = 0;
        for (i in 0...r.debug.fontDecisions.length) {
            var d = r.debug.fontDecisions[i];
            if (d.role == "CjkPunctuation") {
                n++;
            }
        }
        if (n == 0)
            ContextualDashEllipsisRoleResolverTestSupport.fail("cjk decisions missing");
    }

    @:test public static function parentheticalPairSharesOneFaceAndSubstitution():Void {
        var s = "\u4ED6\u5F7B\u591C\u60F3Jessica\u2014\u2014Jessica\u662F\u4ED6\u7684\u524D\u5973\u53CB\u2014\u2014\u7761\u4E0D\u7740\u89C9";
        var r = ContextualDashEllipsisRoleResolverTestSupport.layout(s);
        var n = 0;
        for (i in 0...r.debug.fontDecisions.length)
            if (r.debug.fontDecisions[i].role == "CjkPunctuation")
                n++;
        if (n == 0)
            ContextualDashEllipsisRoleResolverTestSupport.fail("pair decisions missing");
    }

    @:test public static function standaloneWesternEllipsisCannotBeRewrittenByTheSubstitutor():Void {
        var r = ContextualDashEllipsisRoleResolverTestSupport.layout("\u2026", "en-US");
        var d = r.debug.fontDecisions[0];
        if (d.role != "LatinText" || d.sourceText != "\u2026" || d.displayText != "\u2026")
            ContextualDashEllipsisRoleResolverTestSupport.fail("standalone ellipsis");
    }
}
