package ink.duo3.tiqian.compose

import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import ink.duo3.tiqian.core.LayoutResult
import ink.duo3.tiqian.core.TextSpan
import ink.duo3.tiqian.core.ColorSpan
import ink.duo3.tiqian.shaping.skia.SkiaSystemTypefaces
import ink.duo3.tiqian.shaping.skia.drawTiqianGlyphs
import ink.duo3.tiqian.shaping.skia.lineInkSkipIntervals
import ink.duo3.tiqian.shaping.skia.shapeTextBlob
import ink.duo3.tiqian.shaping.skia.vertGlyphIds
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
    spans: List<TextSpan> = emptyList(),
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
        drawTiqianGlyphs(skCanvas, result, cjkFont, latinFont, paint, shaper, colorSpans = colorSpans, spans = spans)

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

        // 行间注 (ruby, ADR 0032): 注文 shaped at its own size and centred over the
        // base x-span the engine computed. We measure the real注文 width here so a
        // 注文 wider than the base overhangs symmetrically (v1; 避让 is a follow-up).
        for (ruby in result.debug.rubyDecisions) {
            // 注文 uses its OWN font (注音 needs ㄅㄆㄇ glyphs; 拼音/释义 may differ) —
            // resolved via the shared resolver, defaulting to the Latin face.
            val tf = SkiaSystemTypefaces.typeface(isLatin = true, family = ruby.fontFamilies.firstOrNull(), style = org.jetbrains.skia.FontStyle.NORMAL)
                ?: SkiaSystemTypefaces.latin
            val rubyFont = Font(tf, ruby.fontSize)
            val width = rubyFont.measureTextWidth(ruby.text)
            shapeTextBlob(shaper, ruby.text, rubyFont, result.input.textStyle.locale)?.let { blob ->
                skCanvas.drawTextBlob(blob, ruby.centerX - width / 2f, ruby.baselineY, paint)
            }
        }

        // 注音 (ADR 0033): ㄅㄆㄇ symbols fill their 9×9 box; 调号 are ink-detected and
        // scaled so their ink WIDTH fills the box, then vertically centred. FORCED CJK
        // 注文 font (the optimized large tone glyphs live there, not in Western faces).
        for (z in result.debug.zhuyinDecisions) {
            val tf = (
                SkiaSystemTypefaces.typeface(isLatin = false, family = z.fontFamilies.firstOrNull(), style = org.jetbrains.skia.FontStyle.NORMAL)
                    ?: SkiaSystemTypefaces.cjk
                ) ?: continue
            for (p in z.placements) {
                when (p.role) {
                    ink.duo3.tiqian.core.ZhuyinGlyphRole.Symbol -> {
                        val f = Font(tf, p.height) // box height = symbol 字身框 (0.3em)
                        // Centre by the VERT glyph's advance (not the plain glyph's — they
                        // can differ, e.g. half- vs full-width), since we draw the vert form.
                        val gids = vertGlyphIds(tf, shaper, p.text, result.input.textStyle.locale)
                        val adv = if (gids.isEmpty()) f.measureTextWidth(p.text) else f.getWidths(gids).sum()
                        shapeTextBlob(shaper, p.text, f, result.input.textStyle.locale, vertical = true)?.let { blob ->
                            skCanvas.drawTextBlob(blob, p.left + (p.width - adv) / 2f, p.top + p.height * 0.88f, paint)
                        }
                    }
                    ink.duo3.tiqian.core.ZhuyinGlyphRole.Neutral -> {
                        // 轻声: full-width vert glyph at the COLUMN-WIDTH size (not scaled);
                        // h-centre by its vert advance, ink-position the dot into the box.
                        val gids = vertGlyphIds(tf, shaper, p.text, result.input.textStyle.locale)
                        if (gids.isEmpty()) continue
                        val f = Font(tf, p.width) // full-width em = column width (9 份)
                        val adv = f.getWidths(gids).sum()
                        val b = f.getBounds(gids).first()
                        shapeTextBlob(shaper, p.text, f, result.input.textStyle.locale, vertical = true)?.let { blob ->
                            val drawX = p.left + (p.width - adv) / 2f
                            val baselineY = p.top + p.height / 2f - (b.top + b.bottom) / 2f
                            skCanvas.drawTextBlob(blob, drawX, baselineY, paint)
                        }
                    }
                    ink.duo3.tiqian.core.ZhuyinGlyphRole.Tone -> {
                        // Ink-detect the `vert` glyph (the form actually drawn), so the
                        // scale-to-width + vertical-centre match what lands on screen.
                        val glyphs = vertGlyphIds(tf, shaper, p.text, result.input.textStyle.locale)
                        if (glyphs.isEmpty()) continue
                        val ref = Font(tf, p.height) // a reference size; rescale to ink width
                        val refBounds = ref.getBounds(glyphs).first()
                        if (refBounds.width <= 0f) continue
                        val scaled = Font(tf, p.height * (p.width / refBounds.width))
                        val b = scaled.getBounds(glyphs).first()
                        shapeTextBlob(shaper, p.text, scaled, result.input.textStyle.locale, vertical = true)?.let { blob ->
                            // ink left → box left; ink vertical centre → box vertical centre.
                            val drawX = p.left - b.left
                            val baselineY = p.top + p.height / 2f - (b.top + b.bottom) / 2f
                            skCanvas.drawTextBlob(blob, drawX, baselineY, paint)
                        }
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

