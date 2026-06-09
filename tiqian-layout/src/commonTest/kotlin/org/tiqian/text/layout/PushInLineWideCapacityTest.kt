package org.tiqian.text.layout

import org.tiqian.text.core.Cluster
import org.tiqian.text.core.TextRange
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * CLREQ 推入 is an in-line glue compression, NOT a single-cluster trailing
 * shrink. When the offender's own trailing glue is insufficient, PushIn
 * may draw shrink from any preceding cluster on the same line that still
 * has compressible trailing glue (typically other `、`, `，`, `。`).
 *
 * Counterpart of ADR 0006 (hanging is opt-in): PushIn never overflows
 * maxWidth — if the line-wide capacity sum is still short, we fall through
 * to CarryPrevious/LeaveRagged.
 */
class PushInLineWideCapacityTest {

    @Test
    fun pushInAggregatesShrinkFromMultiplePrecedingClusters() {
        // 5 ideographs + `、` + 5 ideographs + `。` at maxWidth=160. Greedy
        // fills line 0 up to char 9 (=160), pushes `、` to position 5 within
        // line 0 (still fits), and tries to put `。` at line 1 start. PushIn
        // must succeed by drawing from BOTH `、`'s trailing glue and `。`'s
        // own trailing glue.
        //
        // Test geometry uses simple widths:
        //   ideograph advance = 16
        //   `、` advance = 16, trailing glue capacity = 8
        //   `。` advance = 16, trailing glue capacity = 8
        // Line 0 greedy (10 clusters * 16 = 160) just fits. Offender `。` at
        // index 10 would overflow by 16, line-wide capacity = 8 + 8 = 16.
        val clusters = mutableListOf<Cluster>()
        repeat(5) { i -> clusters += cluster(i, i + 1, "中", 16f) }
        clusters += cluster(5, 6, "、", 16f)
        repeat(4) { i -> clusters += cluster(6 + i, 7 + i, "文", 16f) }
        clusters += cluster(10, 11, "。", 16f)

        val capacities = mapOf(
            5 to 8f,   // `、` trailing glue
            10 to 8f,  // `。` trailing glue
        )

        val solution = GreedyLineBreaker().breakLines(
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 160f,
            pushInCapacities = capacities,
        )

        // PushIn must absorb the `。` into line 0.
        assertEquals(1, solution.lines.size)
        val line = solution.lines.single()
        assertEquals(0..10, line.clusterRange)
        assertEquals(160f, line.adjustedWidth)

        val repair = line.repair
        assertNotNull(repair)
        assertTrue(repair is RepairOption.PushIn)
        assertEquals(10, repair.offenderClusterIndex)
        assertEquals(16f, repair.totalShrink)
        assertEquals(16f, repair.totalAvailableCapacity)
        // Both clusters with capacity contributed in cluster order.
        assertEquals(listOf(5, 10), repair.allocations.map { it.clusterIndex })
        // Proportional split: equal capacity → equal share.
        assertEquals(8f, repair.allocations[0].shrink)
        assertEquals(8f, repair.allocations[1].shrink)
    }

    @Test
    fun pushInRejectsWhenLineWideCapacityStillInsufficient() {
        // Same shape but only 4 px of capacity remains (a single `、` worth
        // half-glue). Overflow 16 > capacity 4 → reject PushIn, fall to
        // CarryPrevious. CarryPrevious would put `文。` (=32) on a fresh
        // line below — fits if there's room. (Greedy here leaves line 1
        // ragged when carry-overflows; here CarryPrevious passes.)
        val clusters = mutableListOf<Cluster>()
        repeat(5) { i -> clusters += cluster(i, i + 1, "中", 16f) }
        clusters += cluster(5, 6, "、", 16f)
        repeat(4) { i -> clusters += cluster(6 + i, 7 + i, "文", 16f) }
        clusters += cluster(10, 11, "。", 16f)

        val solution = GreedyLineBreaker().breakLines(
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 160f,
            pushInCapacities = mapOf(5 to 4f),
        )

        // PushIn rejected. CarryPrevious takes `文` (index 9) along with `。`.
        assertEquals(2, solution.lines.size)
        assertEquals(0..8, solution.lines[0].clusterRange)
        assertEquals(9..10, solution.lines[1].clusterRange)
        val repair = solution.lines[1].repair
        assertTrue(repair is RepairOption.CarryPrevious)

        // The rejected PushIn must still be diagnostic-visible.
        val pushInCandidate = solution.lines[1].repairCandidates
            .firstOrNull { it.kind == "PushIn" }
        assertNotNull(pushInCandidate)
        assertEquals(false, pushInCandidate.accepted)
        assertEquals("insufficient-capacity", pushInCandidate.rejectionReason)
        assertEquals(4f, pushInCandidate.availableCapacity)
        assertEquals(16f, pushInCandidate.requiredShrink)
    }

    @Test
    fun pushInOffenderOnlyCapacityStillWorksBackCompat() {
        // Offender carries its own 4 px capacity, no other capacity on the
        // line. Should still behave like the pre-refactor single-cluster
        // PushIn — exactly one allocation on the offender.
        val clusters = listOf(
            cluster(0, 1, "中", 16f),
            cluster(1, 2, "文", 16f),
            cluster(2, 3, "中", 16f),
            cluster(3, 4, "。", 16f),
        )
        val solution = GreedyLineBreaker().breakLines(
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 60f,
            pushInCapacities = mapOf(3 to 4f),
        )

        assertEquals(1, solution.lines.size)
        val line = solution.lines.single()
        val repair = line.repair
        assertTrue(repair is RepairOption.PushIn)
        assertEquals(listOf(3), repair.allocations.map { it.clusterIndex })
        assertEquals(4f, repair.totalShrink)
    }

    private fun cluster(start: Int, end: Int, text: String, advance: Float): Cluster =
        Cluster(
            range = TextRange(start, end),
            text = text,
            fontKey = "test",
            advance = advance,
        )
}
