package org.tiqian.layout;

import org.tiqian.core.TextRange;
import org.tiqian.layout.ContextualDashEllipsisRoleResolver.ContextualDashEllipsisRoles;
import org.tiqian.layout.QuotePairAnalyzer.QuotePairAwareFontRoleClassifier;
import org.tiqian.font.CjkFontRoleClassifier;
import org.tiqian.font.FontRole;
import org.tiqian.font.FontRoleContext;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

// Kotlin source: engine/src/commonTest/kotlin/org/tiqian/layout/
// ContextualDashEllipsisRoleResolverCoverageTest.kt, third class
// (ContextualRoleExtensionCoverageTest). Every Kotlin assertion there is a
// plain kotlin.test check (no trace event), so the Haxe side checks silently
// with TracedAssertions.fail and records only the section marker.
class ContextualRoleExtensionCoverageTest {
    @:test
    public static function contextualRoleExtensionsWrapOutsideThePipeline():Void {
        ContextualRoleExtensionCoverageSupport.start("contextualRoleExtensionsWrapOutsideThePipeline");
        final base = new CjkFontRoleClassifier();
        final context = new FontRoleContext("zh-Hans");

        // No contextual marks in the text: each extension returns the receiver
        // unchanged. The context-free calls also execute the default-argument
        // expressions.
        if (ContextualDashEllipsisRoles.withContextualDashEllipsisRoles(base, "\u4E2D\u6587", context) != base) {
            TracedAssertions.fail("dash extension changed the mark-free receiver");
        }
        if (QuotePairAwareFontRoleClassifier.withContextualQuoteRoles(base, "\u4E2D\u6587", context) != base) {
            TracedAssertions.fail("quote extension changed the mark-free receiver");
        }
        if (ContextualDashEllipsisRoles.withContextualDashEllipsisRoles(base, "\u4E2D\u6587") != base) {
            TracedAssertions.fail("context-free dash extension changed the mark-free receiver");
        }
        if (QuotePairAwareFontRoleClassifier.withContextualQuoteRoles(base, "\u4E2D\u6587") != base) {
            TracedAssertions.fail("context-free quote extension changed the mark-free receiver");
        }

        // With marks the wrappers resolve the run role directly and delegate
        // every other range to the base classifier.
        final dashText = "\u4E2D\u6587\u2014English";
        final dashAware = ContextualDashEllipsisRoles.withContextualDashEllipsisRoles(base, dashText, context);
        if (dashAware.classify(dashText, new TextRange(2, 3), context) != FontRole.CjkPunctuation) {
            TracedAssertions.fail("dash-aware wrapper missed the dash run role");
        }
        if (dashAware.classify(dashText, new TextRange(0, 1), context) != base.classify(dashText, new TextRange(0, 1), context)) {
            TracedAssertions.fail("dash-aware wrapper stopped delegating untouched ranges");
        }

        final quoteText = "\u4E2Da\u201Cb\u201Dc\u6587";
        final quoteAware = QuotePairAwareFontRoleClassifier.withContextualQuoteRoles(base, quoteText, context);
        if (quoteAware.classify(quoteText, new TextRange(2, 3), context) != FontRole.LatinText) {
            TracedAssertions.fail("quote-aware wrapper missed the nested Latin quote role");
        }
    }
}

class ContextualRoleExtensionCoverageSupport {
    public static function start(n:String):Void
        new TestTraceRecorder("ContextualRoleExtensionCoverageTest").section(n);
}
