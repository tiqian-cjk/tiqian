package org.tiqian.text.layout

import org.tiqian.text.core.Cluster
import org.tiqian.text.font.FontRole

/**
 * Justifier — distributes a line's deficit (maxWidth - adjustedWidth) across
 * glue resources in priority order:
 *
 *   1. PunctuationGlue   — restores room that PunctuationSpacingCompressor
 *                          took away (capacity = the spacing plan's reduction).
 *   2. CjkLatinSpace     — small extra space at CJK ↔ Latin boundaries.
 *   3. WordSpace         — space inside Latin runs. Stub Latin clusters are
 *                          treated as single units, so this is a no-op until
 *                          a real shaping adapter splits them into words.
 *   4. CjkInterChar      — last resort: evenly add a small slice between
 *                          adjacent CJK clusters.
 *
 * The default heuristic name for this policy chain is
 * `PunctuationGlueFirstJustification` (see ADR notes).
 *
 * Each [JustificationAllocation] targets a specific cluster: the delta is
 * understood as trailing space added to that cluster's advance.
 */
class Justifier(
    private val cjkLatinSpaceEm: Float = 0.25f,
    private val cjkInterCharMaxEm: Float = 0.25f,
) {
    fun justify(
        adjustedClusters: List<Cluster>,
        clusterRoles: List<FontRole>,
        lineClusterRange: IntRange,
        maxWidth: Float,
        spacingPlan: PunctuationSpacingCompressionResult,
        fontSize: Float,
        skip: Boolean,
    ): JustificationPlan {
        require(clusterRoles.size == adjustedClusters.size) {
            "clusterRoles must align with adjustedClusters."
        }

        val first = adjustedClusters[lineClusterRange.first]
        val last = adjustedClusters[lineClusterRange.last]
        val adjustedWidth = lineClusterRange.sumOf { adjustedClusters[it].advance.toDouble() }.toFloat()
        val deficitBefore = (maxWidth - adjustedWidth).coerceAtLeast(0f)

        if (skip || deficitBefore <= 0f) {
            return JustificationPlan(
                lineClusterRange = lineClusterRange,
                allocations = emptyList(),
                deficitBefore = deficitBefore,
                unfilledDeficit = deficitBefore,
            )
        }

        var remaining = deficitBefore
        val allocations = mutableListOf<JustificationAllocation>()

        // 1. PunctuationGlue — give back what was compressed within this line.
        val punctOpps = buildPunctuationOpportunities(
            adjustedClusters = adjustedClusters,
            lineClusterRange = lineClusterRange,
            spacingPlan = spacingPlan,
        )
        remaining = allocate(
            deficit = remaining,
            opportunities = punctOpps,
            reason = "PunctuationGlueFirstJustification",
            into = allocations,
        )
        if (remaining <= 0f) return finalize(lineClusterRange, deficitBefore, remaining, allocations)

        // 2. CjkLatinSpace — open the boundary between CJK and Latin clusters.
        val cjkLatinOpps = buildBoundaryOpportunities(
            adjustedClusters = adjustedClusters,
            clusterRoles = clusterRoles,
            lineClusterRange = lineClusterRange,
            kind = GlueKind.CjkLatinSpace,
            priority = 1,
            capacity = cjkLatinSpaceEm * fontSize,
        ) { left, right -> left.isCjkLatinBoundaryWith(right) }
        remaining = allocate(
            deficit = remaining,
            opportunities = cjkLatinOpps,
            reason = "CjkLatinSpace",
            into = allocations,
        )
        if (remaining <= 0f) return finalize(lineClusterRange, deficitBefore, remaining, allocations)

        // 3. WordSpace — no-op until Latin clusters split into words.

        // 4. CjkInterChar — last resort.
        val cjkInterOpps = buildBoundaryOpportunities(
            adjustedClusters = adjustedClusters,
            clusterRoles = clusterRoles,
            lineClusterRange = lineClusterRange,
            kind = GlueKind.CjkInterChar,
            priority = 3,
            capacity = cjkInterCharMaxEm * fontSize,
        ) { left, right -> left.isCjkLike() && right.isCjkLike() }
        remaining = allocate(
            deficit = remaining,
            opportunities = cjkInterOpps,
            reason = "CjkInterChar",
            into = allocations,
        )

        return finalize(lineClusterRange, deficitBefore, remaining, allocations)
    }

    private fun buildPunctuationOpportunities(
        adjustedClusters: List<Cluster>,
        lineClusterRange: IntRange,
        spacingPlan: PunctuationSpacingCompressionResult,
    ): List<JustificationOpportunity> {
        val lineStart = adjustedClusters[lineClusterRange.first].range.start
        val lineEnd = adjustedClusters[lineClusterRange.last].range.end
        return spacingPlan.adjustments
            .filter { it.reductionTargetRange.start >= lineStart && it.reductionTargetRange.end <= lineEnd }
            .mapNotNull { adj ->
                val targetIdx = (lineClusterRange.first..lineClusterRange.last).firstOrNull { idx ->
                    val cr = adjustedClusters[idx].range
                    adj.reductionTargetRange.start >= cr.start && adj.reductionTargetRange.end <= cr.end
                } ?: return@mapNotNull null
                JustificationOpportunity(
                    targetClusterIndex = targetIdx,
                    kind = GlueKind.PunctuationTrailing,
                    priority = 0,
                    capacity = adj.reduction,
                )
            }
    }

    private inline fun buildBoundaryOpportunities(
        adjustedClusters: List<Cluster>,
        clusterRoles: List<FontRole>,
        lineClusterRange: IntRange,
        kind: GlueKind,
        priority: Int,
        capacity: Float,
        predicate: (left: FontRole, right: FontRole) -> Boolean,
    ): List<JustificationOpportunity> {
        if (capacity <= 0f) return emptyList()
        val opps = mutableListOf<JustificationOpportunity>()
        for (idx in lineClusterRange.first until lineClusterRange.last) {
            val left = clusterRoles[idx]
            val right = clusterRoles[idx + 1]
            if (predicate(left, right)) {
                opps += JustificationOpportunity(
                    targetClusterIndex = idx,
                    kind = kind,
                    priority = priority,
                    capacity = capacity,
                )
            }
        }
        return opps
    }

    private fun allocate(
        deficit: Float,
        opportunities: List<JustificationOpportunity>,
        reason: String,
        into: MutableList<JustificationAllocation>,
    ): Float {
        if (deficit <= 0f || opportunities.isEmpty()) return deficit
        val totalCapacity = opportunities.sumOf { it.capacity.toDouble() }.toFloat()
        if (totalCapacity <= 0f) return deficit

        return if (totalCapacity >= deficit) {
            val factor = deficit / totalCapacity
            opportunities.forEach { opp ->
                val alloc = opp.capacity * factor
                if (alloc > 0f) {
                    into += JustificationAllocation(
                        targetClusterIndex = opp.targetClusterIndex,
                        kind = opp.kind,
                        priority = opp.priority,
                        delta = alloc,
                        reason = reason,
                    )
                }
            }
            0f
        } else {
            opportunities.forEach { opp ->
                if (opp.capacity > 0f) {
                    into += JustificationAllocation(
                        targetClusterIndex = opp.targetClusterIndex,
                        kind = opp.kind,
                        priority = opp.priority,
                        delta = opp.capacity,
                        reason = reason,
                    )
                }
            }
            deficit - totalCapacity
        }
    }

    private fun finalize(
        lineClusterRange: IntRange,
        deficitBefore: Float,
        unfilled: Float,
        allocations: List<JustificationAllocation>,
    ): JustificationPlan = JustificationPlan(
        lineClusterRange = lineClusterRange,
        allocations = allocations,
        deficitBefore = deficitBefore,
        unfilledDeficit = unfilled.coerceAtLeast(0f),
    )

    private fun FontRole.isCjkLatinBoundaryWith(other: FontRole): Boolean =
        (isCjkLike() && other == FontRole.LatinText) ||
            (this == FontRole.LatinText && other.isCjkLike())

    private fun FontRole.isCjkLike(): Boolean =
        this == FontRole.CjkText || this == FontRole.CjkPunctuation
}

data class JustificationOpportunity(
    val targetClusterIndex: Int,
    val kind: GlueKind,
    val priority: Int,
    val capacity: Float,
)

data class JustificationAllocation(
    val targetClusterIndex: Int,
    val kind: GlueKind,
    val priority: Int,
    val delta: Float,
    val reason: String,
)

data class JustificationPlan(
    val lineClusterRange: IntRange,
    val allocations: List<JustificationAllocation>,
    val deficitBefore: Float,
    val unfilledDeficit: Float,
)
