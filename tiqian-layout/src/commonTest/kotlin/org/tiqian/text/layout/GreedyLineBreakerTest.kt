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
