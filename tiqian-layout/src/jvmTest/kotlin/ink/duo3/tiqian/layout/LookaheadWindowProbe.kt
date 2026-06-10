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
        "咖啡（coffee）在十七世纪经威尼斯传入欧洲。最初它被当作药物出售，价格高得吓人，真正" +
            "让它流行起来的是随后遍地开花的咖啡馆——读报、辩论、下棋、写作——城市生活忽然多出一个公" +
            "共客厅。意大利人做出了 espresso，维也纳人往杯里加奶油，土耳其人坚持连渣同煮……" +
            "每座城市都相信自己手里那一杯才是正统。有人说：「先有咖啡馆，后有启蒙运动」。这话说得夸张" +
            "，但也不算太离谱。"

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
