package org.tiqian.layout;

import org.tiqian.font.FontRole;
import org.tiqian.font.FontRoleContext;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class ContextualDashEllipsisRoleResolverCoverageSupport {
    public static function start(n:String):Void
        new TestTraceRecorder("ContextualDashEllipsisRoleResolverCoverageTest").section(n);

    public static function surrogateText(c:Array<Int>):String {
        var s = "";
        var i = 0;
        while (i < c.length) {
            s += String.fromCharCode(c[i]);
            i++;
        }
        return s;
    }

    public static function valid(d:Array<ContextualDashEllipsisRoleResolver.DashEllipsisRoleDecision>, source:String, prefix:String):Bool {
        if (d.length != 2)
            return false;
        var i = 0;
        while (i < d.length) {
            if (d[i].role != FontRole.CjkPunctuation || d[i].source != source || !StringTools.startsWith(d[i].reason, prefix))
                return false;
            i++;
        }
        return true;
    }
}

class ContextualDashEllipsisRoleResolverCoverageTest {
    @:test public static function parentheticalPairWithOnlyLeftOuterScriptTakesTheLeftRole():Void {
        ContextualDashEllipsisRoleResolverCoverageSupport.start("parentheticalPairWithOnlyLeftOuterScriptTakesTheLeftRole");
        final d = new ContextualDashEllipsisRoleResolver().resolve("\u4E2D\u6587\u2014\u2014word\u2014\u2014", new FontRoleContext("zh-Hans"));
        if (!ContextualDashEllipsisRoleResolverCoverageSupport.valid(d, "ParentheticalDashPairContext", "only-left-outer-script"))
            TracedAssertions.fail(Std.string(d));
    }

    @:test public static function parentheticalPairWithOnlyRightOuterScriptTakesTheRightRole():Void {
        ContextualDashEllipsisRoleResolverCoverageSupport.start("parentheticalPairWithOnlyRightOuterScriptTakesTheRightRole");
        final d = new ContextualDashEllipsisRoleResolver().resolve("\u2014\u2014word\u2014\u2014\u4E2D\u6587", new FontRoleContext("zh-Hans"));
        if (!ContextualDashEllipsisRoleResolverCoverageSupport.valid(d, "ParentheticalDashPairContext", "only-right-outer-script"))
            TracedAssertions.fail(Std.string(d));
    }

    @:test public static function parentheticalPairWithoutOuterScriptFallsBackToParagraphLanguage():Void {
        ContextualDashEllipsisRoleResolverCoverageSupport.start("parentheticalPairWithoutOuterScriptFallsBackToParagraphLanguage");
        final d = new ContextualDashEllipsisRoleResolver().resolve("\u2014\u2014word\u2014\u2014", new FontRoleContext("zh-Hans"));
        if (!ContextualDashEllipsisRoleResolverCoverageSupport.valid(d, "ParagraphLanguageDashEllipsisContext", "parenthetical-pair-no-outer-context"))
            TracedAssertions.fail(Std.string(d));
    }

    @:test public static function forwardPassWalkerArmsRunBeforeTheClassifierRejectsLoneSurrogates():Void {
        ContextualDashEllipsisRoleResolverCoverageSupport.start("forwardPassWalkerArmsRunBeforeTheClassifierRejectsLoneSurrogates");
        final r = new ContextualDashEllipsisRoleResolver();
        TracedAssertions.assertFailsWith(null, () -> r.resolve(ContextualDashEllipsisRoleResolverCoverageSupport.surrogateText([0x2014, 0xD83D])));
        TracedAssertions.assertFailsWith(null, () -> r.resolve(ContextualDashEllipsisRoleResolverCoverageSupport.surrogateText([0xD83D, 0x2014])));
        TracedAssertions.assertFailsWith(null, () -> r.resolve(ContextualDashEllipsisRoleResolverCoverageSupport.surrogateText([0xD83D, 0xFFFD, 0x2014])));
    }
}
