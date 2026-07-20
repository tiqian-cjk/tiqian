package org.tiqian.compose

import org.tiqian.core.DecorationKind
import org.tiqian.core.DecorationSpan
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.TextRange
import org.tiqian.core.TiqianTextContent
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.shaping.skia.SkiaFontMetricsResolver
import org.tiqian.shaping.skia.SkiaSystemTypefaces
import org.tiqian.shaping.skia.SkiaTextShaper
import org.jetbrains.skia.Font
import kotlin.test.Test

/**
 * Diagnostic (no assertions): the REAL gap between a 着重号 dot's ink bottom and
 * the next line's CJK ink top, in px, using the same Skia path the Compose
 * renderer draws with. Tells us whether the dot actually clears the next line.
 */
class EmphasisClearanceProbe {

    @Test
    fun reportEmphasisToNextLineClearance() {
        val fontSize = 16f
        val engine = ExplainableStubParagraphLayoutEngine(
            lineBreaker = LookaheadLineBreaker(),
            textShaper = SkiaTextShaper(),
            fontMetricsResolver = SkiaFontMetricsResolver(),
        )
        val text = "他强调：豆子新鲜最要紧，烘焙其次。"
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent(text),
                constraints = LayoutConstraints(maxWidth = 160f),
                decorations = listOf(DecorationSpan(TextRange(4, 16), DecorationKind.Emphasis)),
            ),
        )

        val cjkFont = Font(SkiaSystemTypefaces.cjk, fontSize)
        val hanInk = cjkFont.getBounds(shortArrayOf(cjkFont.getUTF32Glyph('中'.code))).first()
        // The renderer draws a circle of the engine-emitted dotDiameter (NOT the
        // full `•` glyph), so the dot's ink half-height is dotDiameter/2.
        val dotHalf = (result.debug.decorationDecisions.firstOrNull { it.applied }?.dotDiameter ?: 0f) / 2f
        val hanInkAscent = -hanInk.top // px above baseline

        println()
        println("=== 着重号 → next-line clearance @${fontSize}px (EMPHASIS_DOT_CENTER_EM resolved) ===")
        println("lines=${result.lines.size} hanInkAscent=${"%.2f".format(hanInkAscent)} dotInkHalfHeight=${"%.2f".format(dotHalf)}")
        val dots = result.debug.decorationDecisions.filter { it.applied }
        for ((i, line) in result.lines.withIndex()) {
            val nextBaseline = result.lines.getOrNull(i + 1)?.baseline ?: continue
            val nextInkTop = nextBaseline - hanInkAscent
            val lineDots = dots.filter { it.anchorY > line.baseline - 1f && it.anchorY < nextBaseline - 1f }
            for (dot in lineDots) {
                val dotBottom = dot.anchorY + dotHalf
                println(
                    "line$i baseline=${"%.2f".format(line.baseline)} dotAnchorY=${"%.2f".format(dot.anchorY)} " +
                        "dotBottom=${"%.2f".format(dotBottom)} nextInkTop=${"%.2f".format(nextInkTop)} " +
                        "=> clearance=${"%.2f".format(nextInkTop - dotBottom)}px",
                )
            }
        }
        cjkFont.close()
    }
}
