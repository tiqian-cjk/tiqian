package org.tiqian.layout;

import org.tiqian.layout.QuotePairAnalyzer.QuotePair;
import org.tiqian.layout.QuotePairAnalyzer.QuoteType;
import org.tiqian.test.TestHelpers;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class QuotePairAnalyzerSurrogateAdjacencyTest {
    @:test public static function lowQuoteCodePointsTakeTheSwitchDefaultWithoutPairing():Void {
        QuotePairAnalyzerSurrogateAdjacencyTestSupport.rec("lowQuoteCodePointsTakeTheSwitchDefaultWithoutPairing");
        TracedAssertions.assertEqualsQuotePairArray([new QuotePair(2, 3, QuoteType.Double)], new QuotePairAnalyzer().analyze("\u201A\u201B\u201C\u201D"));
    }

    @:test(except = ["swift", "rust"]) public static function apostropheAfterASurrogatePairWalksTheCombineArmBefore():Void {
        QuotePairAnalyzerSurrogateAdjacencyTestSupport.rec("apostropheAfterASurrogatePairWalksTheCombineArmBefore");
        TracedAssertions.assertFalse(QuotePairAnalyzer.isNonCjkInWordApostrophe(TestHelpers.surrogateText([0xD83D, 0xDE00, 0x2019, 0x78]), 2));
        TracedAssertions.assertFailsWith(null, () -> QuotePairAnalyzer.isNonCjkInWordApostrophe(TestHelpers.surrogateText([0xDC00, 0x2019, 0x78]), 1));
        TracedAssertions.assertFailsWith(null,
            () -> QuotePairAnalyzer.isNonCjkInWordApostrophe(TestHelpers.surrogateText([0x61, 0x62, 0xDC00, 0x2019, 0x78]), 3));
        TracedAssertions.assertFalse(QuotePairAnalyzer.isNonCjkInWordApostrophe("\uE000\u2019b", 1));
        TracedAssertions.assertFailsWith(null,
            () -> QuotePairAnalyzer.isNonCjkInWordApostrophe(TestHelpers.surrogateText([0x78, 0xDC00, 0xDC00, 0x2019, 0x78]), 3));
    }

    @:test(except = ["swift", "rust"]) public static function apostropheBeforeASurrogateWalksBothLowCheckArms():Void {
        QuotePairAnalyzerSurrogateAdjacencyTestSupport.rec("apostropheBeforeASurrogateWalksBothLowCheckArms");
        TracedAssertions.assertFalse(QuotePairAnalyzer.isNonCjkInWordApostrophe(TestHelpers.surrogateText([0x61, 0x2019, 0xD83D, 0xDE00]), 1));
        TracedAssertions.assertFailsWith(null, () -> QuotePairAnalyzer.isNonCjkInWordApostrophe(TestHelpers.surrogateText([0x61, 0x2019, 0xD83D, 0x62]), 1));
    }

    @:test(except = ["swift", "rust"]) public static function plainAndBoundaryNeighboursWalkTheNonSurrogateArms():Void {
        QuotePairAnalyzerSurrogateAdjacencyTestSupport.rec("plainAndBoundaryNeighboursWalkTheNonSurrogateArms");
        TracedAssertions.assertTrue(QuotePairAnalyzer.isNonCjkInWordApostrophe("a\u2019b", 1));
        TracedAssertions.assertFalse(QuotePairAnalyzer.isNonCjkInWordApostrophe("\u2019a", 0));
        TracedAssertions.assertFalse(QuotePairAnalyzer.isNonCjkInWordApostrophe("a\u2019", 1));
        TracedAssertions.assertFailsWith(null, () -> QuotePairAnalyzer.isNonCjkInWordApostrophe(TestHelpers.surrogateText([0x61, 0x2019, 0xDC00]), 1));
        TracedAssertions.assertFailsWith(null, () -> QuotePairAnalyzer.isNonCjkInWordApostrophe(TestHelpers.surrogateText([0x61, 0x2019, 0xD83D]), 1));
        TracedAssertions.assertFailsWith(null, () -> QuotePairAnalyzer.isNonCjkInWordApostrophe(TestHelpers.surrogateText([0x61, 0x2019, 0xD83D, 0xE000]), 1));
    }

    public static function flushTestTrace():Void {
        TestTraceRecorder.flushClass("QuotePairAnalyzerSurrogateAdjacencyTest");
    }

}
