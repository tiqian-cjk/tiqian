package org.tiqian.layout

import org.tiqian.core.TiqianIllegalArgumentException

import kotlin.test.Test
import org.tiqian.test.trace.assertEquals
import org.tiqian.test.trace.assertFailsWith
import org.tiqian.test.trace.assertFalse
import org.tiqian.test.trace.assertTrue
import kotlin.test.AfterTest
import org.tiqian.test.trace.TestTraceRecorder

// A lone surrogate written inside a string literal is replaced with '?' when
// the JS test bundle re-serializes its sources, so inputs that carry one are
// built from char codes at runtime to keep the code unit intact everywhere.
private fun surrogateText(vararg codes: Int): String =
    CharArray(codes.size) { codes[it].toChar() }.concatToString()

/**
 * The quote switch's low-quote case edges and the surrogate-walk arms of the
 * apostrophe helpers: codePointBefore and codePointAtOrNull only run for a
 * U+2019 apostrophe, so each arm needs the apostrophe adjacent to a specific
 * surrogate shape.
 */
class QuotePairAnalyzerSurrogateAdjacencyTest {
    private val testTrace = TestTraceRecorder("QuotePairAnalyzerSurrogateAdjacencyTest")


    private val analyzer = QuotePairAnalyzer()

    @Test
    fun lowQuoteCodePointsTakeTheSwitchDefaultWithoutPairing() {
        testTrace.section("lowQuoteCodePointsTakeTheSwitchDefaultWithoutPairing")
        // U+201A and U+201B are their own tableswitch edges routing to the
        // no-op default: neither opens nor closes a pair, so only the “ ”
        // couple at indices 2..3 pairs.
        val pairs = analyzer.analyze("‚‛“”")
        assertEquals(listOf(QuotePair(2, 3, QuoteType.Double)), pairs)
    }

    @Test
    fun apostropheAfterASurrogatePairWalksTheCombineArmBefore() {
        testTrace.section("apostropheAfterASurrogatePairWalksTheCombineArmBefore")
        // The apostrophe at 2 looks back onto a full pair: the in-range test
        // fails (low surrogate), the index >= 2 test passes, and the high
        // surrogate before it combines into U+1F600 — not a word character,
        // so the apostrophe check answers false.
        assertFalse("😀’x".isNonCjkInWordApostrophe(2))
        // A lone low surrogate at the string start reaches the same in-range
        // failure with index < 2, returning the lone half; the word-character
        // lookup rejects a non-scalar and the helper throws.
        assertFailsWith<TiqianIllegalArgumentException> {
            surrogateText(0xDC00, 0x2019, 'x'.code).isNonCjkInWordApostrophe(1)
        }
        // A lone low surrogate with a plain char before it: the high check
        // fails, the low half returns alone, and the lookup throws again.
        assertFailsWith<TiqianIllegalArgumentException> {
            surrogateText('a'.code, 'b'.code, 0xDC00, 0x2019, 'x'.code).isNonCjkInWordApostrophe(3)
        }
        // A private-use char above the low-surrogate range fails the range
        // test on its upper comparison and returns as a plain code point,
        // which is not a word character.
        assertFalse("\uE000’b".isNonCjkInWordApostrophe(1))
        // Two low surrogates in a row: the leading char of the pair lookback
        // is itself above the high-surrogate range, so the low half returns
        // alone and the lookup throws. The apostrophe needs a right neighbour:
        // the rewritten helper walks both flanks before the word-character
        // lookup, so a string-end apostrophe returns false at the null flank
        // without ever reaching the throwing lookup.
        assertFailsWith<TiqianIllegalArgumentException> {
            surrogateText('x'.code, 0xDC00, 0xDC00, 0x2019, 'x'.code).isNonCjkInWordApostrophe(3)
        }
    }

    @Test
    fun apostropheBeforeASurrogateWalksBothLowCheckArms() {
        testTrace.section("apostropheBeforeASurrogateWalksBothLowCheckArms")
        // The apostrophe's right neighbour is a full pair: codePointAtOrNull
        // combines it into U+1F600 (not a word character).
        assertFalse("a’😀".isNonCjkInWordApostrophe(1))
        // The right neighbour is a high surrogate with no low half after it:
        // the low check fails, the high half returns alone, and the
        // word-character lookup rejects the non-scalar with the same throw.
        assertFailsWith<TiqianIllegalArgumentException> {
            surrogateText('a'.code, 0x2019, 0xD83D, 'b'.code).isNonCjkInWordApostrophe(1)
        }
    }

    @Test
    fun plainAndBoundaryNeighboursWalkTheNonSurrogateArms() {
        testTrace.section("plainAndBoundaryNeighboursWalkTheNonSurrogateArms")
        // Plain BMP letters on both sides: the surrogate range tests fail on
        // their first comparison and both walkers return the raw char codes,
        // which are non-CJK word characters, so the apostrophe qualifies.
        assertTrue("a’b".isNonCjkInWordApostrophe(1))
        // Apostrophe at the string start: no left neighbour to look at.
        assertFalse("’a".isNonCjkInWordApostrophe(0))
        // Apostrophe at the string end: the right-neighbour index misses the
        // string and the walker answers null.
        assertFalse("a’".isNonCjkInWordApostrophe(1))
        // A lone low surrogate right after the apostrophe fails the
        // high-surrogate range test and returns as-is; the lookup throws.
        assertFailsWith<TiqianIllegalArgumentException> {
            surrogateText('a'.code, 0x2019, 0xDC00).isNonCjkInWordApostrophe(1)
        }
        // A high surrogate at the very end passes the range test but has no
        // room for its low half; the lone half returns and the lookup throws.
        assertFailsWith<TiqianIllegalArgumentException> {
            surrogateText('a'.code, 0x2019, 0xD83D).isNonCjkInWordApostrophe(1)
        }
        // A high surrogate followed by a private-use char above the
        // low-surrogate range: the low check fails on its upper comparison,
        // the high half returns alone, and the lookup throws.
        assertFailsWith<TiqianIllegalArgumentException> {
            surrogateText('a'.code, 0x2019, 0xD83D, 0xE000).isNonCjkInWordApostrophe(1)
        }
    }

    @AfterTest
    fun flushTestTrace() {
        testTrace.flush()
    }
}