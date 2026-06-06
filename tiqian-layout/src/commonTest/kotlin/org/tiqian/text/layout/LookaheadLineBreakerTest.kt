package org.tiqian.text.layout

import org.tiqian.text.core.Cluster
import org.tiqian.text.core.TextRange
import kotlin.test.Test
import kotlin.test.assertEquals

class LookaheadLineBreakerTest {

    @Test
    fun emptyInputProducesNoLines() {
        val solution = LookaheadLineBreaker().breakLines(emptyList(), emptyList(), maxWidth = 100f)
        assertEquals(0, solution.lines.size)
    }

    @Test
    fun lookaheadMatchesGreedyWhenShiftingEarlierGivesNoBenefit() {
        // 6 plain CJK clusters at maxWidth=64. No forbidden punctuation anywhere,
        // so greedy's 4+2 split has lowest badness — shifting earlier just adds
        // raggedness for nothing.
        val clusters = (0 until 6).map { i -> cluster(i, i + 1, "x", 16f) }
        val solution = LookaheadLineBreaker().breakLines(clusters, clusters, maxWidth = 64f)

        assertEquals(2, solution.lines.size)
        assertEquals(0..3, solution.lines[0].clusterRange)
        assertEquals(4..5, solution.lines[1].clusterRange)
        assertEquals(0f, solution.totalBadness)
    }

    @Test
    fun lookaheadShiftsBreakEarlierToAvoidKinsokuRepair() {
        // Greedy + kinsoku on `中文中文中文。` at maxWidth=48 produces a
        // CarryPrevious repair on the last line. Lookahead (window=1) detects
        // that shifting the first break one cluster earlier dissolves the
        // conflict and prefers that layout despite the added raggedness on
        // line 0 (rag 16 * 0.5 = 8) being less than the repair penalty (10).
        val clusters = listOf(
            cluster(0, 1, "中", 16f),
            cluster(1, 2, "文", 16f),
            cluster(2, 3, "中", 16f),
            cluster(3, 4, "文", 16f),
            cluster(4, 5, "中", 16f),
            cluster(5, 6, "文", 16f),
            cluster(6, 7, "。", 16f),
        )

        val greedy = GreedyLineBreaker().breakLines(clusters, clusters, maxWidth = 48f)
        val lookahead = LookaheadLineBreaker().breakLines(clusters, clusters, maxWidth = 48f)

        // Greedy ends up with a CarryPrevious repair.
        assertEquals(3, greedy.lines.size)
        assertEquals(true, greedy.lines[2].repair is RepairOption.CarryPrevious)
        assertEquals(10f, greedy.totalBadness)

        // Lookahead avoids the conflict entirely.
        assertEquals(3, lookahead.lines.size)
        assertEquals(null, lookahead.lines[0].repair)
        assertEquals(null, lookahead.lines[1].repair)
        assertEquals(null, lookahead.lines[2].repair)
        assertEquals(0f, lookahead.totalBadness)

        // Concrete shape: 32 / 48 / 32 instead of greedy's 48 / 32 / 32.
        assertEquals(32f, lookahead.lines[0].adjustedWidth)
        assertEquals(48f, lookahead.lines[1].adjustedWidth)
        assertEquals(32f, lookahead.lines[2].adjustedWidth)
        assertEquals(0..1, lookahead.lines[0].clusterRange)
        assertEquals(2..4, lookahead.lines[1].clusterRange)
        assertEquals(5..6, lookahead.lines[2].clusterRange)
    }

    @Test
    fun lookaheadKeepsGreedyBreakWhenPushInGlueCoversRepair() {
        val clusters = listOf(
            cluster(0, 1, "中", 16f),
            cluster(1, 2, "文", 16f),
            cluster(2, 3, "中", 16f),
            cluster(3, 4, "。", 16f),
        )
        val solution = LookaheadLineBreaker().breakLines(
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 60f,
            pushInCapacities = mapOf(3 to 4f),
        )

        assertEquals(1, solution.lines.size)
        val line = solution.lines.single()
        assertEquals(0..3, line.clusterRange)
        assertEquals(60f, line.adjustedWidth)
        assertEquals(true, line.repair is RepairOption.PushIn)
        assertEquals(2f, solution.totalBadness)
    }

    @Test
    fun lookaheadScoresFuturePushInBeforeChoosingEarlierBreak() {
        val clusters = listOf(
            cluster(0, 1, "中", 16f),
            cluster(1, 2, "文", 16f),
            cluster(2, 3, "中", 16f),
            cluster(3, 4, "文", 16f),
            cluster(4, 5, "中", 16f),
            cluster(5, 6, "文", 16f),
            cluster(6, 7, "。", 16f),
        )
        val solution = LookaheadLineBreaker().breakLines(
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 60f,
            pushInCapacities = mapOf(6 to 4f),
        )

        assertEquals(2, solution.lines.size)
        assertEquals(0..2, solution.lines[0].clusterRange)
        assertEquals(3..6, solution.lines[1].clusterRange)
        assertEquals(60f, solution.lines[1].adjustedWidth)
        assertEquals(true, solution.lines[1].repair is RepairOption.PushIn)
        assertEquals(2f, solution.totalBadness)
    }

    @Test
    fun lookaheadFallsBackToGreedyWhenAlternativesAreWorse() {
        // No forbidden punctuation and an em of raggedness saved by greedy.
        // Lookahead should not prefer earlier breaks here.
        val clusters = (0 until 9).map { i -> cluster(i, i + 1, "x", 16f) }
        val solution = LookaheadLineBreaker().breakLines(clusters, clusters, maxWidth = 64f)

        assertEquals(3, solution.lines.size)
        assertEquals(0..3, solution.lines[0].clusterRange)
        assertEquals(4..7, solution.lines[1].clusterRange)
        assertEquals(8..8, solution.lines[2].clusterRange)
    }

    @Test
    fun windowZeroReducesLookaheadToGreedy() {
        // window=0 means only the greedy break is considered.
        val clusters = listOf(
            cluster(0, 1, "中", 16f),
            cluster(1, 2, "文", 16f),
            cluster(2, 3, "中", 16f),
            cluster(3, 4, "文", 16f),
            cluster(4, 5, "中", 16f),
            cluster(5, 6, "文", 16f),
            cluster(6, 7, "。", 16f),
        )
        val solution = LookaheadLineBreaker(window = 0).breakLines(clusters, clusters, maxWidth = 48f)

        // Same as greedy: CarryPrevious on last line.
        assertEquals(3, solution.lines.size)
        assertEquals(true, solution.lines[2].repair is RepairOption.CarryPrevious)
    }

    private fun cluster(start: Int, end: Int, text: String, advance: Float): Cluster =
        Cluster(
            range = TextRange(start, end),
            text = text,
            fontKey = "test",
            advance = advance,
        )
}
