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

class QuotePairAnalyzerCoverageTestSupport {
    public static function rec(n:String):Void
        new TestTraceRecorder("QuotePairAnalyzerCoverageTest").section(n);

    public static function a():QuotePairAnalyzer
        return new QuotePairAnalyzer();

    public static function nonEmpty(t:String):Void {
        var d = a().classifyQuoteRoles(t, []);
        TracedAssertions.assertTrue(d.length > 0);
    }

    public static function failLow(t:String):Void
        TracedAssertions.assertFailsWith(null, () -> a().classifyQuoteRoles(t, []));
}
