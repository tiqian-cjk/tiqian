package org.tiqian.layout

import org.tiqian.clreq.ClreqProfile
import org.tiqian.clreq.LineAdjustmentStrategy
import org.tiqian.core.Cluster
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.core.TextRange
import org.tiqian.core.TiqianTextContent
import org.tiqian.test.EarlyLayoutFixtures
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * `LineAdjustmentPushIn` (ADR 0031 修订): the default PushInFirst pulls an
 * over-the-edge cluster in and COMPRESSES whenever the line's glue capacity
 * allows — but ONLY there, never as floor-filling on every line (the [ADR 0022]
 * over-compression trap). `PushOutOnly` reproduces greedy-then-stretch.
 */
class LineAdjustmentPushInTest {

    private val fixture = EarlyLayoutFixtures.all.first { it.id == "real-paragraph-1" }

    private fun layout(strategy: LineAdjustmentStrategy): LayoutResult {
        val base = ClreqProfile.MainlandHorizontal
        val engine = ExplainableStubParagraphLayoutEngine(
            lineBreaker = LookaheadLineBreaker(),
            clreqProfileResolver = {
                base.copy(adjustment = base.adjustment.copy(lineAdjustment = strategy))
            },
        )
        return engine.layout(
            LayoutInput(content = TiqianTextContent(fixture.text), constraints = fixture.constraints),
        )
    }

    private fun LayoutResult.fillPushInCount(): Int =
        debug.lineDecisions.count { it.repairDecision?.reasonCode == "LineAdjustmentPushIn" }

    @Test
    fun pushInFirstCompressesSomeBoundariesPushOutOnlyNone() {
        val auto = layout(LineAdjustmentStrategy.PushInFirst)
        val pushOut = layout(LineAdjustmentStrategy.PushOutOnly)

        // 仅推出 = 旧行为：从不为容纳越界字而压缩。
        assertEquals(0, pushOut.fillPushInCount(), "PushOutOnly must never fill-push-in")
        // PushInFirst 在「挤一挤放得下」处推入压缩。
        assertTrue(auto.fillPushInCount() > 0, "PushInFirst should compress at least one boundary")
        // 节约版面：Auto 行数 ≤ 仅推出。
        assertTrue(
            auto.lines.size <= pushOut.lines.size,
            "PushInFirst (${auto.lines.size}) should not need more lines than PushOutOnly (${pushOut.lines.size})",
        )
    }

    @Test
    fun pushInFirstDoesNotCompressEveryLine() {
        val auto = layout(LineAdjustmentStrategy.PushInFirst)
        // ADR 0022 guard: 压缩不是常规填充——仍应有自然/拉伸态的行，不能整段塞满。
        assertTrue(
            auto.fillPushInCount() < auto.lines.size,
            "not every line should be a fill-push-in (${auto.fillPushInCount()}/${auto.lines.size})",
        )
    }

    @Test
    fun noShrinkFillPushInCanContinueUntilTheLineIsNoLongerLoose() {
        val clusters = listOf(
            cluster(0, "甲", 30f),
            cluster(1, "乙", 30f),
            cluster(2, "丙", 20f),
            cluster(3, "丁", 20f),
            cluster(4, "戊", 20f),
            cluster(5, "己", 20f),
        )
        val lines = listOf(
            rebuildLine(0..1, clusters, clusters),
            rebuildLine(2..5, clusters, clusters),
        )

        val filled = applyFillPushIn(
            lines = lines,
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 100f,
            shrinkOpportunities = emptyList(),
            firstLineIndent = 0f,
            compressBias = 1_000_000f,
            forbiddenLineStartClusters = emptySet(),
            forbiddenLineEndClusters = emptySet(),
            unbreakableRanges = emptyList(),
            pushInPenalty = 2,
            gapBoundaries = setOf(0, 1, 2, 3, 4),
        )

        assertEquals(0..3, filled[0].clusterRange)
        assertEquals(100f, filled[0].adjustedWidth)
        assertEquals(4..5, filled[1].clusterRange)
        val repair = filled[0].repair as RepairOption.PushIn
        assertEquals(0f, repair.totalShrink)
    }

    @Test
    fun fillPushInPullsMinimalGroupToAvoidForbiddenNextHead() {
        val clusters = listOf(
            cluster(0, "甲", 30f),
            cluster(1, "乙", 30f),
            cluster(2, "势", 20f),
            cluster(3, "。", 10f),
            cluster(4, "后", 50f),
        )
        val lines = listOf(
            rebuildLine(0..1, clusters, clusters),
            rebuildLine(2..4, clusters, clusters),
        )

        val filled = applyFillPushIn(
            lines = lines,
            naturalClusters = clusters,
            adjustedClusters = clusters,
            maxWidth = 100f,
            shrinkOpportunities = emptyList(),
            firstLineIndent = 0f,
            compressBias = 1_000_000f,
            forbiddenLineStartClusters = setOf(3),
            forbiddenLineEndClusters = emptySet(),
            unbreakableRanges = emptyList(),
            pushInPenalty = 2,
            gapBoundaries = setOf(0, 1, 2, 3),
        )

        assertEquals(0..3, filled[0].clusterRange)
        assertEquals(90f, filled[0].adjustedWidth)
        assertEquals(4..4, filled[1].clusterRange)
        val repair = filled[0].repair as RepairOption.PushIn
        assertEquals(3, repair.offenderClusterIndex)
        assertEquals(0f, repair.totalShrink)
    }

    private fun cluster(index: Int, text: String, advance: Float): Cluster =
        Cluster(
            range = TextRange(index, index + 1),
            text = text,
            fontKey = "test",
            advance = advance,
        )
}
