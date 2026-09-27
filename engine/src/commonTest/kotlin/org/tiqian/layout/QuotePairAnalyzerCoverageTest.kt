package org.tiqian.layout

import org.tiqian.core.TiqianIllegalArgumentException

import org.tiqian.core.TextRange
import org.tiqian.font.CjkFontRoleClassifier
import org.tiqian.font.FontRole
import org.tiqian.font.FontRoleClassifier
import org.tiqian.font.FontRoleContext
import kotlin.test.Test
import org.tiqian.test.trace.assertEquals
import org.tiqian.test.trace.assertTrue
import org.tiqian.test.trace.assertFailsWith
import kotlin.test.AfterTest
import org.tiqian.test.trace.TestTraceRecorder

// A lone surrogate written inside a string literal is replaced with '?' when
// the JS test bundle re-serializes its sources, so inputs that carry one are
// built from char codes at runtime to keep the code unit intact everywhere.
private fun surrogateText(vararg codes: Int): String =
    CharArray(codes.size) { codes[it].toChar() }.concatToString()

class QuotePairAnalyzerCoverageTest {
    private val testTrace = TestTraceRecorder("QuotePairAnalyzerCoverageTest")

    private val analyzer = QuotePairAnalyzer()
    private val classifier = CjkFontRoleClassifier()

    @Test
    fun deprecatedClassifyPairsWithFontRoleClassifierDelegates() {
        testTrace.section("deprecatedClassifyPairsWithFontRoleClassifierDelegates")
        val text = "\u4ED6\u8BF4\u201C\u4F60\u597D\u201D"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)
        assertEquals(FontRole.CjkPunctuation, roles[2])
    }

    @Test
    fun deprecatedClassifyQuoteRolesWithFontRoleClassifierDelegates() {
        testTrace.section("deprecatedClassifyQuoteRolesWithFontRoleClassifierDelegates")
        val text = "\u4ED6\u8BF4\u201C\u4F60\u597D\u201D"
        val pairs = analyzer.analyze(text)
        val decisions = analyzer.classifyQuoteRoles(text, pairs, classifier)
        assertTrue(decisions.isNotEmpty())
    }

    @Test
    fun codePointBeforeSurrogatePairReturnsSupplementary() {
        testTrace.section("codePointBeforeSurrogatePairReturnsSupplementary")
        // Supplementary character U+1F600 followed by U+2019
        val text = "\uD83D\uDE00\u2019"
        val result = analyzer.analyze(text)
        // U+2019 is not a closing quote for a single-quote stack when preceded by emoji
        // because isNonCjkInWordApostrophe returns false (emoji is not a word char)
        assertEquals(0, result.size)
    }

    @Test
    fun codePointAtOrNullSurrogatePairReturnsSupplementary() {
        testTrace.section("codePointAtOrNullSurrogatePairReturnsSupplementary")
        // This exercises codePointAtOrNull with a valid surrogate pair.
        // The emoji followed by a right quote triggers codePointAtOrNull
        // in isNonCjkInWordApostrophe (checking char after the quote).
        val text = "\u2019\uD83D\uDE00"
        val decisions = analyzer.classifyQuoteRoles(text, emptyList())
        assertTrue(decisions.isNotEmpty())
    }

    @Test
    fun codePointAtOrNullNonSurrogateReturnsSelf() {
        testTrace.section("codePointAtOrNullNonSurrogateReturnsSelf")
        val decisions = analyzer.classifyQuoteRoles("abc", emptyList())
        assertTrue(decisions.isEmpty())
    }

    @Test
    fun codePointBeforeReturnsNullAtStart() {
        testTrace.section("codePointBeforeReturnsNullAtStart")
        val decisions = analyzer.classifyQuoteRoles("\u2019", emptyList())
        assertTrue(decisions.isNotEmpty())
    }

    @Test
    fun codePointBeforeReturnsSupplementaryForSurrogatePair() {
        testTrace.section("codePointBeforeReturnsSupplementaryForSurrogatePair")
        val text = "\uD83D\uDE00\u2019"
        val decisions = analyzer.classifyQuoteRoles(text, emptyList())
        assertTrue(decisions.isNotEmpty())
    }

    @Test
    fun quotePairAwareFontRoleClassifierUsesOverride() {
        testTrace.section("quotePairAwareFontRoleClassifierUsesOverride")
        val roles = mapOf(2 to FontRole.LatinText)
        val overrideClassifier = QuotePairAwareFontRoleClassifier(classifier, roles)
        val result = overrideClassifier.classify("ab", TextRange(0, 2), FontRoleContext())
        assertEquals(FontRole.LatinText, result)
    }

    @Test
    fun quotePairAwareFontRoleClassifierDelegatesWhenNoOverride() {
        testTrace.section("quotePairAwareFontRoleClassifierDelegatesWhenNoOverride")
        val overrideClassifier = QuotePairAwareFontRoleClassifier(classifier, emptyMap())
        val result = overrideClassifier.classify("ab", TextRange(0, 2), FontRoleContext())
        assertEquals(classifier.classify("ab", TextRange(0, 2), FontRoleContext()), result)
    }

    @Test
    fun doubleQuoteCloseWithEmptyStackIgnores() {
        testTrace.section("doubleQuoteCloseWithEmptyStackIgnores")
        val text = "\u201D"
        val pairs = analyzer.analyze(text)
        assertEquals(0, pairs.size)
    }

    @Test
    fun singleQuoteCloseWithEmptyStackIgnores() {
        testTrace.section("singleQuoteCloseWithEmptyStackIgnores")
        val text = "\u2019"
        val pairs = analyzer.analyze(text)
        assertEquals(0, pairs.size)
    }

    @Test
    fun inWordApostropheAfterSupplementaryDoesNotClose() {
        testTrace.section("inWordApostropheAfterSupplementaryDoesNotClose")
        // Supplementary char followed by ', then word char
        // This exercises codePointBefore surrogate path in isNonCjkInWordApostrophe
        val text = "\uD83D\uDE00\u2019x"
        val decisions = analyzer.classifyQuoteRoles(text, emptyList())
        assertTrue(decisions.isNotEmpty())
    }

    @Test
    fun codePointAtOrNullWithSupplementaryAfterQuote() {
        testTrace.section("codePointAtOrNullWithSupplementaryAfterQuote")
        // ' followed by high surrogate then low surrogate
        val text = "a\u2019\uD83D\uDE00"
        val decisions = analyzer.classifyQuoteRoles(text, emptyList())
        assertTrue(decisions.isNotEmpty())
    }

    @Test
    fun codePointBeforeWithHighSurrogateBeforeQuote() {
        testTrace.section("codePointBeforeWithHighSurrogateBeforeQuote")
        // High surrogate + low surrogate + '
        val text = "\uD83D\uDE00\u2019"
        val decisions = analyzer.classifyQuoteRoles(text, emptyList())
        assertTrue(decisions.isNotEmpty())
    }

    @Test
    fun codePointBeforeWithLowSurrogateAtStart() {
        testTrace.section("codePointBeforeWithLowSurrogateAtStart")
        // Lone low surrogate before quote at index 1 → index < 2 branch
        val text = surrogateText(0xDC00, 0x2019)
        assertFailsWith<TiqianIllegalArgumentException> {
            analyzer.classifyQuoteRoles(text, emptyList())
        }
    }

    @Test
    fun codePointBeforeWithLowSurrogateAfterNonHighSurrogate() {
        testTrace.section("codePointBeforeWithLowSurrogateAfterNonHighSurrogate")
        // 'a' at 0, low surrogate at 1, quote at 2 → high not a high surrogate
        val text = surrogateText('a'.code, 0xDC00, 0x2019)
        assertFailsWith<TiqianIllegalArgumentException> {
            analyzer.classifyQuoteRoles(text, emptyList())
        }
    }

    @Test
    fun codePointAtOrNullWithIndexOutOfRange() {
        testTrace.section("codePointAtOrNullWithIndexOutOfRange")
        // Quote at last position → codePointAtOrNull(index+1) out of bounds
        val text = "a\u2019"
        val decisions = analyzer.classifyQuoteRoles(text, emptyList())
        assertTrue(decisions.isNotEmpty())
    }

    @Test
    fun codePointAtOrNullWithHighSurrogateAtEnd() {
        testTrace.section("codePointAtOrNullWithHighSurrogateAtEnd")
        val text = surrogateText(0x2019, 0xD800)
        assertFailsWith<IllegalArgumentException> {
            analyzer.classifyQuoteRoles(text, emptyList())
        }
    }

    @Test
    fun codePointAtOrNullWithHighSurrogateFollowedByNonLowSurrogate() {
        testTrace.section("codePointAtOrNullWithHighSurrogateFollowedByNonLowSurrogate")
        val text = surrogateText(0x2019, 0xD800, 'a'.code)
        assertFailsWith<IllegalArgumentException> {
            analyzer.classifyQuoteRoles(text, emptyList())
        }
    }

    @Test
    fun analyzeWithDoubleQuoteOpen() {
        testTrace.section("analyzeWithDoubleQuoteOpen")
        val text = "\u201Cabc"
        val pairs = analyzer.analyze(text)
        assertEquals(0, pairs.size)
    }

    @Test
    fun codePointAtOrNullHighSurrogateNotInRangeReturnsHigh() {
        testTrace.section("codePointAtOrNullHighSurrogateNotInRangeReturnsHigh")
        val text = "x\u2019a"
        val decisions = analyzer.classifyQuoteRoles(text, emptyList())
        assertTrue(decisions.isNotEmpty())
    }

    @Test
    fun codePointBeforeLowInRangeIndexGe2HighNotInRange() {
        testTrace.section("codePointBeforeLowInRangeIndexGe2HighNotInRange")
        val text = surrogateText('a'.code, 0xDC00, 0x2019)
        assertFailsWith<TiqianIllegalArgumentException> {
            analyzer.classifyQuoteRoles(text, emptyList())
        }
    }

    @Test
    fun singleQuotePairMatch() {
        testTrace.section("singleQuotePairMatch")
        val text = "\u2018\u2019"
        val pairs = analyzer.analyze(text)
        assertEquals(1, pairs.size)
        assertEquals(QuoteType.Single, pairs[0].quoteType)
    }

    @Test
    fun codePointAtOrNullLoneHighSurrogateAfterQuote() {
        testTrace.section("codePointAtOrNullLoneHighSurrogateAfterQuote")
        val text = surrogateText('a'.code, 0x2019, 0xD800, 'a'.code)
        assertFailsWith<TiqianIllegalArgumentException> {
            analyzer.classifyQuoteRoles(text, emptyList())
        }
    }

    @Test
    fun codePointAtOrNullHighSurrogateAtStringEnd() {
        testTrace.section("codePointAtOrNullHighSurrogateAtStringEnd")
        val text = surrogateText('a'.code, 0x2019, 0xD800)
        assertFailsWith<TiqianIllegalArgumentException> {
            analyzer.classifyQuoteRoles(text, emptyList())
        }
    }

    @Test
    fun analyzeWithAllQuoteTypes() {
        testTrace.section("analyzeWithAllQuoteTypes")
        val text = "\u201C\u2018abc\u2019\u201D"
        val pairs = analyzer.analyze(text)
        assertEquals(2, pairs.size)
    }

    @Test
    fun codePointBeforeNonSurrogateBmpChar() {
        testTrace.section("codePointBeforeNonSurrogateBmpChar")
        val text = "\u0041\u2019"
        val decisions = analyzer.classifyQuoteRoles(text, emptyList())
        assertTrue(decisions.isNotEmpty())
    }

    @AfterTest
    fun flushTestTrace() {
        testTrace.flush()
    }
}