package org.tiqian.layout

import org.tiqian.core.Cluster
import org.tiqian.core.LineEndReason
import org.tiqian.core.TextRange
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
            shrinkOpportunities = listOf(
                ShrinkOpportunity(3, tier = 6, capacity = 4f, channel = ShrinkChannel.TrailingGlue),
            ),
        )

        assertEquals(1, solution.lines.size)
        val line = solution.lines.single()
        assertEquals(0..3, line.clusterRange)
        assertEquals(64f, line.naturalWidth)
        assertEquals(60f, line.adjustedWidth)
        val repair = line.repair
        assertEquals(true, repair is RepairOption.PushIn)
        repair as RepairOption.PushIn
        assertEquals(3, repair.offenderClusterIndex)
        assertEquals(4f, repair.totalShrink)
        assertEquals(4f, repair.totalAvailableCapacity)
        assertEquals(listOf(3), repair.allocations.map { it.clusterIndex })
        assertEquals(4f, repair.allocations.single().shrink)
        assertEquals(4f, repair.allocations.single().availableCapacity)
        assertEquals(1, line.repairCandidates.size)
        assertEquals("PushIn", line.repairCandidates.single().kind)
        assertEquals(true, line.repairCandidates.single().accepted)
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
            shrinkOpportunities = listOf(
                ShrinkOpportunity(3, tier = 6, capacity = 4f, channel = ShrinkChannel.TrailingGlue),
            ),
        )

        assertEquals(2, solution.lines.size)
        assertEquals(0..1, solution.lines[0].clusterRange)
        assertEquals(2..3, solution.lines[1].clusterRange)
        assertEquals(true, solution.lines[1].repair is RepairOption.CarryPrevious)
        assertEquals(2, solution.lines[1].repairCandidates.size)
        assertEquals("PushIn", solution.lines[1].repairCandidates[0].kind)
        assertEquals(false, solution.lines[1].repairCandidates[0].accepted)
        assertEquals("insufficient-capacity", solution.lines[1].repairCandidates[0].rejectionReason)
        assertEquals("CarryPrevious", solution.lines[1].repairCandidates[1].kind)
        assertEquals(true, solution.lines[1].repairCandidates[1].accepted)
    }

    @Test
    fun kinsokuRejectsCarryPreviousWhenCarriedLineWouldOverflow() {
        val clusters = listOf(
            cluster(0, 1, "a", 16f),
            cluster(1, 2, "b", 16f),
            cluster(2, 3, "c", 16f),
            cluster(3, 4, "d", 16f),
            cluster(4, 5, "。", 16f),
            cluster(5, 6, "e", 16f),
            cluster(6, 7, "f", 16f),
            cluster(7, 8, "g", 16f),
        )
        val solution = GreedyLineBreaker().breakLines(
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 64f,
        )

        assertEquals(2, solution.lines.size)
        assertEquals(0..3, solution.lines[0].clusterRange)
        assertEquals(4..7, solution.lines[1].clusterRange)
        assertEquals(64f, solution.lines[1].adjustedWidth)
        assertEquals(true, solution.lines[1].repair is RepairOption.LeaveRagged)
        assertEquals(3, solution.lines[1].repairCandidates.size)
        assertEquals("PushIn", solution.lines[1].repairCandidates[0].kind)
        assertEquals(false, solution.lines[1].repairCandidates[0].accepted)
        assertEquals("insufficient-capacity", solution.lines[1].repairCandidates[0].rejectionReason)
        assertEquals("CarryPrevious", solution.lines[1].repairCandidates[1].kind)
        assertEquals(false, solution.lines[1].repairCandidates[1].accepted)
        assertEquals("carry-overflows", solution.lines[1].repairCandidates[1].rejectionReason)
        assertEquals(3, solution.lines[1].repairCandidates[1].carriedClusterIndex)
        assertEquals("LeaveRagged", solution.lines[1].repairCandidates[2].kind)
        assertEquals(true, solution.lines[1].repairCandidates[2].accepted)
        assertEquals(20f, solution.totalBadness)
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

    @Test
    fun hangsPauseStopPastMeasureWhenEnabledAndPushInCannotFit() {
        // a,b,c,d,。 maxWidth=64: greedy = [a b c d](64), [。]. PushIn needs
        // 16 but 。 carries no shrink opportunity here → with hanging enabled
        // 。 hangs at the end of line 0 (beyond the measure) instead of
        // CarryPrevious pulling d down.
        val clusters = listOf(
            cluster(0, 1, "a", 16f),
            cluster(1, 2, "b", 16f),
            cluster(2, 3, "c", 16f),
            cluster(3, 4, "d", 16f),
            cluster(4, 5, "。", 16f),
        )
        val solution = breaker.breakLines(
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 64f,
            hangableClusters = setOf(4),
        )

        assertEquals(1, solution.lines.size)
        val line = solution.lines.single()
        assertEquals(0..4, line.clusterRange)
        assertEquals(4, line.hangingClusterIndex)
        // Measure-fill width excludes the hung mark (content a b c d = 64).
        assertEquals(64f, line.adjustedWidth)
        val repair = line.repair
        assertEquals(true, repair is RepairOption.Hang)
        repair as RepairOption.Hang
        assertEquals(4, repair.offenderClusterIndex)
        val candidate = line.repairCandidates.single { it.kind == "Hang" }
        assertEquals(true, candidate.accepted)
    }

    @Test
    fun doesNotHangWhenDisabled() {
        // Same shape, hanging off (empty set) → CarryPrevious pulls d down.
        val clusters = listOf(
            cluster(0, 1, "a", 16f),
            cluster(1, 2, "b", 16f),
            cluster(2, 3, "c", 16f),
            cluster(3, 4, "d", 16f),
            cluster(4, 5, "。", 16f),
        )
        val solution = breaker.breakLines(
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 64f,
        )

        assertEquals(2, solution.lines.size)
        assertEquals(null, solution.lines[0].hangingClusterIndex)
        assertEquals(true, solution.lines[1].repair is RepairOption.CarryPrevious)
    }

    @Test
    fun pushInStillPreferredOverHangWhenGlueCovers() {
        // 。 carries trailing-glue capacity ≥ overflow → PushIn keeps it in
        // the measure; hanging is the fallback, not the first choice.
        val clusters = listOf(
            cluster(0, 1, "a", 16f),
            cluster(1, 2, "b", 16f),
            cluster(2, 3, "c", 16f),
            cluster(3, 4, "。", 16f),
        )
        val solution = breaker.breakLines(
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 60f,
            shrinkOpportunities = listOf(
                ShrinkOpportunity(3, tier = 6, capacity = 8f, channel = ShrinkChannel.TrailingGlue),
            ),
            hangableClusters = setOf(3),
        )

        assertEquals(1, solution.lines.size)
        assertEquals(null, solution.lines[0].hangingClusterIndex)
        assertEquals(true, solution.lines[0].repair is RepairOption.PushIn)
    }

    @Test
    fun retreatsBreakSoLineDoesNotEndOnOpeningMark() {
        // 中中（中中 maxWidth=48: greedy fills 中中（ (48), 中 overflows. The
        // line would END on （ (forbidden at line end) → break retreats to
        // 中中, the （ moves to the next line's start (cascade-free).
        val clusters = listOf(
            cluster(0, 1, "中", 16f),
            cluster(1, 2, "中", 16f),
            cluster(2, 3, "（", 16f),
            cluster(3, 4, "中", 16f),
            cluster(4, 5, "中", 16f),
        )
        val solution = breaker.breakLines(
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 48f,
            forbiddenLineEndClusters = setOf(2),
        )

        assertEquals(2, solution.lines.size)
        assertEquals(0..1, solution.lines[0].clusterRange)
        assertEquals(2..4, solution.lines[1].clusterRange)
        val repair = solution.lines[0].repair
        assertEquals(true, repair is RepairOption.CarryNext)
        repair as RepairOption.CarryNext
        assertEquals(2, repair.movedClusterIndex)
    }

    @Test
    fun keepsOpenerAtLineEndWhenItIsTheLineSoleCluster() {
        // （中中中 maxWidth=16: greedy line 0 = （ alone (next overflows).
        // Retreating would empty the line → the violation is kept (no
        // infinite shorten), 中 starts line 1.
        val clusters = listOf(
            cluster(0, 1, "（", 16f),
            cluster(1, 2, "中", 16f),
            cluster(2, 3, "中", 16f),
        )
        val solution = breaker.breakLines(
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 16f,
            forbiddenLineEndClusters = setOf(0),
        )
        assertEquals(0..0, solution.lines[0].clusterRange)
        assertEquals(null, solution.lines[0].repair)
    }

    @Test
    fun mandatoryBreakClosesLineAndPreservesTrailingEmptyLine() {
        val clusters = listOf(
            cluster(0, 1, "中", 16f),
            cluster(1, 2, "\n", 0f, displayText = ""),
        )
        val solution = breaker.breakLines(
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 160f,
            hardBreakAfterClusters = setOf(1),
        )

        assertEquals(2, solution.lines.size)
        assertEquals(0..1, solution.lines[0].clusterRange)
        assertEquals(LineEndReason.MandatoryBreak, solution.lines[0].endReason)
        assertEquals(TextRange(2, 2), solution.lines[1].sourceRange)
        assertEquals(LineEndReason.ParagraphEnd, solution.lines[1].endReason)
    }

    @Test
    fun mandatoryBreakBlocksKinsokuRepairAcrossBoundary() {
        val clusters = listOf(
            cluster(0, 1, "中", 16f),
            cluster(1, 2, "\n", 0f, displayText = ""),
            cluster(2, 3, "。", 16f),
        )
        val solution = breaker.breakLines(
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 160f,
            hardBreakAfterClusters = setOf(1),
        )

        assertEquals(2, solution.lines.size)
        assertEquals(0..1, solution.lines[0].clusterRange)
        assertEquals(2..2, solution.lines[1].clusterRange)
        assertEquals(null, solution.lines[1].repair)
    }

    private fun cluster(
        start: Int,
        end: Int,
        text: String,
        advance: Float,
        displayText: String = text,
    ): Cluster =
        Cluster(
            range = TextRange(start, end),
            text = text,
            displayText = displayText,
            fontKey = "test",
            advance = advance,
        )
}
