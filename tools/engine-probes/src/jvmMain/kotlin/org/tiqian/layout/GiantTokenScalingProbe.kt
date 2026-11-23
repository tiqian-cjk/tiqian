package org.tiqian.layout

import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.shaping.jvm.AwtTextShaper
import kotlin.system.measureNanoTime
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * A paragraph whose content is one giant unbreakable ASCII token — the shape of a 100KB TeX
 * pixel-art source demoted to prose — must lay out in near-linear time. Planning used to be
 * quadratic on this shape (per-range cluster scans, per-boundary decision scans, per-break
 * unbreakable-range scans) and a real 106KB Zhihu formula ANR'd the app; see UnbreakableRanges
 * and clusterIndexRangeFor. The ceiling is generous against CI noise but far below the
 * quadratic behavior it guards against.
 *
 * Known defect (recorded, not fixed here): a single 80k token in cold state takes 19.5–21.6 s
 * and grows near-quadratically with input size.
 */
class GiantTokenScalingProbe {

    private fun giantTokenInput(length: Int): LayoutInput {
        val unit = "\\rlap{\\color{#BB9}{\\rule{4px}{320px}}}{"
        val token = buildString(length + unit.length) {
            while (this.length < length) append(unit)
        }.substring(0, length)
        return LayoutInput(
            content = TiqianTextContent(token),
            constraints = LayoutConstraints(maxWidth = 1248f),
            paragraphStyle = ParagraphStyle(),
        )
    }

    @Test
    fun giantTokenLayoutStaysFarBelowTheQuadraticCeiling() {
        val engine = ExplainableStubParagraphLayoutEngine(
            lineBreaker = GreedyLineBreaker(),
            textShaper = AwtTextShaper(),
        )
        val small = giantTokenInput(20_000)
        val large = giantTokenInput(80_000)
        engine.layout(small)
        engine.layout(large)
        val warm20k = (1..3).minOf { measureNanoTime { engine.layout(small) } } / 1_000_000.0
        val warm80k = (1..3).minOf { measureNanoTime { engine.layout(large) } } / 1_000_000.0
        val ratio = warm80k / warm20k
        println("giant-token 20k warm layout: $warm20k ms; 80k warm layout: $warm80k ms; ratio: $ratio")
        assertTrue(
            warm80k < 6_000.0,
            "80k single-token layout took $warm80k ms; the quadratic planning regression is back",
        )
        assertTrue(
            ratio < 6.0,
            "80k/20k warm scaling ratio $ratio (80k=$warm80k ms, 20k=$warm20k ms) exceeds 6.0; " +
                "expected near-linear (4x), quadratic would be 16x",
        )
    }

    @Test
    fun measureGiantTokenScalingMatrix() {
        if (System.getenv("TIQIAN_RUN_EXPERIMENTS") != "1") {
            println("GiantTokenScalingProbe: set TIQIAN_RUN_EXPERIMENTS=1 to run the matrix.")
            return
        }
        for (breaker in listOf("lookahead", "greedy")) {
            for (length in listOf(5_000, 10_000, 20_000, 40_000, 80_000)) {
                val engine = ExplainableStubParagraphLayoutEngine(
                    lineBreaker = if (breaker == "lookahead") LookaheadLineBreaker() else GreedyLineBreaker(),
                    textShaper = AwtTextShaper(),
                    annotationCache = LruWidthIndependentAnnotationCache(maxEntries = 8),
                )
                val input = giantTokenInput(length)
                repeat(if (length <= 10_000) 2 else 1) { engine.layout(input) }
                val warm = (1..3).minOf { measureNanoTime { engine.layout(input) } }
                val cold = measureNanoTime {
                    engine.annotationCache.clear()
                    engine.layout(input)
                }
                println(
                    "giant-token[$breaker] length=$length  warm=${warm / 1_000_000.0} ms  " +
                        "cold=${cold / 1_000_000.0} ms",
                )
            }
        }
    }
}
