package org.tiqian.layout;

// The helpers of the legacy file's first class stay in that class's module, so
// a second module reaches the support type through the owning module path.
import org.tiqian.layout.ContextualDashEllipsisRoleResolverTest.ContextualDashEllipsisRoleResolverTestSupport;

/**
    The legacy suite declares this class beside ContextualDashEllipsisRoleResolverTest
    inside one file: engine/src/commonTest/kotlin/org/tiqian/layout/ContextualDashEllipsisRoleResolverTest.kt:193.
    A Haxe module carries one test class under its own module path, and the Kotlin
    runner reports a test id as module path plus method name
    (packages/compiler/reflaxe/kotlin/kotlincompiler/Compiler.hx:159), so the four
    ids of this class exist on the legacy side only unless the class gets a module
    named after it. The four entry points and their bodies are unchanged from the
    port's merged class.
**/
class ContextualDashEllipsisLayoutTest {
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
