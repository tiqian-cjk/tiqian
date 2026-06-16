package ink.duo3.tiqian.layout

import ink.duo3.tiqian.core.Cluster
import ink.duo3.tiqian.font.FontRole

/**
 * Justifier — distributes a line's deficit (maxWidth - adjustedWidth) across
 * glue resources in CLREQ's expansion order（拉伸处理的优先顺序）:
 *
 *   1. WordSpace         — space inside Latin runs（西文词距，CLREQ 第一档）.
 *                          Word spaces are standalone clusters after
 *                          `LatinWordSegmentation`; all instances in a line
 *                          stretch simultaneously by equal amounts.
 *   2. CjkLatinSpace     — the sino-western gap（中西间距）: stretches from
 *                          the autospace base (0.25em) by up to another
 *                          0.25em — total 0.5em, CLREQ's upper bound.
 *   3. CjkInterChar      — last resort: EVEN inter-character expansion
 *                          （平均拉大字距）, UNCAPPED — CLREQ's final tier
 *                          has no upper bound, and a justified line left
 *                          short reads as an untrimmed line-end blank.
 *
 * CLREQ's expansion list has no punctuation-space tier: punctuation
 * adjustment space participates in COMPRESSION only. The earlier tier-1
 * (`PunctuationGlueFirstJustification`) is removed accordingly — see
 * ADR 0004 amendments.
 *
 * Each [JustificationAllocation] targets a specific cluster: the delta is
 * understood as trailing space added to that cluster's advance.
 *
 * Tier-3 eligibility — `CjkOnlyInterCharBoundary`: 平均拉大字距 is UNIFORM
 * TRACKING over every CJK↔CJK boundary（汉字↔汉字、汉字↔标点的任一侧、
 * 标点↔标点——含已折叠的相邻标点对）, all at the same share. Collapsed or
 * trimmed punctuation blanks are never PREFERENTIALLY refilled (their
 * original width is gone for good), but they take the uniform share like
 * every other position — the user-ratified reading of「加空白也是跟其他
 * 一样尽量均匀地加」. Excluded: any boundary touching a Latin-role cluster
 * — intra-word letter spacing does not exist as a tier at all, punctuation↔
 * Latin never stretches（「中文标点与西文之间不加间距」）, and ideograph↔
 * alpha belongs to tier 2.
 */
class Justifier(
    private val cjkLatinSpaceEm: Float = 0.25f,
    /**
     * CLREQ 拉伸第①档：「每个西文词距最大可以拉伸到半个汉字字宽」——the
     * word space's FINAL width is capped at this (absolute). Headroom is
     * `cap − naturalSpaceWidth`, so a 二分空 (0.5em) is already at the cap
     * and does not stretch (a finer proportional space would).
     */
    private val wordSpaceMaxEm: Float = 0.5f,
    /** CLREQ 拉伸第②档：中西间距 final width cap（≤半个汉字字宽）. */
    private val cjkLatinSpaceMaxEm: Float = 0.5f,
) {
    fun justify(
        adjustedClusters: List<Cluster>,
        clusterRoles: List<FontRole>,
        lineClusterRange: IntRange,
        maxWidth: Float,
        fontSize: Float,
        skip: Boolean,
        /**
         * 「在一些排版风格中，中西间距固定默认宽度……不允许被拉伸」—
         * false disables the CjkLatinSpace tier (AdjustmentStylePolicy).
         */
        allowSinoWesternGapStretch: Boolean = true,
        /**
         * `AvoidStretchAroundConnectors` — CLREQ 平均拉大字距的限制②：
         * 「避免对连接号、分隔号与其前后的字符进行拉伸处理」。Cluster
         * indices of Connector / Solidus marks; boundaries touching them
         * are excluded from the CjkInterChar tier.
         */
        avoidStretchClusters: Set<Int> = emptySet(),
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

        // 1. WordSpace — stretch Latin word spaces（CLREQ 拉伸第一档：西文
        // 词距，一行内多处应同时、同等量处理）. A word space is a space-run
        // cluster between two Latin word clusters; sino-western gap spaces
        // (CJK-adjacent) are normalised by autospace and are NOT word
        // spaces. Line-edge-collapsed spaces (advance 0) are skipped.
        // Equal caps + proportional allocation = equal amounts.
        val wordSpaceOpps = buildList {
            for (idx in lineClusterRange) {
                if (!adjustedClusters[idx].isWordSpaceBetweenLatin(idx, adjustedClusters, clusterRoles)) continue
                val naturalWidth = adjustedClusters[idx].advance
                if (naturalWidth <= 0f) continue
                // Headroom to the absolute cap (CLREQ ≤ 0.5em final width);
                // a 二分空 already at the cap gets none.
                val headroom = (wordSpaceMaxEm * fontSize - naturalWidth).coerceAtLeast(0f)
                if (headroom <= 0f) continue
                add(
                    JustificationOpportunity(
                        targetClusterIndex = idx,
                        kind = GlueKind.WordSpace,
                        priority = 0,
                        capacity = headroom,
                    ),
                )
            }
        }
        remaining = allocate(
            deficit = remaining,
            opportunities = wordSpaceOpps,
            reason = "WordSpace",
            into = allocations,
        )
        if (remaining <= 0f) return finalize(lineClusterRange, deficitBefore, remaining, allocations)

        // 2. CjkLatinSpace — the sino-western gap（中西间距）, stretched from its
        // 0.25em base up to 0.5em, every instance in the line by equal amounts
        // (CLREQ 拉伸第②档：同时、同等量). The same gap takes two shapes:
        //
        //   (a) VIRTUAL — a CJK↔Latin cluster boundary with no typed space.
        //       `IdeographAlphaJustifyBoundary`: same rule as autospace
        //       (ADR 0009), ideograph ↔ alpha only; CjkPunctuation ↔ Latin is
        //       punctuation-glue territory and gets nothing here.
        //   (b) TYPED — an author U+0020 between an ideograph and a Latin word,
        //       which autospace normalised to the 0.25em base. It IS the 中西
        //       间距 and must stretch too (`TypedSinoWesternSpaceStretches`).
        //       Earlier `TypedSpaceBoundaryDefersToWordSpace` deferred it to the
        //       WordSpace tier, but a CJK-adjacent space is not a word space, so
        //       it fell through ALL tiers — a「了 espresso」line then stretched
        //       only on its CJK half. The virtual boundary still excludes typed
        //       spaces so the same gap is never counted twice.
        val cjkLatinOpps = if (!allowSinoWesternGapStretch) {
            emptyList()
        } else {
            buildBoundaryOpportunities(
                adjustedClusters = adjustedClusters,
                lineClusterRange = lineClusterRange,
                kind = GlueKind.CjkLatinSpace,
                priority = 1,
                capacity = cjkLatinSpaceEm * fontSize,
            ) { leftIdx, rightIdx ->
                clusterRoles[leftIdx].isIdeographAlphaBoundaryWith(clusterRoles[rightIdx]) &&
                    !adjustedClusters[leftIdx].text.endsWith(' ') &&
                    !adjustedClusters[rightIdx].text.startsWith(' ')
            } + buildList {
                for (idx in lineClusterRange) {
                    if (!adjustedClusters[idx].isSinoWesternTypedSpace(idx, adjustedClusters, clusterRoles)) continue
                    // A space collapsed to 0 at a line edge (LineEdgeWordSpaceCollapse)
                    // must NOT be revived as a stretchable gap, or the trimmed edge
                    // blank reappears at 0.5em.
                    val width = adjustedClusters[idx].advance
                    if (width <= 0f) continue
                    val headroom = (cjkLatinSpaceMaxEm * fontSize - width).coerceAtLeast(0f)
                    if (headroom <= 0f) continue
                    add(
                        JustificationOpportunity(
                            targetClusterIndex = idx,
                            kind = GlueKind.CjkLatinSpace,
                            priority = 1,
                            capacity = headroom,
                        ),
                    )
                }
            }
        }
        remaining = allocate(
            deficit = remaining,
            opportunities = cjkLatinOpps,
            reason = "CjkLatinSpace",
            into = allocations,
        )
        if (remaining <= 0f) return finalize(lineClusterRange, deficitBefore, remaining, allocations)

        // 3. CjkInterChar — last resort: EVEN expansion across boundaries
        // （CLREQ「平均拉大字距」）, uncapped (equal per-boundary capacity =
        // the whole remaining deficit, so proportional allocation degenerates
        // to an exact even split that always fills the line).
        // `CjkOnlyInterCharBoundary`: uniform tracking over EVERY CJK↔CJK
        // boundary — punctuation solid sides and collapsed pairs included,
        // all at the same share (no preferential refill of trimmed blanks;
        // see class doc). Latin-touching boundaries never qualify.
        val cjkInterOpps = buildBoundaryOpportunities(
            adjustedClusters = adjustedClusters,
            lineClusterRange = lineClusterRange,
            kind = GlueKind.CjkInterChar,
            priority = 3,
            capacity = remaining,
        ) { leftIdx, rightIdx ->
            clusterRoles[leftIdx].isCjkLike() && clusterRoles[rightIdx].isCjkLike() &&
                // AvoidStretchAroundConnectors: boundaries touching 连接号/
                // 分隔号 stay closed（CLREQ 拉伸限制②）.
                leftIdx !in avoidStretchClusters && rightIdx !in avoidStretchClusters
        }
        remaining = allocate(
            deficit = remaining,
            opportunities = cjkInterOpps,
            reason = "CjkInterChar",
            into = allocations,
        )

        return finalize(lineClusterRange, deficitBefore, remaining, allocations)
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

    private fun FontRole.isCjkLike(): Boolean =
        this == FontRole.CjkText || this == FontRole.CjkPunctuation

    /**
     * A word space: a space-run cluster whose nearest non-space context is
     * Latin on both sides. CJK-adjacent space clusters are sino-western
     * gaps (autospace's territory), not word spaces.
     */
    private fun Cluster.isWordSpaceBetweenLatin(
        idx: Int,
        clusters: List<Cluster>,
        roles: List<FontRole>,
    ): Boolean {
        if (text.isEmpty() || !text.all { it == ' ' }) return false
        if (roles[idx] != FontRole.LatinText) return false
        val prevLatinWord = idx > 0 &&
            roles[idx - 1] == FontRole.LatinText &&
            !clusters[idx - 1].text.all { it == ' ' }
        val nextLatinWord = idx < clusters.lastIndex &&
            roles[idx + 1] == FontRole.LatinText &&
            !clusters[idx + 1].text.all { it == ' ' }
        return prevLatinWord && nextLatinWord
    }

    /**
     * A typed sino-western gap: a space-run cluster with an ideograph on one
     * side and a Latin WORD on the other (`TypedSinoWesternSpaceStretches`).
     * Mirrors `isIdeographAlphaBoundaryWith` (CjkText ↔ LatinText only — a
     * punctuation-adjacent typed space is glue territory, not 中西间距).
     */
    private fun Cluster.isSinoWesternTypedSpace(
        idx: Int,
        clusters: List<Cluster>,
        roles: List<FontRole>,
    ): Boolean {
        if (text.isEmpty() || !text.all { it == ' ' }) return false
        val leftCjk = idx > 0 && roles[idx - 1] == FontRole.CjkText
        val rightCjk = idx < clusters.lastIndex && roles[idx + 1] == FontRole.CjkText
        val leftLatinWord = idx > 0 &&
            roles[idx - 1] == FontRole.LatinText && !clusters[idx - 1].text.all { it == ' ' }
        val rightLatinWord = idx < clusters.lastIndex &&
            roles[idx + 1] == FontRole.LatinText && !clusters[idx + 1].text.all { it == ' ' }
        return (leftCjk && rightLatinWord) || (leftLatinWord && rightCjk)
    }
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
