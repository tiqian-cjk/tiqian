package org.tiqian.text.layout

import org.tiqian.text.core.Cluster
import org.tiqian.text.core.TextRange
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class GreedyLineBreakerTest {
    private val breaker = GreedyLineBreaker()

    @Test
    fun emptyInputProducesNoLines() {
        val solution = breaker.breakLines(emptyList(), emptyList(), maxWidth = 100f)
        assertEquals(0, solution.lines.size)
    }

    @Test
    fun singleClusterFitsOnOneLine() {
        val clusters = listOf(cluster(0, 1, "中", 16f))
        val solution = breaker.breakLines(clusters, clusters, maxWidth = 64f)
        assertEquals(1, solution.lines.size)
        val line = solution.lines.single()
        assertEquals(0..0, line.clusterRange)
        assertEquals(TextRange(0, 1), line.sourceRange)
        assertEquals(16f, line.naturalWidth)
        assertEquals(16f, line.adjustedWidth)
    }

    @Test
    fun fillsLineUntilOverflowThenStartsNewLine() {
        val clusters = (0 until 5).map { i -> cluster(i, i + 1, "x", 16f) }
        // maxWidth = 48f -> 3 clusters fit (48f), 4th overflows.
        val solution = breaker.breakLines(clusters, clusters, maxWidth = 48f)
        assertEquals(2, solution.lines.size)
        assertEquals(0..2, solution.lines[0].clusterRange)
        assertEquals(48f, solution.lines[0].adjustedWidth)
        assertEquals(3..4, solution.lines[1].clusterRange)
        assertEquals(32f, solution.lines[1].adjustedWidth)
    }

    @Test
    fun naturalAndAdjustedWidthsTrackIndependently() {
        // Cluster 1 is compressed: natural=16f, adjusted=12f.
        val natural = listOf(cluster(0, 1, "，", 16f), cluster(1, 2, "。", 16f))
        val adjusted = listOf(cluster(0, 1, "，", 16f), cluster(1, 2, "。", 12f))
        val solution = breaker.breakLines(natural, adjusted, maxWidth = 64f)
        val line = solution.lines.single()
        assertEquals(32f, line.naturalWidth)
        assertEquals(28f, line.adjustedWidth)
    }

    @Test
    fun clusterWiderThanMaxWidthGetsOwnLineRatherThanInfiniteLoop() {
        // First cluster narrow, second cluster wider than maxWidth.
        val clusters = listOf(
            cluster(0, 1, "中", 16f),
            cluster(1, 8, "English", 112f),
        )
        val solution = breaker.breakLines(clusters, clusters, maxWidth = 80f)
        assertEquals(2, solution.lines.size)
        assertEquals(0..0, solution.lines[0].clusterRange)
        assertEquals(1..1, solution.lines[1].clusterRange)
        assertEquals(112f, solution.lines[1].adjustedWidth)
    }

    @Test
    fun kinsokuCarryPreviousMovesPrevClusterToNextLine() {
        val clusters = listOf(
            cluster(0, 1, "a", 16f),
            cluster(1, 2, "b", 16f),
            cluster(2, 3, "c", 16f),
            cluster(3, 4, "。", 16f), // forbidden at line start per ClreqKinsokuRule
        )
        // maxWidth=48f -> greedy line 0 = a,b,c (48f), line 1 = 。 (16f).
        val solution = GreedyLineBreaker().breakLines(clusters, clusters, maxWidth = 48f)

        assertEquals(2, solution.lines.size)
        assertEquals(0..1, solution.lines[0].clusterRange)
        assertEquals(2..3, solution.lines[1].clusterRange)
        assertEquals(32f, solution.lines[0].adjustedWidth)
        assertEquals(32f, solution.lines[1].adjustedWidth)
        val repair = solution.lines[1].repair
        assertEquals(true, repair is RepairOption.CarryPrevious)
        assertEquals(10f, solution.totalBadness)
    }

    @Test
    fun kinsokuPushesForbiddenPunctuationIntoPreviousLineWhenGlueCapacityCoversOverflow() {
        val clusters = listOf(
            cluster(0, 1, "a", 16f),
            cluster(1, 2, "b", 16f),
            cluster(2, 3, "c", 16f),
            cluster(3, 4, "。", 16f), // forbidden at line start per ClreqKinsokuRule
        )
        // maxWidth=60f -> greedy line 0 = a,b,c (48f), line 1 = 。 (16f).
        // Pushing 。 into line 0 would overflow by 4f; punctuation trailing
        // glue capacity covers that, so PushIn is preferred over CarryPrevious.
        val solution = GreedyLineBreaker().breakLines(
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 60f,
            pushInCapacities = mapOf(3 to 4f),
        )

        assertEquals(1, solution.lines.size)
        val line = solution.lines.single()
        assertEquals(0..3, line.clusterRange)
        assertEquals(64f, line.naturalWidth)
        assertEquals(60f, line.adjustedWidth)
        val repair = line.repair
        assertEquals(true, repair is RepairOption.PushIn)
        repair as RepairOption.PushIn
        assertEquals(3, repair.targetClusterIndex)
        assertEquals(4f, repair.shrink)
        assertEquals(2f, solution.totalBadness)
    }

    @Test
    fun kinsokuCarriesPreviousWhenPushInCapacityCannotCoverOverflow() {
        val clusters = listOf(
            cluster(0, 1, "a", 16f),
            cluster(1, 2, "b", 16f),
            cluster(2, 3, "c", 16f),
            cluster(3, 4, "。", 16f),
        )
        val solution = GreedyLineBreaker().breakLines(
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 59f,
            pushInCapacities = mapOf(3 to 4f),
        )

        assertEquals(2, solution.lines.size)
        assertEquals(0..1, solution.lines[0].clusterRange)
        assertEquals(2..3, solution.lines[1].clusterRange)
        assertEquals(true, solution.lines[1].repair is RepairOption.CarryPrevious)
    }

    @Test
    fun kinsokuLeaveRaggedWhenPrevLineIsSingleCluster() {
        // Force prev line to single cluster: clusters[0] alone is wider than maxWidth.
        val clusters = listOf(
            cluster(0, 7, "English", 112f),
            cluster(7, 8, "。", 16f),
        )
        val solution = GreedyLineBreaker().breakLines(clusters, clusters, maxWidth = 64f)

        assertEquals(2, solution.lines.size)
        val repair = solution.lines[1].repair
        assertEquals(true, repair is RepairOption.LeaveRagged)
        assertEquals(20f, solution.totalBadness)
    }

    @Test
    fun customKinsokuRuleOverridesDefault() {
        // Inject a rule that never forbids -> no repair even when 。 would lead line.
        val breaker = GreedyLineBreaker(
            kinsoku = object : KinsokuRule {
                override fun forbiddenAtLineStart(cluster: Cluster) = false
                override fun forbiddenAtLineEnd(cluster: Cluster) = false
            },
        )
        val clusters = listOf(
            cluster(0, 1, "a", 16f),
            cluster(1, 2, "b", 16f),
            cluster(2, 3, "c", 16f),
            cluster(3, 4, "。", 16f),
        )
        val solution = breaker.breakLines(clusters, clusters, maxWidth = 48f)
        assertEquals(2, solution.lines.size)
        assertEquals(null, solution.lines[1].repair)
        assertEquals(0f, solution.totalBadness)
    }

    @Test
    fun misalignedClusterListsThrow() {
        val a = listOf(cluster(0, 1, "中", 16f), cluster(1, 2, "文", 16f))
        val b = listOf(cluster(0, 1, "中", 16f))
        assertFailsWith<IllegalArgumentException> {
            breaker.breakLines(a, b, maxWidth = 100f)
        }
    }

    private fun cluster(start: Int, end: Int, text: String, advance: Float): Cluster =
        Cluster(
            range = TextRange(start, end),
            text = text,
            fontKey = "test",
            advance = advance,
        )
}
