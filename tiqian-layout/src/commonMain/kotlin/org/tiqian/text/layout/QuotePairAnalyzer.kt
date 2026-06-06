package org.tiqian.text.layout

import org.tiqian.text.core.TextRange
import org.tiqian.text.font.FontRole
import org.tiqian.text.font.FontRoleClassifier

data class QuotePair(
    val openIndex: Int,
    val closeIndex: Int,
    val quoteType: QuoteType,
)

enum class QuoteType { Double, Single }

/**
 * Analyzes curly quote pairs in text and classifies each pair as CJK or Latin
 * based on the outer context of the opening quote.
 *
 * Curly quotes (U+201C/201D, U+2018/2019) share code points between CJK and
 * Western typography. Per-character heuristics cannot reliably classify them
 * because the closing quote's meaningful context is on the opposite side from
 * its content. Pair-based analysis solves this by classifying both quotes in a
 * pair together based on the opening quote's outer (left) context. If there is
 * no meaningful outer context, the quoted content is used as a fallback.
 *
 * Unmatched quotes (e.g. apostrophes in "it's") are not included in the result
 * and fall back to the delegate classifier's per-character heuristic.
 */
class QuotePairAnalyzer {

    fun analyze(text: String): List<QuotePair> {
        val stack = ArrayDeque<Pair<Int, QuoteType>>()
        val pairs = mutableListOf<QuotePair>()

        for (i in text.indices) {
            when (text[i].code) {
                0x201C -> stack.addLast(i to QuoteType.Double)
                0x2018 -> stack.addLast(i to QuoteType.Single)
                0x201D -> {
                    if (stack.isNotEmpty() && stack.last().second == QuoteType.Double) {
                        val match = stack.removeLast()
                        pairs.add(QuotePair(match.first, i, QuoteType.Double))
                    }
                }
                0x2019 -> {
                    if (stack.isNotEmpty() && stack.last().second == QuoteType.Single) {
                        val match = stack.removeLast()
                        pairs.add(QuotePair(match.first, i, QuoteType.Single))
                    }
                }
            }
        }

        return pairs
    }

    fun classifyPairs(
        text: String,
        pairs: List<QuotePair>,
        fontRoleClassifier: FontRoleClassifier,
    ): Map<Int, FontRole> {
        val result = mutableMapOf<Int, FontRole>()
        for (pair in pairs) {
            val role = resolvePairContext(text, pair, fontRoleClassifier)
            result[pair.openIndex] = role
            result[pair.closeIndex] = role
        }
        return result
    }

    /**
     * Resolves whether the quote pair belongs to a CJK or Latin context.
     *
     * The opening quote's left context wins. At text start, the quoted content
     * becomes the fallback context, so English-leading text keeps Latin quotes
     * while Chinese-leading text keeps CJK punctuation behavior.
     */
    private fun resolvePairContext(
        text: String,
        pair: QuotePair,
        classifier: FontRoleClassifier,
    ): FontRole =
        scanLeftForMeaningfulRole(
            text = text,
            startIndex = pair.openIndex - 1,
            classifier = classifier,
        )
            ?: scanRightForMeaningfulRole(
                text = text,
                startIndex = pair.openIndex + 1,
                endIndex = pair.closeIndex,
                classifier = classifier,
            )
            ?: scanRightForMeaningfulRole(
                text = text,
                startIndex = pair.closeIndex + 1,
                endIndex = text.length,
                classifier = classifier,
            )
            ?: FontRole.CjkPunctuation

    /**
     * Scans left for the first character that clearly belongs to a CJK or Latin
     * run. Neutral punctuation is skipped so separators such as dashes do not
     * override the real textual context.
     *
     * Returns null at text boundary or when no meaningful context is found.
     */
    private fun scanLeftForMeaningfulRole(
        text: String,
        startIndex: Int,
        classifier: FontRoleClassifier,
    ): FontRole? {
        var i = startIndex
        while (i >= 0) {
            val c = text[i].code

            if (c.isNeutralQuoteContextCodePoint()) {
                i--
                continue
            }

            // Handle surrogate pairs (scanning backwards from low surrogate)
            val startIndex = if (
                c in 0xDC00..0xDFFF &&
                i > 0 &&
                text[i - 1].code in 0xD800..0xDBFF
            ) {
                i - 1
            } else {
                i
            }

            val role = classifier.classify(text, TextRange(startIndex, i + 1))
            when (role) {
                FontRole.LatinText -> return FontRole.LatinText
                FontRole.CjkText, FontRole.CjkPunctuation -> return FontRole.CjkPunctuation
                else -> { /* skip Unknown, Symbol, Emoji, spaces, ASCII punctuation */ }
            }
            i = startIndex - 1
        }
        return null
    }

    private fun scanRightForMeaningfulRole(
        text: String,
        startIndex: Int,
        endIndex: Int,
        classifier: FontRoleClassifier,
    ): FontRole? {
        var i = startIndex
        while (i < endIndex) {
            val c = text[i].code

            if (c.isNeutralQuoteContextCodePoint()) {
                i++
                continue
            }

            val charCount = if (
                c in 0xD800..0xDBFF &&
                i + 1 < endIndex &&
                text[i + 1].code in 0xDC00..0xDFFF
            ) {
                2
            } else {
                1
            }

            val role = classifier.classify(text, TextRange(i, i + charCount))
            when (role) {
                FontRole.LatinText -> return FontRole.LatinText
                FontRole.CjkText, FontRole.CjkPunctuation -> return FontRole.CjkPunctuation
                else -> { /* keep scanning */ }
            }
            i += charCount
        }
        return null
    }

    private fun Int.isNeutralQuoteContextCodePoint(): Boolean =
        this == 0x0009 ||
            this == 0x000A ||
            this == 0x000D ||
            this == 0x0020 ||
            this == 0x002D ||
            this == 0x002E ||
            this == 0x002F ||
            this == 0x003A ||
            this == 0x005F ||
            this == 0x007E ||
            this == 0x2013 ||
            this == 0x2014 ||
            this == 0x2018 ||
            this == 0x2019 ||
            this == 0x201C ||
            this == 0x201D
}

/**
 * Wraps a delegate [FontRoleClassifier] and overrides classification for
 * quote characters that have been resolved by [QuotePairAnalyzer].
 *
 * Characters not in [quoteRoles] are classified by the delegate as usual,
 * preserving per-character heuristics for unmatched quotes.
 */
class QuotePairAwareFontRoleClassifier(
    private val delegate: FontRoleClassifier,
    private val quoteRoles: Map<Int, FontRole>,
) : FontRoleClassifier {
    override fun classify(text: String, range: TextRange): FontRole =
        quoteRoles[range.start] ?: delegate.classify(text, range)
}
