package ink.duo3.tiqian.compose

import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import ink.duo3.tiqian.core.LayoutResult
import ink.duo3.tiqian.shaping.skia.ColorSpan
import ink.duo3.tiqian.shaping.skia.SkiaSystemTypefaces
import ink.duo3.tiqian.shaping.skia.drawTiqianGlyphs
import ink.duo3.tiqian.shaping.skia.lineInkSkipIntervals
import org.jetbrains.skia.Font
import org.jetbrains.skia.Paint
import org.jetbrains.skia.shaper.Shaper

/**
 * Draws a [LayoutResult] onto the Compose desktop canvas. Pure presentation:
 * x stepping comes from cluster advances the ENGINE resolved; glyphs come
 * from the shared language-tagged blob path ([shapeTextBlob]) so forms match
 * what the engine measured. The cluster walk (autospace strips, line-edge
 * gap suppression) is the same contract the playground raster implements.
 */
internal fun DrawScope.drawParagraph(
    result: LayoutResult,
    color: Int = 0xFF000000.toInt(),
    colorSpans: List<ColorSpan> = emptyList(),
) {
    val fontSize = result.input.textStyle.fontSize
    val cjkFont = Font(SkiaSystemTypefaces.cjk, fontSize)
    val latinFont = Font(SkiaSystemTypefaces.latin, fontSize)
    val paint = Paint().apply { this.color = color }
    val shaper = Shaper.makeShaperDrivenWrapper()

    drawIntoCanvas { canvas ->
        val skCanvas = canvas.nativeCanvas
        // Shared cluster-walk (tiqian-shaping-skia) — same path the playground
        // raster uses, so the role-containment / leading-shift handling can't
        // drift between the two.
        drawTiqianGlyphs(skCanvas, result, cjkFont, latinFont, paint, shaper, colorSpans = colorSpans)

        // Emphasis dots (ADR 0018): a filled circle of the engine-decided
        // diameter centred on the anchor — smaller than the `•` glyph so it
        // seats in the line gap without touching the next line.
        for (dot in result.debug.decorationDecisions) {
            if (dot.applied && dot.dotDiameter > 0f) {
                skCanvas.drawCircle(dot.anchorX, dot.anchorY, dot.dotDiameter / 2f, paint)
            }
        }

        // Decoration segments (ADR 0018/0024): 示亡号 frames (continuation
        // edges stay undrawn), 专名号 straight underlines, 书名号甲式 wavy
        // underlines.
        if (result.debug.decorationSegments.isNotEmpty()) {
            val framePaint = Paint().apply {
                this.color = color
                mode = org.jetbrains.skia.PaintMode.STROKE
                strokeWidth = (fontSize / 16f).coerceAtLeast(1f)
            }
            // text-decoration-skip-ink (Compose lacks it): break the 行间线 around
            // any glyph ink that crosses it, via Skia's getIntercepts. For pure
            // CJK the line sits below the face → no intercepts → continuous; it
            // matters for Western descenders inside a 专名号/书名号 span.
            val skipPad = framePaint.strokeWidth.coerceAtLeast(1f)
            for (seg in result.debug.decorationSegments) {
                when (seg.kind) {
                    "ProperNoun" -> {
                        val skips = result.lineInkSkipIntervals(
                            result.lines[seg.lineIndex], cjkFont, latinFont, shaper, seg.top - skipPad, seg.top + skipPad,
                        )
                        keptIntervals(seg.left, seg.right, skips, skipPad) { x0, x1 ->
                            skCanvas.drawLine(x0, seg.top, x1, seg.top, framePaint)
                        }
                    }
                    "BookTitle" -> {
                        val skips = result.lineInkSkipIntervals(
                            result.lines[seg.lineIndex], cjkFont, latinFont, shaper, seg.top - skipPad, seg.top + skipPad,
                        )
                        keptIntervals(seg.left, seg.right, skips, skipPad) { x0, x1 ->
                            skCanvas.drawPath(ink.duo3.tiqian.shaping.skia.wavyLinePath(x0, x1, seg.top, fontSize), framePaint)
                        }
                    }
                    else -> {
                        skCanvas.drawLine(seg.left, seg.top, seg.right, seg.top, framePaint)
                        skCanvas.drawLine(seg.left, seg.bottom, seg.right, seg.bottom, framePaint)
                        if (!seg.openStart) skCanvas.drawLine(seg.left, seg.top, seg.left, seg.bottom, framePaint)
                        if (!seg.openEnd) skCanvas.drawLine(seg.right, seg.top, seg.right, seg.bottom, framePaint)
                    }
                }
            }
        }
    }
}

/**
 * Draws the KEPT runs of `[left, right]` — i.e. the whole span minus the [skips]
 * intervals (flat `[s0,e0,…]`, each padded by [gap] and merged) — invoking
 * [draw] per kept run. This is the skip-ink break: ink intervals are the gaps.
 */
private inline fun keptIntervals(
    left: Float,
    right: Float,
    skips: FloatArray,
    gap: Float,
    draw: (Float, Float) -> Unit,
) {
    val merged = ArrayList<FloatArray>()
    var i = 0
    while (i + 1 < skips.size) {
        val s = (skips[i] - gap).coerceIn(left, right)
        val e = (skips[i + 1] + gap).coerceIn(left, right)
        if (e > s) merged += floatArrayOf(s, e)
        i += 2
    }
    merged.sortBy { it[0] }
    var cursor = left
    for (iv in merged) {
        if (iv[0] > cursor + 0.5f) draw(cursor, iv[0])
        cursor = maxOf(cursor, iv[1])
    }
    if (cursor < right - 0.5f) draw(cursor, right)
}

