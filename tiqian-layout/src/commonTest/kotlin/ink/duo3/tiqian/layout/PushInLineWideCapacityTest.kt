package ink.duo3.tiqian.layout

import ink.duo3.tiqian.core.Cluster
import ink.duo3.tiqian.core.TextRange
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

    @Test
    fun pushInMergesOffenderThatFitsAfterChainedRepairs() {
        // Regression for the `、` / `」` line-start escape: an earlier chained
        // PushIn shortens a line, after which a later forbidden offender
        // simply FITS on its previous line. `overflow <= 0` must be treated
        // as a zero-shrink merge, not rejected as "no-overflow" (which
        // cascaded into carry-overflows → LeaveRagged).
        //
        // maxWidth=64. Greedy: [中中中」][。中中中][、中]
        //  i=1: 。 forbidden → PushIn (shrink 16 from 」+。) →
        //       line0=中中中」。(64), line1=中中中(48)
        //  i=2: 、 forbidden → expanded line1+、 = 64 → overflow 0 →
        //       zero-shrink merge → line1=中中中、(64), line2=中(16)
        val clusters = listOf(
            cluster(0, 1, "中", 16f),
            cluster(1, 2, "中", 16f),
            cluster(2, 3, "中", 16f),
            cluster(3, 4, "」", 16f),
            cluster(4, 5, "。", 16f),
            cluster(5, 6, "中", 16f),
            cluster(6, 7, "中", 16f),
            cluster(7, 8, "中", 16f),
            cluster(8, 9, "、", 16f),
            cluster(9, 10, "中", 16f),
        )
        val solution = GreedyLineBreaker().breakLines(
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 64f,
            pushInCapacities = mapOf(3 to 8f, 4 to 8f, 8 to 8f),
        )

        assertEquals(3, solution.lines.size)
        assertEquals(0..4, solution.lines[0].clusterRange)
        assertEquals(5..8, solution.lines[1].clusterRange)
        assertEquals(9..9, solution.lines[2].clusterRange)

        // No line may start with a forbidden mark.
        for (line in solution.lines) {
            val first = clusters[line.clusterRange.first].text
            assertTrue(first == "中", "line starts with forbidden '$first'")
        }

        // The zero-shrink merge is an accepted PushIn with shrink 0.
        val merge = solution.lines[1].repair
        assertTrue(merge is RepairOption.PushIn)
        assertEquals(0f, merge.totalShrink)
        assertTrue(merge.reason.endsWith("fits-no-shrink"))
        assertEquals(64f, solution.lines[1].adjustedWidth)
    }

    @Test
    fun carryPreviousRefusesToSplitUnbreakableSpan() {
        // 中中王小明。 maxWidth=80: line0 = 中中王小明 (80), line1 = 。
        // forbidden. PushIn rejected (overflow 16 > capacity 8); carrying
        // 明 (index 4) would split the 王小明 span (2..4) → the carry is
        // refused and the line stays LeaveRagged with an explicit reason.
        val clusters = listOf(
            cluster(0, 1, "中", 16f),
            cluster(1, 2, "中", 16f),
            cluster(2, 3, "王", 16f),
            cluster(3, 4, "小", 16f),
            cluster(4, 5, "明", 16f),
            cluster(5, 6, "。", 16f),
        )
        val solution = GreedyLineBreaker().breakLines(
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 80f,
            pushInCapacities = mapOf(5 to 8f),
            unbreakableRanges = listOf(2..4),
        )

        assertEquals(2, solution.lines.size)
        val repair = solution.lines[1].repair
        assertTrue(repair is RepairOption.LeaveRagged)
        assertTrue(repair.reason.endsWith("carry-would-split-mourning-span"))
        val carryCandidate = solution.lines[1].repairCandidates
            .first { it.kind == "CarryPrevious" }
        assertEquals("carry-would-split-mourning-span", carryCandidate.rejectionReason)
    }

    private fun cluster(start: Int, end: Int, text: String, advance: Float): Cluster =
        Cluster(
            range = TextRange(start, end),
            text = text,
            fontKey = "test",
            advance = advance,
        )
}
