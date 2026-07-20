package org.tiqian.layout

import org.tiqian.core.TextRange
import org.tiqian.font.CjkFontRoleClassifier
import org.tiqian.font.FontRole
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
    fun contractionApostropheDoesNotCloseOuterSingleQuote() {
        val text = "\u2018that\u2019s\u2019"

        assertEquals(
            listOf(QuotePair(0, text.lastIndex, QuoteType.Single)),
            analyzer.analyze(text),
        )
    }

    @Test
    fun contractionInsideCjkSingleQuotesKeepsApostropheLatin() {
        val text = "\u4E2D\u2018that\u2019s\u2019\u4E2D"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)

        assertEquals(FontRole.CjkPunctuation, roles[1])
        assertEquals(FontRole.CjkPunctuation, roles[text.lastIndex - 1])
        assertEquals(FontRole.LatinText, roles[6])
        assertEquals(FontRole.LatinText, classifier.classify(text, TextRange(6, 7)))
    }

    @Test
    fun inWordApostropheMatrixDoesNotConsumeOuterQuotePairs() {
        for (word in listOf("that’s", "l’été", "rock’n’roll", "version2’s")) {
            assertTrue(analyzer.analyze(word).isEmpty(), word)
            val decisions = analyzer.classifyQuoteRoles(word, emptyList(), classifier)
            assertTrue(decisions.all { it.role == FontRole.LatinText }, "$word: $decisions")
            assertTrue(
                decisions.all { it.source == "LatinInWordApostropheExclusion" },
                "$word: $decisions",
            )

            val quoted = "‘$word’"
            val pair = analyzer.analyze(quoted)
            assertEquals(listOf(QuotePair(0, quoted.lastIndex, QuoteType.Single)), pair, quoted)
            val roles = analyzer.classifyPairs(quoted, pair, classifier)
            assertEquals("L".repeat(quoted.count { it.isCurlyQuote() }), roles.toRoleSignature(quoted), quoted)
        }
    }

    @Test
    fun unmatchedCurlyQuotesUseDirectionalContext() {
        val cases = listOf(
            QuoteRoleCase("leading elision at text start", "’90s", "L"),
            QuoteRoleCase("leading elision after CJK and Western space", "中文 ’90s", "L"),
            QuoteRoleCase("trailing possessive", "James’ book", "L"),
            QuoteRoleCase("truncated Latin opening quote", "“Hello", "L"),
            QuoteRoleCase("truncated Latin closing quote", "Hello”", "L"),
            QuoteRoleCase("unspaced CJK opening quote", "中文“Hello", "C"),
            QuoteRoleCase("unmatched CJK closing quote", "中文”", "C"),
            QuoteRoleCase("context-free quote", "”", "C"),
        )

        for (case in cases) assertRoleSignature(case)
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
    fun whitespaceDelimitedLatinQuotePairOverridesCjkOuterContext() {
        val text = "（如 ‘O’, ‘Q’）"
        val decisions = analyzer.classifyQuoteRoles(
            text,
            analyzer.analyze(text),
            classifier,
        )

        assertEquals(listOf(3, 5, 8, 10), decisions.map { it.index }.sorted())
        assertTrue(decisions.all { it.role == FontRole.LatinText }, decisions.toString())
        assertTrue(
            decisions.all { it.source == "WhitespaceDelimitedLatinQuotePair" },
            decisions.toString(),
        )
    }

    @Test
    fun unspacedCjkQuotationOfLatinTextRemainsCjk() {
        val text = "他说‘hello’"
        val roles = analyzer.classifyPairs(text, analyzer.analyze(text), classifier)

        assertEquals(FontRole.CjkPunctuation, roles[2])
        assertEquals(FontRole.CjkPunctuation, roles[text.lastIndex])
    }

    @Test
    fun spacedCjkQuotedContentRemainsCjk() {
        val text = "他说 ‘你好’"
        val roles = analyzer.classifyPairs(text, analyzer.analyze(text), classifier)

        assertEquals(FontRole.CjkPunctuation, roles[3])
        assertEquals(FontRole.CjkPunctuation, roles[text.lastIndex])
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
    fun numberedCjkQuotePrefixUsesQuotedContent() {
        val text = "1.\u201C\u4F60\u77E5\u9053\u674E\u767D\u662F\u600E\u4E48\u6B7B\u7684\u5417\uFF1F\u201D"
        val pairs = analyzer.analyze(text)
        val decisions = analyzer.classifyQuoteRoles(text, pairs, classifier)

        assertEquals(FontRole.CjkPunctuation, decisions.single { it.index == 2 }.role)
        assertEquals(FontRole.CjkPunctuation, decisions.single { it.index == text.lastIndex }.role)
        assertEquals("NumberedCjkQuotePrefix", decisions.single { it.index == 2 }.source)
    }

    @Test
    fun numberedLatinQuotePrefixStillUsesLatinContent() {
        val text = "1.\u201CHello\u201D"
        val pairs = analyzer.analyze(text)
        val roles = analyzer.classifyPairs(text, pairs, classifier)

        assertEquals(FontRole.LatinText, roles[2])
        assertEquals(FontRole.LatinText, roles[8])
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

    @Test
    fun representativeQuoteContextMatrixRemainsStable() {
        val cases = listOf(
            QuoteRoleCase("Latin content at text start", "“Hello”", "LL"),
            QuoteRoleCase("CJK content at text start", "“你好”", "CC"),
            QuoteRoleCase("CJK prose quoting Latin", "他说“hello”", "CC"),
            QuoteRoleCase("Latin prose quoting CJK", "He said “你好”", "LL"),
            QuoteRoleCase("spaced Western initials in CJK", "（如 ‘O’, ‘Q’）", "LLLL"),
            QuoteRoleCase("spaced CJK quotation", "他说 ‘你好’", "CC"),
            QuoteRoleCase("empty pair before Latin", "“”English", "LL"),
            QuoteRoleCase("empty pair before CJK", "“”中文", "CC"),
            QuoteRoleCase("context-free empty pair", "“”", "CC"),
            QuoteRoleCase("numbered CJK quotation", "1.“中文”", "CC"),
            QuoteRoleCase("numbered Latin quotation", "1.“Hello”", "LL"),
            QuoteRoleCase("mixed CJK outer Latin inner", "他说：“She said ‘hello’.”", "CLLC"),
            QuoteRoleCase("mixed Latin outer CJK inner", "English “他说‘你好’” end", "LCCL"),
            QuoteRoleCase("CJK outer with contraction", "中文‘don’t’", "CLC"),
            QuoteRoleCase("spaced Latin outer with contraction", "中文 ‘don’t’", "LLL"),
            QuoteRoleCase("pair across mandatory break", "他说：“第一行\n第二行。”", "CC"),
            QuoteRoleCase("tab-delimited Western quote", "（如\t‘O’）", "LL"),
        )

        for (case in cases) assertRoleSignature(case)
    }

    @Test
    fun roleDecisionSourcesStayExplainableAcrossFallbackPaths() {
        val cases = listOf(
            "“Hello”" to "QuotePairQuotedContentContext",
            "English—“Hello”" to "QuotePairOuterContext",
            "（如 ‘O’）" to "WhitespaceDelimitedLatinQuotePair",
            "1.“中文”" to "NumberedCjkQuotePrefix",
            "“”English" to "QuotePairFollowingContext",
            "“”" to "QuotePairDefaultCjkContext",
            "that’s" to "LatinInWordApostropheExclusion",
            "中文 ’90s" to "WhitespaceDelimitedUnmatchedLatinQuote",
            "James’" to "UnmatchedCurlyQuoteOuterContext",
            "’90s" to "UnmatchedCurlyQuoteFollowingContext",
            "”" to "UnmatchedCurlyQuoteDefaultCjkContext",
        )

        for ((text, expectedSource) in cases) {
            val decisions = analyzer.classifyQuoteRoles(text, analyzer.analyze(text), classifier)
            assertTrue(decisions.isNotEmpty(), text)
            assertTrue(decisions.all { it.source == expectedSource }, "$text: $decisions")
        }
    }

    private data class QuoteRoleCase(
        val label: String,
        val text: String,
        val expectedSignature: String,
    )

    private fun assertRoleSignature(case: QuoteRoleCase) {
        val roles = analyzer.classifyPairs(case.text, analyzer.analyze(case.text), classifier)
        assertEquals(case.expectedSignature, roles.toRoleSignature(case.text), case.label)
    }

    private fun Map<Int, FontRole>.toRoleSignature(text: String): String =
        text.indices
            .filter { text[it].isCurlyQuote() }
            .joinToString(separator = "") { index ->
                when (this[index]) {
                    FontRole.LatinText -> "L"
                    FontRole.CjkPunctuation -> "C"
                    else -> "?"
                }
            }

    private fun Char.isCurlyQuote(): Boolean =
        this == '\u2018' || this == '\u2019' || this == '\u201C' || this == '\u201D'
}
