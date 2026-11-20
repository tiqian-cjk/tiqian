package org.tiqian.layout

import org.tiqian.core.Ic
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.shaping.jvm.AwtTextShaper
import kotlin.system.measureNanoTime
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Scale and stress benchmark for [WidthIndependentAnnotationCache] across text lengths
 * ranging from 100 characters to 50,000 characters of pseudo Chinese-Latin mixed prose.
 */
class ParagraphScaleBenchmarkProbe {

    private fun generateMixedText(targetLength: Int): String {
        val fragments = listOf(
            "提椠（Tiqian）是面向中文正文的 CJK 段落布局引擎，",
            "支持 CLREQ 规范中定义的标点挤压（Punctuation Compression）与两端对齐（Justification）。",
            "在 Web 平台上，pretext 和 tiqian 分别探索了不同的折行策略与渲染路径。",
            "对于 long technical tokens 如 `https://example.com/api/v1/resource?id=12345`，引擎会进行安全回退。",
            "中西文混排时（Chinese and English typography mixed together），会根据上下文自动插入 1/4em 盘古间距。",
            "咖啡（coffee）在十七世纪经威尼斯传入欧洲，最初被当作药物出售。",
            "每一个 breakpoint 和 responsive layout 都需要在 resize 时保持绝对跟手与流畅。",
        )
        val sb = StringBuilder(targetLength + 200)
        var idx = 0
        while (sb.length < targetLength) {
            sb.append(fragments[idx % fragments.size])
            idx++
        }
        return sb.substring(0, targetLength)
    }

    @Test
    fun benchmarkScaleFrom100To50000Chars() {
        // Wall-clock probe: the resize<=cold ordering compares a single cold
        // sample against an averaged loop and the 5ms budget assumes an idle
        // desktop-class host, so a loaded CI runner can fail both without any
        // code regression. Gate behind the experiments flag like the sibling
        // probes in this directory; LayoutBenchmarkProbe keeps the always-on
        // catastrophic-regression ceiling.
        if (System.getenv("TIQIAN_RUN_EXPERIMENTS") != "1") {
            println("ParagraphScaleBenchmarkProbe: set TIQIAN_RUN_EXPERIMENTS=1 to run.")
            return
        }
        val lengths = listOf(100, 500, 2_000, 10_000, 50_000)
        val widths = floatArrayOf(800f, 760f, 720f, 680f, 640f, 600f)

        println("\n" + "=".repeat(90))
        println("=== Tiqian Layout Scale Benchmark: Cold vs Resize (WidthIndependentAnnotationCache) ===")
        println("%-8s | %-12s | %-12s | %-10s | %-18s".format(
            "Chars", "Cold (ms)", "Resize (ms)", "Speedup", "Per-1k Chars (µs)",
        ))
        println("-".repeat(90))

        for (length in lengths) {
            val text = generateMixedText(length)
            val cache = LruWidthIndependentAnnotationCache(maxEntries = 128)
            val engine = ExplainableStubParagraphLayoutEngine(
                lineBreaker = LookaheadLineBreaker(),
                textShaper = AwtTextShaper(),
                annotationCache = cache,
            )

            val baseInput = LayoutInput(
                content = TiqianTextContent(text),
                constraints = LayoutConstraints(maxWidth = widths[0]),
                paragraphStyle = ParagraphStyle(firstLineIndent = Ic(2f)),
            )

            // Warm up JVM JIT compiler
            repeat(3) {
                engine.layout(baseInput.copy(constraints = LayoutConstraints(maxWidth = widths[it % widths.size])))
            }
            cache.clear()

            // 1. Cold layout (includes shaping, fallback, punctuation atomization, ruby, autospace)
            val coldNanos = measureNanoTime {
                engine.layout(baseInput)
            }
            val coldMs = coldNanos / 1_000_000.0

            // 2. Resize layout (WidthIndependentAnnotationCache hit -> rebreak & justify only)
            val resizeIterations = when {
                length <= 500 -> 100
                length <= 2_000 -> 50
                length <= 10_000 -> 20
                else -> 5
            }
            val resizeNanos = measureNanoTime {
                repeat(resizeIterations) { i ->
                    val w = widths[(i + 1) % widths.size]
                    engine.layout(baseInput.copy(constraints = LayoutConstraints(maxWidth = w)))
                }
            }
            val resizeMs = (resizeNanos / 1_000_000.0) / resizeIterations
            val speedup = coldMs / resizeMs.coerceAtLeast(0.001)
            val usPer1kChars = (resizeMs * 1000.0) / (length / 1000.0)

            println("%-8d | %10.2f ms | %10.3f ms | %8.1fx | %16.1f µs".format(
                length, coldMs, resizeMs, speedup, usPer1kChars,
            ))

            assertTrue(
                resizeMs <= coldMs,
                "Resize layout ($resizeMs ms) must be faster than cold layout ($coldMs ms) for $length chars",
            )
            if (length <= 500) {
                assertTrue(resizeMs < 5.0, "500-char paragraph resize must take < 5ms (got $resizeMs ms)")
            }
        }
        println("=".repeat(90) + "\n")
    }
}
