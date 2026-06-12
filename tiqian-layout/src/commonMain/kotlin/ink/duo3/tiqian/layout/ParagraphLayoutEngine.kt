package ink.duo3.tiqian.layout

import ink.duo3.tiqian.clreq.AutoSpaceMode
import ink.duo3.tiqian.clreq.AutoSpacePolicy
import ink.duo3.tiqian.clreq.BuiltInClreqProfileResolver
import ink.duo3.tiqian.clreq.ClreqProfile
import ink.duo3.tiqian.clreq.ClreqProfileResolver
import ink.duo3.tiqian.clreq.LineEndPunctuationStyle
import ink.duo3.tiqian.clreq.PunctuationClass
import ink.duo3.tiqian.clreq.PunctuationGluePlacement
import ink.duo3.tiqian.clreq.ClreqPunctuationGlyphSubstitutor
import ink.duo3.tiqian.core.AutoSpaceDecisionInfo
import ink.duo3.tiqian.core.Cluster
import ink.duo3.tiqian.core.ClusterGeometryDecisionInfo
import ink.duo3.tiqian.core.DecorationDecisionInfo
import ink.duo3.tiqian.core.DecorationKind
import ink.duo3.tiqian.core.DecorationSegmentInfo
import ink.duo3.tiqian.core.DecorationSpan
import ink.duo3.tiqian.core.FontDecisionInfo
import ink.duo3.tiqian.core.LineEdgeTrimDecisionInfo
import ink.duo3.tiqian.core.Glyph
import ink.duo3.tiqian.core.GlyphRun
import ink.duo3.tiqian.core.JustificationAllocationInfo
import ink.duo3.tiqian.core.JustificationDecisionInfo
import ink.duo3.tiqian.core.LayoutDebugInfo
import ink.duo3.tiqian.core.LayoutInput
import ink.duo3.tiqian.core.LayoutResult
import ink.duo3.tiqian.core.LineBox
import ink.duo3.tiqian.core.LineDebugInfo
import ink.duo3.tiqian.core.LineDecisionInfo
import ink.duo3.tiqian.core.LineRepairAllocationInfo
import ink.duo3.tiqian.core.LineRepairCandidateInfo
import ink.duo3.tiqian.core.LineRepairDecisionInfo
import ink.duo3.tiqian.core.MetricDecisionInfo
import ink.duo3.tiqian.core.PunctuationDecisionInfo
import ink.duo3.tiqian.core.Rect
import ink.duo3.tiqian.core.RoleOverrideInfo
import ink.duo3.tiqian.core.Size
import ink.duo3.tiqian.core.SpacingDecisionInfo
import ink.duo3.tiqian.core.LastLineAlignment
import ink.duo3.tiqian.core.TextRange
import ink.duo3.tiqian.font.CjkFontRoleClassifier
import ink.duo3.tiqian.font.FallbackResolver
import ink.duo3.tiqian.font.FontMetricsNormalizationInput
import ink.duo3.tiqian.font.FontMetricsNormalizer
import ink.duo3.tiqian.font.FontMetricsRequest
import ink.duo3.tiqian.font.FontMetricsResolver
import ink.duo3.tiqian.font.FontDecision
import ink.duo3.tiqian.font.FontRequest
import ink.duo3.tiqian.font.FontRole
import ink.duo3.tiqian.font.FontRoleClassifier
import ink.duo3.tiqian.font.FontRoleContext
import ink.duo3.tiqian.font.LayoutFontMetrics
import ink.duo3.tiqian.font.PreferCjkForAmbiguousPunctuationResolver
import ink.duo3.tiqian.font.RawFontMetrics
import ink.duo3.tiqian.font.ScriptAwareFontMetricsNormalizer
import ink.duo3.tiqian.font.StubFontMetricsResolver
import ink.duo3.tiqian.shaping.ExplainableStubTextShaper
import ink.duo3.tiqian.shaping.ShapingInput
import ink.duo3.tiqian.shaping.TextShaper

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

        // SubstitutionRollbackOnMissingGlyph: a CLREQ display substitution
        // (ADR 0003, e.g. `——` → `⸺`) is only an improvement if the resolved
        // font actually covers the substituted codepoint — `⸺` U+2E3A is
        // absent from PingFang SC / Hiragino / Heiti and would render tofu.
        // When the shaper reports .notdef glyphs for a substituted cluster,
        // re-shape with the source text and record the rollback.
        val substitutionRollbackRanges = mutableSetOf<TextRange>()
        // LatinWordSegmentation (gap audit 缺口 2): Latin runs are shaped per
        // word/space segment so each word and each space run becomes its own
        // cluster — line breaks happen at word boundaries, word spaces become
        // first-class adjustable clusters (CLREQ 西文词距). Cross-segment
        // kerning at a space boundary is negligible.
        val shapingResults = fontDecisions.flatMap { decision ->
            decision.shapingSegments(text).map { segmentRange ->
                val sourceText = text.substring(segmentRange.start, segmentRange.end)
                val substitution = punctuationGlyphSubstitutor.substitute(sourceText)
                val shaped = textShaper.shape(
                    ShapingInput(
                        text = text,
                        range = segmentRange,
                        style = input.textStyle,
                        fontDecision = decision,
                        displayText = substitution.displayText,
                    ),
                )
                if (substitution.displayText == sourceText || shaped.decisions.none { it.missingGlyphs > 0 }) {
                    shaped
                } else {
                    substitutionRollbackRanges += segmentRange
                    textShaper.shape(
                        ShapingInput(
                            text = text,
                            range = segmentRange,
                            style = input.textStyle,
                            fontDecision = decision,
                            displayText = sourceText,
                        ),
                    )
                }
            }
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
        // CLREQ 挤压处理优先顺序 (ADR 0020): tiered shrink resources for
        // PushIn. Punctuation classes map to tiers; style knobs gate the
        // inline-stop and sino-western tiers.
        val adjustmentStyle = clreqProfile.adjustment
        val glueCaps = baseGeometry.glueCapacities()
        val gapClusterRanges = autoSpaceDecisions
            .filter { it.side == "gap" }
            .map { it.clusterRange }
            .toSet()
        val atomClassByRange = punctuationAtoms.associate { it.range to it.punctuationClass }
        val shrinkOpportunities = buildList {
            naturalClusters.forEachIndexed { idx, cluster ->
                val caps = glueCaps[idx]
                if (caps != null) {
                    val cls = atomClassByRange[cluster.range]
                    when (cls) {
                        PunctuationClass.Interpunct,
                        PunctuationClass.MiddleDot,
                        -> {
                            val both = caps.leading + caps.trailing
                            if (both > 0f) {
                                add(ShrinkOpportunity(idx, tier = 3, capacity = both, channel = ShrinkChannel.LeadingAndTrailingGlue))
                            }
                        }

                        PunctuationClass.PauseOrStop -> {
                            val isStop = cluster.displayText.firstOrNull() in INLINE_STOPS
                            val tier = if (isStop) 4 else 6
                            // Knob off: 行内句问叹 keep full width — their glue
                            // is only reachable via the tier-1 line-end
                            // promotion (行末削半 is a separate rule).
                            val lineEndOnly = isStop && !adjustmentStyle.allowInlineStopCompression
                            if (caps.trailing > 0f) {
                                add(
                                    ShrinkOpportunity(
                                        idx,
                                        tier = tier,
                                        capacity = caps.trailing,
                                        channel = ShrinkChannel.TrailingGlue,
                                        lineEndOnly = lineEndOnly,
                                    ),
                                )
                            }
                        }

                        else -> if (caps.trailing > 0f) {
                            add(ShrinkOpportunity(idx, tier = 6, capacity = caps.trailing, channel = ShrinkChannel.TrailingGlue))
                        }
                    }
                } else if (cluster.isSpaceRun()) {
                    if (cluster.range in gapClusterRanges) {
                        if (adjustmentStyle.allowSinoWesternGapAdjustment && cluster.advance > 0f) {
                            add(ShrinkOpportunity(idx, tier = 5, capacity = cluster.advance, channel = ShrinkChannel.RawAdvance))
                        }
                    } else {
                        // Word space: min 1/4em (CLREQ 挤压第②档).
                        val capacity = cluster.advance - WORD_SPACE_MIN_EM * fontSize
                        if (capacity > 0f) {
                            add(ShrinkOpportunity(idx, tier = 2, capacity = capacity, channel = ShrinkChannel.RawAdvance))
                        }
                    }
                }
            }
        }

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
        // ParagraphFirstLineIndent (CLREQ 段首缩排): the first line's usable
        // measure shrinks by the indent; rendering shifts its start edge.
        val firstLineIndent = input.paragraphStyle.firstLineIndentEm.coerceAtLeast(0f) * fontSize
        val lineSolution = if (text.isEmpty()) {
            LineSolution(emptyList())
        } else {
            lineBreaker.breakLines(
                naturalClusters = naturalClusters,
                adjustedClusters = clusters,
                maxWidth = input.constraints.maxWidth,
                firstLineIndent = firstLineIndent,
                shrinkOpportunities = shrinkOpportunities,
                // MourningSpanKeptUnbroken: 示亡号 spans stay on one line
                // whenever they fit (ADR 0018).
                unbreakableRanges = input.decorations
                    .filter { it.kind == DecorationKind.Mourning }
                    .mapNotNull { span -> naturalClusters.clusterIndexRangeFor(span.range) },
            )
        }

        val clusterRoles = naturalClusters.map { cluster ->
            fontDecisions.first { cluster.range.isInside(it.range) }.role
        }
        val pushInAllocations = lineSolution.lines
            .mapNotNull { it.repair as? RepairOption.PushIn }
            .flatMap { it.allocations }
        val pushInTrailing = HashMap<Int, Float>()
        val pushInLeading = HashMap<Int, Float>()
        val pushInRawTrims = HashMap<Int, Float>()
        for (alloc in pushInAllocations) {
            when (alloc.channel) {
                ShrinkChannel.TrailingGlue ->
                    pushInTrailing.merge(alloc.clusterIndex, alloc.shrink) { a, b -> a + b }
                ShrinkChannel.LeadingAndTrailingGlue -> {
                    // CLREQ: 间隔号挤压必须同时从字面两侧、同等量处理.
                    pushInLeading.merge(alloc.clusterIndex, alloc.shrink / 2f) { a, b -> a + b }
                    pushInTrailing.merge(alloc.clusterIndex, alloc.shrink / 2f) { a, b -> a + b }
                }
                ShrinkChannel.RawAdvance ->
                    pushInRawTrims.merge(alloc.clusterIndex, alloc.shrink) { a, b -> a + b }
            }
        }
        val pushInGeometry = baseGeometry
            .consumeTrailingByCluster(pushInTrailing)
            .consumeLeadingByCluster(pushInLeading)
        val pushInClusters = pushInGeometry.resolveClusters()
        val edgeTrimResult = pushInGeometry.consumeLineEdgeGlue(
            lines = lineSolution.lines,
            forceLineEndHalfWidth = adjustmentStyle.lineEndPunctuation ==
                LineEndPunctuationStyle.ForceHalfWidth,
        )
        // TextAutoSpaceLineEdgeTrim: the autospace replacement gap lives in
        // the Latin cluster's advance, not in punctuation glue, so the edge
        // trim above can't see it. A typed-space boundary gap landing on a
        // line edge must disappear like any other line-edge blank — without
        // this, justified lines stop one gap short of the right edge.
        val autoSpaceGap = clreqProfile.autoSpace.gapEm * fontSize
        val autoSpaceEdgeTrims = HashMap<Int, Float>()
        val autoSpaceEdgeDecisions = mutableListOf<LineEdgeTrimDecisionInfo>()
        lineSolution.lines.forEach { line ->
            fun trimEdge(clusterIdx: Int, side: String) {
                val decision = autoSpaceDecisions.firstOrNull {
                    it.clusterRange == naturalClusters[clusterIdx].range && it.side == side
                } ?: return
                autoSpaceEdgeTrims.merge(clusterIdx, autoSpaceGap) { a, b -> a + b }
                autoSpaceEdgeDecisions += LineEdgeTrimDecisionInfo(
                    lineRange = line.sourceRange,
                    clusterRange = decision.clusterRange,
                    side = side,
                    trimAmount = autoSpaceGap,
                    consumedBefore = 0f,
                    naturalGlue = autoSpaceGap,
                    reason = "TextAutoSpaceLineEdgeTrim",
                )
            }
            trimEdge(line.clusterRange.last, "trailing")
            trimEdge(line.clusterRange.first, "leading")

            // LineEdgeWordSpaceCollapse: a space-run cluster landing on a
            // line edge collapses entirely (CSS-like line-edge space
            // removal; also CLREQ — no sino-western gap at line edges).
            fun collapseEdgeSpace(clusterIdx: Int, side: String) {
                val cluster = naturalClusters[clusterIdx]
                if (!cluster.isSpaceRun()) return
                val advance = naturalClusters[clusterIdx].advance
                if (advance <= 0f) return
                autoSpaceEdgeTrims.merge(clusterIdx, advance) { a, b -> a + b }
                autoSpaceEdgeDecisions += LineEdgeTrimDecisionInfo(
                    lineRange = line.sourceRange,
                    clusterRange = cluster.range,
                    side = side,
                    trimAmount = advance,
                    consumedBefore = 0f,
                    naturalGlue = advance,
                    reason = "LineEdgeWordSpaceCollapse",
                )
            }
            collapseEdgeSpace(line.clusterRange.last, "trailing")
            collapseEdgeSpace(line.clusterRange.first, "leading")
        }
        val rawTrims = HashMap<Int, Float>(autoSpaceEdgeTrims)
        pushInRawTrims.forEach { (idx, amount) -> rawTrims.merge(idx, amount) { a, b -> a + b } }
        val trimmedGeometry = edgeTrimResult.geometry.withRawEdgeTrims(rawTrims)
        val trimmedClusters = trimmedGeometry.resolveClusters()
        val edgeTrimDecisions = edgeTrimResult.decisions + autoSpaceEdgeDecisions

        // CLREQ:「中文排版特别是书籍正文排版极少使用左齐右不齐，原则上
        // 应该进行两端对齐」— justification is the baseline, not an option:
        // every non-last line goes through the justify chain. The last line
        // is positioned by ParagraphStyle.lastLineAlignment instead.
        val justificationPlans: List<JustificationPlan?> = lineSolution.lines.mapIndexed { lineIndex, lineCandidate ->
            val isLast = lineIndex == lineSolution.lines.lastIndex
            if (isLast) {
                null
            } else {
                justifier.justify(
                    adjustedClusters = trimmedClusters,
                    clusterRoles = clusterRoles,
                    lineClusterRange = lineCandidate.clusterRange,
                    maxWidth = if (lineCandidate.clusterRange.first == 0) {
                        input.constraints.maxWidth - firstLineIndent
                    } else {
                        input.constraints.maxWidth
                    },
                    fontSize = fontSize,
                    skip = false,
                    allowSinoWesternGapStretch = adjustmentStyle.allowSinoWesternGapAdjustment,
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
            val baseIndent = if (lineCandidate.clusterRange.first == 0) firstLineIndent else 0f
            // LastLineAlignment: the last line is the paragraph's only
            // alignment degree of freedom (CLREQ 双齐 baseline). Center/End
            // express as an extra start-edge inset within the line's usable
            // measure — renderers and decoration geometry consume
            // LineBox.indent unchanged.
            val isLast = lineIndex == lineSolution.lines.lastIndex
            val limit = input.constraints.maxWidth - baseIndent
            val alignmentInset = if (!isLast) {
                0f
            } else {
                when (input.paragraphStyle.lastLineAlignment) {
                    LastLineAlignment.Start -> 0f
                    LastLineAlignment.Center -> ((limit - visualWidth) / 2f).coerceAtLeast(0f)
                    LastLineAlignment.End -> (limit - visualWidth).coerceAtLeast(0f)
                }
            }
            LineBox(
                range = lineCandidate.sourceRange,
                baseline = lineMetrics.baseline + lineIndex * lineMetrics.height,
                top = lineIndex * lineMetrics.height,
                bottom = (lineIndex + 1) * lineMetrics.height,
                naturalWidth = lineCandidate.naturalWidth,
                adjustedWidth = adjustedWidth,
                visualWidth = visualWidth,
                indent = baseIndent + alignmentInset,
                debug = LineDebugInfo(
                    repair = lineCandidate.repair?.let { "${it::class.simpleName}:${it.reason}" },
                    notes = listOf(
                        "line:${lineIndex}:clusters=${lineCandidate.clusterRange.first}-${lineCandidate.clusterRange.last}",
                        "natural=${lineCandidate.naturalWidth},adjusted=${lineCandidate.adjustedWidth},visual=$visualWidth",
                    ),
                ),
            )
        }
        val decorationDecisions = computeDecorationDecisions(
            decorations = input.decorations,
            lineRanges = lineSolution.lines.map { it.clusterRange },
            lineBoxes = lines,
            finalClusters = finalClusters,
            clusterRoles = clusterRoles,
            justifyDeltaByCluster = justifyDeltaByCluster,
            fontSize = fontSize,
        )
        val decorationSegments = computeDecorationSegments(
            decorations = input.decorations,
            lineRanges = lineSolution.lines.map { it.clusterRange },
            lineBoxes = lines,
            finalClusters = finalClusters,
            justifyDeltaByCluster = justifyDeltaByCluster,
            fontSize = fontSize,
        )

        val widestLine = lines.maxOfOrNull { it.indent + it.visualWidth } ?: 0f
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
                    val rolledBack = substitutionRollbackRanges.any { it.isInside(decision.range) }
                    FontDecisionInfo(
                        range = decision.range,
                        sourceText = clusterText,
                        displayText = if (rolledBack) clusterText else substitution.displayText,
                        role = decision.role.name,
                        fontKey = decision.candidate.key,
                        reason = decision.reason,
                        substitutionReason = if (rolledBack) {
                            "${substitution.reason}:SubstitutionRollbackOnMissingGlyph"
                        } else {
                            substitution.reason
                        },
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
                        inkBoundsFallback = atom.inkBoundsFallback,
                        haltAdvance = atom.haltAdvance,
                        haltValidation = atom.haltValidation,
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
                decorationDecisions = decorationDecisions,
                decorationSegments = decorationSegments,
            ),
        )
    }

    /**
     * Named heuristic: `EmphasisDotOnHanText` (ADR 0018, CLREQ 着重号).
     *
     * Resolves decoration spans into per-cluster dot anchors AFTER all
     * geometry is final — decorations never feed back into metrics, breaks
     * or justification. Per CLREQ, only Han text carries a dot: punctuation
     * inside the span is skipped (`clreq-no-dot-on-punctuation`), and
     * non-Han clusters are skipped (`no-dot-on-non-han`; western emphasis
     * is italics, out of scope).
     *
     * Anchor = the point the dot INK CENTRE must land on: x is the glyph
     * centre (final position minus the trailing justification delta), y is
     * `baseline + EMPHASIS_DOT_CENTER_EM·em`. The drop is baseline-relative,
     * NOT em-box-relative: CenteredCjkVisual gives the em box an artificial
     * 0.5em descent while real Han ink ends ≈0.1em below the baseline — an
     * em-box-relative drop landed the dots inside the NEXT line's ink.
     * 0.35em tucks the dot snugly under the character (≈2px clearance at
     * 16px) and clears the next line even at lineHeight 1.0. Renderers
     * measure their dot glyph's ink and align its centre here, so font
     * differences stay in the render layer.
     */
    private fun computeDecorationDecisions(
        decorations: List<DecorationSpan>,
        lineRanges: List<IntRange>,
        lineBoxes: List<LineBox>,
        finalClusters: List<Cluster>,
        clusterRoles: List<FontRole>,
        justifyDeltaByCluster: Map<Int, Float>,
        fontSize: Float,
    ): List<DecorationDecisionInfo> {
        if (decorations.isEmpty()) return emptyList()

        val decisions = mutableListOf<DecorationDecisionInfo>()
        for (span in decorations) {
            if (span.kind != DecorationKind.Emphasis) continue
            lineRanges.forEachIndexed { lineIndex, clusterRange ->
                var x = lineBoxes[lineIndex].indent
                for (idx in clusterRange) {
                    val cluster = finalClusters[idx]
                    val coveredBySpan = cluster.range.start >= span.range.start &&
                        cluster.range.end <= span.range.end
                    if (coveredBySpan) {
                        val role = clusterRoles[idx]
                        val applied = role == FontRole.CjkText
                        val glyphAdvance = cluster.advance - (justifyDeltaByCluster[idx] ?: 0f)
                        decisions += DecorationDecisionInfo(
                            clusterRange = cluster.range,
                            sourceText = cluster.text,
                            kind = span.kind.name,
                            applied = applied,
                            reason = when {
                                applied -> "EmphasisDotOnHanText"
                                role == FontRole.CjkPunctuation -> "clreq-no-dot-on-punctuation"
                                else -> "no-dot-on-non-han"
                            },
                            anchorX = x + glyphAdvance / 2f,
                            anchorY = lineBoxes[lineIndex].baseline + fontSize * EMPHASIS_DOT_CENTER_EM,
                        )
                    }
                    x += cluster.advance
                }
            }
        }
        return decisions
    }

    /**
     * 示亡号 frame geometry (ADR 0018). One rectangle per line the span
     * touches. Vertical bounds are the conventional CJK CHARACTER FACE
     * (字面): `baseline - 0.88em .. baseline + 0.12em`, hugging the face
     * with NO margin. Neither layout em box (artificial 0.5/0.5 split that
     * real ink overflows), nor raw line metrics (include inter-line air),
     * nor per-glyph ink (varies with glyph shape — `一` would collapse the
     * frame and break uniformity across a name list) describe the face;
     * the 0.88/0.12 split encodes the standard CJK design box. Replacing
     * it with font-reported ideographic metrics (BASE table) is follow-up.
     * `openStart`/`openEnd` mark continuation edges when the span had to
     * split across lines (only when wider than the measure —
     * `MourningSpanKeptUnbroken` otherwise prevents the split at break
     * time).
     */
    private fun computeDecorationSegments(
        decorations: List<DecorationSpan>,
        lineRanges: List<IntRange>,
        lineBoxes: List<LineBox>,
        finalClusters: List<Cluster>,
        justifyDeltaByCluster: Map<Int, Float>,
        fontSize: Float,
    ): List<DecorationSegmentInfo> {
        val mourningSpans = decorations.filter { it.kind == DecorationKind.Mourning }
        if (mourningSpans.isEmpty()) return emptyList()

        val segments = mutableListOf<DecorationSegmentInfo>()
        for (span in mourningSpans) {
            val spanSegments = mutableListOf<DecorationSegmentInfo>()
            lineRanges.forEachIndexed { lineIndex, clusterRange ->
                var x = lineBoxes[lineIndex].indent
                var left: Float? = null
                var right = 0f
                var segStart = -1
                var segEnd = -1
                for (idx in clusterRange) {
                    val cluster = finalClusters[idx]
                    val covered = cluster.range.start >= span.range.start &&
                        cluster.range.end <= span.range.end
                    if (covered) {
                        if (left == null) {
                            left = x
                            segStart = cluster.range.start
                        }
                        right = x + cluster.advance - (justifyDeltaByCluster[idx] ?: 0f)
                        segEnd = cluster.range.end
                    }
                    x += cluster.advance
                }
                val leftEdge = left ?: return@forEachIndexed
                val baseline = lineBoxes[lineIndex].baseline
                spanSegments += DecorationSegmentInfo(
                    sourceRange = TextRange(segStart, segEnd),
                    kind = span.kind.name,
                    lineIndex = lineIndex,
                    left = leftEdge,
                    top = baseline - fontSize * MOURNING_FRAME_FACE_ASCENT_EM,
                    right = right,
                    bottom = baseline + fontSize * MOURNING_FRAME_FACE_DESCENT_EM,
                    openStart = segStart > span.range.start,
                    openEnd = segEnd < span.range.end,
                    reason = "",
                )
            }
            val reason = if (spanSegments.size <= 1) {
                "MourningSpanKeptUnbroken"
            } else {
                "mourning-span-split-across-lines"
            }
            segments += spanSegments.map { it.copy(reason = reason) }
        }
        return segments
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

    /**
     * Named heuristic: `MissingInkBoundsFallback` (recording side).
     *
     * Returns null only when no shaping information exists at all — the
     * expected pure-policy path. When shaping ran but ink cannot be
     * attributed, this returns a [PunctuationInkInput] carrying a
     * `boundsFallbackReason` so the punctuation decision records *why*
     * geometry degraded instead of silently looking like the policy path.
     */
    private fun Cluster.punctuationInkInputFor(displayIndex: Int, shapedGlyphs: List<Glyph>): PunctuationInkInput? {
        if (shapedGlyphs.isEmpty()) return null
        val glyph = when {
            shapedGlyphs.size == displayText.length -> shapedGlyphs.getOrNull(displayIndex)
            displayText.length == 1 -> shapedGlyphs.unionAsSingleGlyph()
            else -> null
        } ?: return PunctuationInkInput(
            // Glyph count does not line up with display characters, so per-
            // character advance/ink cannot be attributed. Advance 0 keeps the
            // builder on the policy advance; only the reason is recorded.
            advance = 0f,
            inkBounds = null,
            boundsFallbackReason = "glyph-cluster-mapping-ambiguous",
        )
        return PunctuationInkInput(
            advance = glyph.advance,
            inkBounds = glyph.bounds,
            boundsFallbackReason = if (glyph.bounds == null) "shaper-no-ink-bounds" else null,
            haltAdvance = glyph.haltAdvance,
            haltPlacementX = glyph.haltPlacementX,
        )
    }

    private fun List<Glyph>.unionAsSingleGlyph(): Glyph? {
        if (isEmpty()) return null
        val first = first()
        val bounds = mapNotNull { it.bounds }
        if (bounds.isEmpty()) return first
        return first.copy(
            advance = sumOf { it.advance.toDouble() }.toFloat(),
            // halt metrics are per-glyph; a union pseudo-glyph has none.
            haltAdvance = null,
            haltPlacementX = null,
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

    /**
     * Named heuristic: `LatinWordSegmentation`. A LatinText font decision is
     * shaped per alternating word / space-run segment; every other role
     * shapes as one segment. Spaces become standalone clusters: break
     * opportunities, sino-western gaps (when CJK-adjacent) or stretchable
     * word spaces (when between two Latin words).
     */
    private fun FontDecision.shapingSegments(text: String): List<TextRange> {
        if (role != FontRole.LatinText) return listOf(range)
        val segments = mutableListOf<TextRange>()
        var segStart = range.start
        var inSpace = text[range.start] == ' '
        for (i in (range.start + 1) until range.end) {
            val isSpace = text[i] == ' '
            if (isSpace != inSpace) {
                segments += TextRange(segStart, i)
                segStart = i
                inSpace = isSpace
            }
        }
        segments += TextRange(segStart, range.end)
        return segments
    }

    private fun Cluster.isSpaceRun(): Boolean =
        text.isNotEmpty() && text.all { it == ' ' }

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
     * Applies `AutoSpacePolicy` to (word-segmented) natural clusters.
     *
     * Post `LatinWordSegmentation`, U+0020 runs are standalone clusters and
     * the model is per-cluster (CSS Text 4 + ADR 0009; CLREQ:「原则上，汉字
     * 与西文字母、数字间使用不多于四分之一个汉字宽的字距或空白」):
     *
     * - **space-run cluster with a CjkText neighbour** — the cluster IS the
     *   sino-western gap: its advance normalises to `gapEm`
     *   (`TextAutoSpaceReplace`, decision side="gap"; renderers need no
     *   offsets, the cluster width is the gap).
     * - **space-run cluster between two Latin words** — a word space
     *   (CLREQ 西文词距): untouched here; justification stretches it.
     * - **word cluster directly adjacent to CjkText** (no space cluster in
     *   between) — `TextAutoSpaceInsert`: the gap is added into the word
     *   cluster's advance on that side; renderers offset glyphs by the
     *   recorded side decision. Only under [AutoSpaceMode.Insert];
     *   [AutoSpaceMode.Replace] keeps the conservative behaviour.
     *
     * Punctuation neighbours never produce a gap (their spacing is the
     * punctuation glue model's job).
     */
    private fun List<Cluster>.applyAutoSpacePolicy(
        fontDecisions: List<FontDecision>,
        policy: AutoSpacePolicy,
        fontSize: Float,
    ): AutoSpaceApplicationResult {
        if (isEmpty()) return AutoSpaceApplicationResult(emptyList(), emptyList())

        val roles = map { cluster -> fontDecisions.firstOrNull { cluster.range.isInside(it.range) }?.role }
        val decisions = mutableListOf<AutoSpaceDecisionInfo>()
        val gap = policy.gapEm * fontSize
        val mode = policy.cjkLatin

        val updated = mapIndexed { idx, cluster ->
            if (roles[idx] != FontRole.LatinText) return@mapIndexed cluster
            if (mode == AutoSpaceMode.Disabled) return@mapIndexed cluster
            val prevRole = if (idx > 0) roles[idx - 1] else null
            val nextRole = if (idx < lastIndex) roles[idx + 1] else null

            if (cluster.isSpaceRun()) {
                val cjkAdjacent = prevRole == FontRole.CjkText || nextRole == FontRole.CjkText
                if (!cjkAdjacent) return@mapIndexed cluster
                val reduction = cluster.advance - gap
                if (reduction == 0f) return@mapIndexed cluster
                decisions += AutoSpaceDecisionInfo(
                    clusterRange = cluster.range,
                    side = "gap",
                    boundaryRole = FontRole.CjkText.name,
                    mode = AutoSpaceMode.Replace.name,
                    charactersAffected = cluster.text.length,
                    reductionPerChar = reduction / cluster.text.length,
                    totalReduction = reduction,
                    reason = "TextAutoSpaceReplace:space-cluster-to-gap",
                )
                cluster.copy(advance = gap)
            } else {
                if (mode != AutoSpaceMode.Insert) return@mapIndexed cluster
                var added = 0f
                if (prevRole == FontRole.CjkText) {
                    added += gap
                    decisions += AutoSpaceDecisionInfo(
                        clusterRange = cluster.range,
                        side = "leading",
                        boundaryRole = FontRole.CjkText.name,
                        mode = mode.name,
                        charactersAffected = 0,
                        reductionPerChar = 0f,
                        totalReduction = -gap,
                        reason = "TextAutoSpaceInsert:ideograph-alpha:quarter-em",
                    )
                }
                if (nextRole == FontRole.CjkText) {
                    added += gap
                    decisions += AutoSpaceDecisionInfo(
                        clusterRange = cluster.range,
                        side = "trailing",
                        boundaryRole = FontRole.CjkText.name,
                        mode = mode.name,
                        charactersAffected = 0,
                        reductionPerChar = 0f,
                        totalReduction = -gap,
                        reason = "TextAutoSpaceInsert:ideograph-alpha:quarter-em",
                    )
                }
                if (added == 0f) cluster else cluster.copy(advance = cluster.advance + added)
            }
        }
        return AutoSpaceApplicationResult(updated, decisions)
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
                targetClusterIndex = offenderClusterIndex,
                shrink = totalShrink,
                availableCapacity = totalAvailableCapacity,
                pushInAllocations = allocations.map { alloc ->
                    LineRepairAllocationInfo(
                        clusterRange = clusters[alloc.clusterIndex].range,
                        shrink = alloc.shrink,
                        availableCapacity = alloc.availableCapacity,
                    )
                },
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
    /**
     * Raw advance reductions that are NOT punctuation glue — currently only
     * `TextAutoSpaceLineEdgeTrim` (the autospace replacement gap baked into a
     * Latin cluster's advance, removed again when the boundary lands on a
     * line edge). Applied unconditionally in [resolvedAdvance].
     */
    private val rawEdgeTrimByCluster: Map<Int, Float> = emptyMap(),
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

    fun consumeTrailingByCluster(consumptionByCluster: Map<Int, Float>): PunctuationGeometryLedger =
        copy(
            budgets = budgets.consume(consumptionByCluster) { budget, amount ->
                budget.copy(
                    trailingConsumed = (budget.trailingConsumed + amount)
                        .coerceAtMost(budget.trailingNatural),
                )
            },
        )

    fun consumeLeadingByCluster(consumptionByCluster: Map<Int, Float>): PunctuationGeometryLedger =
        copy(
            budgets = budgets.consume(consumptionByCluster) { budget, amount ->
                budget.copy(
                    leadingConsumed = (budget.leadingConsumed + amount)
                        .coerceAtMost(budget.leadingNatural),
                )
            },
        )

    /** Remaining leading/trailing glue per punctuation cluster index. */
    fun glueCapacities(): Map<Int, GlueCapacity> =
        budgets.mapNotNull { (index, budget) ->
            val leading = budget.leadingRemaining
            val trailing = budget.trailingRemaining
            if (leading > 0f || trailing > 0f) index to GlueCapacity(leading, trailing) else null
        }.toMap()

    fun addJustificationDeltas(deltaByCluster: Map<Int, Float>): PunctuationGeometryLedger =
        copy(justificationDeltaByCluster = deltaByCluster)

    fun withRawEdgeTrims(trimByCluster: Map<Int, Float>): PunctuationGeometryLedger =
        if (trimByCluster.isEmpty()) this else copy(rawEdgeTrimByCluster = trimByCluster)

    fun consumeLineEdgeGlue(
        lines: List<LineCandidate>,
        forceLineEndHalfWidth: Boolean = true,
    ): LineEdgeTrimResult {
        if (lines.isEmpty() || budgets.isEmpty()) {
            return LineEdgeTrimResult(this, emptyList())
        }

        val decisions = mutableListOf<LineEdgeTrimDecisionInfo>()
        val leadingConsumptionByCluster = HashMap<Int, Float>()
        val trailingConsumptionByCluster = HashMap<Int, Float>()
        lines.forEach { line ->
            val lastIdx = line.clusterRange.last
            // 宽松风格 (AllowFullWidth): the unconditional line-end half-width
            // trim is skipped; the blank was only available as on-demand
            // shrink capacity during PushIn.
            val trailingBudget = if (forceLineEndHalfWidth) budgets[lastIdx] else null
            trailingBudget?.let { budget ->
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
        val rawTrim = rawEdgeTrimByCluster[index] ?: 0f
        val geometry = geometries[index] ?: run {
            val delta = justificationDeltaByCluster[index] ?: 0f
            return (cluster.advance + delta - rawTrim).coerceAtLeast(0f)
        }
        val budget = budgets[index]
            ?: return (geometry.bodyWidth + (justificationDeltaByCluster[index] ?: 0f) - rawTrim).coerceAtLeast(0f)
        val delta = justificationDeltaByCluster[index] ?: 0f
        return (
            geometry.bodyWidth +
                budget.leadingRemaining +
                budget.trailingRemaining +
                delta -
                rawTrim
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

/** ADR 0018: dot ink centre sits this far below the BASELINE. */
private const val EMPHASIS_DOT_CENTER_EM = 0.35f

/** CLREQ 挤压第②档：西文词距最小压至四分之一汉字宽. */
private const val WORD_SPACE_MIN_EM = 0.25f

/** CLREQ 挤压第④档对象：「位于行内的句号、问号、感叹号」. */
private val INLINE_STOPS = setOf('。', '！', '？', '．')

/** Remaining glue per side, input to the tiered shrink model (ADR 0020). */
internal data class GlueCapacity(val leading: Float, val trailing: Float)

/**
 * ADR 0018: 示亡号 frame hugs the CJK character face (字面) with no margin.
 * The face spans baseline-0.88em..baseline+0.12em in conventional CJK
 * design; font-reported ideographic metrics are a follow-up.
 */
private const val MOURNING_FRAME_FACE_ASCENT_EM = 0.88f
private const val MOURNING_FRAME_FACE_DESCENT_EM = 0.12f

/**
 * Contiguous cluster-index range whose clusters are fully covered by
 * [sourceRange]; null when no cluster is covered.
 */
private fun List<Cluster>.clusterIndexRangeFor(sourceRange: TextRange): IntRange? {
    var first = -1
    var last = -1
    forEachIndexed { idx, cluster ->
        if (cluster.range.start >= sourceRange.start && cluster.range.end <= sourceRange.end) {
            if (first == -1) first = idx
            last = idx
        }
    }
    return if (first == -1) null else first..last
}

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
