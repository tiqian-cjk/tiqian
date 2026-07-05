package org.tiqian.layout

import org.tiqian.core.Cluster
import org.tiqian.font.FontRole

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
 * Tier-3 eligibility — UNIFORM TRACKING over every remaining 字符间距 at the
 * same share: 汉字↔汉字、汉字↔标点的任一侧、标点↔标点（含已折叠的相邻标点对），
 * AND `PunctuationLatinInterChar`: 标点↔西文（a 标点 face abutting a Western
 * word）— CLREQ tier ③「剩余所有字符间距」excludes only 不可断标点字间距 and
 * 连接号/分隔号前后, NOT 标点↔西文. Collapsed or trimmed punctuation blanks are
 * never PREFERENTIALLY refilled (their original width is gone for good), but
 * they take the uniform share like every other position — the user-ratified
 * reading of「加空白也是跟其他一样尽量均匀地加」. Excluded: 汉字↔西文 (that is
 * 中西间距, tier 2) and 西文↔西文 (word distance is tier 1, intra-word letter
 * spacing is never a tier). Atomic long marks (dash / ellipsis) also keep both
 * neighbours closed: stretching around a two-em dash reads as a generated space
 * and violates the source-preserving long-mark model.
 */
class Justifier(
    /**
     * CLREQ 拉伸第①档：「每个西文词距最大可以拉伸到半个汉字字宽」——the
     * word space's FINAL width is capped at this (absolute). Headroom is
     * `cap − naturalSpaceWidth`, so a 二分空 (0.5em) is already at the cap
     * and does not stretch (a finer proportional space would).
     */
    private val wordSpaceMaxEm: Float = 0.5f,
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
         * 中西间距的基准（autospace）宽度，拉伸从此起步。与 [cjkLatinSpaceMaxEm]
         * 是一对（`AutoSpacePolicy.gapEm..stretchMaxEm`，ADR 0009 修订），由调用方
         * 从 profile 传入——REQUIRED，避免同一数字在两处各存一份漂移。
         */
        cjkLatinSpaceBaseEm: Float,
        /**
         * CLREQ 拉伸第②档：中西间距的拉伸上限（final width）。CLREQ 字面 0.5em，
         * 注② 实践 1/3em——`AutoSpacePolicy.stretchMaxEm` 提供。
         */
        cjkLatinSpaceMaxEm: Float,
        /**
         * `NoStretchBoundaryClusters` — cluster indices whose adjacent
         * boundaries stay closed in CjkInterChar. Covers CLREQ's explicit
         * connector / solidus limit and the engine's atomic long-mark model
         * for dash / ellipsis.
         */
        noStretchBoundaryClusters: Set<Int> = emptySet(),
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
        //   (a) VIRTUAL — a CJK↔Latin cluster boundary with no typed space
        //       whose boundary-adjacent western character is alpha/numeric.
        //       `IdeographAlphaNumericJustifyBoundary`: same rule as autospace
        //       (ADR 0009); punctuation-led LatinText runs such as `/TERFism`
        //       keep Latin shaping but do not become 中西间距.
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
                // Headroom from the base 中西间距 up to the (style-set) cap.
                capacity = ((cjkLatinSpaceMaxEm - cjkLatinSpaceBaseEm) * fontSize).coerceAtLeast(0f),
            ) { leftIdx, rightIdx ->
                isIdeographAlphaNumericBoundary(leftIdx, rightIdx, adjustedClusters, clusterRoles) &&
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
        // （CLREQ「剩余所有字符间距，同时、同等量拉伸」）, uncapped (equal
        // per-boundary capacity = the whole remaining deficit, so proportional
        // allocation degenerates to an exact even split that always fills the
        // line). Uniform tracking over EVERY remaining 字符间距 — punctuation
        // solid sides and collapsed pairs included, all at the same share (no
        // preferential refill of trimmed blanks; see class doc). Eligible:
        //   - CJK↔CJK（汉字、标点任一侧、标点↔标点）;
        //   - `PunctuationLatinInterChar`: 标点↔西文 — a 标点 face abutting a
        //     Western word IS 剩余字符间距 too (CLREQ tier ③ excludes only
        //     不可断标点 + 连接号/分隔号, NOT 标点↔西文). Only 汉字↔西文 stays
        //     out — that is 中西间距, handled by tier ② above.
        // Excluded: 西文↔西文 (word distance is tier ①, intra-word never), and
        // the no-stretch boundaries.
        fun isWesternWord(idx: Int): Boolean =
            clusterRoles[idx] == FontRole.LatinText && adjustedClusters[idx].text.any { it != ' ' }
        val cjkInterOpps = buildBoundaryOpportunities(
            adjustedClusters = adjustedClusters,
            lineClusterRange = lineClusterRange,
            kind = GlueKind.CjkInterChar,
            priority = 3,
            capacity = remaining,
        ) { leftIdx, rightIdx ->
            val l = clusterRoles[leftIdx]
            val r = clusterRoles[rightIdx]
            val bothCjk = l.isCjkLike() && r.isCjkLike()
            val punctWestern = (l == FontRole.CjkPunctuation && isWesternWord(rightIdx)) ||
                (isWesternWord(leftIdx) && r == FontRole.CjkPunctuation)
            (bothCjk || punctWestern) &&
                // NoStretchBoundaryClusters: boundaries touching connectors,
                // solidus, dash, or ellipsis stay closed.
                leftIdx !in noStretchBoundaryClusters && rightIdx !in noStretchBoundaryClusters
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
     * 压缩到行长 — the COMPRESSION counterpart of [justify] (CLREQ §6.2.2.3
     * 挤压处理的优先顺序). Distributes a line's [surplus] (adjustedWidth − 行长)
     * over the engine's tiered [shrinkOpportunities] in ASCENDING tier order
     * （①行末半宽 ②西文词距 ③间隔号 ④夹注 ⑤逗顿分 ⑥中西间距 ⑦句问叹）: a tier is
     * exhausted before the next is touched; within a tier every instance shrinks
     * simultaneously by an equal fraction of its capacity (matching [allocate]'s
     * stretch sharing). Output [PushInAllocation]s reuse the existing
     * channel-based application path (ADR 0020), so this is purely the
     * direction-symmetric distributor — `LineAdjustmentStrategy` decides WHEN to
     * call it vs [justify]. `lineEndOnly` opportunities (行末削半 promotion) are
     * the caller's to filter; this only distributes what it is given.
     */
    fun compress(
        surplus: Float,
        shrinkOpportunities: List<ShrinkOpportunity>,
    ): CompressionPlan {
        if (surplus <= 0f) return CompressionPlan(emptyList(), 0f, 0f)
        var remaining = surplus
        val allocations = mutableListOf<PushInAllocation>()
        val byTier = shrinkOpportunities.filter { it.capacity > 0f }.groupBy { it.tier }
        for (tier in byTier.keys.sorted()) {
            if (remaining <= 0f) break
            val tierOpps = byTier.getValue(tier)
            val totalCapacity = tierOpps.sumOf { it.capacity.toDouble() }.toFloat()
            if (totalCapacity <= 0f) continue
            val factor = (remaining / totalCapacity).coerceAtMost(1f)
            for (opp in tierOpps) {
                val shrink = opp.capacity * factor
                if (shrink > 0f) {
                    allocations += PushInAllocation(opp.clusterIndex, shrink, opp.capacity, opp.channel)
                }
            }
            remaining -= totalCapacity * factor
        }
        return CompressionPlan(
            allocations = allocations,
            surplusBefore = surplus,
            unfilledSurplus = remaining.coerceAtLeast(0f),
        )
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

    private fun isIdeographAlphaNumericBoundary(
        leftIdx: Int,
        rightIdx: Int,
        clusters: List<Cluster>,
        roles: List<FontRole>,
    ): Boolean {
        val left = roles[leftIdx]
        val right = roles[rightIdx]
        return when {
            left == FontRole.CjkText && right == FontRole.LatinText ->
                clusters[rightIdx].text.firstOrNull()?.isAlphaNumericAutoSpaceBoundaryChar() == true
            left == FontRole.LatinText && right == FontRole.CjkText ->
                clusters[leftIdx].text.lastOrNull()?.isAlphaNumericAutoSpaceBoundaryChar() == true
            else -> false
        }
    }

    private fun Char.isAlphaNumericAutoSpaceBoundaryChar(): Boolean =
        isLetter() || isDigit()

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
     * side and an alpha/numeric western word edge on the other
     * (`TypedSinoWesternSpaceStretches`). Mirrors
     * `isIdeographAlphaNumericBoundary`: slash/bracket-adjacent typed spaces
     * are punctuation/author spacing territory, not 中西间距.
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
            roles[idx - 1] == FontRole.LatinText &&
            clusters[idx - 1].text.lastOrNull()?.isAlphaNumericAutoSpaceBoundaryChar() == true
        val rightLatinWord = idx < clusters.lastIndex &&
            roles[idx + 1] == FontRole.LatinText &&
            clusters[idx + 1].text.firstOrNull()?.isAlphaNumericAutoSpaceBoundaryChar() == true
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

/**
 * The compression counterpart of [JustificationPlan]: negative-direction
 * [PushInAllocation]s that shrink a line by [surplusBefore] − [unfilledSurplus]
 * (CLREQ §6.2.2.3). [unfilledSurplus] > 0 means even full compression could not
 * absorb the overflow — the caller (`LineAdjustmentStrategy`) must then 推出.
 */
data class CompressionPlan(
    val allocations: List<PushInAllocation>,
    val surplusBefore: Float,
    val unfilledSurplus: Float,
)
