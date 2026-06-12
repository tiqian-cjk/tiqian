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
    // Consumed LEADING glue shifts the glyph origin LEFT: the blob still
    // contains the font's built-in leading blank (e.g. the left half of a
    // fullwidth `“`), but the engine removed it from the cluster's advance
    // (line-start trim, 间隔号 two-sided push-in). Without the shift the ink
    // lands inside the next cluster. Trailing-side consumption needs no
    // shift — ink is origin-anchored.
    val leadingConsumedByRange = result.debug.geometryDecisions
        .filter { it.leadingGlueConsumed > 0f }
        .associate { it.range to it.leadingGlueConsumed }

    drawIntoCanvas { canvas ->
        val skCanvas = canvas.nativeCanvas
        for (line in result.lines) {
            val lineClusters = result.clusters.filter {
                it.range.start >= line.range.start && it.range.end <= line.range.end
            }
            var x = line.indent
            val baselineY = line.baseline
            for ((clusterIndexInLine, cluster) in lineClusters.withIndex()) {
                // Containment, not equality: LatinWordSegmentation splits a
                // font decision's range (' espresso') into word/space
                // clusters ('espresso') — an equality lookup misses and the
                // word silently falls back to the CJK font, whose Latin
                // glyphs are narrower than the engine-measured advance (the
                // difference surfaced as phantom whitespace after each word).
                val role = result.debug.fontDecisions.firstOrNull {
                    cluster.range.start >= it.range.start && cluster.range.end <= it.range.end
                }?.role
                val font = if (role == "LatinText") latinFont else cjkFont

                val autoSpaces = result.debug.autoSpaceDecisions
                    .filter { it.clusterRange == cluster.range }
                val leadingDecision = autoSpaces.firstOrNull { it.side == "leading" }
                val leadingStrip = leadingDecision?.charactersAffected ?: 0
                val trailingDecision = autoSpaces.firstOrNull { it.side == "trailing" }
                val trailingStrip = trailingDecision?.charactersAffected ?: 0
                val isLineStart = clusterIndexInLine == 0
                val isLineEnd = clusterIndexInLine == lineClusters.lastIndex
                // Insert decisions carry charactersAffected=0 but still gap.
                val leadingGap = if (leadingDecision != null && !isLineStart) autoSpaceGap else 0f
                val trailingGap = if (trailingDecision != null && !isLineEnd) autoSpaceGap else 0f
                val paintText = cluster.displayText
                    .drop(leadingStrip)
                    .let { if (trailingStrip > 0) it.dropLast(trailingStrip) else it }

                if (paintText.isNotEmpty()) {
                    val leadingShift = leadingConsumedByRange[cluster.range] ?: 0f
                    shapeTextBlob(shaper, paintText, font, language)?.let { blob ->
                        skCanvas.drawTextBlob(blob, x + leadingGap - leadingShift, baselineY, paint)
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

        // 示亡号 frames (ADR 0018); continuation edges stay undrawn.
        if (result.debug.decorationSegments.isNotEmpty()) {
            val framePaint = Paint().apply {
                this.color = color
                mode = org.jetbrains.skia.PaintMode.STROKE
                strokeWidth = (fontSize / 16f).coerceAtLeast(1f)
            }
            for (seg in result.debug.decorationSegments) {
                skCanvas.drawLine(seg.left, seg.top, seg.right, seg.top, framePaint)
                skCanvas.drawLine(seg.left, seg.bottom, seg.right, seg.bottom, framePaint)
                if (!seg.openStart) skCanvas.drawLine(seg.left, seg.top, seg.left, seg.bottom, framePaint)
                if (!seg.openEnd) skCanvas.drawLine(seg.right, seg.top, seg.right, seg.bottom, framePaint)
            }
        }
    }
}

/** CLREQ 着重号 glyph: U+2022 BULLET (CLREQ allows U+25CF or U+2022). */
private const val EMPHASIS_DOT = '•'
