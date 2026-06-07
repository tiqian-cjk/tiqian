package org.tiqian.text.layout

import org.tiqian.text.clreq.BuiltInClreqProfileResolver
import org.tiqian.text.clreq.ClreqProfile
import org.tiqian.text.clreq.ClreqProfileResolver
import org.tiqian.text.clreq.ClreqPunctuationGlyphSubstitutor
import org.tiqian.text.core.Cluster
import org.tiqian.text.core.FontDecisionInfo
import org.tiqian.text.core.Glyph
import org.tiqian.text.core.GlyphRun
import org.tiqian.text.core.JustificationAllocationInfo
import org.tiqian.text.core.JustificationDecisionInfo
import org.tiqian.text.core.LayoutDebugInfo
import org.tiqian.text.core.LayoutInput
import org.tiqian.text.core.LayoutResult
import org.tiqian.text.core.LineBox
import org.tiqian.text.core.LineDebugInfo
import org.tiqian.text.core.LineDecisionInfo
import org.tiqian.text.core.LineRepairCandidateInfo
import org.tiqian.text.core.LineRepairDecisionInfo
import org.tiqian.text.core.MetricDecisionInfo
import org.tiqian.text.core.PunctuationDecisionInfo
import org.tiqian.text.core.RoleOverrideInfo
import org.tiqian.text.core.Size
import org.tiqian.text.core.SpacingDecisionInfo
import org.tiqian.text.core.TextAlign
import org.tiqian.text.core.TextRange
import org.tiqian.text.font.CjkFontRoleClassifier
import org.tiqian.text.font.FallbackResolver
import org.tiqian.text.font.FontMetricsNormalizationInput
import org.tiqian.text.font.FontMetricsNormalizer
import org.tiqian.text.font.FontMetricsRequest
import org.tiqian.text.font.FontMetricsResolver
import org.tiqian.text.font.FontDecision
import org.tiqian.text.font.FontRequest
import org.tiqian.text.font.FontRole
import org.tiqian.text.font.FontRoleClassifier
import org.tiqian.text.font.FontRoleContext
import org.tiqian.text.font.LayoutFontMetrics
import org.tiqian.text.font.PreferCjkForAmbiguousPunctuationResolver
import org.tiqian.text.font.RawFontMetrics
import org.tiqian.text.font.ScriptAwareFontMetricsNormalizer
import org.tiqian.text.font.StubFontMetricsResolver
import org.tiqian.text.shaping.ExplainableStubTextShaper
import org.tiqian.text.shaping.ShapingInput
import org.tiqian.text.shaping.TextShaper

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
    private val bracketPairAnalyzer: BracketPairAnalyzer = BracketPairAnalyzer(),
    private val lineBreaker: LineBreaker = GreedyLineBreaker(),
    private val justifier: Justifier = Justifier(),
    private val textShaper: TextShaper = ExplainableStubTextShaper(),
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
        val bracketPairs = bracketPairAnalyzer.analyze(text)
        val bracketRoleOverrides = bracketPairAnalyzer.classifyPairs(text, bracketPairs, fontRoleClassifier, context)
        val combinedRoleOverrides = quoteRoleOverrides + bracketRoleOverrides
        val roleOverrideInfos = quoteRoleOverrides.toRoleOverrideInfos(
            text = text,
            baseClassifier = fontRoleClassifier,
            context = context,
            source = "QuotePairAwareLatinContext",
            reason = "quote-pair-outer-context",
        ) + bracketRoleOverrides.toRoleOverrideInfos(
            text = text,
            baseClassifier = fontRoleClassifier,
            context = context,
            source = "BracketPairAwareLatinContext",
            reason = "bracket-pair-outer-context",
        )
        val effectiveClassifier: FontRoleClassifier = if (combinedRoleOverrides.isNotEmpty()) {
            QuotePairAwareFontRoleClassifier(fontRoleClassifier, combinedRoleOverrides)
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

        val shapingResults = fontDecisions.map { decision ->
            val sourceText = text.substring(decision.range.start, decision.range.end)
            val substitution = punctuationGlyphSubstitutor.substitute(sourceText)
            textShaper.shape(
                ShapingInput(
                    text = text,
                    range = decision.range,
                    style = input.textStyle,
                    fontDecision = decision,
                    displayText = substitution.displayText,
                ),
            )
        }
        val naturalClusters = shapingResults.flatMap { it.clusters }
        val shapingDecisions = shapingResults.flatMap { it.decisions }
        naturalClusters.requireCoveredBy(fontDecisions)

        val punctuationAtoms = naturalClusters.flatMap { cluster ->
            cluster.punctuationAtoms(em = fontSize, builder = punctuationAtomBuilder)
        }
        val spacingPlan = punctuationSpacingCompressor.compress(punctuationAtoms)
        val clusters = naturalClusters.withPunctuationSpacingCompression(spacingPlan)
        val pushInCapacities = clusters.pushInCapacities(punctuationAtoms)

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

        val lineMetrics = metricDecisions.lineMetrics(input.paragraphStyle.lineHeight)
        val lineSolution = if (text.isEmpty()) {
            LineSolution(emptyList())
        } else {
            lineBreaker.breakLines(
                naturalClusters = naturalClusters,
                adjustedClusters = clusters,
                maxWidth = input.constraints.maxWidth,
                pushInCapacities = pushInCapacities,
            )
        }

        val clusterRoles = naturalClusters.map { cluster ->
            fontDecisions.first { cluster.range.isInside(it.range) }.role
        }
        val pushInShrinkByCluster = lineSolution.lines
            .mapNotNull { it.repair as? RepairOption.PushIn }
            .groupBy { it.targetClusterIndex }
            .mapValues { (_, repairs) -> repairs.sumOf { it.shrink.toDouble() }.toFloat() }
        val pushInClusters = clusters.mapIndexed { idx, c ->
            val shrink = pushInShrinkByCluster[idx] ?: 0f
            if (shrink == 0f) c else c.copy(advance = (c.advance - shrink).coerceAtLeast(0f))
        }
        val justify = input.paragraphStyle.textAlign == TextAlign.Justify
        val justificationPlans: List<JustificationPlan?> = lineSolution.lines.mapIndexed { lineIndex, lineCandidate ->
            val isLast = lineIndex == lineSolution.lines.lastIndex
            if (!justify || isLast) {
                null
            } else {
                justifier.justify(
                    adjustedClusters = pushInClusters,
                    clusterRoles = clusterRoles,
                    lineClusterRange = lineCandidate.clusterRange,
                    maxWidth = input.constraints.maxWidth,
                    spacingPlan = spacingPlan,
                    fontSize = fontSize,
                    skip = false,
                )
            }
        }
        val justifyDeltaByCluster = HashMap<Int, Float>().apply {
            justificationPlans.filterNotNull()
                .flatMap { it.allocations }
                .forEach { alloc -> merge(alloc.targetClusterIndex, alloc.delta) { a, b -> a + b } }
        }
        val finalClusters = pushInClusters.mapIndexed { idx, c ->
            val extra = justifyDeltaByCluster[idx] ?: 0f
            if (extra == 0f) c else c.copy(advance = c.advance + extra)
        }

        val glyphRuns = finalClusters.groupAdjacentBy { it.fontKey }.map { runClusters ->
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

        val lines = lineSolution.lines.mapIndexed { lineIndex, lineCandidate ->
            val visualWidth = lineCandidate.clusterRange
                .sumOf { finalClusters[it].advance.toDouble() }
                .toFloat()
            LineBox(
                range = lineCandidate.sourceRange,
                baseline = lineMetrics.baseline + lineIndex * lineMetrics.height,
                top = lineIndex * lineMetrics.height,
                bottom = (lineIndex + 1) * lineMetrics.height,
                naturalWidth = lineCandidate.naturalWidth,
                adjustedWidth = lineCandidate.adjustedWidth,
                visualWidth = visualWidth,
                debug = LineDebugInfo(
                    repair = lineCandidate.repair?.let { "${it::class.simpleName}:${it.reason}" },
                    notes = listOf(
                        "line:${lineIndex}:clusters=${lineCandidate.clusterRange.first}-${lineCandidate.clusterRange.last}",
                        "natural=${lineCandidate.naturalWidth},adjusted=${lineCandidate.adjustedWidth},visual=$visualWidth",
                    ),
                ),
            )
        }
        val widestLine = lines.maxOfOrNull { it.visualWidth } ?: 0f
        val totalHeight = if (lines.isEmpty()) lineMetrics.height else lines.size * lineMetrics.height
        val resultWidth = widestLine.coerceAtMost(input.constraints.maxWidth)

        return LayoutResult(
            input = input,
            size = Size(
                width = resultWidth,
                height = totalHeight,
            ),
            clusters = finalClusters,
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
                shapingDecisions = shapingDecisions,
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
                        kind = lineBreaker.strategyName,
                        repair = candidate.repair?.let { "${it::class.simpleName}" },
                        repairPenalty = candidate.repair?.penalty ?: 0,
                        repairDecision = candidate.repair?.toDecisionInfo(clusters),
                        repairCandidates = candidate.repairCandidates.map { it.toDecisionInfo(clusters) },
                        notes = listOf(
                            "index:$lineIndex",
                            "natural:${line.naturalWidth}",
                            "adjusted:${line.adjustedWidth}",
                            "visual:${line.visualWidth}",
                        ) + listOfNotNull(candidate.repair?.let { "repair-reason:${it.reason}" }),
                    )
                },
                justificationDecisions = justificationPlans.zip(lineSolution.lines)
                    .mapNotNull { (plan, candidate) ->
                        plan
                            ?.takeIf { it.allocations.isNotEmpty() || it.deficitBefore > 0f }
                            ?.let {
                                JustificationDecisionInfo(
                                    lineRange = candidate.sourceRange,
                                    deficitBefore = it.deficitBefore,
                                    deficitAfter = it.unfilledDeficit,
                                    allocations = it.allocations.map { alloc ->
                                        JustificationAllocationInfo(
                                            clusterRange = clusters[alloc.targetClusterIndex].range,
                                            kind = alloc.kind.name,
                                            priority = alloc.priority,
                                            delta = alloc.delta,
                                            reason = alloc.reason,
                                        )
                                    },
                                )
                            }
                    },
            ),
        )
    }

    private fun Map<Int, FontRole>.toRoleOverrideInfos(
        text: String,
        baseClassifier: FontRoleClassifier,
        context: FontRoleContext,
        source: String,
        reason: String,
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
                    source = source,
                    reason = reason,
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

    private fun List<Cluster>.requireCoveredBy(fontDecisions: List<FontDecision>) {
        fontDecisions.forEach { decision ->
            val coveringClusters = filter { cluster -> cluster.range.isInside(decision.range) }
                .sortedBy { it.range.start }
            var cursor = decision.range.start
            for (cluster in coveringClusters) {
                require(cluster.range.start == cursor) {
                    "TextShaper returned non-contiguous clusters for ${decision.range}: $coveringClusters"
                }
                cursor = cluster.range.end
            }
            require(cursor == decision.range.end) {
                "TextShaper must return clusters covering ${decision.range}; coveredUntil=$cursor"
            }
        }
    }

    private fun List<Cluster>.pushInCapacities(atoms: List<PunctuationAtom>): Map<Int, Float> {
        if (atoms.isEmpty()) return emptyMap()

        return mapIndexedNotNull { index, cluster ->
            val capacity = atoms
                .filter { atom -> atom.range.isInside(cluster.range) }
                .sumOf { atom -> (atom.trailingGlue.natural - atom.trailingGlue.min).toDouble() }
                .toFloat()
            if (capacity > 0f) index to capacity else null
        }.toMap()
    }

    private fun RepairCandidate.toDecisionInfo(clusters: List<Cluster>): LineRepairCandidateInfo =
        LineRepairCandidateInfo(
            kind = kind,
            reasonCode = reasonCode,
            offenderRange = clusters[offenderClusterIndex].range,
            penalty = penalty,
            accepted = accepted,
            rejectionReason = rejectionReason,
            targetClusterIndex = targetClusterIndex,
            carriedClusterIndex = carriedClusterIndex,
            shrink = shrink,
            requiredShrink = requiredShrink,
            availableCapacity = availableCapacity,
        )

    private fun RepairOption.toDecisionInfo(clusters: List<Cluster>): LineRepairDecisionInfo =
        when (this) {
            is RepairOption.PushIn -> LineRepairDecisionInfo(
                kind = "PushIn",
                reasonCode = "ForbiddenAtLineStart",
                offenderRange = clusters[offenderClusterIndex].range,
                penalty = penalty,
                targetClusterIndex = targetClusterIndex,
                shrink = shrink,
                availableCapacity = availableCapacity,
            )

            is RepairOption.CarryPrevious -> LineRepairDecisionInfo(
                kind = "CarryPrevious",
                reasonCode = "ForbiddenAtLineStart",
                offenderRange = clusters[offenderClusterIndex].range,
                penalty = penalty,
                carriedClusterIndex = carriedClusterIndex,
            )

            is RepairOption.LeaveRagged -> LineRepairDecisionInfo(
                kind = "LeaveRagged",
                reasonCode = "ForbiddenAtLineStart",
                offenderRange = clusters[offenderClusterIndex].range,
                penalty = penalty,
            )

            is RepairOption.Hang -> LineRepairDecisionInfo(
                kind = "Hang",
                reasonCode = "ForbiddenAtLineStart",
                offenderRange = clusters[offenderClusterIndex].range,
                penalty = penalty,
            )
        }

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
