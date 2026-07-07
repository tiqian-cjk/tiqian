package org.tiqian.compose

import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import org.tiqian.core.LayoutResult
import org.tiqian.core.RichTextRole
import org.tiqian.core.RichTextLineSegment
import org.tiqian.core.RichTextSpan
import org.tiqian.core.TextSpan
import org.tiqian.core.ColorSpan
import org.tiqian.core.positionedRichTextSegments
import org.tiqian.shaping.skia.SkiaSystemTypefaces
import org.tiqian.shaping.skia.drawTiqianGlyphs
import org.tiqian.shaping.skia.lineInkSkipIntervals
import org.tiqian.shaping.skia.shapeTextBlob
import org.tiqian.shaping.skia.vertGlyphIds
import org.jetbrains.skia.Font
import org.jetbrains.skia.Paint
import org.jetbrains.skia.PaintMode
import org.jetbrains.skia.Rect
import org.jetbrains.skia.shaper.Shaper
import kotlin.math.max
import kotlin.math.min

/**
 * Draws a [LayoutResult] onto the Compose desktop canvas. Pure presentation:
 * x stepping comes from cluster advances the ENGINE resolved; glyphs come
 * from the shared language-tagged blob path ([shapeTextBlob]) so forms match
 * what the engine measured. The cluster walk (autospace strips, line-edge
 * gap suppression) is the same contract the playground raster implements.
 */
internal actual fun ContentDrawScope.drawParagraph(
    result: LayoutResult,
    color: Int,
    colorSpans: List<ColorSpan>,
    richTextSpans: List<RichTextSpan>,
    spans: List<TextSpan>,
) {
    val fontSize = result.input.textStyle.fontSize
    val cjkFont = Font(SkiaSystemTypefaces.cjk, fontSize)
    val latinFont = Font(SkiaSystemTypefaces.latin, fontSize)
    val paint = Paint().apply { this.color = color }
    val shaper = Shaper.makeShaperDrivenWrapper()

    drawIntoCanvas { canvas ->
        val skCanvas = canvas.nativeCanvas
        // Segment geometry once per draw: both backgrounds and lines consume it.
        val richTextSegments = result.positionedRichTextSegments(richTextSpans)
        drawSkiaRichTextBackgrounds(skCanvas, richTextSegments)

        // Shared cluster-walk (tiqian-shaping-skia) — same path the playground
        // raster uses, so the role-containment / leading-shift handling can't
        // drift between the two.
        drawTiqianGlyphs(skCanvas, result, cjkFont, latinFont, paint, shaper, colorSpans = colorSpans, spans = spans)
        drawSkiaRichTextLines(skCanvas, result, color, colorSpans, richTextSegments, spans, cjkFont, latinFont, shaper)

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
            val skipBandPad = framePaint.strokeWidth.coerceAtLeast(1f)
            val skipClearance = browserLikeSkipInkClearance(fontSize, framePaint.strokeWidth)
            for (seg in result.debug.decorationSegments) {
                when (seg.kind) {
                    "ProperNoun" -> {
                        drawSkiaStraightInterlinearLine(
                            canvas = skCanvas,
                            result = result,
                            lineIndex = seg.lineIndex,
                            left = seg.left,
                            right = seg.right,
                            lineY = seg.top,
                            paint = framePaint,
                            skipBandPad = skipBandPad,
                            skipClearance = skipClearance,
                            spans = spans,
                            cjkFont = cjkFont,
                            latinFont = latinFont,
                            shaper = shaper,
                        )
                    }
                    "BookTitle" -> {
                        val skips = result.lineInkSkipIntervals(
                            result.lines[seg.lineIndex],
                            cjkFont,
                            latinFont,
                            shaper,
                            seg.top - skipBandPad,
                            seg.top + skipBandPad,
                            spans,
                        )
                        keptIntervals(seg.left, seg.right, skips, skipClearance) { x0, x1 ->
                            skCanvas.drawPath(org.tiqian.shaping.skia.wavyLinePath(x0, x1, seg.top, fontSize), framePaint)
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
            val rubyStyle = org.jetbrains.skia.FontStyle(ruby.fontWeight, org.jetbrains.skia.FontStyle.NORMAL.width, org.jetbrains.skia.FontSlant.UPRIGHT)
            val tf = SkiaSystemTypefaces.typeface(isLatin = true, family = ruby.fontFamilies.firstOrNull(), style = rubyStyle)
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
        for (z in result.debug.bopomofoDecisions) {
            val tf = (
                SkiaSystemTypefaces.typeface(
                    isLatin = false,
                    family = z.fontFamilies.firstOrNull(),
                    style = org.jetbrains.skia.FontStyle(z.fontWeight, org.jetbrains.skia.FontStyle.NORMAL.width, org.jetbrains.skia.FontSlant.UPRIGHT),
                )
                    ?: SkiaSystemTypefaces.cjk
                ) ?: continue
            for (p in z.placements) {
                when (p.role) {
                    org.tiqian.core.BopomofoGlyphRole.Symbol -> {
                        val f = Font(tf, p.height) // box height = symbol 字身框 (0.3em)
                        // Centre by the VERT glyph's advance (not the plain glyph's — they
                        // can differ, e.g. half- vs full-width), since we draw the vert form.
                        val gids = vertGlyphIds(tf, shaper, p.text, result.input.textStyle.locale)
                        val adv = if (gids.isEmpty()) f.measureTextWidth(p.text) else f.getWidths(gids).sum()
                        shapeTextBlob(shaper, p.text, f, result.input.textStyle.locale, vertical = true)?.let { blob ->
                            skCanvas.drawTextBlob(blob, p.left + (p.width - adv) / 2f, p.top + p.height * 0.88f, paint)
                        }
                    }
                    org.tiqian.core.BopomofoGlyphRole.Neutral -> {
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
                    org.tiqian.core.BopomofoGlyphRole.Tone -> {
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

private fun drawSkiaRichTextBackgrounds(
    canvas: org.jetbrains.skia.Canvas,
    segments: List<RichTextLineSegment>,
) {
    val paint = Paint()
    for (seg in segments) {
        val argb = when (seg.span.role) {
            RichTextRole.Background -> seg.span.paint.argb
            RichTextRole.InlineCode -> seg.span.paint.argb ?: INLINE_CODE_BACKGROUND_COLOR
            else -> null
        } ?: continue
        paint.color = argb
        paint.mode = PaintMode.FILL
        canvas.drawRect(Rect.makeLTRB(seg.left, seg.top, seg.right, seg.bottom), paint)
    }
}

private fun drawSkiaRichTextLines(
    canvas: org.jetbrains.skia.Canvas,
    result: LayoutResult,
    color: Int,
    colorSpans: List<ColorSpan>,
    segments: List<RichTextLineSegment>,
    spans: List<TextSpan>,
    cjkFont: Font,
    latinFont: Font,
    shaper: Shaper,
) {
    val paint = Paint().apply {
        mode = PaintMode.STROKE
        strokeWidth = (result.input.textStyle.fontSize / 16f).coerceAtLeast(1f)
    }
    val skipBandPad = paint.strokeWidth.coerceAtLeast(1f)
    // Skip-ink intervals re-shape the line's clusters — memoize per (line, band)
    // so several underline segments on one line pay for shaping once per draw.
    val skipCache = HashMap<Long, FloatArray>()
    for (seg in segments) {
        val role = seg.span.role
        if (role != RichTextRole.Underline && role != RichTextRole.LineThrough) continue
        val style = spans.lastOrNull { seg.range.start >= it.range.start && seg.range.start < it.range.end }?.style
            ?: result.input.textStyle
        val rawLineY = if (role == RichTextRole.Underline) {
            // Reuse the same horizontal line geometry as 专名号: a close line below
            // the CJK face, with skip-ink only for ink that actually crosses it.
            seg.baseline + style.fontSize * INTERLINEAR_UNDERLINE_OFFSET_EM
        } else {
            seg.baseline - style.fontSize * GENERIC_LINE_THROUGH_OFFSET_EM
        }
        val lineY = rawLineY.coerceIn(seg.top + paint.strokeWidth / 2f, seg.bottom - paint.strokeWidth / 2f)
        paint.color = seg.span.paint.argb ?: colorAt(seg.range.start, color, colorSpans)
        if (role == RichTextRole.Underline) {
            drawSkiaStraightInterlinearLine(
                canvas = canvas,
                result = result,
                lineIndex = seg.lineIndex,
                left = seg.left,
                right = seg.right,
                lineY = lineY,
                paint = paint,
                skipBandPad = skipBandPad,
                skipClearance = browserLikeSkipInkClearance(style.fontSize, paint.strokeWidth),
                spans = spans,
                cjkFont = cjkFont,
                latinFont = latinFont,
                shaper = shaper,
                skipCache = skipCache,
            )
        } else {
            canvas.drawLine(seg.left, lineY, seg.right, lineY, paint)
        }
    }
}

private fun drawSkiaStraightInterlinearLine(
    canvas: org.jetbrains.skia.Canvas,
    result: LayoutResult,
    lineIndex: Int,
    left: Float,
    right: Float,
    lineY: Float,
    paint: Paint,
    skipBandPad: Float,
    skipClearance: Float,
    spans: List<TextSpan>,
    cjkFont: Font,
    latinFont: Font,
    shaper: Shaper,
    skipCache: MutableMap<Long, FloatArray>? = null,
) {
    val line = result.lines.getOrNull(lineIndex) ?: return
    val cacheKey = (lineIndex.toLong() shl 32) or (lineY.toRawBits().toLong() and 0xFFFFFFFFL)
    val skips = skipCache?.getOrPut(cacheKey) {
        result.lineInkSkipIntervals(line, cjkFont, latinFont, shaper, lineY - skipBandPad, lineY + skipBandPad, spans)
    } ?: result.lineInkSkipIntervals(line, cjkFont, latinFont, shaper, lineY - skipBandPad, lineY + skipBandPad, spans)
    keptIntervals(left, right, skips, skipClearance) { x0, x1 ->
        canvas.drawLine(x0, lineY, x1, lineY, paint)
    }
}

private fun colorAt(offset: Int, color: Int, colorSpans: List<ColorSpan>): Int =
    colorSpans.lastOrNull { offset >= it.start && offset < it.end }?.argb ?: color

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

private const val INLINE_CODE_BACKGROUND_COLOR: Int = 0x1A000000
private const val INTERLINEAR_UNDERLINE_OFFSET_EM = 0.18f
private const val GENERIC_LINE_THROUGH_OFFSET_EM = 0.30f
private const val BROWSER_LIKE_SKIP_INK_CLEARANCE_EM = 0.10f
private const val BROWSER_LIKE_SKIP_INK_CLEARANCE_MAX = 13f

private fun browserLikeSkipInkClearance(fontSize: Float, strokeWidth: Float): Float =
    min(max(strokeWidth, fontSize * BROWSER_LIKE_SKIP_INK_CLEARANCE_EM), BROWSER_LIKE_SKIP_INK_CLEARANCE_MAX)
