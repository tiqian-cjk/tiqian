package org.tiqian.text.layout

import org.tiqian.text.core.Cluster
import org.tiqian.text.core.TextRange

interface LineBreaker {
    val strategyName: String
        get() = "custom"

    fun breakLines(
        naturalClusters: List<Cluster>,
        adjustedClusters: List<Cluster>,
        maxWidth: Float,
        pushInCapacities: Map<Int, Float> = emptyMap(),
    ): LineSolution
}

/**
 * GreedyLineBreaker — fills each line until the next cluster would overflow,
 * then starts a new line. After the greedy pass, [kinsoku] is consulted to
 * detect breaks that would place a forbidden-at-line-start cluster at the
 * beginning of a line; such breaks trigger [RepairOption.CarryPrevious]
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
        pushInCapacities: Map<Int, Float>,
    ): LineSolution {
        if (adjustedClusters.isEmpty()) return LineSolution(emptyList())
        require(naturalClusters.size == adjustedClusters.size) {
            "naturalClusters and adjustedClusters must align cluster-for-cluster."
        }

        val greedy = greedyFill(naturalClusters, adjustedClusters, maxWidth)
        return applyKinsokuRepairs(
            initial = greedy,
            naturalClusters = naturalClusters,
            adjustedClusters = adjustedClusters,
            maxWidth = maxWidth,
            kinsoku = kinsoku,
            pushInCapacities = pushInCapacities,
            pushInPenalty = pushInPenalty,
            carryPreviousPenalty = carryPreviousPenalty,
            leaveRaggedPenalty = leaveRaggedPenalty,
        )
    }

    private fun greedyFill(
        naturalClusters: List<Cluster>,
        adjustedClusters: List<Cluster>,
        maxWidth: Float,
    ): List<LineCandidate> {
        val lines = mutableListOf<LineCandidate>()
        var lineStart = 0
        var adjustedAccum = 0f
        var naturalAccum = 0f

        for (i in adjustedClusters.indices) {
            val nextAdjusted = adjustedAccum + adjustedClusters[i].advance
            val overflows = nextAdjusted > maxWidth && i > lineStart
            if (overflows) {
                lines += buildLine(
                    adjustedClusters = adjustedClusters,
                    clusterRange = lineStart..(i - 1),
                    naturalWidth = naturalAccum,
                    adjustedWidth = adjustedAccum,
                )
                lineStart = i
                adjustedAccum = adjustedClusters[i].advance
                naturalAccum = naturalClusters[i].advance
            } else {
                adjustedAccum = nextAdjusted
                naturalAccum += naturalClusters[i].advance
            }
        }

        lines += buildLine(
            adjustedClusters = adjustedClusters,
            clusterRange = lineStart..adjustedClusters.lastIndex,
            naturalWidth = naturalAccum,
            adjustedWidth = adjustedAccum,
        )
        return lines
    }

    private fun buildLine(
        adjustedClusters: List<Cluster>,
        clusterRange: IntRange,
        naturalWidth: Float,
        adjustedWidth: Float,
    ): LineCandidate {
        val first = adjustedClusters[clusterRange.first]
        val last = adjustedClusters[clusterRange.last]
        return LineCandidate(
            clusterRange = clusterRange,
            sourceRange = TextRange(first.range.start, last.range.end),
            naturalWidth = naturalWidth,
            adjustedWidth = adjustedWidth,
        )
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
 */
class LookaheadLineBreaker(
    private val window: Int = 1,
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
        pushInCapacities: Map<Int, Float>,
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
            val greedyEnd = findGreedyEnd(adjustedClusters, lineStart, maxWidth)
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
            val candidates = ((greedyEnd - window)..greedyEnd)
                .filter { it in (lineStart + 1)..adjustedClusters.size }
                .distinct()

            var bestEnd = greedyEnd
            var bestScore = Float.POSITIVE_INFINITY
            for (e in candidates) {
                val score = scoreCandidate(
                    s = lineStart,
                    e = e,
                    natural = naturalClusters,
                    adjusted = adjustedClusters,
                    maxWidth = maxWidth,
                    pushInCapacities = pushInCapacities,
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
            pushInCapacities = pushInCapacities,
            pushInPenalty = pushInPenalty,
            carryPreviousPenalty = carryPreviousPenalty,
            leaveRaggedPenalty = leaveRaggedPenalty,
        )
    }

    private fun scoreCandidate(
        s: Int,
        e: Int,
        natural: List<Cluster>,
        adjusted: List<Cluster>,
        maxWidth: Float,
        pushInCapacities: Map<Int, Float>,
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
            pushInCapacities = pushInCapacities,
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
    pushInCapacities: Map<Int, Float> = emptyMap(),
    pushInPenalty: Int,
    carryPreviousPenalty: Int,
    leaveRaggedPenalty: Int,
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
            pushInCapacities = pushInCapacities,
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
        val newPrevRange = prev.clusterRange.first..(carriedIndex - 1)
        val newCurrRange = carriedIndex..curr.clusterRange.last
        repairCandidates += RepairCandidate(
            kind = "CarryPrevious",
            reasonCode = "ForbiddenAtLineStart",
            offenderClusterIndex = curr.clusterRange.first,
            penalty = carryPreviousPenalty,
            accepted = true,
            carriedClusterIndex = carriedIndex,
        )
        mutable[i - 1] = rebuildLine(newPrevRange, naturalClusters, adjustedClusters)
        mutable[i] = rebuildLine(
            newCurrRange,
            naturalClusters,
            adjustedClusters,
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

private fun tryPushIn(
    prev: LineCandidate,
    curr: LineCandidate,
    naturalClusters: List<Cluster>,
    adjustedClusters: List<Cluster>,
    maxWidth: Float,
    pushInCapacities: Map<Int, Float>,
    pushInPenalty: Int,
): PushInResult {
    val offenderIndex = curr.clusterRange.first
    val expandedRange = prev.clusterRange.first..offenderIndex
    val expanded = rebuildLine(expandedRange, naturalClusters, adjustedClusters)
    val overflow = expanded.adjustedWidth - maxWidth

    val capacity = pushInCapacities[offenderIndex] ?: 0f
    if (overflow <= 0f || overflow > capacity) {
        return PushInResult(
            previous = prev,
            current = curr,
            candidate = RepairCandidate(
                kind = "PushIn",
                reasonCode = "ForbiddenAtLineStart",
                offenderClusterIndex = offenderIndex,
                penalty = pushInPenalty,
                accepted = false,
                rejectionReason = if (overflow <= 0f) "no-overflow" else "insufficient-capacity",
                targetClusterIndex = offenderIndex,
                requiredShrink = overflow.coerceAtLeast(0f),
                availableCapacity = capacity,
            ),
        )
    }

    val offender = adjustedClusters[offenderIndex]
    val candidate = RepairCandidate(
        kind = "PushIn",
        reasonCode = "ForbiddenAtLineStart",
        offenderClusterIndex = offenderIndex,
        penalty = pushInPenalty,
        accepted = true,
        targetClusterIndex = offenderIndex,
        shrink = overflow,
        requiredShrink = overflow,
        availableCapacity = capacity,
    )
    val repairedPrevious = expanded.copy(
        adjustedWidth = expanded.adjustedWidth - overflow,
        repair = RepairOption.PushIn(
            penalty = pushInPenalty,
            reason = "ForbiddenAtLineStart:${offender.text}:pushed-in=$overflow",
            offenderClusterIndex = offenderIndex,
            targetClusterIndex = offenderIndex,
            shrink = overflow,
            availableCapacity = capacity,
        ),
        repairCandidates = listOf(candidate),
    )
    val repairedCurrent = if (offenderIndex == curr.clusterRange.last) {
        null
    } else {
        rebuildLine((offenderIndex + 1)..curr.clusterRange.last, naturalClusters, adjustedClusters)
    }
    return PushInResult(repairedPrevious, repairedCurrent, candidate)
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
