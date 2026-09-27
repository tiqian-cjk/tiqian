package org.tiqian.layout;

import org.tiqian.layout.QuotePairAnalyzer.QuotePair;
import org.tiqian.layout.QuotePairAnalyzer.QuoteType;
import org.tiqian.test.TestHelpers;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class QuotePairAnalyzerSurrogateAdjacencyTestSupport {
    public static function rec(n:String):Void
        new TestTraceRecorder("QuotePairAnalyzerSurrogateAdjacencyTest").section(n);
}
