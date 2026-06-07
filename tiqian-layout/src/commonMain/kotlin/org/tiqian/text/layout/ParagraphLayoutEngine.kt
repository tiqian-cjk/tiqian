package org.tiqian.text.layout

import org.tiqian.text.clreq.AutoSpaceMode
import org.tiqian.text.clreq.AutoSpacePolicy
import org.tiqian.text.clreq.BuiltInClreqProfileResolver
import org.tiqian.text.clreq.ClreqProfile
import org.tiqian.text.clreq.ClreqProfileResolver
import org.tiqian.text.clreq.PunctuationGluePlacement
import org.tiqian.text.clreq.ClreqPunctuationGlyphSubstitutor
import org.tiqian.text.core.AutoSpaceDecisionInfo
import org.tiqian.text.core.Cluster
import org.tiqian.text.core.ClusterGeometryDecisionInfo
import org.tiqian.text.core.FontDecisionInfo
import org.tiqian.text.core.LineEdgeTrimDecisionInfo
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
import org.tiqian.text.core.Rect
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
        val roleOverrideInfos = quoteRoleOverrides.toRoleOverrideInfos(
            text = text,
            baseClassifier = fontRoleClassifier,
            context = context,
            source = "QuotePairAwareLatinContext",
            reason = "quote-pair-outer-context",
        )
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
        val rawNaturalClusters = shapingResults.flatMap { it.clusters }
        val shapedGlyphsByClusterRange = shapingResults
            .flatMap { it.glyphRuns }
            .flatMap { it.glyphs }
            .groupBy { it.clusterRange }
        val shapingDecisions = shapingResults.flatMap { it.decisions }
        rawNaturalClusters.requireCoveredBy(fontDecisions)

        val autoSpaceResult = rawNaturalClusters.applyAutoSpacePolicy(
            fontDecisions = fontDecisions,
            policy = clreqProfile.autoSpace,
            fontSize = fontSize,
        )
        val naturalClusters = autoSpaceResult.clusters
        val autoSpaceDecisions = autoSpaceResult.decisions

        val punctuationAtoms = naturalClusters.flatMap { cluster ->
            cluster.punctuationAtoms(
                em = fontSize,
                builder = punctuationAtomBuilder,
                shapedGlyphs = shapedGlyphsByClusterRange[cluster.range].orEmpty(),
                gluePlacement = clreqProfile.gluePlacement,
            )
        }
        val spacingPlan = punctuationSpacingCompressor.compress(punctuationAtoms, em = fontSize)
        val baseGeometry = PunctuationGeometryLedger.from(
            naturalClusters = naturalClusters,
            punctuationAtoms = punctuationAtoms,
            spacingPlan = spacingPlan,
        )
        val clusters = baseGeometry.resolveClusters()
        val pushInCapacities = baseGeometry.pushInCapacities()

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
        val pushInGeometry = baseGeometry.consumeTrailingByCluster(pushInShrinkByCluster)
        val pushInClusters = pushInGeometry.resolveClusters()
        val edgeTrimResult = pushInGeometry.consumeLineEdgeGlue(
            lines = lineSolution.lines,
        )
        val trimmedGeometry = edgeTrimResult.geometry
        val trimmedClusters = trimmedGeometry.resolveClusters()
        val edgeTrimDecisions = edgeTrimResult.decisions

        val justify = input.paragraphStyle.textAlign == TextAlign.Justify
        val justificationPlans: List<JustificationPlan?> = lineSolution.lines.mapIndexed { lineIndex, lineCandidate ->
            val isLast = lineIndex == lineSolution.lines.lastIndex
            if (!justify || isLast) {
                null
            } else {
                justifier.justify(
                    adjustedClusters = trimmedClusters,
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
        val finalGeometry = trimmedGeometry.addJustificationDeltas(justifyDeltaByCluster)
        val finalClusters = finalGeometry.resolveClusters()
        val geometryDecisions = finalGeometry.toDecisionInfo()

        val glyphRuns = finalClusters.groupAdjacentBy { it.fontKey }.map { runClusters ->
            GlyphRun(
                range = TextRange(runClusters.first().range.start, runClusters.last().range.end),
                fontKey = runClusters.first().fontKey,
                glyphs = runClusters.flatMapIndexed { fallbackGlyphId, cluster ->
                    shapedGlyphsByClusterRange[cluster.range]
                        ?.mapToResolvedAdvance(cluster)
                        ?: listOf(
                            Glyph(
                                id = fallbackGlyphId.toUInt(),
                                clusterRange = cluster.range,
                                advance = cluster.advance,
                            ),
                        )
                },
                advance = runClusters.sumOf { it.advance.toDouble() }.toFloat(),
            )
        }

        val lines = lineSolution.lines.mapIndexed { lineIndex, lineCandidate ->
            val adjustedWidth = lineCandidate.clusterRange
                .sumOf { trimmedClusters[it].advance.toDouble() }
                .toFloat()
            val visualWidth = lineCandidate.clusterRange
                .sumOf { finalClusters[it].advance.toDouble() }
                .toFloat()
            LineBox(
                range = lineCandidate.sourceRange,
                baseline = lineMetrics.baseline + lineIndex * lineMetrics.height,
                top = lineIndex * lineMetrics.height,
                bottom = (lineIndex + 1) * lineMetrics.height,
                naturalWidth = lineCandidate.naturalWidth,
                adjustedWidth = adjustedWidth,
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
                        inkBounds = atom.inkBounds,
                        geometrySource = atom.geometrySource,
                        policyBodyFloor = atom.policyBodyFloor,
                        inkWidth = atom.inkWidth,
                        inkCenter = atom.inkCenter,
                    )
                },
                geometryDecisions = geometryDecisions,
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
                autoSpaceDecisions = autoSpaceDecisions,
                lineEdgeTrimDecisions = edgeTrimDecisions,
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

    private fun Cluster.punctuationAtoms(
        em: Float,
        builder: PunctuationAtomBuilder,
        shapedGlyphs: List<Glyph>,
        gluePlacement: PunctuationGluePlacement,
    ): List<PunctuationAtom> {
        if (displayText.isEmpty()) return emptyList()

        return displayText.mapIndexedNotNull { index, char ->
            builder.build(
                char = char,
                range = displayCharSourceRange(index),
                em = em,
                inkInput = punctuationInkInputFor(index, shapedGlyphs),
                gluePlacement = gluePlacement,
            )
        }
    }

    private fun Cluster.punctuationInkInputFor(displayIndex: Int, shapedGlyphs: List<Glyph>): PunctuationInkInput? {
        if (shapedGlyphs.isEmpty()) return null
        val glyph = when {
            shapedGlyphs.size == displayText.length -> shapedGlyphs.getOrNull(displayIndex)
            displayText.length == 1 -> shapedGlyphs.unionAsSingleGlyph()
            else -> null
        } ?: return null
        return PunctuationInkInput(
            advance = glyph.advance,
            inkBounds = glyph.bounds,
        )
    }

    private fun List<Glyph>.unionAsSingleGlyph(): Glyph? {
        if (isEmpty()) return null
        val first = first()
        val bounds = mapNotNull { it.bounds }
        if (bounds.isEmpty()) return first
        return first.copy(
            advance = sumOf { it.advance.toDouble() }.toFloat(),
            bounds = Rect(
                left = bounds.minOf { it.left.toDouble() }.toFloat(),
                top = bounds.minOf { it.top.toDouble() }.toFloat(),
                right = bounds.maxOf { it.right.toDouble() }.toFloat(),
                bottom = bounds.maxOf { it.bottom.toDouble() }.toFloat(),
            ),
        )
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

    private fun List<Glyph>.mapToResolvedAdvance(cluster: Cluster): List<Glyph> {
        val sourceAdvance = sumOf { it.advance.toDouble() }.toFloat()
        if (sourceAdvance <= 0f) {
            val fallbackAdvance = cluster.advance / size.coerceAtLeast(1)
            return map { it.copy(advance = fallbackAdvance, clusterRange = cluster.range) }
        }

        val scale = cluster.advance / sourceAdvance
        return map { glyph ->
            glyph.copy(
                clusterRange = cluster.range,
                advance = glyph.advance * scale,
            )
        }
    }

    /**
     * Applies `AutoSpacePolicy` to natural clusters. The named heuristic is
     * `TextAutoSpaceReplace` — at CJK ↔ Latin / digit boundaries, typed
     * U+0020 SPACE characters that sit at the edge of a Latin-classified
     * cluster have their contribution to the cluster's advance reduced from
     * the stub shaper's 1em down to `policy.gapEm`.
     *
     * This mirrors CSS Text Module Level 4 `text-autospace`: the autospace
     * gap REPLACES the typed space rather than adding to it (avoiding the
     * "1em space + 0.25em autospace = 1.25em double gap" problem).
     *
     * Only `AutoSpaceMode.Replace` is implemented in this slice. `Insert`
     * requires virtual cluster injection (typed space stays at 1em and an
     * additional 0.25em is inserted) and is deferred to a future slice.
     */
    private fun List<Cluster>.applyAutoSpacePolicy(
        fontDecisions: List<FontDecision>,
        policy: AutoSpacePolicy,
        fontSize: Float,
    ): AutoSpaceApplicationResult {
        if (isEmpty()) return AutoSpaceApplicationResult(emptyList(), emptyList())

        val decisions = mutableListOf<AutoSpaceDecisionInfo>()
        val updated = mapIndexed { idx, cluster ->
            val role = fontDecisions.firstOrNull { it.range == cluster.range }?.role
                ?: return@mapIndexed cluster
            if (role != FontRole.LatinText) return@mapIndexed cluster

            val prevRole = if (idx > 0) fontDecisions.firstOrNull { it.range == this[idx - 1].range }?.role else null
            val nextRole = if (idx < lastIndex) fontDecisions.firstOrNull { it.range == this[idx + 1].range }?.role else null

            val leadingSpaces = cluster.text.takeWhile { it == ' ' }.length
            val trailingSpaces = cluster.text.takeLastWhile { it == ' ' }.length
                .let { count -> if (cluster.text.length == leadingSpaces) 0 else count }

            val leadingReduction = leadingSpaces.boundaryReduction(
                boundaryRole = prevRole,
                cluster = cluster,
                side = "leading",
                policy = policy,
                fontSize = fontSize,
                decisions = decisions,
            )
            val trailingReduction = trailingSpaces.boundaryReduction(
                boundaryRole = nextRole,
                cluster = cluster,
                side = "trailing",
                policy = policy,
                fontSize = fontSize,
                decisions = decisions,
            )
            val totalReduction = leadingReduction + trailingReduction
            if (totalReduction == 0f) {
                cluster
            } else {
                cluster.copy(advance = (cluster.advance - totalReduction).coerceAtLeast(0f))
            }
        }
        return AutoSpaceApplicationResult(updated, decisions)
    }

    /**
     * `TextAutoSpaceReplace` per CSS Text 4 + ADR 0009: a CJK ↔ Latin (or
     * Latin ↔ CJK) boundary needs ONE autospace gap, regardless of how many
     * typed U+0020 the author placed at the boundary. Earlier implementation
     * scaled the gap by the typed-space count, which violated the spec: two
     * typed spaces should be folded into the same single autospace, not
     * widen the boundary to `2 × gapEm`.
     *
     * Receiver `this` is the number of edge spaces in the Latin cluster on
     * this side. Return value is the total advance reduction to apply to
     * the Latin cluster: `count × spaceAdvance - 1 × autospaceGap`,
     * floored at zero so 0-count is a no-op.
     */
    private fun Int.boundaryReduction(
        boundaryRole: FontRole?,
        cluster: Cluster,
        side: String,
        policy: AutoSpacePolicy,
        fontSize: Float,
        decisions: MutableList<AutoSpaceDecisionInfo>,
    ): Float {
        if (this == 0 || boundaryRole == null) return 0f
        val mode = policy.modeFor(boundaryRole) ?: return 0f
        if (mode != AutoSpaceMode.Replace) return 0f

        // Stub shaper assigns 1em per typed U+0020. The autospace replaces
        // ALL of them (whether 1 or N) with a single gap of policy.gapEm × em.
        val typedAdvance = this * fontSize
        val replacementGap = policy.gapEm * fontSize
        val total = (typedAdvance - replacementGap).coerceAtLeast(0f)
        if (total == 0f) return 0f
        decisions += AutoSpaceDecisionInfo(
            clusterRange = cluster.range,
            side = side,
            boundaryRole = boundaryRole.name,
            mode = mode.name,
            charactersAffected = this,
            reductionPerChar = total / this,
            totalReduction = total,
            reason = "TextAutoSpaceReplace:cjk-${if (boundaryRole == FontRole.CjkText) "ideograph" else "punctuation"}:n-to-one-gap",
        )
        return total
    }

    private fun AutoSpacePolicy.modeFor(role: FontRole): AutoSpaceMode? =
        when (role) {
            FontRole.CjkText, FontRole.CjkPunctuation -> cjkLatin
            else -> null
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

private data class AutoSpaceApplicationResult(
    val clusters: List<Cluster>,
    val decisions: List<AutoSpaceDecisionInfo>,
)

private data class PunctuationGeometryLedger(
    private val naturalClusters: List<Cluster>,
    private val geometries: Map<Int, PunctuationClusterGeometry>,
    private val budgets: Map<Int, GlueBudget>,
    private val justificationDeltaByCluster: Map<Int, Float> = emptyMap(),
) {
    companion object {
        fun from(
            naturalClusters: List<Cluster>,
            punctuationAtoms: List<PunctuationAtom>,
            spacingPlan: PunctuationSpacingCompressionResult,
        ): PunctuationGeometryLedger {
            val geometries = buildPunctuationClusterGeometries(
                naturalClusters = naturalClusters,
                punctuationAtoms = punctuationAtoms,
            )
            val budgets = geometries.mapValues { (_, geometry) ->
                GlueBudget(
                    leadingNatural = geometry.leadingGlueNatural,
                    leadingConsumed = 0f,
                    trailingNatural = geometry.trailingGlueNatural,
                    trailingConsumed = 0f,
                )
            }
            return PunctuationGeometryLedger(
                naturalClusters = naturalClusters,
                geometries = geometries,
                budgets = budgets,
            ).consumeSpacing(spacingPlan)
        }

        private fun buildPunctuationClusterGeometries(
            naturalClusters: List<Cluster>,
            punctuationAtoms: List<PunctuationAtom>,
        ): Map<Int, PunctuationClusterGeometry> {
            if (punctuationAtoms.isEmpty()) return emptyMap()

            return naturalClusters.mapIndexedNotNull { index, cluster ->
                val atomsForCluster = punctuationAtoms.filter { it.range.isInside(cluster.range) }
                if (atomsForCluster.isEmpty()) return@mapIndexedNotNull null
                index to PunctuationClusterGeometry(
                    range = cluster.range,
                    sourceText = cluster.text,
                    displayText = cluster.displayText,
                    baseAdvance = cluster.advance,
                    bodyWidth = atomsForCluster.sumOf { it.bodyWidth.toDouble() }.toFloat(),
                    leadingGlueNatural = atomsForCluster.first().leadingGlue.natural,
                    trailingGlueNatural = atomsForCluster.last().trailingGlue.natural,
                    reason = atomsForCluster.first().geometrySource,
                )
            }.toMap()
        }
    }

    fun resolveClusters(): List<Cluster> =
        naturalClusters.mapIndexed { index, cluster ->
            val resolved = resolvedAdvance(index, cluster)
            if (resolved == cluster.advance) cluster else cluster.copy(advance = resolved)
        }

    fun pushInCapacities(): Map<Int, Float> =
        budgets.mapNotNull { (index, budget) ->
            val capacity = budget.trailingRemaining
            if (capacity > 0f) index to capacity else null
        }.toMap()

    fun consumeTrailingByCluster(consumptionByCluster: Map<Int, Float>): PunctuationGeometryLedger =
        copy(
            budgets = budgets.consume(consumptionByCluster) { budget, amount ->
                budget.copy(
                    trailingConsumed = (budget.trailingConsumed + amount)
                        .coerceAtMost(budget.trailingNatural),
                )
            },
        )

    fun addJustificationDeltas(deltaByCluster: Map<Int, Float>): PunctuationGeometryLedger =
        copy(justificationDeltaByCluster = deltaByCluster)

    fun consumeLineEdgeGlue(lines: List<LineCandidate>): LineEdgeTrimResult {
        if (lines.isEmpty() || budgets.isEmpty()) {
            return LineEdgeTrimResult(this, emptyList())
        }

        val decisions = mutableListOf<LineEdgeTrimDecisionInfo>()
        val leadingConsumptionByCluster = HashMap<Int, Float>()
        val trailingConsumptionByCluster = HashMap<Int, Float>()
        lines.forEach { line ->
            val lastIdx = line.clusterRange.last
            budgets[lastIdx]?.let { budget ->
                val remaining = budget.trailingRemaining
                if (remaining > 0f) {
                    trailingConsumptionByCluster.merge(lastIdx, remaining) { a, b -> a + b }
                    decisions += LineEdgeTrimDecisionInfo(
                        lineRange = line.sourceRange,
                        clusterRange = naturalClusters[lastIdx].range,
                        side = "trailing",
                        trimAmount = remaining,
                        consumedBefore = budget.trailingConsumed,
                        naturalGlue = budget.trailingNatural,
                        reason = "LineEndHalfWidthPunctuation",
                    )
                }
            }

            val firstIdx = line.clusterRange.first
            budgets[firstIdx]?.let { budget ->
                val remaining = budget.leadingRemaining
                if (remaining > 0f) {
                    leadingConsumptionByCluster.merge(firstIdx, remaining) { a, b -> a + b }
                    decisions += LineEdgeTrimDecisionInfo(
                        lineRange = line.sourceRange,
                        clusterRange = naturalClusters[firstIdx].range,
                        side = "leading",
                        trimAmount = remaining,
                        consumedBefore = budget.leadingConsumed,
                        naturalGlue = budget.leadingNatural,
                        reason = "LineStartHalfWidthPunctuation",
                    )
                }
            }
        }

        val updated = copy(
            budgets = budgets
                .consume(leadingConsumptionByCluster) { budget, amount ->
                    budget.copy(
                        leadingConsumed = (budget.leadingConsumed + amount)
                            .coerceAtMost(budget.leadingNatural),
                    )
                }
                .consume(trailingConsumptionByCluster) { budget, amount ->
                    budget.copy(
                        trailingConsumed = (budget.trailingConsumed + amount)
                            .coerceAtMost(budget.trailingNatural),
                    )
                },
        )
        return LineEdgeTrimResult(updated, decisions)
    }

    fun toDecisionInfo(): List<ClusterGeometryDecisionInfo> =
        geometries.map { (index, geometry) ->
            val budget = budgets.getValue(index)
            val delta = justificationDeltaByCluster[index] ?: 0f
            ClusterGeometryDecisionInfo(
                range = geometry.range,
                sourceText = geometry.sourceText,
                displayText = geometry.displayText,
                baseAdvance = geometry.baseAdvance,
                bodyWidth = geometry.bodyWidth,
                leadingGlueNatural = budget.leadingNatural,
                leadingGlueConsumed = budget.leadingConsumed,
                trailingGlueNatural = budget.trailingNatural,
                trailingGlueConsumed = budget.trailingConsumed,
                justificationDelta = delta,
                resolvedAdvance = resolvedAdvance(index, naturalClusters[index]),
                source = "PunctuationGeometryLedger",
                reason = geometry.reason,
            )
        }

    private fun consumeSpacing(
        spacingPlan: PunctuationSpacingCompressionResult,
    ): PunctuationGeometryLedger =
        copy(
            budgets = budgets.consumeByRange(
                clusters = naturalClusters,
                adjustments = spacingPlan.adjustments,
            ),
        )

    private fun resolvedAdvance(index: Int, cluster: Cluster): Float {
        val geometry = geometries[index] ?: run {
            val delta = justificationDeltaByCluster[index] ?: 0f
            return (cluster.advance + delta).coerceAtLeast(0f)
        }
        val budget = budgets[index]
            ?: return (geometry.bodyWidth + (justificationDeltaByCluster[index] ?: 0f)).coerceAtLeast(0f)
        val delta = justificationDeltaByCluster[index] ?: 0f
        return (
            geometry.bodyWidth +
                budget.leadingRemaining +
                budget.trailingRemaining +
                delta
            ).coerceAtLeast(0f)
    }
}

private data class PunctuationClusterGeometry(
    val range: TextRange,
    val sourceText: String,
    val displayText: String,
    val baseAdvance: Float,
    val bodyWidth: Float,
    val leadingGlueNatural: Float,
    val trailingGlueNatural: Float,
    val reason: String,
)

private data class GlueBudget(
    val leadingNatural: Float,
    val leadingConsumed: Float,
    val trailingNatural: Float,
    val trailingConsumed: Float,
) {
    val leadingRemaining: Float get() = (leadingNatural - leadingConsumed).coerceAtLeast(0f)
    val trailingRemaining: Float get() = (trailingNatural - trailingConsumed).coerceAtLeast(0f)
}

private data class LineEdgeTrimResult(
    val geometry: PunctuationGeometryLedger,
    val decisions: List<LineEdgeTrimDecisionInfo>,
)

private fun Map<Int, GlueBudget>.consume(
    consumptionByCluster: Map<Int, Float>,
    apply: (GlueBudget, Float) -> GlueBudget,
): Map<Int, GlueBudget> {
    if (consumptionByCluster.isEmpty()) return this

    return toMutableMap().also { updated ->
        consumptionByCluster.forEach { (index, amount) ->
            if (amount <= 0f) return@forEach
            updated[index]?.let { budget -> updated[index] = apply(budget, amount) }
        }
    }
}

private fun Map<Int, GlueBudget>.consumeByRange(
    clusters: List<Cluster>,
    adjustments: List<PunctuationSpacingAdjustment>,
): Map<Int, GlueBudget> {
    if (adjustments.isEmpty()) return this

    return toMutableMap().also { updated ->
        adjustments.forEach { adjustment ->
            val targetIdx = clusters.indexOfFirst { adjustment.reductionTargetRange.isInside(it.range) }
            if (targetIdx < 0) return@forEach
            updated[targetIdx]?.let { current ->
                // Consume reduction from whichever side has remaining capacity.
                // With class-based single-sided glue, all glue may be on one
                // side (e.g. PauseOrStop → trailing only, Opening → leading only).
                val leadingRemaining = current.leadingNatural - current.leadingConsumed
                val trailingRemaining = current.trailingNatural - current.trailingConsumed
                updated[targetIdx] = if (trailingRemaining >= leadingRemaining) {
                    current.copy(
                        trailingConsumed = (current.trailingConsumed + adjustment.reduction)
                            .coerceAtMost(current.trailingNatural),
                    )
                } else {
                    current.copy(
                        leadingConsumed = (current.leadingConsumed + adjustment.reduction)
                            .coerceAtMost(current.leadingNatural),
                    )
                }
            }
        }
    }
}

private fun TextRange.isInside(other: TextRange): Boolean =
    start >= other.start && end <= other.end
