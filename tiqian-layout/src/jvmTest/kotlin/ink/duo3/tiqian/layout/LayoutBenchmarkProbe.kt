package ink.duo3.tiqian.layout

import ink.duo3.tiqian.core.LayoutConstraints
import ink.duo3.tiqian.core.LayoutInput
import ink.duo3.tiqian.core.ParagraphStyle
import ink.duo3.tiqian.core.TextAlign
import ink.duo3.tiqian.core.TiqianTextContent
import ink.duo3.tiqian.shaping.ExplainableStubTextShaper
import ink.duo3.tiqian.shaping.TextShaper
import ink.duo3.tiqian.shaping.jvm.AwtTextShaper
import kotlin.system.measureNanoTime
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Throughput baseline for the layout pipeline (Slice 6 验收). Lays out the
 * long real-text paragraph repeatedly and reports µs/layout per shaper ×
 * breaker combination. Observational; the only hard assertion is a generous
 * ceiling that catches catastrophic regressions (an accidental O(n²) in the
 * hot path), not micro-noise.
 */
class LayoutBenchmarkProbe {

    private val paragraph =
        "咖啡（coffee）在十七世纪经威尼斯传入欧洲。最初它被当作药物出售，价格高得吓人，真正" +
            "让它流行起来的是随后遍地开花的咖啡馆——读报、辩论、下棋、写作——城市生活忽然多出一个公" +
            "共客厅。意大利人做出了 espresso，维也纳人往杯里加奶油，土耳其人坚持连渣同煮……" +
            "每座城市都相信自己手里那一杯才是正统。有人说：「先有咖啡馆，后有启蒙运动」。这话说得夸张" +
            "，但也不算太离谱。"

    @Test
    fun reportLayoutThroughputBaseline() {
        val warmup = 50
        val iterations = 200
        val combos: List<Triple<String, TextShaper, LineBreaker>> = listOf(
            Triple("stub+greedy", ExplainableStubTextShaper(), GreedyLineBreaker()),
            Triple("stub+lookahead", ExplainableStubTextShaper(), LookaheadLineBreaker()),
            Triple("awt+greedy", AwtTextShaper(), GreedyLineBreaker()),
            Triple("awt+lookahead", AwtTextShaper(), LookaheadLineBreaker()),
        )

        println()
        println("=== Layout throughput baseline (${paragraph.length} chars, justify, 320px) ===")
        for ((label, shaper, breaker) in combos) {
            val engine = ExplainableStubParagraphLayoutEngine(
                lineBreaker = breaker,
                textShaper = shaper,
            )
            val input = LayoutInput(
                content = TiqianTextContent(paragraph),
                constraints = LayoutConstraints(maxWidth = 320f),
                paragraphStyle = ParagraphStyle(textAlign = TextAlign.Justify),
            )
            repeat(warmup) { engine.layout(input) }
            val nanos = measureNanoTime { repeat(iterations) { engine.layout(input) } }
            val microsPerLayout = nanos / 1000.0 / iterations
            println("%-16s %8.1f µs/layout".format(label, microsPerLayout))

            assertTrue(
                microsPerLayout < 50_000,
                "$label took ${microsPerLayout}µs per layout — order-of-magnitude regression",
            )
        }
        println()
    }
}
