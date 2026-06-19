package ink.duo3.tiqian.layout

import ink.duo3.tiqian.clreq.ClreqProfile
import ink.duo3.tiqian.clreq.LineAdjustmentStrategy
import ink.duo3.tiqian.core.LayoutInput
import ink.duo3.tiqian.core.LayoutResult
import ink.duo3.tiqian.core.TiqianTextContent
import ink.duo3.tiqian.test.EarlyLayoutFixtures
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * `LineAdjustmentPushIn` (ADR 0031): Auto pulls an over-the-edge cluster in and
 * COMPRESSES where 仅推出 would STRETCH — but only where 压缩 is the smaller
 * (bias-weighted) deviation, never on every line (the [ADR 0022] over-compression
 * trap). `PushOutOnly` reproduces the historical greedy-then-stretch behavior.
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

    private fun LayoutResult.stretchedLineCount(): Int =
        debug.justificationDecisions.count { it.deficitBefore > 0.001f }

    @Test
    fun autoCompressesSomeBoundariesPushOutOnlyNone() {
        val auto = layout(LineAdjustmentStrategy.Auto)
        val pushOut = layout(LineAdjustmentStrategy.PushOutOnly)

        // 仅推出 = 旧行为：从不为容纳越界字而压缩。
        assertEquals(0, pushOut.fillPushInCount(), "PushOutOnly must never fill-push-in")
        // Auto 在「挤一挤放得下」处推入压缩。
        assertTrue(auto.fillPushInCount() > 0, "Auto should compress at least one boundary")
        // 节约版面：Auto 行数 ≤ 仅推出。
        assertTrue(
            auto.lines.size <= pushOut.lines.size,
            "Auto (${auto.lines.size}) should not need more lines than PushOutOnly (${pushOut.lines.size})",
        )
    }

    @Test
    fun autoDoesNotCompressEveryLine() {
        val auto = layout(LineAdjustmentStrategy.Auto)
        // ADR 0022 guard: 压缩不是常规填充——仍应有自然/拉伸态的行，不能整段塞满。
        assertTrue(
            auto.fillPushInCount() < auto.lines.size,
            "not every line should be a fill-push-in (${auto.fillPushInCount()}/${auto.lines.size})",
        )
    }
}
