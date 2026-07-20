package org.tiqian.compose

import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Rect
import android.graphics.RectF
import android.text.TextPaint
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import org.tiqian.core.Glyph
import org.tiqian.core.Cluster
import org.tiqian.core.ColorSpan
import org.tiqian.core.DecorationKind
import org.tiqian.core.LayoutResult
import org.tiqian.core.LineBox
import org.tiqian.core.RichTextLineSegment
import org.tiqian.core.RichTextRole
import org.tiqian.core.RichTextSpan
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.BopomofoGlyphRole
import org.tiqian.core.positionedClusters
import org.tiqian.core.positionedRichTextSegments
import org.tiqian.font.FontRole
import org.tiqian.shaping.android.AndroidPositionedGlyphFontRegistry
import org.tiqian.shaping.android.AndroidTypefaceResolver
import org.tiqian.shaping.android.SystemAndroidTypefaceResolver
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

private val AndroidRendererTypefaces = SystemAndroidTypefaceResolver()

internal actual fun ContentDrawScope.drawParagraph(
    result: LayoutResult,
    color: Int,
    colorSpans: List<ColorSpan>,
    richTextSpans: List<RichTextSpan>,
    spans: List<TextSpan>,
) {
    drawIntoCanvas { canvas ->
        val native = canvas.nativeCanvas
        // Segment geometry once per draw: both backgrounds and lines consume it.
        val richTextSegments = result.positionedRichTextSegments(richTextSpans)
        drawAndroidRichTextBackgrounds(native, richTextSegments)
        drawAndroidGlyphs(native, result, color, colorSpans, spans, AndroidRendererTypefaces)
        drawAndroidRichTextLines(native, result, color, colorSpans, richTextSegments, spans, AndroidRendererTypefaces)
        drawAndroidDecorations(native, result, color, colorSpans, spans, AndroidRendererTypefaces)
        drawAndroidRuby(native, result, color, AndroidRendererTypefaces)
        drawAndroidBopomofo(native, result, color, AndroidRendererTypefaces)
    }
}

private fun drawAndroidGlyphs(
    canvas: android.graphics.Canvas,
    result: LayoutResult,
    color: Int,
    colorSpans: List<ColorSpan>,
    spans: List<TextSpan>,
    typefaces: AndroidTypefaceResolver,
) {
    val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        textLocale = Locale.forLanguageTag(result.input.textStyle.locale)
    }
    val glyphsByClusterRange = result.glyphRuns
        .flatMap { it.glyphs }
        .groupBy { it.clusterRange }
    result.forEachAndroidPositionedCluster(spans) { _, cluster, drawX, baselineY, run ->
        paint.color = colorSpans.lastOrNull { cluster.range.start >= it.start && cluster.range.start < it.end }?.argb ?: color
        paint.textSize = run.style.fontSize
        paint.typeface = typefaces.resolve(run.role, run.style.fontFamilies, run.style.fontWeight, run.style.italic)
        paint.fontFeatureSettings = null
        val glyphs = glyphsByClusterRange[cluster.range].orEmpty()
        // minSdk 31 == Android S, so Canvas.drawGlyphs is always available; per-glyph
        // replay falls back to contextual string drawing only when a glyph's shaped
        // Font key is missing/evicted (drawPositionedGlyphs returns false).
        if (drawPositionedGlyphs(canvas, glyphs, drawX, baselineY, paint)) {
            return@forEachAndroidPositionedCluster
        }
        // CjkPunctuation clusters need the full-buffer clipped draw (context GSUB);
        // plain 汉字 are context-independent and keep the cheaper sub-range draw.
        //
        // ItalicContextBufferLeakGuard: slanted context glyphs can overhang past
        // the pen-span clip and appear as ink that does not belong to the target
        // cluster. For italic punctuation, prefer target-only drawing over
        // leaking the synthetic context buffer.
        val clipToContext = run.role == FontRole.CjkPunctuation && !run.style.italic
        drawContextShapedText(canvas, cluster.displayText, drawX, baselineY, run.role, paint, clipToContext)
    }

    val hyphenPaint = TextPaint(paint).apply {
        this.color = color
        textSize = result.input.textStyle.fontSize
        typeface = result.input.textStyle.let { style ->
            typefaces.resolve(FontRole.LatinText, style.fontFamilies, style.fontWeight, style.italic)
        }
    }
    for (line in result.lines) {
        if (line.hyphenAdvance > 0f) {
            drawContextShapedText(canvas, "-", line.indent + line.visualWidth, line.baseline, FontRole.LatinText, hyphenPaint)
        }
    }
}

private fun drawPositionedGlyphs(
    canvas: android.graphics.Canvas,
    glyphs: List<Glyph>,
    originX: Float,
    originY: Float,
    paint: Paint,
): Boolean {
    if (glyphs.isEmpty()) return false
    val fonts = glyphs.map { glyph ->
        val key = glyph.renderFontKey ?: return false
        AndroidPositionedGlyphFontRegistry.fontFor(key) ?: return false
    }

    var start = 0
    while (start < glyphs.size) {
        val font = fonts[start]
        var end = start + 1
        while (end < glyphs.size && fonts[end] === font) {
            end += 1
        }
        val count = end - start
        val ids = IntArray(count) { index -> glyphs[start + index].id.toInt() }
        val positions = FloatArray(count * 2) { index ->
            val glyph = glyphs[start + index / 2]
            if (index % 2 == 0) originX + glyph.x else originY + glyph.y
        }
        canvas.drawGlyphs(ids, 0, positions, 0, count, font, paint)
        start = end
    }
    return true
}

private fun drawAndroidDecorations(
    canvas: android.graphics.Canvas,
    result: LayoutResult,
    color: Int,
    colorSpans: List<ColorSpan>,
    spans: List<TextSpan>,
    typefaces: AndroidTypefaceResolver,
) {
    val fontSize = result.input.textStyle.fontSize
    val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        style = Paint.Style.FILL
    }
    for (dot in result.debug.decorationDecisions) {
        if (dot.applied && dot.dotDiameter > 0f) {
            fillPaint.color = colorAt(dot.clusterRange.start, color, colorSpans)
            canvas.drawCircle(dot.anchorX, dot.anchorY, dot.dotDiameter / 2f, fillPaint)
        }
    }

    if (result.debug.decorationSegments.isEmpty()) return
    val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        style = Paint.Style.STROKE
        strokeWidth = (fontSize / 16f).coerceAtLeast(1f)
    }
    val skipBandPad = strokePaint.strokeWidth.coerceAtLeast(1f)
    val skipClearance = browserLikeSkipInkClearance(fontSize, strokePaint.strokeWidth)
    for (seg in result.debug.decorationSegments) {
        strokePaint.color = colorAt(seg.sourceRange.start, color, colorSpans)
        when (seg.kind) {
            DecorationKind.ProperNoun.name -> {
                drawAndroidStraightInterlinearLine(
                    canvas = canvas,
                    result = result,
                    lineIndex = seg.lineIndex,
                    left = seg.left,
                    right = seg.right,
                    lineY = seg.top,
                    paint = strokePaint,
                    skipBandPad = skipBandPad,
                    skipClearance = skipClearance,
                    spans = spans,
                    typefaces = typefaces,
                )
            }
            DecorationKind.BookTitle.name -> {
                val skips = result.androidLineInkSkipIntervals(
                    result.lines[seg.lineIndex], seg.top - skipBandPad, seg.top + skipBandPad, spans, typefaces,
                )
                keptIntervals(seg.left, seg.right, skips, skipClearance) { x0, x1 ->
                    canvas.drawPath(wavyLinePath(x0, x1, seg.top, fontSize), strokePaint)
                }
            }
            else -> {
                canvas.drawLine(seg.left, seg.top, seg.right, seg.top, strokePaint)
                canvas.drawLine(seg.left, seg.bottom, seg.right, seg.bottom, strokePaint)
                if (!seg.openStart) canvas.drawLine(seg.left, seg.top, seg.left, seg.bottom, strokePaint)
                if (!seg.openEnd) canvas.drawLine(seg.right, seg.top, seg.right, seg.bottom, strokePaint)
            }
        }
    }
}

private fun drawAndroidRichTextBackgrounds(
    canvas: android.graphics.Canvas,
    segments: List<RichTextLineSegment>,
) {
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    for (seg in segments) {
        val argb = when (seg.span.role) {
            RichTextRole.Background -> seg.span.paint.argb
            RichTextRole.InlineCode -> seg.span.paint.argb ?: INLINE_CODE_BACKGROUND_COLOR
            else -> null
        } ?: continue
        paint.color = argb
        canvas.drawRect(seg.left, seg.top, seg.right, seg.bottom, paint)
    }
}

private fun drawAndroidRichTextLines(
    canvas: android.graphics.Canvas,
    result: LayoutResult,
    color: Int,
    colorSpans: List<ColorSpan>,
    segments: List<RichTextLineSegment>,
    spans: List<TextSpan>,
    typefaces: AndroidTypefaceResolver,
) {
    val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = (result.input.textStyle.fontSize / 16f).coerceAtLeast(1f)
    }
    val skipBandPad = strokePaint.strokeWidth.coerceAtLeast(1f)
    // Skip-ink intervals re-measure the line's clusters — memoize per (line, band)
    // so several underline segments on one line pay for the walk once per draw.
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
        val lineY = rawLineY.coerceIn(seg.top + strokePaint.strokeWidth / 2f, seg.bottom - strokePaint.strokeWidth / 2f)
        strokePaint.color = seg.span.paint.argb ?: colorAt(seg.range.start, color, colorSpans)
        if (role == RichTextRole.Underline) {
            drawAndroidStraightInterlinearLine(
                canvas = canvas,
                result = result,
                lineIndex = seg.lineIndex,
                left = seg.left,
                right = seg.right,
                lineY = lineY,
                paint = strokePaint,
                skipBandPad = skipBandPad,
                skipClearance = browserLikeSkipInkClearance(style.fontSize, strokePaint.strokeWidth),
                spans = spans,
                typefaces = typefaces,
                skipCache = skipCache,
            )
        } else {
            canvas.drawLine(seg.left, lineY, seg.right, lineY, strokePaint)
        }
    }
}

private fun drawAndroidStraightInterlinearLine(
    canvas: android.graphics.Canvas,
    result: LayoutResult,
    lineIndex: Int,
    left: Float,
    right: Float,
    lineY: Float,
    paint: Paint,
    skipBandPad: Float,
    skipClearance: Float,
    spans: List<TextSpan>,
    typefaces: AndroidTypefaceResolver,
    skipCache: MutableMap<Long, FloatArray>? = null,
) {
    val line = result.lines.getOrNull(lineIndex) ?: return
    val cacheKey = (lineIndex.toLong() shl 32) or (lineY.toRawBits().toLong() and 0xFFFFFFFFL)
    val skips = skipCache?.getOrPut(cacheKey) {
        result.androidLineInkSkipIntervals(line, lineY - skipBandPad, lineY + skipBandPad, spans, typefaces)
    } ?: result.androidLineInkSkipIntervals(line, lineY - skipBandPad, lineY + skipBandPad, spans, typefaces)
    keptIntervals(left, right, skips, skipClearance) { x0, x1 ->
        canvas.drawLine(x0, lineY, x1, lineY, paint)
    }
}

private fun colorAt(offset: Int, color: Int, colorSpans: List<ColorSpan>): Int =
    colorSpans.lastOrNull { offset >= it.start && offset < it.end }?.argb ?: color

private fun drawAndroidRuby(
    canvas: android.graphics.Canvas,
    result: LayoutResult,
    color: Int,
    typefaces: AndroidTypefaceResolver,
) {
    val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        textLocale = Locale.forLanguageTag(result.input.textStyle.locale)
    }
    for (ruby in result.debug.rubyDecisions) {
        paint.textSize = ruby.fontSize
        paint.typeface = typefaces.resolve(FontRole.LatinText, ruby.fontFamilies, ruby.fontWeight, italic = false)
        paint.fontFeatureSettings = null
        val width = paint.measureText(ruby.text)
        drawContextShapedText(canvas, ruby.text, ruby.centerX - width / 2f, ruby.baselineY, FontRole.LatinText, paint)
    }
}

private fun drawAndroidBopomofo(
    canvas: android.graphics.Canvas,
    result: LayoutResult,
    color: Int,
    typefaces: AndroidTypefaceResolver,
) {
    val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        textLocale = Locale.forLanguageTag(result.input.textStyle.locale)
        fontFeatureSettings = "'vert' on"
    }
    val bounds = Rect()
    for (z in result.debug.bopomofoDecisions) {
        paint.typeface = typefaces.resolve(FontRole.CjkText, z.fontFamilies, z.fontWeight, italic = false)
        for (p in z.placements) {
            when (p.role) {
                BopomofoGlyphRole.Symbol -> {
                    // ㄅㄆㄇ are full-em CJK glyphs → sit on the 字身框 baseline (0.88),
                    // like body CJK; 轻声/声调 below ink-center because they are small marks.
                    paint.textSize = p.height
                    val drawX = p.left + (p.width - paint.measureText(p.text)) / 2f
                    canvas.drawTextRun(p.text, 0, p.text.length, 0, p.text.length, drawX, p.top + p.height * 0.88f, false, paint)
                }
                BopomofoGlyphRole.Neutral -> {
                    paint.textSize = p.width
                    paint.getTextBounds(p.text, 0, p.text.length, bounds)
                    val drawX = p.left + (p.width - paint.measureText(p.text)) / 2f
                    val baselineY = p.top + p.height / 2f - (bounds.top + bounds.bottom) / 2f
                    canvas.drawTextRun(p.text, 0, p.text.length, 0, p.text.length, drawX, baselineY, false, paint)
                }
                BopomofoGlyphRole.Tone -> {
                    paint.textSize = p.height
                    paint.getTextBounds(p.text, 0, p.text.length, bounds)
                    val scale = if (bounds.width() > 0) p.width / bounds.width() else 1f
                    paint.textSize = p.height * scale
                    paint.getTextBounds(p.text, 0, p.text.length, bounds)
                    val baselineY = p.top + p.height / 2f - (bounds.top + bounds.bottom) / 2f
                    canvas.drawTextRun(p.text, 0, p.text.length, 0, p.text.length, p.left - bounds.left, baselineY, false, paint)
                }
            }
        }
    }
}

private data class AndroidClusterRun(
    val role: FontRole,
    val style: TextStyle,
)

private inline fun LayoutResult.forEachAndroidPositionedCluster(
    spans: List<TextSpan>,
    action: (line: LineBox, cluster: Cluster, drawX: Float, baselineY: Float, run: AndroidClusterRun) -> Unit,
) {
    val baseStyle = input.textStyle
    val emphasisRanges = input.decorations
        .filter { it.kind == DecorationKind.Emphasis }
        .map { it.range }

    for (line in lines) {
        for (positioned in positionedClusters(line)) {
            val cluster = clusters[positioned.clusterIndex]
            val role = debug.fontDecisions.firstOrNull {
                cluster.range.start >= it.range.start && cluster.range.end <= it.range.end
            }?.role.toFontRole()
            val isLatin = role == FontRole.LatinText
            val spanStyle = spans.lastOrNull { cluster.range.start >= it.range.start && cluster.range.start < it.range.end }?.style
            val italic = (spanStyle?.italic ?: false) ||
                (isLatin && emphasisRanges.any { cluster.range.start >= it.start && cluster.range.start < it.end })
            val style = (spanStyle ?: baseStyle).copy(italic = italic)
            if (cluster.displayText.isNotEmpty()) {
                action(
                    line,
                    cluster,
                    positioned.drawX,
                    line.baseline + cluster.baselineShift,
                    AndroidClusterRun(role, style),
                )
            }
        }
    }
}

private fun String?.toFontRole(): FontRole =
    runCatching { if (this == null) null else FontRole.valueOf(this) }.getOrNull() ?: FontRole.CjkText

private fun drawContextShapedText(
    canvas: android.graphics.Canvas,
    text: String,
    x: Float,
    y: Float,
    role: FontRole,
    paint: TextPaint,
    clipToContext: Boolean = false,
) {
    if (text.isEmpty()) return
    val useHanContext = role == FontRole.CjkText || role == FontRole.CjkPunctuation
    if (useHanContext && clipToContext) {
        // FullBufferClippedPunctuationDraw: drawTextRun keeps context-driven GSUB
        // (locl 2em dash, zh quote forms…) only for glyphs INSIDE the drawn range —
        // a sub-range draw of `中<cluster>中` renders the context-free narrow form
        // (measured on Pixel: 1.55em vs 1.84em for `⸺`). Draw the WHOLE buffer with
        // the pen shifted so the cluster lands at [x], and clip to the cluster's
        // NATURAL pen span inside the buffer — the context 中s sit exactly outside
        // that span. The RESOLVED cluster advance must NOT be the clip: justify can
        // stretch it past the trailing 中 (its left stroke bled in as a phantom
        // vertical bar), and glue compression can shrink it into the glyph's own
        // ink (opening quotes got their face cut off).
        val buffer = "中${text}中"
        val penOrigin = paint.getRunAdvance(buffer, 0, buffer.length, 0, buffer.length, false, 1)
        val penEnd = paint.getRunAdvance(buffer, 0, buffer.length, 0, buffer.length, false, 1 + text.length)
        canvas.save()
        canvas.clipRect(x, y - paint.textSize * 2f, x + (penEnd - penOrigin), y + paint.textSize)
        canvas.drawTextRun(buffer, 0, buffer.length, 0, buffer.length, x - penOrigin, y, false, paint)
        canvas.restore()
    } else if (useHanContext) {
        val buffer = "中${text}中"
        canvas.drawTextRun(buffer, 1, 1 + text.length, 0, buffer.length, x, y, false, paint)
    } else {
        canvas.drawTextRun(text, 0, text.length, 0, text.length, x, y, false, paint)
    }
}

private fun LayoutResult.androidLineInkSkipIntervals(
    line: LineBox,
    bandTop: Float,
    bandBottom: Float,
    spans: List<TextSpan>,
    typefaces: AndroidTypefaceResolver,
): FloatArray {
    val out = mutableListOf<Float>()
    val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        textLocale = Locale.forLanguageTag(input.textStyle.locale)
    }
    val path = Path()
    val bounds = RectF()
    forEachAndroidPositionedCluster(spans) { l, cluster, drawX, baselineY, run ->
        if (l !== line) return@forEachAndroidPositionedCluster
        // AndroidOutlineBandSkipInk: TextBlob.getIntercepts is Skia-only, so the
        // Android renderer derives equivalent intervals from the real outline
        // path and the underline's vertical band. This skips only the ink slice
        // that touches the line, not the whole glyph or text cluster.
        paint.textSize = run.style.fontSize
        paint.typeface = typefaces.resolve(run.role, run.style.fontFamilies, run.style.fontWeight, run.style.italic)
        paint.fontFeatureSettings = null
        path.reset()
        paint.getTextPath(cluster.displayText, 0, cluster.displayText.length, drawX, baselineY, path)
        if (path.isEmpty) return@forEachAndroidPositionedCluster
        path.computeBounds(bounds, true)
        if (bounds.bottom < bandTop || bounds.top > bandBottom) return@forEachAndroidPositionedCluster
        path.horizontalBandIntercepts(bandTop, bandBottom).forEach { out += it }
    }
    return out.toFloatArray()
}

private data class PathPoint(val x: Float, val y: Float)

private fun Path.horizontalBandIntercepts(bandTop: Float, bandBottom: Float): FloatArray {
    if (isEmpty) return FloatArray(0)
    val contours = flattenedContours(errorPx = 0.4f)
    if (contours.isEmpty()) return FloatArray(0)
    val out = mutableListOf<Float>()
    val bandHeight = (bandBottom - bandTop).coerceAtLeast(0f)
    val samples = max(1, ceil(bandHeight / 0.5f).toInt())
    for (sample in 0..samples) {
        val y = bandTop + bandHeight * (sample.toFloat() / samples)
        val xs = mutableListOf<Float>()
        for (contour in contours) {
            for (index in 0 until contour.lastIndex) {
                val a = contour[index]
                val b = contour[index + 1]
                if ((a.y <= y && y < b.y) || (b.y <= y && y < a.y)) {
                    val t = (y - a.y) / (b.y - a.y)
                    xs += a.x + (b.x - a.x) * t
                }
            }
        }
        xs.sort()
        var index = 0
        while (index + 1 < xs.size) {
            val left = xs[index]
            val right = xs[index + 1]
            if (right > left + 0.25f) {
                out += left
                out += right
            }
            index += 2
        }
    }
    return out.toFloatArray()
}

private fun Path.flattenedContours(errorPx: Float): List<List<PathPoint>> {
    val contours = mutableListOf<List<PathPoint>>()
    val measure = PathMeasure(this, false)
    val step = errorPx.coerceAtLeast(0.25f)
    do {
        val length = measure.length
        if (length <= 0f) continue
        val count = ceil(length / step).toInt().coerceAtLeast(1)
        val points = ArrayList<PathPoint>(count + 2)
        val position = FloatArray(2)
        for (index in 0..count) {
            val distance = length * (index.toFloat() / count)
            if (measure.getPosTan(distance, position, null)) {
                val point = PathPoint(position[0], position[1])
                if (points.lastOrNull() != point) points += point
            }
        }
        val first = points.firstOrNull()
        val last = points.lastOrNull()
        if (first != null && last != null && first != last) points += first
        if (points.size >= 3) contours += points
    } while (measure.nextContour())
    return contours
}

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
        cursor = max(cursor, iv[1])
    }
    if (cursor < right - 0.5f) draw(cursor, right)
}

private fun wavyLinePath(left: Float, right: Float, y: Float, fontSize: Float): Path {
    val path = Path()
    val halfWave = (fontSize * 0.2f).coerceAtLeast(1f)
    val amplitude = fontSize * 0.06f
    path.moveTo(left, y)
    var x = left
    var up = true
    while (x < right - WAVY_ENDPOINT_EPSILON_PX) {
        val rawNextX = x + halfWave
        val nextX = if (rawNextX >= right - WAVY_ENDPOINT_EPSILON_PX) right else rawNextX
        val controlY = if (up) y - amplitude * 2f else y + amplitude * 2f
        path.quadTo((x + nextX) / 2f, controlY, nextX, y)
        x = nextX
        up = !up
    }
    return path
}

private const val INLINE_CODE_BACKGROUND_COLOR: Int = 0x1A000000
private const val INTERLINEAR_UNDERLINE_OFFSET_EM = 0.18f
private const val GENERIC_LINE_THROUGH_OFFSET_EM = 0.30f
private const val BROWSER_LIKE_SKIP_INK_CLEARANCE_EM = 0.10f
private const val BROWSER_LIKE_SKIP_INK_CLEARANCE_MAX = 13f
private const val WAVY_ENDPOINT_EPSILON_PX = 0.01f

private fun browserLikeSkipInkClearance(fontSize: Float, strokeWidth: Float): Float =
    min(max(strokeWidth, fontSize * BROWSER_LIKE_SKIP_INK_CLEARANCE_EM), BROWSER_LIKE_SKIP_INK_CLEARANCE_MAX)
