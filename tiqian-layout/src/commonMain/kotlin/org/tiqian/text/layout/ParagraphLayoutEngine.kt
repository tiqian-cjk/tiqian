package org.tiqian.text.layout

import org.tiqian.text.clreq.ClreqPunctuationGlyphSubstitutor
import org.tiqian.text.core.Cluster
import org.tiqian.text.core.Glyph
import org.tiqian.text.core.GlyphRun
import org.tiqian.text.core.LayoutDebugInfo
import org.tiqian.text.core.LayoutInput
import org.tiqian.text.core.LayoutResult
import org.tiqian.text.core.LineBox
import org.tiqian.text.core.LineDebugInfo
import org.tiqian.text.core.Size
import org.tiqian.text.core.TextRange
import org.tiqian.text.font.CjkFontRoleClassifier
import org.tiqian.text.font.FallbackResolver
import org.tiqian.text.font.FontRequest
import org.tiqian.text.font.FontRole
import org.tiqian.text.font.FontRoleClassifier
import org.tiqian.text.font.PreferCjkForAmbiguousPunctuationResolver

interface ParagraphLayoutEngine {
    fun layout(input: LayoutInput): LayoutResult
}

class ExplainableStubParagraphLayoutEngine(
    private val fontRoleClassifier: FontRoleClassifier = CjkFontRoleClassifier(),
    private val fallbackResolver: FallbackResolver = PreferCjkForAmbiguousPunctuationResolver(),
    private val punctuationGlyphSubstitutor: ClreqPunctuationGlyphSubstitutor = ClreqPunctuationGlyphSubstitutor(),
) : ParagraphLayoutEngine {
    override fun layout(input: LayoutInput): LayoutResult {
        val text = input.content.text
        val fontSize = input.textStyle.fontSize
        val advance = fontSize

        val clusterRanges = clusterRanges(text)
        val fontDecisions = clusterRanges.map { range ->
            val role = fontRoleClassifier.classify(text, range)
            fallbackResolver.resolve(
                text = text,
                range = range,
                request = FontRequest(
                    preferredFamilies = input.textStyle.fontFamilies,
                    locale = input.textStyle.locale,
                    role = role,
                ),
            )
        }

        val clusters = fontDecisions.map { decision ->
            val sourceText = text.substring(decision.range.start, decision.range.end)
            val substitution = punctuationGlyphSubstitutor.substitute(sourceText)
            Cluster(
                range = decision.range,
                text = sourceText,
                displayText = substitution.displayText,
                fontKey = decision.candidate.key,
                advance = advance * sourceText.layoutAdvanceEmCount(substitution.displayText),
            )
        }

        val glyphRuns = clusters.groupAdjacentBy { it.fontKey }.map { runClusters ->
            GlyphRun(
                range = TextRange(runClusters.first().range.start, runClusters.last().range.end),
                fontKey = runClusters.first().fontKey,
                glyphs = runClusters.mapIndexed { glyphId, cluster ->
                    Glyph(
                        id = glyphId.toUInt(),
                        clusterRange = cluster.range,
                        advance = cluster.advance,
                    )
                },
                advance = runClusters.sumOf { it.advance.toDouble() }.toFloat(),
            )
        }

        val totalAdvance = glyphRuns.sumOf { it.advance.toDouble() }.toFloat()
        val naturalWidth = totalAdvance.coerceAtMost(input.constraints.maxWidth)
        val lineHeight = input.paragraphStyle.lineHeight ?: fontSize * 1.4f
        val lines = if (text.isEmpty()) {
            emptyList()
        } else {
            listOf(
                LineBox(
                    range = TextRange(0, text.length),
                    baseline = fontSize,
                    top = 0f,
                    bottom = lineHeight,
                    naturalWidth = naturalWidth,
                    adjustedWidth = naturalWidth,
                    visualWidth = naturalWidth,
                    debug = LineDebugInfo(
                        repair = null,
                        notes = listOf("ExplainableStubParagraphLayoutEngine emits one unoptimized line."),
                    ),
                )
            )
        }

        return LayoutResult(
            input = input,
            size = Size(
                width = naturalWidth,
                height = lineHeight,
            ),
            clusters = clusters,
            glyphRuns = glyphRuns,
            lines = lines,
            debug = LayoutDebugInfo(
                fontDecisions = fontDecisions.map { decision ->
                    val clusterText = text.substring(decision.range.start, decision.range.end)
                    val substitution = punctuationGlyphSubstitutor.substitute(clusterText)
                    "font:${decision.range.start}-${decision.range.end}:$clusterText->${substitution.displayText}:${decision.role}:${decision.candidate.key}:${decision.reason}:${substitution.reason}"
                },
                metricDecisions = listOf("metrics:raw-placeholder"),
                lineDecisions = listOf("line:single-placeholder"),
            ),
        )
    }

    private fun clusterRanges(text: String): List<TextRange> {
        val ranges = mutableListOf<TextRange>()
        var index = 0
        while (index < text.length) {
            val codePoint = text.codePointAtCompat(index)
            val charCount = codePoint.charCount()
            val start = index
            val firstRange = TextRange(start, start + charCount)
            val role = fontRoleClassifier.classify(text, firstRange)

            index += charCount
            if (role == FontRole.LatinText) {
                while (index < text.length) {
                    val nextCodePoint = text.codePointAtCompat(index)
                    val nextCharCount = nextCodePoint.charCount()
                    val nextRange = TextRange(index, index + nextCharCount)
                    if (fontRoleClassifier.classify(text, nextRange) != FontRole.LatinText) break
                    index += nextCharCount
                }
            } else if (role == FontRole.CjkPunctuation && codePoint.isRepeatableCjkPunctuation()) {
                while (index < text.length) {
                    val nextCodePoint = text.codePointAtCompat(index)
                    if (nextCodePoint != codePoint) break
                    index += nextCodePoint.charCount()
                }
            }

            ranges.add(TextRange(start, index))
        }
        return ranges
    }

    private fun String.codePointCount(): Int =
        codePointCountCompat(0, length)

    private fun String.layoutAdvanceEmCount(displayText: String): Int =
        when {
            this == "——" && displayText == "⸺" -> 2
            else -> codePointCount()
        }

    private fun Int.isRepeatableCjkPunctuation(): Boolean =
        this == 0x2014 || this == 0x2026 || this == 0x22EF

    private fun String.codePointAtCompat(index: Int): Int {
        val high = this[index].code
        if (high !in 0xD800..0xDBFF || index + 1 >= length) return high

        val low = this[index + 1].code
        if (low !in 0xDC00..0xDFFF) return high

        return 0x10000 + ((high - 0xD800) shl 10) + (low - 0xDC00)
    }

    private fun String.codePointCountCompat(start: Int, end: Int): Int {
        var count = 0
        var index = start
        while (index < end) {
            index += codePointAtCompat(index).charCount()
            count += 1
        }
        return count
    }

    private fun Int.charCount(): Int =
        if (this > 0xFFFF) 2 else 1

    private inline fun <T, K> List<T>.groupAdjacentBy(keySelector: (T) -> K): List<List<T>> {
        if (isEmpty()) return emptyList()

        val groups = mutableListOf<MutableList<T>>()
        var currentKey = keySelector(first())
        var currentGroup = mutableListOf(first())

        for (item in drop(1)) {
            val key = keySelector(item)
            if (key == currentKey) {
                currentGroup.add(item)
            } else {
                groups.add(currentGroup)
                currentKey = key
                currentGroup = mutableListOf(item)
            }
        }

        groups.add(currentGroup)
        return groups
    }
}
