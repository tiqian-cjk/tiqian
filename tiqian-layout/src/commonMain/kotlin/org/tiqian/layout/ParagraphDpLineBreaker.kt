package org.tiqian.layout

import org.tiqian.core.Cluster
import org.tiqian.core.LineEndReason

/**
 * ParagraphDpLineBreaker — paragraph-global line breaking over the ADR 0038
 * amortized-adjustment cost (ADR 0041).
 *
 * `ParagraphGlobalAmortizedOptimum`: [LookaheadLineBreaker] commits each break
 * after scoring a window-2 shift with a 2-line greedy rollout; compensation can
 * never propagate further than that horizon, so at narrow measures a tight spot
 * late in the paragraph ends up concentrated on one line (measured up to
 * ~16px/gap on the fixture corpus where the global optimum keeps every line
 * under ~2px/gap). This breaker instead solves the whole segment: nodes are
 * line starts, edges are candidate lines, and an exact DP over edges minimizes
 * the SAME per-line badness the lookahead scores — convex fill density +
 * neighbor-difference (ADR 0038), gapless raggedness, and
 * `SingleClusterLinePenalty` — so the cost model stays shared and explainable.
 *
 * Division of labour: the DP owns the break skeleton AND the push-in choice.
 * `CompressionAsDpEdge`: [applyFillPushIn]'s cascade is a per-boundary greedy
 * re-flow — layered on top of a globally planned skeleton it rewrites the plan
 * cluster by cluster and reintroduces the very trap the plan avoided (measured:
 * the fill cascade converted a 1.1-cost DP plan back into the lookahead's
 * 46-cost output at 240px). So this strategy does NOT run [withFillPushIn];
 * instead every candidate line may extend PAST the natural fit while the
 * overflow stays within the line's tiered shrink capacity (the exact
 * [tryPushIn] capacity model). Pricing follows the ADR 0041 修订 v2 model —
 * per-gap-class stretch densities mirroring the justifier's 中西-first fill,
 * compression at par with stretch and free of flat penalties
 * (`CompressionFirstFill`, CLREQ「先挤压、后拉伸」), and a natural-gated
 * neighbor term (`NaturalSetIsReference`) — see [edgeGeometry] and
 * [gatedNeighborCost]. At commit a compressed edge is realized through
 * [tryPushIn], so the recorded PushIn repair (tier order, 行末削半 promotion,
 * allocations) is byte-identical to what the fill pass would have recorded.
 *
 * The committed ends then walk the exact commit path the lookahead uses
 * (`adjustBreakForLineEnd` retreat recorded as CarryNext by [closeFilledLine],
 * MandatoryBreak binding) and [applyKinsokuRepairs] runs unchanged.
 *
 * Named heuristics:
 * - `KinsokuAvoidanceOverRepair`: candidate ends that would start the next
 *   line with a forbidden mark (行首禁则) or end this line on one (行尾禁则)
 *   are filtered out while legal alternatives exist — the DP routes around
 *   the conflict instead of relying on a repair. When no alternative exists
 *   the violating end is kept and the shared repair pass handles it.
 * - `SyntheticHyphenLastResortPenalty`: a flat demerit on every synthetic
 *   hyphen end keeps ADR 0029's whole-word-first contract under a cost-driven
 *   optimizer; [consecutiveSyntheticHyphenPenalty] additionally prices hyphen
 *   ladders via a run counter carried in the DP state (capped —
 *   `HyphenRunStateCap` — runs longer than the cap price like the cap).
 * - `MandatoryBreakBindsPreviousLine`: inside a segment that ends with an
 *   authored break, the position just before the break control is not a
 *   candidate, so the zero-width control always rides the preceding line.
 */
class ParagraphDpLineBreaker(
    private val candidateWindow: Int = 8,
    private val raggednessWeight: Float = 0.5f,
    private val kinsoku: KinsokuRule = ClreqKinsokuRule(),
    private val pushInPenalty: Int = 2,
    private val carryPreviousPenalty: Int = 10,
    private val leaveRaggedPenalty: Int = 20,
    private val syntheticHyphenBreakPenalty: Float = 12f,
    private val consecutiveSyntheticHyphenPenalty: Float = 12f,
    private val consecutiveStretchPenalty: Float = 3f,
) : LineBreaker {
    override val strategyName: String = "paragraph-dp"

    override fun breakLines(
        naturalClusters: List<Cluster>,
        adjustedClusters: List<Cluster>,
        maxWidth: Float,
        shrinkOpportunities: List<ShrinkOpportunity>,
        unbreakableRanges: List<IntRange>,
        firstLineIndent: Float,
        hangableClusters: Set<Int>,
        extendableHangRanges: List<IntRange>,
        forbiddenLineStartClusters: Set<Int>?,
        forbiddenLineEndClusters: Set<Int>,
        hyphenBreakClusters: Set<Int>,
        cjkInterCharBoundaries: Set<Int>,
        maxCjkStretchPerGap: Float,
        sinoWesternBoundaries: Set<Int>,
        sinoWesternStretchCap: Float,
        lineAdjustmentPushIn: Boolean,
        lineAdjustmentCompressBias: Float,
        hardBreakAfterClusters: Set<Int>,
        nonRenderingControlClusters: Set<Int>,
    ): LineSolution {
        if (adjustedClusters.isEmpty()) return LineSolution(emptyList())
        require(naturalClusters.size == adjustedClusters.size) {
            "naturalClusters and adjustedClusters must align cluster-for-cluster."
        }
        require(candidateWindow >= 0) { "candidateWindow must be non-negative." }

        val context = DpContext(
            naturalClusters = naturalClusters,
            adjustedClusters = adjustedClusters,
            maxWidth = maxWidth,
            shrinkOpportunities = shrinkOpportunities,
            unbreakableRanges = unbreakableRanges,
            firstLineIndent = firstLineIndent,
            forbiddenLineStartClusters = forbiddenLineStartClusters,
            forbiddenLineEndClusters = forbiddenLineEndClusters,
            hyphenBreakClusters = hyphenBreakClusters,
            cjkInterCharBoundaries = cjkInterCharBoundaries,
            maxCjkStretchPerGap = maxCjkStretchPerGap,
            sinoWesternBoundaries = sinoWesternBoundaries,
            sinoWesternStretchCap = sinoWesternStretchCap,
            nonRenderingControlClusters = nonRenderingControlClusters,
            gapBoundaries = cjkInterCharBoundaries + sinoWesternBoundaries,
            dRef = maxCjkStretchPerGap,
            allowCompressionEdges = lineAdjustmentPushIn,
        )

        // Segment by authored breaks; the DP never crosses them (ADR 0037).
        val committed = mutableListOf<LineCandidate>()
        val sortedBreaks = hardBreakAfterClusters.toIntArray().also { it.sort() }
        var breakCursor = 0
        var segmentStart = 0
        while (segmentStart < adjustedClusters.size) {
            while (breakCursor < sortedBreaks.size && sortedBreaks[breakCursor] < segmentStart) breakCursor += 1
            val mandatoryEnd = if (breakCursor < sortedBreaks.size) sortedBreaks[breakCursor] else null
            val segmentEndExclusive = mandatoryEnd?.plus(1) ?: adjustedClusters.size
            val ends = solveSegment(context, segmentStart, segmentEndExclusive, mandatoryEnd != null)
            commitSegment(
                committed, ends, segmentStart, mandatoryEnd, context, hardBreakAfterClusters,
            )
            segmentStart = segmentEndExclusive
        }

        // CompressionAsDpEdge: no withFillPushIn — push-in already happened as
        // DP edges with exact tryPushIn records. Kinsoku repairs still run for
        // the rare conflicts the candidate filter could not avoid.
        return applyKinsokuRepairs(
            initial = committed,
            naturalClusters = naturalClusters,
            adjustedClusters = adjustedClusters,
            maxWidth = maxWidth,
            kinsoku = kinsoku,
            shrinkOpportunities = shrinkOpportunities,
            pushInPenalty = pushInPenalty,
            carryPreviousPenalty = carryPreviousPenalty,
            leaveRaggedPenalty = leaveRaggedPenalty,
            unbreakableRanges = unbreakableRanges,
            firstLineIndent = firstLineIndent,
            hangableClusters = hangableClusters,
            extendableHangRanges = extendableHangRanges,
            forbiddenLineStartClusters = forbiddenLineStartClusters,
        )
    }

    private class DpContext(
        val naturalClusters: List<Cluster>,
        val adjustedClusters: List<Cluster>,
        val maxWidth: Float,
        val shrinkOpportunities: List<ShrinkOpportunity>,
        val unbreakableRanges: List<IntRange>,
        val firstLineIndent: Float,
        val forbiddenLineStartClusters: Set<Int>?,
        val forbiddenLineEndClusters: Set<Int>,
        val hyphenBreakClusters: Set<Int>,
        val cjkInterCharBoundaries: Set<Int>,
        val maxCjkStretchPerGap: Float,
        val sinoWesternBoundaries: Set<Int>,
        val sinoWesternStretchCap: Float,
        val nonRenderingControlClusters: Set<Int>,
        val gapBoundaries: Set<Int>,
        val dRef: Float,
        val allowCompressionEdges: Boolean,
    ) {
        /** `gapPrefix[k]` = boundaries below k, so [lineGapCount] over a range is O(1). */
        private val gapPrefix = IntArray(adjustedClusters.size + 1).also { prefix ->
            for (k in adjustedClusters.indices) {
                prefix[k + 1] = prefix[k] + if (k in gapBoundaries) 1 else 0
            }
        }

        /** Per-class prefixes (`GapClassBlindDensity` fix): justify fills 中西 first, then CJK. */
        private val sinoPrefix = IntArray(adjustedClusters.size + 1).also { prefix ->
            for (k in adjustedClusters.indices) {
                prefix[k + 1] = prefix[k] + if (k in sinoWesternBoundaries) 1 else 0
            }
        }
        private val cjkPrefix = IntArray(adjustedClusters.size + 1).also { prefix ->
            for (k in adjustedClusters.indices) {
                prefix[k + 1] = prefix[k] + if (k in cjkInterCharBoundaries) 1 else 0
            }
        }

        /** Advance prefixes so a DP edge's line widths are O(1), not O(line length). */
        private val naturalPrefix = FloatArray(naturalClusters.size + 1).also { prefix ->
            for (k in naturalClusters.indices) prefix[k + 1] = prefix[k] + naturalClusters[k].advance
        }
        private val adjustedPrefix = FloatArray(adjustedClusters.size + 1).also { prefix ->
            for (k in adjustedClusters.indices) prefix[k + 1] = prefix[k] + adjustedClusters[k].advance
        }

        /** [rebuildLine] equivalent with prefix-summed widths (hot DP path only). */
        fun buildLine(clusterRange: IntRange, endReason: LineEndReason): LineCandidate =
            LineCandidate(
                clusterRange = clusterRange,
                sourceRange = org.tiqian.core.TextRange(
                    adjustedClusters[clusterRange.first].range.start,
                    adjustedClusters[clusterRange.last].range.end,
                ),
                naturalWidth = naturalPrefix[clusterRange.last + 1] - naturalPrefix[clusterRange.first],
                adjustedWidth = adjustedPrefix[clusterRange.last + 1] - adjustedPrefix[clusterRange.first],
                endReason = endReason,
            )

        /** Prefix of always-usable shrink capacity; `lineEndOnly` kept per index. */
        private val shrinkPrefix = FloatArray(adjustedClusters.size + 1)
        private val lineEndOnlyCapacity = FloatArray(adjustedClusters.size)

        init {
            for (opp in shrinkOpportunities) {
                if (opp.capacity <= 0f || opp.clusterIndex !in adjustedClusters.indices) continue
                if (opp.lineEndOnly) {
                    lineEndOnlyCapacity[opp.clusterIndex] += opp.capacity
                } else {
                    shrinkPrefix[opp.clusterIndex + 1] += opp.capacity
                }
            }
            for (k in adjustedClusters.indices) shrinkPrefix[k + 1] += shrinkPrefix[k]
        }

        /** Mirrors [lineGapCount] over `[first, last)`. */
        fun gapCount(range: IntRange): Int =
            if (range.isEmptyClusterRange()) 0 else gapPrefix[range.last] - gapPrefix[range.first]

        fun sinoGapCount(range: IntRange): Int =
            if (range.isEmptyClusterRange()) 0 else sinoPrefix[range.last] - sinoPrefix[range.first]

        fun cjkGapCount(range: IntRange): Int =
            if (range.isEmptyClusterRange()) 0 else cjkPrefix[range.last] - cjkPrefix[range.first]

        /**
         * Mirror of [tryPushIn]'s in-line capacity: positive-capacity
         * opportunities inside the line, `lineEndOnly` counted only for the
         * line-end cluster (行末削半 promotion target).
         */
        fun shrinkCapacity(range: IntRange): Float =
            shrinkPrefix[range.last + 1] - shrinkPrefix[range.first] + lineEndOnlyCapacity[range.last]
    }

    /** DP state after taking an edge: (line start, line end, hyphen-run, stretch-run buckets). */
    private class EdgeState(
        val start: Int,
        val end: Int,
        val hyphenRun: Int,
        val stretchRun: Int,
        val cost: Float,
        val parent: EdgeState?,
    )

    /**
     * Candidate ends for a line starting at [start]: every fitting legal break
     * inside `[greedy − candidateWindow, greedy]`, plus the lookahead-greedy
     * baseline end so the DP's universe always contains the greedy chain.
     */
    private fun candidateEnds(context: DpContext, start: Int, segmentEndExclusive: Int, endsWithMandatory: Boolean): List<Int> {
        val limit = lineLimit(context.maxWidth, context.firstLineIndent, start)
        val rawGreedy = findGreedyEnd(
            context.adjustedClusters, start, limit,
            endExclusive = segmentEndExclusive,
            nonRenderingControlClusters = context.nonRenderingControlClusters,
        )
        if (rawGreedy >= segmentEndExclusive) return listOf(segmentEndExclusive)
        val baseline = adjustBreakForUnbreakables(
            breakAt = decideHyphenBreak(
                start, rawGreedy, context.adjustedClusters, limit,
                context.hyphenBreakClusters, context.cjkInterCharBoundaries, context.maxCjkStretchPerGap,
                context.sinoWesternBoundaries, context.sinoWesternStretchCap,
            ),
            lineStart = start,
            unbreakableRanges = context.unbreakableRanges,
        )
        // CompressionAsDpEdge: ends past the natural fit stay candidates while
        // the overflow fits the line's tiered shrink capacity (the exact
        // tryPushIn model, so commit-time realization cannot be rejected).
        val compressed = mutableListOf<Int>()
        if (context.allowCompressionEdges) {
            var width = 0f
            for (k in start until rawGreedy) width += context.adjustedClusters[k].advance
            var e = rawGreedy + 1
            while (e <= segmentEndExclusive && compressed.size < candidateWindow) {
                width += context.adjustedClusters[e - 1].advance
                val overflow = width - limit
                if (overflow > context.shrinkCapacity(start..(e - 1))) break
                compressed += e
                e += 1
            }
        }
        val filtered = (((rawGreedy - candidateWindow)..rawGreedy) + compressed)
            .filter { it in (start + 1)..segmentEndExclusive }
            .filter { e -> !endsWithMandatory || e != segmentEndExclusive - 1 }
            .filter { e -> context.unbreakableRanges.none { e > it.first && e <= it.last } }
            .filter { e ->
                e == segmentEndExclusive ||
                    (start until e).any { it !in context.nonRenderingControlClusters }
            }
        // KinsokuAvoidanceOverRepair: drop conflicted ends only while clean
        // alternatives remain.
        val clean = filtered.filter { e ->
            e == segmentEndExclusive ||
                (
                    context.forbiddenLineStartClusters?.contains(e) != true &&
                        (e - 1) !in context.forbiddenLineEndClusters
                    )
        }
        val pool = clean.ifEmpty { filtered }
        return (if (baseline in (start + 1)..segmentEndExclusive) pool + baseline else pool)
            .distinct()
            .ifEmpty { listOf(baseline.coerceAtLeast(start + 1)) }
    }

    /**
     * Per-line badness mirroring [LookaheadLineBreaker.badness] plus the hyphen
     * demerits, extended with the SIGNED compression side: a compressed edge
     * prices `−overflow/gaps` discounted by [DpContext.compressBias] (Ws/Wc),
     * so the neighbor-difference term sees compressed-next-to-stretched as the
     * visual jump it is.
     */
    /**
     * Prev-independent part of a candidate line's badness (ADR 0041 修订 v2 —
     * the model the 2026-07-18 目检 falsified, repriced):
     *
     * - `GapClassBlindDensity` fix: stretch is priced the way the justifier
     *   RENDERS it — 中西 gaps absorb the deficit first, capped at
     *   [DpContext.sinoWesternStretchCap] each, and only the remainder lands on
     *   CJK 字距. Each class carries its own convex term, so a line whose
     *   averaged density looks mild can no longer hide a word-space pinned at
     *   the cap. Deficit beyond both classes' reach is plain raggedness.
     * - `CompressionFirstFill` fix (CLREQ「先挤压、后拉伸」, ADR 0031
     *   PushInFirst): compression edges carry NO flat penalty and price their
     *   density 1:1 with stretch — the same exchange rate as the fill pass's
     *   ADR 0038 gate — so pulling into punctuation glue beats visible stretch
     *   whenever it cures more than it squeezes. [DpContext.compressBias] no
     *   longer discounts the price: direction preference is the ENGINE's
     *   strategy knob, visibility is the model's, and conflating them was how
     *   compression became a last resort.
     *
     * `StretchRunSparsity` (ADR 0041 修订 v3, 2026-07-18 二次目检): the v2
     * neighbor-difference term rewarded ADJACENT lines with SIMILAR stretch
     * (diff ≈ 0 is free), so the optimum manufactured uniform stretched BLOCKS
     * — measured at 240px: three consecutive 1.9px/gap lines where the
     * lookahead renders six ISOLATED stretched lines each fenced by natural
     * ones, and readers unanimously preferred the isolated profile. Smoothness
     * was the wrong perceptual target; SPARSITY of visibly-stretched lines is
     * the real one (an isolated 4.2px line beats a 3×1.9px band). The convex
     * per-line term alone covers the original ADR 0038 complaint (no single
     * line absorbing everything), so the neighbor term is REPLACED by an
     * escalating run penalty on consecutive lines whose stretch exceeds
     * [VISIBLE_STRETCH_FLOOR_PX] — same shape as the hyphen-ladder demerit.
     * Natural AND compressed lines reset the run: compression is near
     * invisible (CLREQ 先挤压), so a compressed line fences a stretch band
     * just like a natural one.
     *
     * Only the run counters depend on the DP predecessor.
     */
    private class EdgeGeometry(val baseCost: Float, val visibleStretch: Boolean)

    private fun edgeGeometry(context: DpContext, line: LineCandidate, isSegmentLast: Boolean, hyphenEnd: Boolean): EdgeGeometry {
        val limit = lineLimit(context.maxWidth, context.firstLineIndent, line.clusterRange.first)
        val inMeasure = line.inMeasureClusterRange
        val overflow = line.adjustedWidth - limit
        val orphan = if (!isSegmentLast && inMeasure.first == inMeasure.last) leaveRaggedPenalty.toFloat() else 0f
        val hyphenFlat = if (hyphenEnd) syntheticHyphenBreakPenalty else 0f
        val ref = context.dRef.coerceAtLeast(1f)

        if (overflow > 0f) {
            val gaps = maxOf(1, context.gapCount(inMeasure))
            val dComp = overflow / gaps
            return EdgeGeometry(
                baseCost = orphan + hyphenFlat + (dComp * dComp) / ref * raggednessWeight,
                visibleStretch = false,
            )
        }

        val deficit = if (isSegmentLast) 0f else (limit - line.adjustedWidth).coerceAtLeast(0f)
        val sinoGaps = context.sinoGapCount(inMeasure)
        val cjkGaps = context.cjkGapCount(inMeasure)
        val sinoFill = if (sinoGaps > 0) minOf(deficit, sinoGaps * context.sinoWesternStretchCap) else 0f
        val dSino = if (sinoGaps > 0) sinoFill / sinoGaps else 0f
        val cjkDeficit = deficit - sinoFill
        val dCjk = if (cjkGaps > 0) cjkDeficit / cjkGaps else 0f
        val residual = if (cjkGaps == 0) cjkDeficit else 0f
        val convex = (dSino * dSino + dCjk * dCjk) / ref
        return EdgeGeometry(
            baseCost = residual * raggednessWeight + orphan + hyphenFlat + convex * raggednessWeight,
            visibleStretch = maxOf(dSino, dCjk) > VISIBLE_STRETCH_FLOOR_PX,
        )
    }

    /** Exact DP over edges; returns the chosen exclusive line ends, in order. */
    private fun solveSegment(
        context: DpContext,
        segmentStart: Int,
        segmentEndExclusive: Int,
        endsWithMandatory: Boolean,
    ): List<Int> {
        // States keyed by (start, end, hyphenRunAfter, stretchRunAfter); edges
        // only go forward, so increasing start order is a topological order.
        val statesByStart = HashMap<Int, MutableList<EdgeState>>()
        statesByStart[segmentStart] = mutableListOf()
        val bestByKey = HashMap<Long, EdgeState>()

        fun stateKey(start: Int, end: Int, hyphenRun: Int, stretchRun: Int): Long =
            (start.toLong() shl 36) or (end.toLong() shl 4) or
                (hyphenRun.toLong() shl 2) or stretchRun.toLong()

        var terminalBest: EdgeState? = null
        for (start in segmentStart until segmentEndExclusive) {
            val incoming = if (start == segmentStart) {
                listOf(null)
            } else {
                statesByStart[start] ?: continue
            }
            if (incoming.isEmpty()) continue
            val ends = candidateEnds(context, start, segmentEndExclusive, endsWithMandatory)
            for (e in ends) {
                val isSegmentLast = e >= segmentEndExclusive
                val reason = when {
                    !isSegmentLast -> LineEndReason.AutoWrap
                    endsWithMandatory -> LineEndReason.MandatoryBreak
                    else -> LineEndReason.ParagraphEnd
                }
                val line = context.buildLine(
                    clusterRange = start..(e - 1).coerceAtMost(segmentEndExclusive - 1),
                    endReason = reason,
                )
                val hyphenEnd = !isSegmentLast && e in context.hyphenBreakClusters
                val geometry = edgeGeometry(context, line, isSegmentLast, hyphenEnd)
                for (prev in incoming) {
                    val prevCost = prev?.cost ?: 0f
                    val prevHyphenRun = prev?.hyphenRun ?: 0
                    val prevStretchRun = prev?.stretchRun ?: 0
                    val hyphenRunCost = if (hyphenEnd) consecutiveSyntheticHyphenPenalty * prevHyphenRun else 0f
                    // StretchRunSparsity: each additional CONSECUTIVE visibly
                    // stretched line escalates; natural or compressed lines
                    // reset the run.
                    val stretchRunCost = if (geometry.visibleStretch) consecutiveStretchPenalty * prevStretchRun else 0f
                    val cost = prevCost + geometry.baseCost + hyphenRunCost + stretchRunCost
                    val hyphenRunAfter = if (hyphenEnd) (prevHyphenRun + 1).coerceAtMost(HYPHEN_RUN_STATE_CAP) else 0
                    val stretchRunAfter = if (geometry.visibleStretch) (prevStretchRun + 1).coerceAtMost(STRETCH_RUN_STATE_CAP) else 0
                    val key = stateKey(start, e, hyphenRunAfter, stretchRunAfter)
                    val existing = bestByKey[key]
                    if (existing != null && existing.cost <= cost) continue
                    val state = EdgeState(start, e, hyphenRunAfter, stretchRunAfter, cost, prev)
                    bestByKey[key] = state
                    if (isSegmentLast) {
                        if (terminalBest == null || cost < terminalBest!!.cost) terminalBest = state
                    } else {
                        val bucket = statesByStart.getOrPut(e) { mutableListOf() }
                        bucket.removeAll {
                            it.start == start && it.hyphenRun == hyphenRunAfter && it.stretchRun == stretchRunAfter
                        }
                        bucket += state
                    }
                }
            }
        }

        val terminal = terminalBest ?: return greedyFallbackEnds(context, segmentStart, segmentEndExclusive)
        val ends = mutableListOf<Int>()
        var cursor: EdgeState? = terminal
        while (cursor != null) {
            ends += cursor.end
            cursor = cursor.parent
        }
        ends.reverse()
        return ends
    }

    /** Progress guarantee: plain greedy ends if the DP found no terminal state. */
    private fun greedyFallbackEnds(context: DpContext, segmentStart: Int, segmentEndExclusive: Int): List<Int> {
        val ends = mutableListOf<Int>()
        var start = segmentStart
        while (start < segmentEndExclusive) {
            val limit = lineLimit(context.maxWidth, context.firstLineIndent, start)
            val rawGreedy = findGreedyEnd(
                context.adjustedClusters, start, limit,
                endExclusive = segmentEndExclusive,
                nonRenderingControlClusters = context.nonRenderingControlClusters,
            )
            val e = if (rawGreedy >= segmentEndExclusive) {
                segmentEndExclusive
            } else {
                adjustBreakForUnbreakables(
                    breakAt = decideHyphenBreak(
                        start, rawGreedy, context.adjustedClusters, limit,
                        context.hyphenBreakClusters, context.cjkInterCharBoundaries,
                        context.maxCjkStretchPerGap,
                        context.sinoWesternBoundaries, context.sinoWesternStretchCap,
                    ),
                    lineStart = start,
                    unbreakableRanges = context.unbreakableRanges,
                ).coerceAtLeast(start + 1)
            }
            ends += e
            start = e
        }
        return ends
    }

    /** Walks the lookahead's commit path over the DP-chosen ends. */
    private fun commitSegment(
        committed: MutableList<LineCandidate>,
        ends: List<Int>,
        segmentStart: Int,
        mandatoryEnd: Int?,
        context: DpContext,
        hardBreakAfterClusters: Set<Int>,
    ) {
        val naturalClusters = context.naturalClusters
        val adjustedClusters = context.adjustedClusters
        var lineStart = segmentStart
        for (chosenEnd in ends) {
            if (lineStart >= chosenEnd) continue
            val isFinalOfSegment = chosenEnd == ends.last()
            val endReason = when {
                isFinalOfSegment && mandatoryEnd != null -> LineEndReason.MandatoryBreak
                isFinalOfSegment -> LineEndReason.ParagraphEnd
                else -> LineEndReason.AutoWrap
            }
            val lastIndex = if (isFinalOfSegment && mandatoryEnd != null) mandatoryEnd else chosenEnd - 1
            val limit = lineLimit(context.maxWidth, context.firstLineIndent, lineStart)
            val naturalLine = rebuildLine(lineStart..lastIndex, naturalClusters, adjustedClusters, endReason)

            val compressedLine = if (naturalLine.adjustedWidth > limit && lastIndex > lineStart) {
                // CompressionAsDpEdge realization: identical repair records to
                // the fill pass — same tiered capacity, same 行末削半 promotion.
                val result = tryPushIn(
                    prev = rebuildLine(lineStart..lineStart, naturalClusters, adjustedClusters),
                    curr = rebuildLine((lineStart + 1)..lastIndex, naturalClusters, adjustedClusters, endReason),
                    naturalClusters = naturalClusters,
                    adjustedClusters = adjustedClusters,
                    maxWidth = limit,
                    shrinkOpportunities = context.shrinkOpportunities,
                    pushInPenalty = pushInPenalty,
                    mergeThroughClusterIndex = lastIndex,
                    reasonCode = "LineAdjustmentPushIn",
                )
                if (result.candidate.accepted && result.current == null) result.previous else null
            } else {
                null
            }

            if (isFinalOfSegment && mandatoryEnd != null) {
                committed += compressedLine ?: naturalLine
                lineStart = mandatoryEnd + 1
                if (lineStart == adjustedClusters.size) {
                    committed += emptyLineCandidate(
                        sourceOffset = adjustedClusters.last().range.end,
                        endReason = LineEndReason.ParagraphEnd,
                    )
                }
                continue
            }
            if (isFinalOfSegment) {
                committed += compressedLine ?: naturalLine
                lineStart = chosenEnd
                continue
            }
            if (compressedLine != null) {
                // Compressed edges were kinsoku-filtered at candidate time; a
                // 行尾禁则 retreat here would invalidate the recorded shrink.
                committed += compressedLine
                lineStart = chosenEnd
                continue
            }
            // 行尾禁则 retreat exactly as the lookahead commit does; a retreat
            // is recorded as CarryNext by closeFilledLine. A retreat landing on
            // an authored break binds the control to this line.
            val committedEnd = adjustBreakForLineEnd(chosenEnd, lineStart, context.forbiddenLineEndClusters)
            if (committedEnd in hardBreakAfterClusters && lineStart < committedEnd) {
                committed += rebuildLine(
                    lineStart..committedEnd,
                    naturalClusters,
                    adjustedClusters,
                    endReason = LineEndReason.MandatoryBreak,
                )
                lineStart = committedEnd + 1
                continue
            }
            committed += closeFilledLine(
                lineStart..(committedEnd - 1), chosenEnd, naturalClusters, adjustedClusters,
            )
            lineStart = committedEnd
        }
    }

    private companion object {
        /** `HyphenRunStateCap`: hyphen runs beyond this price like the cap. */
        const val HYPHEN_RUN_STATE_CAP = 3

        /** `StretchRunSparsity`: runs beyond this price like the cap. */
        const val STRETCH_RUN_STATE_CAP = 3

        /**
         * `VisibleStretchFloor`: per-gap stretch below this is treated as
         * imperceptible — it neither starts nor extends a stretch run.
         */
        const val VISIBLE_STRETCH_FLOOR_PX = 0.5f
    }
}
