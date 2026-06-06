package org.tiqian.text.layout

import org.tiqian.text.core.TextRange
import org.tiqian.text.font.CjkFontRoleClassifier
import org.tiqian.text.font.FontRole
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class QuotePairAnalyzerTest {
    private val analyzer = QuotePairAnalyzer()
    private val classifier = CjkFontRoleClassifier()

    // -- Pair matching --

    @Test
    fun matchesDoubleQuotePair() {
        // 他说"你好"
        val pairs = analyzer.analyze("\u4ED6\u8BF4\u201C\u4F60\u597D\u201D")
        assertEquals(1, pairs.size)
        assertEquals(QuotePair(2, 5, QuoteType.Double), pairs[0])
    }

    @Test
    fun matchesSingleQuotePair() {
        // 他说'你好'
        val pairs = analyzer.analyze("\u4ED6\u8BF4\u2018\u4F60\u597D\u2019")
        assertEquals(1, pairs.size)
        assertEquals(QuotePair(2, 5, QuoteType.Single), pairs[0])
    }

    @Test
    fun matchesNestedQuotePairs() {
        // 他说："她说'你好'。"
        val text = "\u4ED6\u8BF4\uFF1A\u201C\u5979\u8BF4\u2018\u4F60\u597D\u2019\u3002\u201D"
        val pairs = analyzer.analyze(text)
        assertEquals(2, pairs.size)
        // Inner pair matched first (stack order)
        assertTrue(pairs.any { it == QuotePair(6, 9, QuoteType.Single) })
        assertTrue(pairs.any { it == QuotePair(3, 11, QuoteType.Double) })
    }

    @Test
    fun unmatchedQuotesProduceNoPairs() {
        // it's — unmatched right single quote (apostrophe)
        val pairs = analyzer.analyze("it\u2019s")
        assertEquals(0, pairs.size)
    }

    @Test
    fun mismatchedNestingLeavesQuotesUnmatched() {
        // "hello' — double open, single close, no match
        val pairs = analyzer.analyze("\u201Chello\u2019")
        assertEquals(0, pairs.size)
    }

    // -- Pair classification --

    @Test
    fun classifiesPairAsCjkWhenOuterContextIsCjk() {
        // 他说"你好"
        val text = "\u4ED6\u8BF4\u201C\u4F60\u597D\u201D"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)
        assertEquals(FontRole.CjkPunctuation, roles[2]) // opening "
        assertEquals(FontRole.CjkPunctuation, roles[5]) // closing "
    }

    @Test
    fun classifiesPairAsLatinWhenOuterContextIsLatin() {
        // he said "hello" world
        val text = "he said \u201Chello\u201D world"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)
        assertEquals(FontRole.LatinText, roles[8])  // opening "
        assertEquals(FontRole.LatinText, roles[14]) // closing "
    }

    @Test
    fun classifiesBothQuotesAsCjkForCjkQuotedLatinContent() {
        // 他说"hello" — opening quote's outer context is CJK
        val text = "\u4ED6\u8BF4\u201Chello\u201D"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)
        assertEquals(FontRole.CjkPunctuation, roles[2]) // opening "
        assertEquals(FontRole.CjkPunctuation, roles[8]) // closing " — same as opening
    }

    @Test
    fun classifiesPairAsCjkAtTextBoundary() {
        // "你好" — no outer context, defaults to CJK
        val text = "\u201C\u4F60\u597D\u201D"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)
        assertEquals(FontRole.CjkPunctuation, roles[0]) // opening "
        assertEquals(FontRole.CjkPunctuation, roles[3]) // closing "
    }

    @Test
    fun classifiesTextStartLatinPairFromQuotedContent() {
        val text = "\u201CHello\u201D world"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)
        assertEquals(FontRole.LatinText, roles[0])
        assertEquals(FontRole.LatinText, roles[6])
    }

    @Test
    fun classifiesNestedPairsByOutermostContext() {
        // 他说："她说'你好'。"
        val text = "\u4ED6\u8BF4\uFF1A\u201C\u5979\u8BF4\u2018\u4F60\u597D\u2019\u3002\u201D"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)
        // Outer double quotes — left of " is ： (CJK punctuation)
        assertEquals(FontRole.CjkPunctuation, roles[3])
        assertEquals(FontRole.CjkPunctuation, roles[11])
        // Inner single quotes — skips " and ：, sees 说 (CJK text)
        assertEquals(FontRole.CjkPunctuation, roles[6])
        assertEquals(FontRole.CjkPunctuation, roles[9])
    }

    @Test
    fun classifiesLatinNestedQuotesByOuterContext() {
        // She said "he said 'hello' today" end
        val text = "She said \u201Che said \u2018hello\u2019 today\u201D end"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)
        // All quotes should be Latin
        for ((_, role) in roles) {
            assertEquals(FontRole.LatinText, role)
        }
    }

    @Test
    fun skipsAsciiPunctuationWhenResolvingContext() {
        // English: "hello" — colon and space before quote
        val text = "English: \u201Chello\u201D"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)
        // : is Unknown, space is Unknown, but 'h' in "English" is Latin
        assertEquals(FontRole.LatinText, roles[9])  // opening "
        assertEquals(FontRole.LatinText, roles[15]) // closing "
    }

    @Test
    fun skipsNeutralDashWhenResolvingContext() {
        val text = "English \u2014 \u201Chello\u201D"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)
        assertEquals(FontRole.LatinText, roles[10])
        assertEquals(FontRole.LatinText, roles[16])
    }

    @Test
    fun endOfTextQuotePairClassifiedByOuterContext() {
        // he said "hello"
        val text = "he said \u201Chello\u201D"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)
        assertEquals(FontRole.LatinText, roles[8])  // opening "
        assertEquals(FontRole.LatinText, roles[14]) // closing " at end of text
    }
}
