package org.tiqian.layout

import org.tiqian.core.TextRange
import org.tiqian.font.FontRole
import org.tiqian.font.FontRoleClassifier
import org.tiqian.font.FontRoleContext

data class QuotePair(
    val openIndex: Int,
    val closeIndex: Int,
    val quoteType: QuoteType,
)

enum class QuoteType { Double, Single }

data class QuoteRoleDecision(
    val index: Int,
    val role: FontRole,
    val source: String,
    val reason: String,
)

/**
 * Analyzes curly quote pairs in text and classifies each pair as CJK or Latin
 * from paragraph context.
 *
 * Curly quotes (U+201C/201D, U+2018/2019) share code points between CJK and
 * Western typography. Per-character heuristics cannot reliably classify them
 * because the closing quote's meaningful context is on the opposite side from
 * its content. Pair-based analysis solves this by classifying both quotes in a
 * pair together. Real prose uses the opening quote's outer (left) context, but
 * structural numbered prefixes such as `1.` are ignored so the quoted content
 * can choose the face. If there is no meaningful outer context, the quoted
 * content is used as a fallback.
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
        context: FontRoleContext = FontRoleContext(),
    ): Map<Int, FontRole> =
        classifyQuoteRoles(text, pairs, fontRoleClassifier, context).associate { it.index to it.role }

    fun classifyQuoteRoles(
        text: String,
        pairs: List<QuotePair>,
        fontRoleClassifier: FontRoleClassifier,
        context: FontRoleContext = FontRoleContext(),
    ): List<QuoteRoleDecision> {
        val result = mutableListOf<QuoteRoleDecision>()
        for (pair in pairs) {
            val decision = resolvePairContext(text, pair, fontRoleClassifier, context)
            result.add(
                QuoteRoleDecision(
                    index = pair.openIndex,
                    role = decision.role,
                    source = decision.source,
                    reason = decision.reason,
                ),
            )
            result.add(
                QuoteRoleDecision(
                    index = pair.closeIndex,
                    role = decision.role,
                    source = decision.source,
                    reason = decision.reason,
                ),
            )
        }
        return result
    }

    /**
     * Resolves whether the quote pair belongs to a CJK or Latin context.
     *
     * The opening quote's left context wins for prose. At text start or after a
     * structural numbered prefix, the quoted content becomes the fallback
     * context, so English-leading text keeps Latin quotes while Chinese-leading
     * text keeps CJK punctuation behavior.
     */
    private fun resolvePairContext(
        text: String,
        pair: QuotePair,
        classifier: FontRoleClassifier,
        context: FontRoleContext,
    ): ResolvedQuotePairContext {
        val leftRole = scanLeftForMeaningfulRole(
            text = text,
            startIndex = pair.openIndex - 1,
            classifier = classifier,
            context = context,
        )
        val quotedRole = scanRightForMeaningfulRole(
            text = text,
            startIndex = pair.openIndex + 1,
            endIndex = pair.closeIndex,
            classifier = classifier,
            context = context,
        )

        // `NumberedCjkQuotePrefix`: a paragraph/list ordinal such as `1.` is
        // structure, not Latin prose. Let the quoted text decide the quote face
        // so `1.“中文”` keeps CJK quote geometry while `1.“Hello”` remains Latin.
        if (
            leftRole == FontRole.LatinText &&
            quotedRole == FontRole.CjkPunctuation &&
            hasNumberedQuotePrefix(text, pair.openIndex)
        ) {
            return ResolvedQuotePairContext(
                role = FontRole.CjkPunctuation,
                source = "NumberedCjkQuotePrefix",
                reason = "numbered-prefix-uses-quoted-cjk-context",
            )
        }

        if (leftRole != null) {
            return ResolvedQuotePairContext(
                role = leftRole,
                source = "QuotePairOuterContext",
                reason = "quote-pair-opening-left-context",
            )
        }

        if (quotedRole != null) {
            return ResolvedQuotePairContext(
                role = quotedRole,
                source = "QuotePairQuotedContentContext",
                reason = "quote-pair-quoted-content-context",
            )
        }

        val followingRole = scanRightForMeaningfulRole(
            text = text,
            startIndex = pair.closeIndex + 1,
            endIndex = text.length,
            classifier = classifier,
            context = context,
        )
        if (followingRole != null) {
            return ResolvedQuotePairContext(
                role = followingRole,
                source = "QuotePairFollowingContext",
                reason = "quote-pair-following-context",
            )
        }

        return ResolvedQuotePairContext(
            role = FontRole.CjkPunctuation,
            source = "QuotePairDefaultCjkContext",
            reason = "quote-pair-default-cjk-context",
        )
    }

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
        context: FontRoleContext,
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

            val role = classifier.classify(text, TextRange(startIndex, i + 1), context)
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
        context: FontRoleContext,
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

            val role = classifier.classify(text, TextRange(i, i + charCount), context)
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

    private fun hasNumberedQuotePrefix(text: String, quoteIndex: Int): Boolean {
        var i = quoteIndex - 1
        while (i >= 0 && text[i].isAsciiSpaceOrTab()) i--

        if (i >= 0 && text[i].isNumberedPrefixSuffix()) i--

        var sawDigit = false
        while (i >= 0 && text[i] in '0'..'9') {
            sawDigit = true
            i--
        }
        if (!sawDigit) return false

        if (i >= 0 && text[i].isNumberedPrefixOpeningBracket()) i--
        while (i >= 0 && text[i].isAsciiSpaceOrTab()) i--
        return i < 0 || text[i] == '\n' || text[i] == '\r'
    }

    private fun Char.isAsciiSpaceOrTab(): Boolean =
        this == ' ' || this == '\t'

    private fun Char.isNumberedPrefixSuffix(): Boolean =
        this == '.' ||
            this == ')' ||
            this == ']' ||
            this == '\u3001' ||
            this == '\uFF0E' ||
            this == '\uFF09'

    private fun Char.isNumberedPrefixOpeningBracket(): Boolean =
        this == '(' || this == '[' || this == '\uFF08'

    private data class ResolvedQuotePairContext(
        val role: FontRole,
        val source: String,
        val reason: String,
    )
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
    override fun classify(text: String, range: TextRange, context: FontRoleContext): FontRole =
        quoteRoles[range.start] ?: delegate.classify(text, range, context)
}
