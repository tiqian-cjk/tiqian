package ink.duo3.tiqian.compose

import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import ink.duo3.tiqian.core.LayoutResult
import ink.duo3.tiqian.shaping.skia.SkiaSystemTypefaces
import ink.duo3.tiqian.shaping.skia.shapeTextBlob
import org.jetbrains.skia.Font
import org.jetbrains.skia.Paint
import org.jetbrains.skia.TextLine
import org.jetbrains.skia.shaper.Shaper

/**
 * Draws a [LayoutResult] onto the Compose desktop canvas. Pure presentation:
 * x stepping comes from cluster advances the ENGINE resolved; glyphs come
 * from the shared language-tagged blob path ([shapeTextBlob]) so forms match
 * what the engine measured. The cluster walk (autospace strips, line-edge
 * gap suppression) is the same contract the playground raster implements.
 */
internal fun DrawScope.drawTiqianLayout(
    result: LayoutResult,
    color: Int = 0xFF000000.toInt(),
) {
    val fontSize = result.input.textStyle.fontSize
    val language = result.input.textStyle.locale
    val cjkFont = Font(SkiaSystemTypefaces.cjk, fontSize)
    val latinFont = Font(SkiaSystemTypefaces.latin, fontSize)
    val paint = Paint().apply { this.color = color }
    val shaper = Shaper.makeShaperDrivenWrapper()
    val autoSpaceGap = 0.25f * fontSize

    drawIntoCanvas { canvas ->
        val skCanvas = canvas.nativeCanvas
        for (line in result.lines) {
            val lineClusters = result.clusters.filter {
                it.range.start >= line.range.start && it.range.end <= line.range.end
            }
            var x = 0f
            val baselineY = line.baseline
            for ((clusterIndexInLine, cluster) in lineClusters.withIndex()) {
                val role = result.debug.fontDecisions.firstOrNull { it.range == cluster.range }?.role
                val font = if (role == "LatinText") latinFont else cjkFont

                val autoSpaces = result.debug.autoSpaceDecisions
                    .filter { it.clusterRange == cluster.range }
                val leadingStrip = autoSpaces.firstOrNull { it.side == "leading" }?.charactersAffected ?: 0
                val trailingStrip = autoSpaces.firstOrNull { it.side == "trailing" }?.charactersAffected ?: 0
                val isLineStart = clusterIndexInLine == 0
                val isLineEnd = clusterIndexInLine == lineClusters.lastIndex
                val leadingGap = if (leadingStrip > 0 && !isLineStart) autoSpaceGap else 0f
                val trailingGap = if (trailingStrip > 0 && !isLineEnd) autoSpaceGap else 0f
                val paintText = cluster.displayText
                    .drop(leadingStrip)
                    .let { if (trailingStrip > 0) it.dropLast(trailingStrip) else it }

                if (paintText.isNotEmpty()) {
                    shapeTextBlob(shaper, paintText, font, language)?.let { blob ->
                        skCanvas.drawTextBlob(blob, x + leadingGap, baselineY, paint)
                    }
                }

                if (leadingStrip > 0 || trailingStrip > 0) {
                    val paintWidth = if (paintText.isNotEmpty()) {
                        TextLine.make(paintText, font).width
                    } else {
                        0f
                    }
                    x += leadingGap + paintWidth + trailingGap
                } else {
                    x += cluster.advance
                }
            }
        }

        // Emphasis dots (ADR 0018): the dot glyph's ink centre lands on the
        // engine-decided anchor.
        val appliedDots = result.debug.decorationDecisions.filter { it.applied }
        if (appliedDots.isNotEmpty()) {
            val dotGlyph = cjkFont.getUTF32Glyph(EMPHASIS_DOT.code)
            val dotInk = cjkFont.getBounds(shortArrayOf(dotGlyph)).firstOrNull()
            val dotBlob = shapeTextBlob(shaper, EMPHASIS_DOT.toString(), cjkFont, language)
            if (dotBlob != null && dotInk != null) {
                val inkCenterX = (dotInk.left + dotInk.right) / 2f
                val inkCenterY = (dotInk.top + dotInk.bottom) / 2f
                for (dot in appliedDots) {
                    skCanvas.drawTextBlob(dotBlob, dot.anchorX - inkCenterX, dot.anchorY - inkCenterY, paint)
                }
            }
        }
    }
}

/** CLREQ 着重号 glyph: U+2022 BULLET (CLREQ allows U+25CF or U+2022). */
private const val EMPHASIS_DOT = '•'
