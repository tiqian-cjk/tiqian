package ink.duo3.tiqian.layout

import ink.duo3.tiqian.core.Cluster
import ink.duo3.tiqian.core.TextRange

interface LineBreaker {
    val strategyName: String
        get() = "custom"

    fun breakLines(
        naturalClusters: List<Cluster>,
        adjustedClusters: List<Cluster>,
        maxWidth: Float,
        /**
         * Tiered in-line shrink resources for PushIn, ordered per CLREQ's
         * 挤压处理优先顺序 (ADR 0020). Lower tier = consumed first; the
         * offender's own trailing glue is promoted to tier 1 (行末标点
         * 调成半宽) at repair time.
         */
        shrinkOpportunities: List<ShrinkOpportunity> = emptyList(),
        /**
         * Cluster-index ranges that must stay on one line when they fit
         * (示亡号 spans, ADR 0018). `MourningSpanKeptUnbroken`: a break that
         * would land strictly inside a range moves to the range start
         * instead; a range wider than the measure falls back to splitting.
         */
        unbreakableRanges: List<IntRange> = emptyList(),
    ): LineSolution
}

/**
 * One shrinkable resource on a cluster (ADR 0020, CLREQ 挤压处理优先顺序):
 *
 * - tier 1 — 行末标点削半宽（offender 自身 trailing glue，repair 时晋升）
 * - tier 2 — 西文词距，最小压至 1/4em
 * - tier 3 — 间隔号/居中类，两侧同时等量，压至 0
 * - tier 4 — 行内句号/问号/感叹号 trailing glue（风格开关可禁）
 * - tier 5 — 中西间距（风格开关可禁）
 * - tier 6 — 其余行内标点 glue。CLREQ 程序未列；项目保留为最后手段，
 *            否则 PushIn 在标点稀疏的行上能力大幅下降。
 */
data class ShrinkOpportunity(
    val clusterIndex: Int,
    val tier: Int,
    val capacity: Float,
    val channel: ShrinkChannel,
    /**
     * Usable only when this cluster becomes the merged line's END (tier-1
     * promotion). Used when `allowInlineStopCompression` is off: 行内句问叹
     * keep full width, but 行末削半 (a different CLREQ rule) still applies.
     */
    val lineEndOnly: Boolean = false,
)

enum class ShrinkChannel {
    /** Consume the punctuation atom's trailing glue. */
    TrailingGlue,

    /** Consume leading and trailing glue simultaneously, equal amounts. */
    LeadingAndTrailingGlue,

    /** Reduce the cluster's raw advance (word spaces, gap clusters). */
    RawAdvance,
}

/**
 * Moves [breakAt] out of any unbreakable range it falls strictly inside of
 * (to the range start), provided the line keeps at least one cluster.
 * Returns [breakAt] unchanged otherwise — including the give-up case where
 * the range itself is wider than the line (split fallback).
 */
internal fun adjustBreakForUnbreakables(
    breakAt: Int,
    lineStart: Int,
    unbreakableRanges: List<IntRange>,
): Int {
    val containing = unbreakableRanges.firstOrNull { breakAt > it.first && breakAt <= it.last }
        ?: return breakAt
    return if (containing.first > lineStart) containing.first else breakAt
}

/**
 * GreedyLineBreaker — fills each line until the next cluster would overflow,
 * then starts a new line. After the greedy pass, [kinsoku] is consulted to
 * detect breaks that would place a forbidden-at-line-start cluster at the
 * beginning of a line; such breaks try PushIn first, then CarryPrevious
 * (move the previous cluster onto the next line together with the offender).
 *
 * Repairs that cannot be applied without leaving a line empty fall back to
 * [RepairOption.LeaveRagged] — the unfortunate break is recorded but kept.
 *
 * Slice 4b scope: PushIn via punctuation glue, CarryPrevious, and LeaveRagged.
 * Hang remains profile opt-in and is not a default repair.
 */
class GreedyLineBreaker(
    private val kinsoku: KinsokuRule = ClreqKinsokuRule(),
    private val pushInPenalty: Int = 2,
    private val carryPreviousPenalty: Int = 10,
    private val leaveRaggedPenalty: Int = 20,
) : LineBreaker {
    override val strategyName: String = "greedy"

    override fun breakLines(
        naturalClusters: List<Cluster>,
        adjustedClusters: List<Cluster>,
        maxWidth: Float,
        shrinkOpportunities: List<ShrinkOpportunity>,
        unbreakableRanges: List<IntRange>,
    ): LineSolution {
        if (adjustedClusters.isEmpty()) return LineSolution(emptyList())
        require(naturalClusters.size == adjustedClusters.size) {
            "naturalClusters and adjustedClusters must align cluster-for-cluster."
        }

        val greedy = greedyFill(naturalClusters, adjustedClusters, maxWidth, unbreakableRanges)
        return applyKinsokuRepairs(
            initial = greedy,
            naturalClusters = naturalClusters,
            adjustedClusters = adjustedClusters,
            maxWidth = maxWidth,
            kinsoku = kinsoku,
            shrinkOpportunities = shrinkOpportunities,
            pushInPenalty = pushInPenalty,
            carryPreviousPenalty = carryPreviousPenalty,
            leaveRaggedPenalty = leaveRaggedPenalty,
            unbreakableRanges = unbreakableRanges,
        )
    }

    private fun greedyFill(
        naturalClusters: List<Cluster>,
        adjustedClusters: List<Cluster>,
        maxWidth: Float,
        unbreakableRanges: List<IntRange>,
    ): List<LineCandidate> {
        val lines = mutableListOf<LineCandidate>()
        var lineStart = 0
        var adjustedAccum = 0f
        var naturalAccum = 0f

        var i = 0
        while (i < adjustedClusters.size) {
            val nextAdjusted = adjustedAccum + adjustedClusters[i].advance
            val overflows = nextAdjusted > maxWidth && i > lineStart
            if (overflows) {
                val breakAt = adjustBreakForUnbreakables(i, lineStart, unbreakableRanges)
                lines += rebuildLine(
                    clusterRange = lineStart..(breakAt - 1),
                    naturalClusters = naturalClusters,
                    adjustedClusters = adjustedClusters,
                )
                lineStart = breakAt
                adjustedAccum = adjustedClusters[breakAt].advance
                naturalAccum = naturalClusters[breakAt].advance
                i = breakAt + 1
            } else {
                adjustedAccum = nextAdjusted
                naturalAccum += naturalClusters[i].advance
                i += 1
            }
        }

        lines += rebuildLine(
            clusterRange = lineStart..adjustedClusters.lastIndex,
            naturalClusters = naturalClusters,
            adjustedClusters = adjustedClusters,
        )
        return lines
    }

}

/**
 * LookaheadLineBreaker — runs greedy first, then for each line decision tries
 * shifting the break by [window] clusters on either side and scores each
 * candidate by simulating the next [futureLineHorizon] lines (greedy + kinsoku
 * applied to the splice). Picks the candidate with the lowest combined badness.
 *
 * Badness per line = raggedness * [raggednessWeight] + repair penalty.
 * Last line raggedness is not penalized (a short last line is expected).
 *
 * Defaults are tuned so that a single em of raggedness costs less than a
 * CarryPrevious repair (8 vs 10), and noticeably less than LeaveRagged (8 vs
 * 20), so kinsoku conflicts that can be sidestepped by a one-cluster shift are
 * preferred over leaving the conflict in place.
 *
 * Default [window] is 2 — a cost/benefit middle ground: window 1 already
 * captures most of the repair-avoidance value, larger windows occasionally
 * trade worst-line deficit at narrow measures, and window 3+ has not shown
 * consistent benefit. The numbers are corpus-dependent; re-evaluate with
 * `LookaheadWindowProbe` when the fixture corpus changes.
 */
class LookaheadLineBreaker(
    private val window: Int = 2,
    private val futureLineHorizon: Int = 2,
    private val raggednessWeight: Float = 0.5f,
    private val kinsoku: KinsokuRule = ClreqKinsokuRule(),
    private val pushInPenalty: Int = 2,
    private val carryPreviousPenalty: Int = 10,
    private val leaveRaggedPenalty: Int = 20,
) : LineBreaker {
    override val strategyName: String = "lookahead"

    override fun breakLines(
        naturalClusters: List<Cluster>,
        adjustedClusters: List<Cluster>,
        maxWidth: Float,
        shrinkOpportunities: List<ShrinkOpportunity>,
        unbreakableRanges: List<IntRange>,
    ): LineSolution {
        if (adjustedClusters.isEmpty()) return LineSolution(emptyList())
        require(naturalClusters.size == adjustedClusters.size) {
            "naturalClusters and adjustedClusters must align cluster-for-cluster."
        }
        require(window >= 0) { "window must be non-negative." }
        require(futureLineHorizon >= 0) { "futureLineHorizon must be non-negative." }

        val committed = mutableListOf<LineCandidate>()
        var lineStart = 0
        while (lineStart < adjustedClusters.size) {
            val greedyEnd = adjustBreakForUnbreakables(
                breakAt = findGreedyEnd(adjustedClusters, lineStart, maxWidth),
                lineStart = lineStart,
                unbreakableRanges = unbreakableRanges,
            )
            if (greedyEnd >= adjustedClusters.size) {
                committed += rebuildLine(
                    lineStart..adjustedClusters.lastIndex,
                    naturalClusters,
                    adjustedClusters,
                )
                break
            }

            // Candidates only shift earlier than greedy. PushIn is evaluated
            // during the repair pass below, where punctuation glue capacity is
            // known and the shrink can be recorded on the chosen line.
            // Breaks inside an unbreakable span are never candidates.
            val candidates = ((greedyEnd - window)..greedyEnd)
                .filter { it in (lineStart + 1)..adjustedClusters.size }
                .filter { e -> unbreakableRanges.none { e > it.first && e <= it.last } }
                .distinct()
                .ifEmpty { listOf(greedyEnd) }

            var bestEnd = greedyEnd
            var bestScore = Float.POSITIVE_INFINITY
            for (e in candidates) {
                val score = scoreCandidate(
                    s = lineStart,
                    e = e,
                    natural = naturalClusters,
                    adjusted = adjustedClusters,
                    maxWidth = maxWidth,
                    shrinkOpportunities = shrinkOpportunities,
                )
                if (score < bestScore) {
                    bestScore = score
                    bestEnd = e
                }
            }

            committed += rebuildLine(
                lineStart..(bestEnd - 1),
                naturalClusters,
                adjustedClusters,
            )
            lineStart = bestEnd
        }

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
        )
    }

    private fun scoreCandidate(
        s: Int,
        e: Int,
        natural: List<Cluster>,
        adjusted: List<Cluster>,
        maxWidth: Float,
        shrinkOpportunities: List<ShrinkOpportunity>,
    ): Float {
        val firstLine = rebuildLine(s..(e - 1), natural, adjusted)
        val future = rawGreedyLinesFrom(
            start = e,
            natural = natural,
            adjusted = adjusted,
            maxWidth = maxWidth,
        )
        // Apply kinsoku once across [firstLine] + future so both splice
        // conflicts and future-line conflicts are scored with the same PushIn
        // capacity map as the final repair pass.
        val spliced = applyKinsokuRepairs(
            initial = listOf(firstLine) + future,
            naturalClusters = natural,
            adjustedClusters = adjusted,
            maxWidth = maxWidth,
            kinsoku = kinsoku,
            shrinkOpportunities = shrinkOpportunities,
            pushInPenalty = pushInPenalty,
            carryPreviousPenalty = carryPreviousPenalty,
            leaveRaggedPenalty = leaveRaggedPenalty,
        ).lines

        val horizon = (1 + futureLineHorizon).coerceAtMost(spliced.size)
        var score = 0f
        for (idx in 0 until horizon) {
            val isLast = (idx == spliced.lastIndex)
            score += badness(spliced[idx], maxWidth, isLast)
        }
        return score
    }

    private fun rawGreedyLinesFrom(
        start: Int,
        natural: List<Cluster>,
        adjusted: List<Cluster>,
        maxWidth: Float,
    ): List<LineCandidate> {
        if (start >= adjusted.size) return emptyList()

        val lines = mutableListOf<LineCandidate>()
        var lineStart = start
        var adjustedAccum = 0f

        for (i in start until adjusted.size) {
            val nextAdjusted = adjustedAccum + adjusted[i].advance
            val overflows = nextAdjusted > maxWidth && i > lineStart
            if (overflows) {
                lines += rebuildLine(
                    clusterRange = lineStart..(i - 1),
                    naturalClusters = natural,
                    adjustedClusters = adjusted,
                )
                lineStart = i
                adjustedAccum = adjusted[i].advance
            } else {
                adjustedAccum = nextAdjusted
            }
        }

        lines += rebuildLine(
            clusterRange = lineStart..adjusted.lastIndex,
            naturalClusters = natural,
            adjustedClusters = adjusted,
        )
        return lines
    }

    private fun badness(line: LineCandidate, maxWidth: Float, isLast: Boolean): Float {
        val ragged = if (isLast) 0f else (maxWidth - line.adjustedWidth).coerceAtLeast(0f)
        return ragged * raggednessWeight + (line.repair?.penalty ?: 0).toFloat()
    }
}

internal fun applyKinsokuRepairs(
    initial: List<LineCandidate>,
    naturalClusters: List<Cluster>,
    adjustedClusters: List<Cluster>,
    maxWidth: Float,
    kinsoku: KinsokuRule,
    shrinkOpportunities: List<ShrinkOpportunity> = emptyList(),
    pushInPenalty: Int,
    carryPreviousPenalty: Int,
    leaveRaggedPenalty: Int,
    unbreakableRanges: List<IntRange> = emptyList(),
): LineSolution {
    if (initial.size < 2) return LineSolution(initial)

    val mutable = initial.toMutableList()
    var i = 1
    while (i < mutable.size) {
        val curr = mutable[i]
        val firstCluster = adjustedClusters[curr.clusterRange.first]
        if (!kinsoku.forbiddenAtLineStart(firstCluster)) {
            i += 1
            continue
        }

        val prev = mutable[i - 1]
        val repairCandidates = mutableListOf<RepairCandidate>()
        val pushIn = tryPushIn(
            prev = prev,
            curr = curr,
            naturalClusters = naturalClusters,
            adjustedClusters = adjustedClusters,
            maxWidth = maxWidth,
            shrinkOpportunities = shrinkOpportunities,
            pushInPenalty = pushInPenalty,
        )
        repairCandidates += pushIn.candidate
        if (pushIn.candidate.accepted) {
            mutable[i - 1] = pushIn.previous
            if (pushIn.current == null) {
                mutable.removeAt(i)
            } else {
                mutable[i] = pushIn.current
                continue
            }
            continue
        }

        val canCarry = prev.clusterRange.first < prev.clusterRange.last
        if (!canCarry) {
            repairCandidates += RepairCandidate(
                kind = "CarryPrevious",
                reasonCode = "ForbiddenAtLineStart",
                offenderClusterIndex = curr.clusterRange.first,
                penalty = carryPreviousPenalty,
                accepted = false,
                rejectionReason = "no-room-to-carry",
            )
            repairCandidates += RepairCandidate(
                kind = "LeaveRagged",
                reasonCode = "ForbiddenAtLineStart",
                offenderClusterIndex = curr.clusterRange.first,
                penalty = leaveRaggedPenalty,
                accepted = true,
            )
            mutable[i] = curr.copy(
                repair = RepairOption.LeaveRagged(
                    penalty = leaveRaggedPenalty,
                    reason = "ForbiddenAtLineStart:${firstCluster.text}:no-room-to-carry",
                    offenderClusterIndex = curr.clusterRange.first,
                ),
                repairCandidates = repairCandidates,
            )
            i += 1
            continue
        }

        val carriedIndex = prev.clusterRange.last
        // CarryPrevious must not split an unbreakable span: carrying any
        // cluster other than the span's first would leave part of the span
        // behind on the previous line.
        val splitsUnbreakable = unbreakableRanges.any {
            carriedIndex > it.first && carriedIndex <= it.last
        }
        if (splitsUnbreakable) {
            repairCandidates += RepairCandidate(
                kind = "CarryPrevious",
                reasonCode = "ForbiddenAtLineStart",
                offenderClusterIndex = curr.clusterRange.first,
                penalty = carryPreviousPenalty,
                accepted = false,
                rejectionReason = "carry-would-split-mourning-span",
                carriedClusterIndex = carriedIndex,
            )
            repairCandidates += RepairCandidate(
                kind = "LeaveRagged",
                reasonCode = "ForbiddenAtLineStart",
                offenderClusterIndex = curr.clusterRange.first,
                penalty = leaveRaggedPenalty,
                accepted = true,
            )
            mutable[i] = curr.copy(
                repair = RepairOption.LeaveRagged(
                    penalty = leaveRaggedPenalty,
                    reason = "ForbiddenAtLineStart:${firstCluster.text}:carry-would-split-mourning-span",
                    offenderClusterIndex = curr.clusterRange.first,
                ),
                repairCandidates = repairCandidates,
            )
            i += 1
            continue
        }
        val newPrevRange = prev.clusterRange.first..(carriedIndex - 1)
        val newCurrRange = carriedIndex..curr.clusterRange.last
        val carriedCurrent = rebuildLine(newCurrRange, naturalClusters, adjustedClusters)
        if (carriedCurrent.adjustedWidth > maxWidth) {
            // CLREQ 推出 may not overflow maxWidth — that would be effectively
            // hanging punctuation, which is opt-in per ADR 0006. When the
            // receiving line is already at capacity, this fallback leaves
            // the offender at line start with a LeaveRagged marker. The
            // lookahead breaker is expected to avoid hitting this case by
            // picking a break that has room downstream.
            repairCandidates += RepairCandidate(
                kind = "CarryPrevious",
                reasonCode = "ForbiddenAtLineStart",
                offenderClusterIndex = curr.clusterRange.first,
                penalty = carryPreviousPenalty,
                accepted = false,
                rejectionReason = "carry-overflows",
                carriedClusterIndex = carriedIndex,
            )
            repairCandidates += RepairCandidate(
                kind = "LeaveRagged",
                reasonCode = "ForbiddenAtLineStart",
                offenderClusterIndex = curr.clusterRange.first,
                penalty = leaveRaggedPenalty,
                accepted = true,
            )
            mutable[i] = curr.copy(
                repair = RepairOption.LeaveRagged(
                    penalty = leaveRaggedPenalty,
                    reason = "ForbiddenAtLineStart:${firstCluster.text}:carry-overflows",
                    offenderClusterIndex = curr.clusterRange.first,
                ),
                repairCandidates = repairCandidates,
            )
            i += 1
            continue
        }

        repairCandidates += RepairCandidate(
            kind = "CarryPrevious",
            reasonCode = "ForbiddenAtLineStart",
            offenderClusterIndex = curr.clusterRange.first,
            penalty = carryPreviousPenalty,
            accepted = true,
            carriedClusterIndex = carriedIndex,
        )
        mutable[i - 1] = rebuildLine(newPrevRange, naturalClusters, adjustedClusters)
        mutable[i] = carriedCurrent.copy(
            repair = RepairOption.CarryPrevious(
                penalty = carryPreviousPenalty,
                reason = "ForbiddenAtLineStart:${firstCluster.text}:carried=${adjustedClusters[carriedIndex].text}",
                offenderClusterIndex = curr.clusterRange.first,
                carriedClusterIndex = carriedIndex,
            ),
            repairCandidates = repairCandidates,
        )
        i += 1
    }

    val totalBadness = mutable.sumOf { (it.repair?.penalty ?: 0).toDouble() }.toFloat()
    return LineSolution(mutable, totalBadness = totalBadness)
}

private data class PushInResult(
    val previous: LineCandidate,
    val current: LineCandidate?,
    val candidate: RepairCandidate,
)

/**
 * CLREQ 推入 — compress IN-LINE glue (across every cluster on the merged
 * line) to fit the offender. The offender's own trailing glue is one of
 * many possible contributors; the previous line's `、`, `，`, etc. all
 * count.
 *
 * Single-source contract:
 *   `totalShrink` is the canonical amount of glue this PushIn consumes
 *   across the whole line. `allocations` records per-cluster shrink so the
 *   engine can subtract from each cluster's advance independently.
 *   - [LineCandidate.adjustedWidth] is recomputed here as
 *     `expanded.adjustedWidth - totalShrink` to keep ADR 0005's drawable-
 *     cluster invariant: the line candidate already reflects the post-
 *     shrink geometry the breaker decided. The engine MUST NOT subtract
 *     allocation shrink from cluster advance and ALSO subtract it from
 *     `adjustedWidth` — pick one consumer per derived field.
 *   - Today `totalShrink == overflow`. If a future partial-PushIn lands
 *     (`totalShrink < overflow`), update it here and rely on it as the
 *     only knob; do not reintroduce a second `overflow`-based path.
 */
private fun tryPushIn(
    prev: LineCandidate,
    curr: LineCandidate,
    naturalClusters: List<Cluster>,
    adjustedClusters: List<Cluster>,
    maxWidth: Float,
    shrinkOpportunities: List<ShrinkOpportunity>,
    pushInPenalty: Int,
): PushInResult {
    val offenderIndex = curr.clusterRange.first
    val expandedRange = prev.clusterRange.first..offenderIndex
    val expanded = rebuildLine(expandedRange, naturalClusters, adjustedClusters)
    val overflow = expanded.adjustedWidth - maxWidth

    // Tiered shrink resources across the merged line (CLREQ 挤压处理优先
    // 顺序, ADR 0020). The offender will sit at the merged line's END, so
    // its trailing glue IS the 行末标点削半宽 step — promote it to tier 1.
    val inLine = shrinkOpportunities
        .filter { it.clusterIndex in expandedRange && it.capacity > 0f }
        .filter { !it.lineEndOnly || it.clusterIndex == offenderIndex }
        .map { opp ->
            if (opp.clusterIndex == offenderIndex && opp.channel == ShrinkChannel.TrailingGlue) {
                opp.copy(tier = 1)
            } else {
                opp
            }
        }
    val totalCapacity = inLine.sumOf { it.capacity.toDouble() }.toFloat()

    if (overflow > totalCapacity) {
        return PushInResult(
            previous = prev,
            current = curr,
            candidate = RepairCandidate(
                kind = "PushIn",
                reasonCode = "ForbiddenAtLineStart",
                offenderClusterIndex = offenderIndex,
                penalty = pushInPenalty,
                accepted = false,
                rejectionReason = "insufficient-capacity",
                targetClusterIndex = offenderIndex,
                requiredShrink = overflow.coerceAtLeast(0f),
                availableCapacity = totalCapacity,
            ),
        )
    }

    // `overflow <= 0` is NOT a rejection: upstream repairs in the chain
    // (a PushIn / CarryPrevious on earlier lines) can shorten the previous
    // line after the break was placed, so the offender simply fits now.
    // That is a zero-shrink merge. Refusing it cascaded into
    // carry-overflows → LeaveRagged and left `、` / `」` at line start.
    val shrink = overflow.coerceAtLeast(0f)
    val allocations = if (shrink > 0f) distributePushInShrink(inLine, shrink) else emptyList()
    val offender = adjustedClusters[offenderIndex]
    val candidate = RepairCandidate(
        kind = "PushIn",
        reasonCode = "ForbiddenAtLineStart",
        offenderClusterIndex = offenderIndex,
        penalty = pushInPenalty,
        accepted = true,
        targetClusterIndex = offenderIndex,
        shrink = shrink,
        requiredShrink = shrink,
        availableCapacity = totalCapacity,
    )
    val repairedPrevious = expanded.copy(
        adjustedWidth = expanded.adjustedWidth - shrink,
        repair = RepairOption.PushIn(
            penalty = pushInPenalty,
            reason = if (shrink > 0f) {
                "ForbiddenAtLineStart:${offender.text}:pushed-in=$shrink/$totalCapacity"
            } else {
                "ForbiddenAtLineStart:${offender.text}:fits-no-shrink"
            },
            offenderClusterIndex = offenderIndex,
            allocations = allocations,
            totalShrink = shrink,
            totalAvailableCapacity = totalCapacity,
        ),
        // Preserve any repair history the receiving line already carries
        // (e.g. its own start was repaired earlier in the chain) — the
        // PushIn marker for the absorbed offender must not erase it.
        repairCandidates = prev.repairCandidates + candidate,
    )
    val repairedCurrent = if (offenderIndex == curr.clusterRange.last) {
        null
    } else {
        rebuildLine((offenderIndex + 1)..curr.clusterRange.last, naturalClusters, adjustedClusters)
    }
    return PushInResult(repairedPrevious, repairedCurrent, candidate)
}

/**
 * Distribute [totalShrink] across [opportunities] in STRICT TIER ORDER
 * (CLREQ 挤压处理优先顺序): tier k is exhausted before tier k+1 is touched.
 * Within a tier, shrink is shared proportionally to capacity (equal caps →
 * equal amounts, the CLREQ「同时、同等量」rule); rounding remainder lands on
 * the tier's last entry. Allocations carry the consumption channel so the
 * engine knows whether to consume glue (one- or two-sided) or raw advance.
 */
private fun distributePushInShrink(
    opportunities: List<ShrinkOpportunity>,
    totalShrink: Float,
): List<PushInAllocation> {
    if (opportunities.isEmpty() || totalShrink <= 0f) return emptyList()

    val allocations = mutableListOf<PushInAllocation>()
    var remaining = totalShrink
    for ((_, tierOpps) in opportunities.groupBy { it.tier }.toSortedMap()) {
        if (remaining <= 0f) break
        val tierCapacity = tierOpps.sumOf { it.capacity.toDouble() }.toFloat()
        if (tierCapacity <= 0f) continue
        val tierShrink = remaining.coerceAtMost(tierCapacity)
        var tierRemaining = tierShrink
        val ordered = tierOpps.sortedBy { it.clusterIndex }
        ordered.forEachIndexed { i, opp ->
            val isLast = (i == ordered.lastIndex)
            val share = if (isLast) {
                tierRemaining.coerceAtMost(opp.capacity)
            } else {
                (tierShrink * opp.capacity / tierCapacity).coerceAtMost(opp.capacity)
            }
            if (share > 0f) {
                allocations += PushInAllocation(
                    clusterIndex = opp.clusterIndex,
                    shrink = share,
                    availableCapacity = opp.capacity,
                    channel = opp.channel,
                )
                tierRemaining -= share
            }
        }
        remaining -= (tierShrink - tierRemaining.coerceAtLeast(0f))
    }
    return allocations
}

internal fun rebuildLine(
    clusterRange: IntRange,
    naturalClusters: List<Cluster>,
    adjustedClusters: List<Cluster>,
    repair: RepairOption? = null,
    repairCandidates: List<RepairCandidate> = emptyList(),
): LineCandidate {
    var natural = 0f
    var adjusted = 0f
    for (idx in clusterRange) {
        natural += naturalClusters[idx].advance
        adjusted += adjustedClusters[idx].advance
    }
    return LineCandidate(
        clusterRange = clusterRange,
        sourceRange = TextRange(
            adjustedClusters[clusterRange.first].range.start,
            adjustedClusters[clusterRange.last].range.end,
        ),
        naturalWidth = natural,
        adjustedWidth = adjusted,
        repair = repair,
        repairCandidates = repairCandidates,
    )
}

internal fun findGreedyEnd(
    adjustedClusters: List<Cluster>,
    start: Int,
    maxWidth: Float,
): Int {
    var accum = 0f
    var i = start
    while (i < adjustedClusters.size) {
        val next = accum + adjustedClusters[i].advance
        if (next > maxWidth && i > start) return i
        accum = next
        i += 1
    }
    return adjustedClusters.size
}
