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
 * then starts a new line. No kinsoku repair yet (Slice 4b adds that). Uses
 * adjusted (post-compression) advances for width fitting and natural advances
 * for the line's naturalWidth field so downstream consumers can still recover
 * the pre-compression total.
 */
class GreedyLineBreaker : LineBreaker {
    override fun breakLines(
        naturalClusters: List<Cluster>,
        adjustedClusters: List<Cluster>,
        maxWidth: Float,
    ): LineSolution {
        if (adjustedClusters.isEmpty()) return LineSolution(emptyList())
        require(naturalClusters.size == adjustedClusters.size) {
            "naturalClusters and adjustedClusters must align cluster-for-cluster."
        }

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

        return LineSolution(lines)
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
