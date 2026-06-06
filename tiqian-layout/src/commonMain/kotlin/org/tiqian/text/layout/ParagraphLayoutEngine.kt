package org.tiqian.text.layout

import org.tiqian.text.clreq.BuiltInClreqProfileResolver
import org.tiqian.text.clreq.ClreqProfile
import org.tiqian.text.clreq.ClreqProfileResolver
import org.tiqian.text.clreq.ClreqPunctuationAdvancePolicy
import org.tiqian.text.clreq.ClreqPunctuationGlyphSubstitutor
import org.tiqian.text.core.Cluster
import org.tiqian.text.core.FontDecisionInfo
import org.tiqian.text.core.Glyph
import org.tiqian.text.core.GlyphRun
import org.tiqian.text.core.LayoutDebugInfo
import org.tiqian.text.core.LayoutInput
import org.tiqian.text.core.LayoutResult
import org.tiqian.text.core.LineBox
import org.tiqian.text.core.LineDebugInfo
import org.tiqian.text.core.LineDecisionInfo
import org.tiqian.text.core.MetricDecisionInfo
import org.tiqian.text.core.PunctuationDecisionInfo
import org.tiqian.text.core.RoleOverrideInfo
import org.tiqian.text.core.Size
import org.tiqian.text.core.SpacingDecisionInfo
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
import org.tiqian.text.font.FontRoleContext
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
    private val lineBreaker: LineBreaker = GreedyLineBreaker(),
) : ParagraphLayoutEngine {
    override fun layout(input: LayoutInput): LayoutResult {
        val text = input.content.text
        val fontSize = input.textStyle.fontSize
        val clreqProfile = clreqProfileResolver.resolve(input.profileId)
        val context = FontRoleContext(
            locale = input.textStyle.locale,
            regionHint = clreqProfile.region.name,
        )
        val punctuationGlyphSubstitutor = ClreqPunctuationGlyphSubstitutor(
            policy = clreqProfile.punctuationGlyphPolicy,
        )

        val quotePairs = quotePairAnalyzer.analyze(text)
        val quoteRoleOverrides = quotePairAnalyzer.classifyPairs(text, quotePairs, fontRoleClassifier, context)
        val roleOverrideInfos = quoteRoleOverrides.toRoleOverrideInfos(text, fontRoleClassifier, context)
        val effectiveClassifier: FontRoleClassifier = if (quoteRoleOverrides.isNotEmpty()) {
            QuotePairAwareFontRoleClassifier(fontRoleClassifier, quoteRoleOverrides)
        } else {
            fontRoleClassifier
        }

        val clusterRanges = clusterRanges(text, effectiveClassifier, context, clreqProfile)
        val fontDecisions = clusterRanges.map { range ->
            val role = effectiveClassifier.classify(text, range, context)
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
                advance = fontSize * ClreqPunctuationAdvancePolicy.advanceEm(
                    sourceText = sourceText,
                    displayText = substitution.displayText,
                ),
            )
        }

        val punctuationAtoms = naturalClusters.flatMap { cluster ->
            cluster.punctuationAtoms(em = fontSize, builder = punctuationAtomBuilder)
        }
        val spacingPlan = punctuationSpacingCompressor.compress(punctuationAtoms)
        val clusters = naturalClusters.withPunctuationSpacingCompression(spacingPlan)

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

        val lineMetrics = metricDecisions.lineMetrics(input.paragraphStyle.lineHeight)
        val lineSolution = if (text.isEmpty()) {
            LineSolution(emptyList())
        } else {
            lineBreaker.breakLines(
                naturalClusters = naturalClusters,
                adjustedClusters = clusters,
                maxWidth = input.constraints.maxWidth,
            )
        }
        val lines = lineSolution.lines.mapIndexed { lineIndex, lineCandidate ->
            LineBox(
                range = lineCandidate.sourceRange,
                baseline = lineMetrics.baseline + lineIndex * lineMetrics.height,
                top = lineIndex * lineMetrics.height,
                bottom = (lineIndex + 1) * lineMetrics.height,
                naturalWidth = lineCandidate.naturalWidth,
                adjustedWidth = lineCandidate.adjustedWidth,
                visualWidth = lineCandidate.adjustedWidth,
                debug = LineDebugInfo(
                    repair = lineCandidate.repair?.let { "${it::class.simpleName}:${it.reason}" },
                    notes = listOf(
                        "line:${lineIndex}:clusters=${lineCandidate.clusterRange.first}-${lineCandidate.clusterRange.last}",
                        "natural=${lineCandidate.naturalWidth},adjusted=${lineCandidate.adjustedWidth}",
                    ),
                ),
            )
        }
        val widestLine = lines.maxOfOrNull { it.adjustedWidth } ?: 0f
        val totalHeight = if (lines.isEmpty()) lineMetrics.height else lines.size * lineMetrics.height
        val resultWidth = widestLine.coerceAtMost(input.constraints.maxWidth)

        return LayoutResult(
            input = input,
            size = Size(
                width = resultWidth,
                height = totalHeight,
            ),
            clusters = clusters,
            glyphRuns = glyphRuns,
            lines = lines,
            debug = LayoutDebugInfo(
                fontDecisions = fontDecisions.map { decision ->
                    val clusterText = text.substring(decision.range.start, decision.range.end)
                    val substitution = punctuationGlyphSubstitutor.substitute(clusterText)
                    FontDecisionInfo(
                        range = decision.range,
                        sourceText = clusterText,
                        displayText = substitution.displayText,
                        role = decision.role.name,
                        fontKey = decision.candidate.key,
                        reason = decision.reason,
                        substitutionReason = substitution.reason,
                    )
                },
                metricDecisions = metricDecisions.map { decision ->
                    MetricDecisionInfo(
                        range = decision.range,
                        sourceText = decision.sourceText,
                        role = decision.request.role.name,
                        fontKey = decision.request.fontKey,
                        rawAscent = decision.rawMetrics.ascent,
                        rawDescent = decision.rawMetrics.descent,
                        rawLeading = decision.rawMetrics.leading,
                        rawSource = decision.rawMetrics.source.name,
                        layoutAscent = decision.layoutMetrics.ascent,
                        layoutDescent = decision.layoutMetrics.descent,
                        baselineClass = decision.layoutMetrics.baselineClass.name,
                        metricBox = decision.layoutMetrics.metricBox.name,
                        layoutSource = decision.layoutMetrics.source.name,
                        reason = decision.layoutMetrics.reason,
                    )
                },
                punctuationDecisions = punctuationAtoms.map { atom ->
                    PunctuationDecisionInfo(
                        range = atom.range,
                        char = atom.char,
                        punctuationClass = atom.punctuationClass.name,
                        advance = atom.advance,
                        bodyWidth = atom.bodyWidth,
                        leadingGlueNatural = atom.leadingGlue.natural,
                        trailingGlueNatural = atom.trailingGlue.natural,
                        anchor = atom.anchor.name,
                    )
                },
                spacingDecisions = spacingPlan.adjustments.map { adjustment ->
                    SpacingDecisionInfo(
                        range = adjustment.range,
                        leftChar = adjustment.leftChar,
                        rightChar = adjustment.rightChar,
                        naturalInnerGlue = adjustment.naturalInnerGlue,
                        adjustedInnerGlue = adjustment.adjustedInnerGlue,
                        reduction = adjustment.reduction,
                        reductionTargetRange = adjustment.reductionTargetRange,
                        reason = adjustment.reason,
                    )
                },
                roleOverrides = roleOverrideInfos,
                lineDecisions = lines.zip(lineSolution.lines).mapIndexed { lineIndex, (line, candidate) ->
                    LineDecisionInfo(
                        range = line.range,
                        kind = "greedy",
                        repair = candidate.repair?.let { "${it::class.simpleName}" },
                        repairPenalty = candidate.repair?.penalty ?: 0,
                        notes = listOf(
                            "index:$lineIndex",
                            "natural:${line.naturalWidth}",
                            "adjusted:${line.adjustedWidth}",
                        ) + listOfNotNull(candidate.repair?.let { "repair-reason:${it.reason}" }),
                    )
                },
            ),
        )
    }

    private fun Map<Int, FontRole>.toRoleOverrideInfos(
        text: String,
        baseClassifier: FontRoleClassifier,
        context: FontRoleContext,
    ): List<RoleOverrideInfo> =
        entries
            .sortedBy { it.key }
            .map { (index, overriddenRole) ->
                val sourceText = text.substring(index, (index + 1).coerceAtMost(text.length))
                val originalRole = baseClassifier
                    .classify(text, TextRange(index, index + 1), context)
                RoleOverrideInfo(
                    range = TextRange(index, index + 1),
                    sourceText = sourceText,
                    originalRole = originalRole.name,
                    overriddenRole = overriddenRole.name,
                    source = "QuotePairAwareLatinContext",
                    reason = "quote-pair-outer-context",
                )
            }

    private fun clusterRanges(
        text: String,
        classifier: FontRoleClassifier,
        context: FontRoleContext,
        profile: ClreqProfile,
    ): List<TextRange> {
        val coalesceSet = profile.coalesceRepeatablePunctuation
        val ranges = mutableListOf<TextRange>()
        var index = 0
        while (index < text.length) {
            val codePoint = text.codePointAtCompat(index)
            val charCount = codePoint.charCount()
            val start = index
            val firstRange = TextRange(start, start + charCount)
            val role = classifier.classify(text, firstRange, context)

            index += charCount
            if (role == FontRole.LatinText) {
                while (index < text.length) {
                    val nextCodePoint = text.codePointAtCompat(index)
                    val nextCharCount = nextCodePoint.charCount()
                    val nextRange = TextRange(index, index + nextCharCount)
                    if (classifier.classify(text, nextRange, context) != FontRole.LatinText) break
                    index += nextCharCount
                }
            } else if (role == FontRole.CjkPunctuation && codePoint in coalesceSet) {
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
