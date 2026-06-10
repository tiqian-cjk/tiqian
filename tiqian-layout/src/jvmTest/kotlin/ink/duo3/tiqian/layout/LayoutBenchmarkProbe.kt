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
        "提椠（Tiqian）是一个面向中文正文的 CJK 段落排版引擎。第一阶段的目标不是复刻浏览器级文本系统，" +
            "而是在 shaping 之后、绘制之前的薄薄一层里——字体 fallback、CJK 度量、标点 atom、避头尾修复、" +
            "两端对齐——做出一个可观察、可调试、可扩展的物理模型。换句话说，「功能可以窄，模型必须真」。" +
            "第一阶段并不试图同时覆盖竖排、JLREQ、ruby、纵中横、编辑器、IME……这些不是被遗忘，" +
            "而是被故意推后到模型稳定之后。"

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
