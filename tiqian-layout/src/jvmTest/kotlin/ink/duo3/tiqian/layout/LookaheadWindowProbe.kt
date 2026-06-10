package ink.duo3.tiqian.layout

import ink.duo3.tiqian.core.LayoutConstraints
import ink.duo3.tiqian.core.LayoutInput
import ink.duo3.tiqian.core.ParagraphStyle
import ink.duo3.tiqian.core.TextAlign
import ink.duo3.tiqian.core.TiqianTextContent
import ink.duo3.tiqian.shaping.jvm.AwtTextShaper
import kotlin.test.Test

/**
 * Diagnostic probe: line-deficit distribution of the long paragraph fixture
 * under greedy vs lookahead window 1..3, with real AWT advances. Informs the
 * default window choice (roadmap: lookahead window 2~3 optimization).
 */
class LookaheadWindowProbe {

    private val paragraph =
        "提椠（Tiqian）是一个面向中文正文的 CJK 段落排版引擎。第一阶段的目标不是复刻浏览器级文本系统，" +
            "而是在 shaping 之后、绘制之前的薄薄一层里——字体 fallback、CJK 度量、标点 atom、避头尾修复、" +
            "两端对齐——做出一个可观察、可调试、可扩展的物理模型。换句话说，「功能可以窄，模型必须真」。" +
            "第一阶段并不试图同时覆盖竖排、JLREQ、ruby、纵中横、编辑器、IME……这些不是被遗忘，" +
            "而是被故意推后到模型稳定之后。"

    @Test
    fun reportDeficitsAcrossWindows() {
        val shaper = AwtTextShaper()
        val widths = listOf(240f, 320f, 400f)

        println()
        println("=== Lookahead window probe (AWT advances, justify off) ===")
        for (maxWidth in widths) {
            println("--- maxWidth=$maxWidth ---")
            val breakers: List<Pair<String, LineBreaker>> = listOf(
                "greedy" to GreedyLineBreaker(),
                "look-w1" to LookaheadLineBreaker(window = 1),
                "look-w2" to LookaheadLineBreaker(window = 2),
                "look-w3" to LookaheadLineBreaker(window = 3),
            )
            for ((label, breaker) in breakers) {
                val result = ExplainableStubParagraphLayoutEngine(
                    lineBreaker = breaker,
                    textShaper = shaper,
                ).layout(
                    LayoutInput(
                        content = TiqianTextContent(paragraph),
                        constraints = LayoutConstraints(maxWidth = maxWidth),
                        paragraphStyle = ParagraphStyle(textAlign = TextAlign.Start),
                    ),
                )
                val deficits = result.lines.dropLast(1).map { maxWidth - it.adjustedWidth }
                val repairs = result.debug.lineDecisions.mapNotNull { it.repairDecision?.kind }
                    .groupingBy { it }.eachCount()
                println(
                    "%-8s lines=%-3d maxDeficit=%6.1f avgDeficit=%6.1f repairs=%s".format(
                        label,
                        result.lines.size,
                        deficits.maxOrNull() ?: 0f,
                        if (deficits.isEmpty()) 0f else deficits.average().toFloat(),
                        repairs.ifEmpty { "none" },
                    ),
                )
            }
        }
        println()
    }
}
