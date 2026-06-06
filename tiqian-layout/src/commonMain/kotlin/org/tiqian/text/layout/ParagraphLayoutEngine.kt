package org.tiqian.text.layout

import org.tiqian.text.clreq.BuiltInClreqProfileResolver
import org.tiqian.text.clreq.ClreqPunctuationAdvancePolicy
import org.tiqian.text.clreq.ClreqPunctuationGlyphSubstitutor
import org.tiqian.text.clreq.ClreqProfileResolver
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
import org.tiqian.text.font.FontMetricsNormalizationInput
import org.tiqian.text.font.FontMetricsNormalizer
import org.tiqian.text.font.FontMetricsRequest
import org.tiqian.text.font.FontMetricsResolver
import org.tiqian.text.font.FontRequest
import org.tiqian.text.font.FontRole
import org.tiqian.text.font.FontRoleClassifier
import org.tiqian.text.font.LayoutFontMetrics
import org.tiqian.text.font.PreferCjkForAmbiguousPunctuationResolver
import org.tiqian.text.font.RawFontMetrics
import org.tiqian.text.font.ScriptAwareFontMetricsNormalizer
import org.tiqian.text.font.StubFontMetricsResolver

interface ParagraphLayoutEngine {
    fun layout(input: LayoutInput): LayoutResult
}

class ExplainableStubParagraphLayoutEngine(
    private val fontRoleClassifier: FontRoleClassifier = CjkFontRoleClassifier(),
    private val fallbackResolver: FallbackResolver = PreferCjkForAmbiguousPunctuationResolver(),
    private val clreqProfileResolver: ClreqProfileResolver = BuiltInClreqProfileResolver,
    private val fontMetricsResolver: FontMetricsResolver = StubFontMetricsResolver(),
    private val fontMetricsNormalizer: FontMetricsNormalizer = ScriptAwareFontMetricsNormalizer(),
    private val punctuationAtomBuilder: PunctuationAtomBuilder = PunctuationAtomBuilder(),
    private val punctuationSpacingCompressor: PunctuationSpacingCompressor = PunctuationSpacingCompressor(),
    private val quotePairAnalyzer: QuotePairAnalyzer = QuotePairAnalyzer(),
) : ParagraphLayoutEngine {
    override fun layout(input: LayoutInput): LayoutResult {
        val text = input.content.text
        val fontSize = input.textStyle.fontSize
        val advance = fontSize
        val clreqProfile = clreqProfileResolver.resolve(input.profileId)
        val punctuationGlyphSubstitutor = ClreqPunctuationGlyphSubstitutor(
            policy = clreqProfile.punctuationGlyphPolicy,
        )

        val quotePairs = quotePairAnalyzer.analyze(text)
        val quoteRoleOverrides = quotePairAnalyzer.classifyPairs(text, quotePairs, fontRoleClassifier)
        val effectiveClassifier: FontRoleClassifier = if (quoteRoleOverrides.isNotEmpty()) {
            QuotePairAwareFontRoleClassifier(fontRoleClassifier, quoteRoleOverrides)
        } else {
            fontRoleClassifier
        }

        val clusterRanges = clusterRanges(text, effectiveClassifier)
        val fontDecisions = clusterRanges.map { range ->
            val role = effectiveClassifier.classify(text, range)
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

        val naturalClusters = fontDecisions.map { decision ->
            val sourceText = text.substring(decision.range.start, decision.range.end)
            val substitution = punctuationGlyphSubstitutor.substitute(sourceText)
            Cluster(
                range = decision.range,
                text = sourceText,
                displayText = substitution.displayText,
                fontKey = decision.candidate.key,
                advance = advance * ClreqPunctuationAdvancePolicy.advanceEm(
                    sourceText = sourceText,
                    displayText = substitution.displayText,
                ),
            )
        }

        val punctuationAtoms = naturalClusters.flatMap { cluster ->
            cluster.punctuationAtoms(
                em = fontSize,
                builder = punctuationAtomBuilder,
            )
        }
        val punctuationSpacingCompression = punctuationSpacingCompressor.compress(punctuationAtoms)
        val clusters = naturalClusters.withPunctuationSpacingCompression(punctuationSpacingCompression)

        val metricDecisions = fontDecisions.map { decision ->
            val request = FontMetricsRequest(
                fontKey = decision.candidate.key,
                fontSize = fontSize,
                role = decision.role,
                locale = input.textStyle.locale,
            )
            val rawMetrics = fontMetricsResolver.resolve(request)
            val layoutMetrics = fontMetricsNormalizer.normalize(
                FontMetricsNormalizationInput(
                    request = request,
                    rawMetrics = rawMetrics,
                ),
            )
            ClusterMetricDecision(
                range = decision.range,
                sourceText = text.substring(decision.range.start, decision.range.end),
                request = request,
                rawMetrics = rawMetrics,
                layoutMetrics = layoutMetrics,
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

        val naturalAdvance = naturalClusters.sumOf { it.advance.toDouble() }.toFloat()
        val adjustedAdvance = glyphRuns.sumOf { it.advance.toDouble() }.toFloat()
        val resultWidth = adjustedAdvance.coerceAtMost(input.constraints.maxWidth)
        val lineMetrics = metricDecisions.lineMetrics(input.paragraphStyle.lineHeight)
        val lines = if (text.isEmpty()) {
            emptyList()
        } else {
            listOf(
                LineBox(
                    range = TextRange(0, text.length),
                    baseline = lineMetrics.baseline,
                    top = 0f,
                    bottom = lineMetrics.height,
                    naturalWidth = naturalAdvance,
                    adjustedWidth = adjustedAdvance,
                    visualWidth = adjustedAdvance,
                    debug = LineDebugInfo(
                        repair = null,
                        notes = listOf(
                            "ExplainableStubParagraphLayoutEngine emits one unoptimized line.",
                            "punctuation-atoms:${punctuationAtoms.size}",
                            "punctuation-spacing-reduction:${punctuationSpacingCompression.totalReduction}",
                        ),
                    ),
                )
            )
        }

        return LayoutResult(
            input = input,
            size = Size(
                width = resultWidth,
                height = lineMetrics.height,
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
                metricDecisions = metricDecisions.map { decision ->
                    "metrics:${decision.range.start}-${decision.range.end}:${decision.sourceText}:${decision.request.role}:${decision.request.fontKey}:" +
                        "raw(a=${decision.rawMetrics.ascent},d=${decision.rawMetrics.descent},l=${decision.rawMetrics.leading},source=${decision.rawMetrics.source})->" +
                        "layout(a=${decision.layoutMetrics.ascent},d=${decision.layoutMetrics.descent},baseline=${decision.layoutMetrics.baselineClass},box=${decision.layoutMetrics.metricBox},source=${decision.layoutMetrics.source}):" +
                        decision.layoutMetrics.reason
                },
                punctuationDecisions = punctuationAtoms.map { atom ->
                    "punct:${atom.range.start}-${atom.range.end}:${atom.char}:${atom.punctuationClass}:" +
                        "advance=${atom.advance},body=${atom.bodyWidth}," +
                        "leading=${atom.leadingGlue.natural},trailing=${atom.trailingGlue.natural},anchor=${atom.anchor}"
                },
                punctuationSpacingDecisions = punctuationSpacingCompression.adjustments.map { adjustment ->
                    "spacing:${adjustment.range.start}-${adjustment.range.end}:${adjustment.leftChar}${adjustment.rightChar}:" +
                        "naturalInner=${adjustment.naturalInnerGlue},adjustedInner=${adjustment.adjustedInnerGlue}," +
                        "reduction=${adjustment.reduction},target=${adjustment.reductionTargetRange.start}-${adjustment.reductionTargetRange.end}:" +
                        adjustment.reason
                },
                lineDecisions = listOf("line:single-placeholder"),
            ),
        )
    }

    private fun clusterRanges(text: String, classifier: FontRoleClassifier): List<TextRange> {
        val ranges = mutableListOf<TextRange>()
        var index = 0
        while (index < text.length) {
            val codePoint = text.codePointAtCompat(index)
            val charCount = codePoint.charCount()
            val start = index
            val firstRange = TextRange(start, start + charCount)
            val role = classifier.classify(text, firstRange)

            index += charCount
            if (role == FontRole.LatinText) {
                while (index < text.length) {
                    val nextCodePoint = text.codePointAtCompat(index)
                    val nextCharCount = nextCodePoint.charCount()
                    val nextRange = TextRange(index, index + nextCharCount)
                    if (classifier.classify(text, nextRange) != FontRole.LatinText) break
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

    private fun Int.isRepeatableCjkPunctuation(): Boolean =
        this == 0x2014 || this == 0x2026 || this == 0x22EF

    private fun String.codePointAtCompat(index: Int): Int {
        val high = this[index].code
        if (high !in 0xD800..0xDBFF || index + 1 >= length) return high

        val low = this[index + 1].code
        if (low !in 0xDC00..0xDFFF) return high

        return 0x10000 + ((high - 0xD800) shl 10) + (low - 0xDC00)
    }

    private fun Int.charCount(): Int =
        if (this > 0xFFFF) 2 else 1

    private fun Cluster.punctuationAtoms(em: Float, builder: PunctuationAtomBuilder): List<PunctuationAtom> {
        if (displayText.isEmpty()) return emptyList()

        return displayText.mapIndexedNotNull { index, char ->
            builder.build(
                char = char,
                range = displayCharSourceRange(index),
                em = em,
            )
        }
    }

    private fun Cluster.displayCharSourceRange(displayIndex: Int): TextRange =
        if (displayText.length == text.length) {
            TextRange(
                start = range.start + displayIndex,
                end = range.start + displayIndex + 1,
            )
        } else {
            range
        }

    private fun List<Cluster>.withPunctuationSpacingCompression(
        compression: PunctuationSpacingCompressionResult,
    ): List<Cluster> {
        if (compression.adjustments.isEmpty()) return this

        return map { cluster ->
            val reduction = compression.adjustments
                .filter { adjustment -> adjustment.reductionTargetRange.isInside(cluster.range) }
                .sumOf { it.reduction.toDouble() }
                .toFloat()
            if (reduction == 0f) {
                cluster
            } else {
                cluster.copy(advance = (cluster.advance - reduction).coerceAtLeast(0f))
            }
        }
    }

    private fun TextRange.isInside(other: TextRange): Boolean =
        start >= other.start && end <= other.end

    private fun List<ClusterMetricDecision>.lineMetrics(explicitLineHeight: Float?): ResolvedLineMetrics {
        if (isEmpty()) {
            val height = explicitLineHeight ?: 0f
            return ResolvedLineMetrics(
                baseline = 0f,
                height = height,
            )
        }

        val ascent = maxOf { it.layoutMetrics.ascent }
        val descent = maxOf { it.layoutMetrics.descent }
        val naturalHeight = ascent + descent
        val height = explicitLineHeight?.coerceAtLeast(naturalHeight) ?: naturalHeight
        val extraLeading = (height - naturalHeight).coerceAtLeast(0f)

        return ResolvedLineMetrics(
            baseline = extraLeading / 2f + ascent,
            height = height,
        )
    }

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

private data class ClusterMetricDecision(
    val range: TextRange,
    val sourceText: String,
    val request: FontMetricsRequest,
    val rawMetrics: RawFontMetrics,
    val layoutMetrics: LayoutFontMetrics,
)

private data class ResolvedLineMetrics(
    val baseline: Float,
    val height: Float,
)
