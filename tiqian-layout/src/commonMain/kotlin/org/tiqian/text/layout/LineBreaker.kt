package org.tiqian.text.layout

import org.tiqian.text.core.Cluster
import org.tiqian.text.core.TextRange

interface LineBreaker {
    fun breakLines(
        naturalClusters: List<Cluster>,
        adjustedClusters: List<Cluster>,
        maxWidth: Float,
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
 * Slice 4b scope: CarryPrevious + LeaveRagged. PushIn and Hang need explicit
 * glue accounting / rendering overflow respectively and arrive in later
 * slices.
 */
class GreedyLineBreaker(
    private val kinsoku: KinsokuRule = ClreqKinsokuRule(),
    private val carryPreviousPenalty: Int = 10,
    private val leaveRaggedPenalty: Int = 20,
) : LineBreaker {
    override fun breakLines(
        naturalClusters: List<Cluster>,
        adjustedClusters: List<Cluster>,
        maxWidth: Float,
    ): LineSolution {
        if (adjustedClusters.isEmpty()) return LineSolution(emptyList())
        require(naturalClusters.size == adjustedClusters.size) {
            "naturalClusters and adjustedClusters must align cluster-for-cluster."
        }

        val greedy = greedyFill(naturalClusters, adjustedClusters, maxWidth)
        return applyKinsokuRepairs(greedy, naturalClusters, adjustedClusters)
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
                    naturalClusters = naturalClusters,
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
            naturalClusters = naturalClusters,
            adjustedClusters = adjustedClusters,
            clusterRange = lineStart..adjustedClusters.lastIndex,
            naturalWidth = naturalAccum,
            adjustedWidth = adjustedAccum,
        )
        return lines
    }

    private fun applyKinsokuRepairs(
        initial: List<LineCandidate>,
        naturalClusters: List<Cluster>,
        adjustedClusters: List<Cluster>,
    ): LineSolution {
        if (initial.size < 2) return LineSolution(initial)

        val mutable = initial.toMutableList()
        for (i in 1 until mutable.size) {
            val curr = mutable[i]
            val firstCluster = adjustedClusters[curr.clusterRange.first]
            if (!kinsoku.forbiddenAtLineStart(firstCluster)) continue

            val prev = mutable[i - 1]
            val canCarry = prev.clusterRange.first < prev.clusterRange.last
            if (!canCarry) {
                // Cannot repair without emptying the previous line.
                mutable[i] = curr.copy(
                    repair = RepairOption.LeaveRagged(
                        penalty = leaveRaggedPenalty,
                        reason = "ForbiddenAtLineStart:${firstCluster.text}:no-room-to-carry",
                    ),
                )
                continue
            }

            val carriedIndex = prev.clusterRange.last
            val newPrevRange = prev.clusterRange.first..(carriedIndex - 1)
            val newCurrRange = carriedIndex..curr.clusterRange.last
            mutable[i - 1] = rebuildLine(newPrevRange, naturalClusters, adjustedClusters)
            mutable[i] = rebuildLine(
                newCurrRange,
                naturalClusters,
                adjustedClusters,
                repair = RepairOption.CarryPrevious(
                    penalty = carryPreviousPenalty,
                    reason = "ForbiddenAtLineStart:${firstCluster.text}:carried=${adjustedClusters[carriedIndex].text}",
                ),
            )
        }

        val totalBadness = mutable.sumOf { (it.repair?.penalty ?: 0).toDouble() }.toFloat()
        return LineSolution(mutable, totalBadness = totalBadness)
    }

    private fun buildLine(
        naturalClusters: List<Cluster>,
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

    private fun rebuildLine(
        clusterRange: IntRange,
        naturalClusters: List<Cluster>,
        adjustedClusters: List<Cluster>,
        repair: RepairOption? = null,
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
        )
    }
}
