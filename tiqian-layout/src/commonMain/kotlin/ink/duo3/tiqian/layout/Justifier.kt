package ink.duo3.tiqian.layout

import ink.duo3.tiqian.core.Cluster
import ink.duo3.tiqian.font.FontRole

/**
 * Justifier — distributes a line's deficit (maxWidth - adjustedWidth) across
 * glue resources in priority order:
 *
 *   1. PunctuationGlue   — opens a bounded extra slice on the glue side of
 *                          punctuation atoms (after `。，、`, before `（「`).
 *                          Boundaries collapsed by PunctuationSpacingCompressor
 *                          are EXCLUDED: the CLREQ adjacent-punctuation collapse
 *                          is a hard rule, never elastic — justification must
 *                          not re-open `」。` / `，「`.
 *   2. CjkLatinSpace     — small extra space at CJK ↔ Latin boundaries.
 *   3. WordSpace         — space inside Latin runs. Stub Latin clusters are
 *                          treated as single units, so this is a no-op until
 *                          a real shaping adapter splits them into words.
 *   4. CjkInterChar      — last resort: evenly add a small slice between
 *                          adjacent ideograph (CjkText ↔ CjkText) clusters.
 *                          Punctuation boundaries belong to tier 1, keeping
 *                          the expansion colour uniform.
 *
 * The default heuristic name for this policy chain is
 * `PunctuationGlueFirstJustification` (see ADR notes).
 *
 * Each [JustificationAllocation] targets a specific cluster: the delta is
 * understood as trailing space added to that cluster's advance.
 *
 * Boundary eligibility — named heuristic `GlueSideAwareJustification`:
 * expansion may only open on a punctuation atom's glue side, never the
 * body-anchored (solid) side. Concretely, for MainlandSimplified:
 *
 * - after an Opening mark (`（「`) — the bracket's inner side — is solid:
 *   no CjkInterChar / CjkLatinSpace expansion there;
 * - before a Closing / PauseOrStop mark (`）。，`) is solid: no expansion;
 * - the opposite sides (before Opening, after Closing) carry the atom's
 *   glue and may expand.
 *
 * Without this rule, justification visibly pushed `（Tiqian）` apart from
 * the inside — see clreq-punctuation-audit.md.
 */
class Justifier(
    private val cjkLatinSpaceEm: Float = 0.25f,
    private val cjkInterCharMaxEm: Float = 0.25f,
    /**
     * Cap for tier-1 punctuation glue expansion. Deliberately HALF the
     * inter-char cap: the punctuation blank is already 0.5em, so a 0.25em
     * stretch reads as a hole (`提椠 （` looked like a typed space).
     * 0.125em keeps tier 1 first-in-line but visually subtle.
     */
    private val punctuationGlueExpandEm: Float = 0.125f,
) {
    fun justify(
        adjustedClusters: List<Cluster>,
        clusterRoles: List<FontRole>,
        lineClusterRange: IntRange,
        maxWidth: Float,
        spacingPlan: PunctuationSpacingCompressionResult,
        fontSize: Float,
        skip: Boolean,
        clusterEdgeAnchors: Map<Int, ClusterEdgeAnchors> = emptyMap(),
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

        // 1. PunctuationGlue — bounded expansion on punctuation glue sides.
        val punctOpps = buildPunctuationGlueOpportunities(
            adjustedClusters = adjustedClusters,
            clusterRoles = clusterRoles,
            lineClusterRange = lineClusterRange,
            spacingPlan = spacingPlan,
            clusterEdgeAnchors = clusterEdgeAnchors,
            capacity = punctuationGlueExpandEm * fontSize,
        )
        remaining = allocate(
            deficit = remaining,
            opportunities = punctOpps,
            reason = "PunctuationGlueFirstJustification",
            into = allocations,
        )
        if (remaining <= 0f) return finalize(lineClusterRange, deficitBefore, remaining, allocations)

        // 2. CjkLatinSpace — open the boundary between CJK and Latin clusters.
        // `IdeographAlphaJustifyBoundary`: same boundary rule as autospace
        // (ADR 0009) — only ideograph ↔ alpha. CjkPunctuation ↔ Latin is
        // punctuation-glue territory and must not get an extra space here.
        // `TypedSpaceBoundaryDefersToWordSpace`: when the author already
        // typed a U+0020 at the boundary, the gap is a WordSpace opportunity
        // (deferred until Latin word splitting) — stacking CjkLatinSpace on
        // top doubled the visible gap.
        val cjkLatinOpps = buildBoundaryOpportunities(
            adjustedClusters = adjustedClusters,
            lineClusterRange = lineClusterRange,
            kind = GlueKind.CjkLatinSpace,
            priority = 1,
            capacity = cjkLatinSpaceEm * fontSize,
        ) { leftIdx, rightIdx ->
            clusterRoles[leftIdx].isIdeographAlphaBoundaryWith(clusterRoles[rightIdx]) &&
                !adjustedClusters[leftIdx].text.endsWith(' ') &&
                !adjustedClusters[rightIdx].text.startsWith(' ')
        }
        remaining = allocate(
            deficit = remaining,
            opportunities = cjkLatinOpps,
            reason = "CjkLatinSpace",
            into = allocations,
        )
        if (remaining <= 0f) return finalize(lineClusterRange, deficitBefore, remaining, allocations)

        // 3. WordSpace — no-op until Latin clusters split into words.

        // 4. CjkInterChar — last resort, ideograph ↔ ideograph only.
        // Punctuation-adjacent boundaries are tier-1 territory: mixing them
        // here gave punctuation gaps double weight and uneven colour.
        val cjkInterOpps = buildBoundaryOpportunities(
            adjustedClusters = adjustedClusters,
            lineClusterRange = lineClusterRange,
            kind = GlueKind.CjkInterChar,
            priority = 3,
            capacity = cjkInterCharMaxEm * fontSize,
        ) { leftIdx, rightIdx ->
            clusterRoles[leftIdx] == FontRole.CjkText && clusterRoles[rightIdx] == FontRole.CjkText
        }
        remaining = allocate(
            deficit = remaining,
            opportunities = cjkInterOpps,
            reason = "CjkInterChar",
            into = allocations,
        )

        return finalize(lineClusterRange, deficitBefore, remaining, allocations)
    }

    /**
     * Tier-1 punctuation glue expansion. A boundary qualifies when at least
     * one side is a punctuation cluster AND `GlueSideAwareJustification`
     * holds (only the atom's glue side may stretch — see [boundaryOnGlueSide]).
     *
     * Boundaries collapsed by the spacing plan (`」。` `，「` …) are excluded:
     * CLREQ's adjacent-punctuation collapse is mandatory, so justification
     * must never buy width back from it.
     *
     * The reported kind names the side that supplied the glue: trailing glue
     * of the left atom (`。→第`) or leading glue of the right atom (`中→（`).
     */
    private fun buildPunctuationGlueOpportunities(
        adjustedClusters: List<Cluster>,
        clusterRoles: List<FontRole>,
        lineClusterRange: IntRange,
        spacingPlan: PunctuationSpacingCompressionResult,
        clusterEdgeAnchors: Map<Int, ClusterEdgeAnchors>,
        capacity: Float,
    ): List<JustificationOpportunity> {
        if (capacity <= 0f) return emptyList()
        val collapsedBoundaries = spacingPlan.adjustments
            .map { it.range.start to it.range.end }
            .toSet()
        val opps = mutableListOf<JustificationOpportunity>()
        for (idx in lineClusterRange.first until lineClusterRange.last) {
            val leftPunct = clusterRoles[idx] == FontRole.CjkPunctuation
            val rightPunct = clusterRoles[idx + 1] == FontRole.CjkPunctuation
            if (!leftPunct && !rightPunct) continue
            if (!boundaryOnGlueSide(idx, idx + 1, clusterRoles, clusterEdgeAnchors)) continue
            val boundary = adjustedClusters[idx].range.start to adjustedClusters[idx + 1].range.end
            if (boundary in collapsedBoundaries) continue
            opps += JustificationOpportunity(
                targetClusterIndex = idx,
                kind = if (leftPunct) GlueKind.PunctuationTrailing else GlueKind.PunctuationLeading,
                priority = 0,
                capacity = capacity,
            )
        }
        return opps
    }

    private inline fun buildBoundaryOpportunities(
        adjustedClusters: List<Cluster>,
        lineClusterRange: IntRange,
        kind: GlueKind,
        priority: Int,
        capacity: Float,
        predicate: (leftIdx: Int, rightIdx: Int) -> Boolean,
    ): List<JustificationOpportunity> {
        if (capacity <= 0f) return emptyList()
        val opps = mutableListOf<JustificationOpportunity>()
        for (idx in lineClusterRange.first until lineClusterRange.last) {
            if (predicate(idx, idx + 1)) {
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

    /**
     * `GlueSideAwareJustification` eligibility for the boundary between
     * [leftIdx] and [rightIdx]. The allocation renders as space *between*
     * the two clusters (trailing delta on the left cluster), so:
     *
     * - left punctuation must carry glue on its trailing side — anchor
     *   Leading (`。，）」` body sits left) or Center; anchor Trailing
     *   (`（「` body sits right, boundary is the solid inner side) forbids;
     * - right punctuation must carry glue on its leading side — anchor
     *   Trailing or Center; anchor Leading forbids.
     *
     * A punctuation-role cluster without recorded edge anchors is treated
     * as solid on both sides (conservative: no expansion).
     */
    private fun boundaryOnGlueSide(
        leftIdx: Int,
        rightIdx: Int,
        clusterRoles: List<FontRole>,
        clusterEdgeAnchors: Map<Int, ClusterEdgeAnchors>,
    ): Boolean {
        val leftOk = clusterRoles[leftIdx] != FontRole.CjkPunctuation ||
            clusterEdgeAnchors[leftIdx]?.trailing.let { it != null && it != PunctuationAnchor.Trailing }
        val rightOk = clusterRoles[rightIdx] != FontRole.CjkPunctuation ||
            clusterEdgeAnchors[rightIdx]?.leading.let { it != null && it != PunctuationAnchor.Leading }
        return leftOk && rightOk
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

    private fun FontRole.isIdeographAlphaBoundaryWith(other: FontRole): Boolean =
        (this == FontRole.CjkText && other == FontRole.LatinText) ||
            (this == FontRole.LatinText && other == FontRole.CjkText)
}

/**
 * Edge anchors of a cluster's punctuation atoms, used by
 * `GlueSideAwareJustification`. `leading` / `trailing` are the anchors of
 * the atoms sitting flush at the cluster's start / end; null when that edge
 * is not punctuation.
 */
data class ClusterEdgeAnchors(
    val leading: PunctuationAnchor?,
    val trailing: PunctuationAnchor?,
)

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
