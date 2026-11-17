package org.tiqian.compose

import org.tiqian.core.Ic
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.font.FontMetricsResolver
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.shaping.TextShaper
import org.tiqian.shaping.skia.SkiaFontMetricsResolver
import org.tiqian.shaping.skia.SkiaTextShaper
import kotlin.system.measureNanoTime
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Observational baseline for the default Desktop backend's repeated-width reflow path.
 *
 * This class drives the module-internal [BoundedComposeTextShaperCache] /
 * [BoundedComposeFontMetricsCache], so it lives in this module's jvmTest instead
 * of tools/engine-probes: making those caches public just to move a benchmark
 * would widen the published API. It is named `Test` because compose jvmTest has
 * no release lane; run it with
 * `./gradlew :platforms:compose:compose:jvmTest --tests org.tiqian.compose.ComposeReflowBenchmarkTest`.
 */
class ComposeReflowBenchmarkTest {

    private val paragraph =
        "咖啡（coffee）在十七世纪经威尼斯传入欧洲。最初它被当作药物出售，价格高得吓人，真正" +
            "让它流行起来的是随后遍地开花的咖啡馆——读报、辩论、下棋、写作——城市生活忽然多出一个公" +
            "共客厅。意大利人做出了 espresso，维也纳人往杯里加奶油，土耳其人坚持连渣同煮……" +
            "每座城市都相信自己手里那一杯才是正统。有人说：「先有咖啡馆，后有启蒙运动」。这话说得夸张" +
            "，但也不算太离谱。"

    @Test
    fun reportRepeatedWidthReflowBaseline() {
        val widths = floatArrayOf(320f, 316f, 312f, 308f, 304f)
        val iterations = 100
        println()
        println("=== Compose Desktop reflow (${paragraph.length} chars, ${widths.size} widths) ===")
        for ((label, cached) in listOf("uncached" to false, "cached" to true)) {
            val engine = engine(cached)
            val base = LayoutInput(
                content = TiqianTextContent(paragraph),
                constraints = LayoutConstraints(maxWidth = widths.first()),
                paragraphStyle = ParagraphStyle(firstLineIndent = Ic.Zero),
            )
            val coldMicros = measureNanoTime { engine.layout(base) } / 1000.0
            repeat(4) { cycle ->
                engine.layout(base.copy(constraints = LayoutConstraints(maxWidth = widths[cycle % widths.size])))
            }
            val resizeNanos = measureNanoTime {
                repeat(iterations) { index ->
                    engine.layout(
                        base.copy(constraints = LayoutConstraints(maxWidth = widths[index % widths.size])),
                    )
                }
            }
            val resizeMicros = resizeNanos / 1000.0 / iterations
            println("%-10s cold=%8.1f µs  resize=%8.1f µs/layout".format(label, coldMicros, resizeMicros))
            assertTrue(resizeMicros < 50_000, "$label resize path regressed to $resizeMicros µs/layout")
        }
        println()
    }

    private fun engine(cached: Boolean): ExplainableStubParagraphLayoutEngine {
        val rawShaper: TextShaper = SkiaTextShaper()
        val rawMetrics: FontMetricsResolver = SkiaFontMetricsResolver()
        return ExplainableStubParagraphLayoutEngine(
            lineBreaker = LookaheadLineBreaker(),
            textShaper = if (cached) BoundedComposeTextShaperCache(rawShaper) else rawShaper,
            fontMetricsResolver = if (cached) BoundedComposeFontMetricsCache(rawMetrics) else rawMetrics,
        )
    }
}
