package org.tiqian.text.layout

import org.tiqian.text.core.TextRange
import org.tiqian.text.font.FontRole
import org.tiqian.text.font.FontRoleClassifier
import org.tiqian.text.font.FontRoleContext

data class BracketPair(
    val openIndex: Int,
    val closeIndex: Int,
    val kind: BracketKind,
)

enum class BracketKind { Parenthesis, Square, Curly }

/**
 * Analyzes ASCII bracket pairs `(...)`, `[...]`, `{...}` and classifies each
 * pair as CJK or Latin based on the same outer-context rule [QuotePairAnalyzer]
 * uses.
 *
 * Without this, ASCII brackets in mixed text like `中文(English)中文` would
 * fall through `CjkFontRoleClassifier` to [FontRole.Unknown] (their code
 * points are not in the CJK punctuation set, not Latin letters, and not the
 * `isLatinTechnicalPunctuation` allow-list), landing on the symbol fallback
 * font instead of inheriting the surrounding font role.
 *
 * Fullwidth CJK brackets (（）「」『』《》〈〉【】) are already classified as
 * `CjkPunctuation` by [CjkFontRoleClassifier]; this analyzer only handles the
 * ASCII forms whose role is genuinely context-dependent.
 *
 * Differs from [QuotePairAnalyzer] in two places:
 *  - Open and close glyphs are distinct, so pair matching is unambiguous.
 *  - The text-boundary default is [FontRole.LatinText] because ASCII brackets
 *    are Latin code points; quotes default to CJK because curly quotes are
 *    primarily used as Chinese quotes.
 */
class BracketPairAnalyzer {

    fun analyze(text: String): List<BracketPair> {
        val stacks = HashMap<BracketKind, ArrayDeque<Int>>().apply {
            BracketKind.entries.forEach { put(it, ArrayDeque()) }
        }
        val pairs = mutableListOf<BracketPair>()

        for (i in text.indices) {
            val ch = text[i]
            val openKind = ch.asOpenKind()
            if (openKind != null) {
                stacks.getValue(openKind).addLast(i)
                continue
            }
            val closeKind = ch.asCloseKind()
            if (closeKind != null) {
                val stack = stacks.getValue(closeKind)
                if (stack.isNotEmpty()) {
                    pairs += BracketPair(stack.removeLast(), i, closeKind)
                }
            }
        }

        return pairs
    }

    fun classifyPairs(
        text: String,
        pairs: List<BracketPair>,
        fontRoleClassifier: FontRoleClassifier,
        context: FontRoleContext = FontRoleContext(),
    ): Map<Int, FontRole> {
        val result = mutableMapOf<Int, FontRole>()
        for (pair in pairs) {
            val role = resolvePairContext(text, pair, fontRoleClassifier, context)
            result[pair.openIndex] = role
            result[pair.closeIndex] = role
        }
        return result
    }

    /**
     * Mirrors [QuotePairAnalyzer]'s outer-context rule. Open's left wins; if
     * nothing meaningful is left, inspect inner content; if still nothing,
     * look right of the closing bracket; finally default to LatinText (ASCII
     * brackets are Latin code points by origin).
     */
    private fun resolvePairContext(
        text: String,
        pair: BracketPair,
        classifier: FontRoleClassifier,
        context: FontRoleContext,
    ): FontRole =
        scanLeftForMeaningfulRole(
            text = text,
            startIndex = pair.openIndex - 1,
            classifier = classifier,
            context = context,
        )
            ?: scanRightForMeaningfulRole(
                text = text,
                startIndex = pair.openIndex + 1,
                endIndex = pair.closeIndex,
                classifier = classifier,
                context = context,
            )
            ?: scanRightForMeaningfulRole(
                text = text,
                startIndex = pair.closeIndex + 1,
                endIndex = text.length,
                classifier = classifier,
                context = context,
            )
            ?: FontRole.LatinText

    private fun scanLeftForMeaningfulRole(
        text: String,
        startIndex: Int,
        classifier: FontRoleClassifier,
        context: FontRoleContext,
    ): FontRole? {
        var i = startIndex
        while (i >= 0) {
            val c = text[i].code

            if (c.isNeutralBracketContextCodePoint()) {
                i--
                continue
            }

            val s = if (
                c in 0xDC00..0xDFFF &&
                i > 0 &&
                text[i - 1].code in 0xD800..0xDBFF
            ) {
                i - 1
            } else {
                i
            }

            val role = classifier.classify(text, TextRange(s, i + 1), context)
            when (role) {
                FontRole.LatinText -> return FontRole.LatinText
                FontRole.CjkText, FontRole.CjkPunctuation -> return FontRole.CjkPunctuation
                else -> { /* keep scanning */ }
            }
            i = s - 1
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

            if (c.isNeutralBracketContextCodePoint()) {
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

    private fun Char.asOpenKind(): BracketKind? =
        when (this) {
            '(' -> BracketKind.Parenthesis
            '[' -> BracketKind.Square
            '{' -> BracketKind.Curly
            else -> null
        }

    private fun Char.asCloseKind(): BracketKind? =
        when (this) {
            ')' -> BracketKind.Parenthesis
            ']' -> BracketKind.Square
            '}' -> BracketKind.Curly
            else -> null
        }

    private fun Int.isNeutralBracketContextCodePoint(): Boolean =
        this == 0x0009 ||
            this == 0x000A ||
            this == 0x000D ||
            this == 0x0020 ||
            this == 0x002C ||
            this == 0x002D ||
            this == 0x002E ||
            this == 0x002F ||
            this == 0x003A ||
            this == 0x003B ||
            this == 0x005F ||
            this == 0x2013 ||
            this == 0x2014
}
