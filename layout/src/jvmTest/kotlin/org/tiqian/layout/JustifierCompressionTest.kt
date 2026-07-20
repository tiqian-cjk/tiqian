package org.tiqian.layout

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The Justifier's COMPRESSION direction (CLREQ §6.2.2.3 挤压处理的优先顺序):
 * distribute a line's surplus over tiered [ShrinkOpportunity]s, exhausting a
 * tier before the next, equal-fraction within a tier. Pure distributor — the
 * `LineAdjustmentStrategy` decides when to call it (步骤 ①).
 */
class JustifierCompressionTest {

    private val justifier = Justifier()

    private fun opp(idx: Int, tier: Int, cap: Float) =
        ShrinkOpportunity(idx, tier, cap, ShrinkChannel.TrailingGlue)

    @Test
    fun consumesTiersInAscendingOrder() {
        val opps = listOf(opp(0, 1, 2f), opp(1, 2, 5f), opp(2, 3, 5f))
        val plan = justifier.compress(surplus = 3f, shrinkOpportunities = opps)

        assertEquals(0f, plan.unfilledSurplus, 1e-4f)
        val shrinkByCluster = plan.allocations.associate { it.clusterIndex to it.shrink }
        assertEquals(2f, shrinkByCluster.getValue(0), 1e-4f) // tier 1 fully spent first
        assertEquals(1f, shrinkByCluster.getValue(1), 1e-4f) // tier 2 absorbs the rest (1 of 5)
        assertNull(shrinkByCluster[2], "tier 3 must stay untouched while tier 2 has room")
    }

    @Test
    fun sharesEqualFractionWithinATier() {
        val opps = listOf(opp(0, 2, 2f), opp(1, 2, 6f)) // same tier, total capacity 8
        val plan = justifier.compress(surplus = 4f, shrinkOpportunities = opps) // factor 0.5

        val shrinkByCluster = plan.allocations.associate { it.clusterIndex to it.shrink }
        assertEquals(1f, shrinkByCluster.getValue(0), 1e-4f) // 0.5 × 2
        assertEquals(3f, shrinkByCluster.getValue(1), 1e-4f) // 0.5 × 6
        assertEquals(0f, plan.unfilledSurplus, 1e-4f)
    }

    @Test
    fun reportsUnfilledWhenCapacityExhausted() {
        val opps = listOf(opp(0, 1, 1f), opp(1, 2, 1f)) // total capacity 2
        val plan = justifier.compress(surplus = 5f, shrinkOpportunities = opps)

        assertEquals(3f, plan.unfilledSurplus, 1e-4f) // 5 − 2 cannot be absorbed → caller must 推出
        assertEquals(2, plan.allocations.size)
    }

    @Test
    fun zeroSurplusIsNoOp() {
        val plan = justifier.compress(surplus = 0f, shrinkOpportunities = listOf(opp(0, 1, 5f)))
        assertTrue(plan.allocations.isEmpty())
        assertEquals(0f, plan.unfilledSurplus, 1e-4f)
    }
}
