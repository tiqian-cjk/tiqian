package org.tiqian.android.rendering

import android.annotation.TargetApi
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.DashPathEffect
import android.graphics.Path
import android.graphics.Picture
import android.graphics.RectF
import android.graphics.Region
import android.os.Build
import android.text.TextPaint
import org.tiqian.core.Glyph
import org.tiqian.core.Cluster
import org.tiqian.core.ColorSpan
import org.tiqian.core.DecorationKind
import org.tiqian.core.LayoutResult
import org.tiqian.core.LayoutResultReplayIndex
import org.tiqian.core.LineBox
import org.tiqian.core.RichTextLineSegment
import org.tiqian.core.RichTextRole
import org.tiqian.core.RichTextBackgroundDrawStyle
import org.tiqian.core.RichTextLinePattern
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.richTextDecorationLineY
import org.tiqian.core.resolvedBackgroundCornerRadii
import org.tiqian.core.fittedDashedLineSegments
import org.tiqian.core.fittedDottedLineCenters
import org.tiqian.font.FontRole
import org.tiqian.shaping.android.AndroidPositionedGlyphFontRegistry
import org.tiqian.shaping.android.AndroidTypefaceResolver
import org.tiqian.shaping.android.AndroidTypefaceResolverRegistry
import org.tiqian.shaping.android.requiresHanShapingContext
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

internal class AndroidParagraphDrawCache {
    internal val selectionPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    internal val glyphPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    internal val hyphenPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    internal val richTextBackgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    internal val richTextBackgroundPath = Path()
    internal val richTextBackgroundRect = RectF()
    internal val richTextBackgroundRadii = FloatArray(8)
    internal val richTextLinePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    internal val decorationFillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    internal val decorationStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    internal val rubyPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    internal val skipInkPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    internal val skipInkPath = Path()
    internal val skipInkBounds = RectF()
    internal val skipInkIntervals = HashMap<Long, FloatArray>()
    internal val dashEffects = HashMap<RichTextLinePattern.Dashed, DashPathEffect>()
    internal val platformFonts31 = HashMap<String, Any?>()
    // Kept as Any so loading the cache itself remains safe on API 23-30, where Canvas.drawGlyphs
    // is unavailable. The API 31 helper creates and owns the typed batch lazily.
    internal var glyphBatch31: Any? = null
    internal val hostReplayFaces = HashMap<String, HostReplayFace?>()
    internal val hostReplayPath = Path()

    // NaturalRunCoalescedDraw (ADR 0050): the API<31 draw plan, built once per geometry and
    // replayed each frame. Cleared with the geometry, and also rebuilt when the paint context
    // (text color / colorSpans) baked into its commands changes without a geometry change.
    internal var androidDrawPlan: List<AndroidDrawCommand>? = null
    internal var androidDrawPlanColor: Int = 0
    internal var androidDrawPlanColorSpans: List<ColorSpan>? = null

    fun invalidateGeometry() {
        skipInkIntervals.clear()
        androidDrawPlan = null
        androidDrawPlanColorSpans = null
    }

    fun dispose() {
        skipInkIntervals.clear()
        dashEffects.clear()
        platformFonts31.clear()
        hostReplayFaces.clear()
        glyphBatch31 = null
        androidDrawPlan = null
        androidDrawPlanColorSpans = null
    }
}

/**
 * Replays one Tiqian [LayoutResult] onto a native Android [Canvas].
 *
 * The renderer owns every mutable paint and draw-plan cache used by the replay path. Keep one
 * instance for the lifetime of a drawing surface, call [draw] from that surface's draw callback,
 * and release retained platform objects with [close]. Layout and shaping decisions remain entirely
 * in [LayoutResult]; this class never re-breaks text or adjusts glyph geometry.
 */
class AndroidParagraphRenderer(
    private val typefaces: AndroidTypefaceResolver = AndroidTypefaceResolverRegistry.current,
) : AutoCloseable {
    private val drawCache = AndroidParagraphDrawCache()
    private var geometry: LayoutResultReplayIndex? = null
    private var paintOverhangPicture: Picture? = null
    private var paintOverhangColor: Int = 0
    private var paintOverhangColorSpans: List<ColorSpan>? = null
    private val paintOverhangBounds = RectF()
    private val paintOverhangExcludedBounds = RectF()
    private var paintOverhangPictureLeft = 0f
    private var paintOverhangPictureTop = 0f

    fun draw(
        canvas: Canvas,
        result: LayoutResult,
        replayIndex: LayoutResultReplayIndex,
        color: Int,
        colorSpans: List<ColorSpan> = emptyList(),
        selectionBoxes: List<org.tiqian.core.Rect> = emptyList(),
        selectionColor: Int? = null,
    ) {
        ensureGeometry(replayIndex)
        val spans = result.input.content.spans
        drawAndroidRichTextBackgrounds(
            canvas, replayIndex.richTextBackgroundSegments, drawCache,
        )
        if (selectionColor != null) {
            val selectionPaint = drawCache.selectionPaint
            selectionPaint.style = Paint.Style.FILL
            selectionPaint.color = selectionColor
            for (box in selectionBoxes) {
                canvas.drawRect(box.left, box.top, box.right, box.bottom, selectionPaint)
            }
        }
        drawAndroidGlyphs(
            canvas, result, replayIndex, color, colorSpans, spans, typefaces,
            drawCache,
        )
        drawAndroidRichTextLines(
            canvas, result, replayIndex, color, colorSpans, replayIndex.richTextDecorationSegments,
            spans, typefaces, drawCache,
        )
        drawAndroidDecorations(
            canvas, result, replayIndex, color, colorSpans, spans, typefaces, drawCache,
        )
        drawAndroidRuby(
            canvas, result, color, typefaces, drawCache.rubyPaint,
        )
        drawAndroidBopomofo(canvas, result, color, typefaces)
    }

    /**
     * Replays only paint authorized outside [excludedBounds], using a retained native recording.
     *
     * The first call for a geometry/paint/bounds tuple records the shared paragraph renderer into
     * an Android [Picture]. Subsequent View hierarchy recordings submit that native picture rather
     * than traversing every glyph, decoration, ruby and bopomofo command through Kotlin again.
     * Both rectangles are renderer coordinates derived from the engine's legal paint bounds; this
     * cache never expands them or makes a layout decision.
     */
    fun drawPaintOverhang(
        canvas: Canvas,
        result: LayoutResult,
        replayIndex: LayoutResultReplayIndex,
        color: Int,
        colorSpans: List<ColorSpan> = emptyList(),
        paintBounds: RectF,
        excludedBounds: RectF,
    ) {
        ensureGeometry(replayIndex)
        if (!paintBounds.hasAreaOutside(excludedBounds)) return

        // Picture playback of drawGlyphs can require a hardware destination on API 31+. Preserve
        // the established software-Canvas behavior rather than making the cache a capability gate.
        if (Build.VERSION.SDK_INT >= 31 && !canvas.isHardwareAccelerated) {
            val save = canvas.save()
            if (canvas.clipPaintOverhang(paintBounds, excludedBounds)) {
                draw(canvas, result, replayIndex, color, colorSpans)
            }
            canvas.restoreToCount(save)
            return
        }

        val picture = paintOverhangPicture?.takeIf {
            paintOverhangColor == color &&
                paintOverhangColorSpans == colorSpans &&
                paintOverhangBounds == paintBounds &&
                paintOverhangExcludedBounds == excludedBounds
        } ?: recordPaintOverhang(
            result = result,
            replayIndex = replayIndex,
            color = color,
            colorSpans = colorSpans,
            paintBounds = paintBounds,
            excludedBounds = excludedBounds,
        )

        val save = canvas.save()
        canvas.translate(paintOverhangPictureLeft, paintOverhangPictureTop)
        canvas.drawPicture(picture)
        canvas.restoreToCount(save)
    }

    private fun recordPaintOverhang(
        result: LayoutResult,
        replayIndex: LayoutResultReplayIndex,
        color: Int,
        colorSpans: List<ColorSpan>,
        paintBounds: RectF,
        excludedBounds: RectF,
    ): Picture = tiqianTraceSection("AndroidParagraphRenderer.recordPaintOverhang") {
        val left = kotlin.math.floor(paintBounds.left).toInt()
        val top = kotlin.math.floor(paintBounds.top).toInt()
        val right = kotlin.math.ceil(paintBounds.right).toInt()
        val bottom = kotlin.math.ceil(paintBounds.bottom).toInt()
        val picture = Picture()
        val recordingCanvas = picture.beginRecording(
            (right - left).coerceAtLeast(1),
            (bottom - top).coerceAtLeast(1),
        )
        recordingCanvas.translate(-left.toFloat(), -top.toFloat())
        if (recordingCanvas.clipPaintOverhang(paintBounds, excludedBounds)) {
            draw(
                canvas = recordingCanvas,
                result = result,
                replayIndex = replayIndex,
                color = color,
                colorSpans = colorSpans,
            )
        }
        picture.endRecording()

        paintOverhangPicture = picture
        paintOverhangColor = color
        paintOverhangColorSpans = colorSpans
        paintOverhangBounds.set(paintBounds)
        paintOverhangExcludedBounds.set(excludedBounds)
        paintOverhangPictureLeft = left.toFloat()
        paintOverhangPictureTop = top.toFloat()
        picture
    }

    private fun ensureGeometry(replayIndex: LayoutResultReplayIndex) {
        if (geometry === replayIndex) return
        geometry = replayIndex
        drawCache.invalidateGeometry()
        invalidatePaintOverhangRecording()
    }

    private fun invalidatePaintOverhangRecording() {
        paintOverhangPicture = null
        paintOverhangColorSpans = null
        paintOverhangBounds.setEmpty()
        paintOverhangExcludedBounds.setEmpty()
    }

    fun invalidateGeometry() {
        geometry = null
        drawCache.invalidateGeometry()
        invalidatePaintOverhangRecording()
    }

    override fun close() {
        geometry = null
        drawCache.dispose()
        invalidatePaintOverhangRecording()
    }
}

private fun RectF.hasAreaOutside(excluded: RectF): Boolean =
    !isEmpty && (
        left < excluded.left || top < excluded.top ||
            right > excluded.right || bottom > excluded.bottom
        )

private fun Canvas.clipPaintOverhang(paintBounds: RectF, excludedBounds: RectF): Boolean {
    if (!clipRect(paintBounds)) return false
    return if (Build.VERSION.SDK_INT >= 26) {
        clipOutRect(excludedBounds)
    } else {
        @Suppress("DEPRECATION")
        clipRect(excludedBounds, Region.Op.DIFFERENCE)
    }
}

private fun drawAndroidGlyphs(
    canvas: android.graphics.Canvas,
    result: LayoutResult,
    replayIndex: LayoutResultReplayIndex,
    color: Int,
    colorSpans: List<ColorSpan>,
    spans: List<TextSpan>,
    typefaces: AndroidTypefaceResolver,
    drawCache: AndroidParagraphDrawCache,
) {
    val paint = drawCache.glyphPaint
    paint.color = color
    paint.textLocale = Locale.forLanguageTag(result.input.textStyle.locale)
    if (Build.VERSION.SDK_INT >= 31) {
        drawAndroidPositionedClusters31(
            canvas = canvas,
            result = result,
            replayIndex = replayIndex,
            color = color,
            colorSpans = colorSpans,
            spans = spans,
            typefaces = typefaces,
            paint = paint,
            drawCache = drawCache,
        )
    } else {
        drawAndroidPlatformClusters(
            canvas = canvas,
            result = result,
            replayIndex = replayIndex,
            color = color,
            colorSpans = colorSpans,
            spans = spans,
            typefaces = typefaces,
            paint = paint,
            drawCache = drawCache,
        )
    }

    val hyphenPaint = drawCache.hyphenPaint
    hyphenPaint.set(paint)
    hyphenPaint.textSize = result.input.textStyle.fontSize
    hyphenPaint.typeface = result.input.textStyle.let { style ->
        typefaces.resolve(FontRole.LatinText, style.fontFamilies, style.fontWeight, style.italic)
    }
    for (line in result.lines) {
        if (line.hyphenAdvance > 0f) {
            // The hyphen takes the color of the cluster it breaks after.
            val anchor = result.clusters[line.clusterRange.last].range.start
            hyphenPaint.color = colorSpans.lastOrNull { anchor >= it.start && anchor < it.end }?.argb ?: color
            val originX = line.indent + line.visualWidth
            val platformDrawn = Build.VERSION.SDK_INT >= 31 &&
                drawPositionedGlyphs31(
                    canvas, line.hyphenGlyphs, originX, line.baseline, hyphenPaint, drawCache,
                )
            if (platformDrawn) continue
            if (drawAndroidReplayGlyphs(canvas, line.hyphenGlyphs, originX, line.baseline, hyphenPaint.textSize, hyphenPaint, drawCache)) {
                continue
            }

            drawContextShapedText(canvas, "-", originX, line.baseline, FontRole.LatinText, hyphenPaint)
        }
    }
}

// NaturalRunCoalescedDraw (ADR 0050): API 23-30 has no positioned-glyph batch API, so a naive
// per-cluster drawTextRun makes the first display-list recording cost scale with cluster count.
// Build a coalesced draw plan once per geometry (also rebuilt when the baked text color / colorSpans
// change), then replay the pre-grouped command table. The plan lives in [AndroidDrawPlan.kt].
private fun drawAndroidPlatformClusters(
    canvas: android.graphics.Canvas,
    result: LayoutResult,
    replayIndex: LayoutResultReplayIndex,
    color: Int,
    colorSpans: List<ColorSpan>,
    spans: List<TextSpan>,
    typefaces: AndroidTypefaceResolver,
    paint: TextPaint,
    drawCache: AndroidParagraphDrawCache,
) {
    val plan = drawCache.androidDrawPlan?.takeIf {
        drawCache.androidDrawPlanColor == color && drawCache.androidDrawPlanColorSpans == colorSpans
    } ?: buildAndroidDrawPlan(result, replayIndex, color, colorSpans, spans, typefaces, paint).also {
        drawCache.androidDrawPlan = it
        drawCache.androidDrawPlanColor = color
        drawCache.androidDrawPlanColorSpans = colorSpans
    }
    replayAndroidDrawPlan(canvas, plan, paint, drawCache)
}

/**
 * AndroidPlatformGlyphBatch: API 31+ replays the exact LayoutResult glyph ids and absolute
 * placements through the retained platform Font, combining adjacent equal-style glyphs into one
 * Canvas.drawGlyphs call. A run without an observable platform Font is replayed through the same
 * contextual drawTextRun contract used on API 23-30.
 */
@TargetApi(31)
private fun drawAndroidPositionedClusters31(
    canvas: android.graphics.Canvas,
    result: LayoutResult,
    replayIndex: LayoutResultReplayIndex,
    color: Int,
    colorSpans: List<ColorSpan>,
    spans: List<TextSpan>,
    typefaces: AndroidTypefaceResolver,
    paint: TextPaint,
    drawCache: AndroidParagraphDrawCache,
) {
    val batch = (drawCache.glyphBatch31 as? AndroidGlyphBatch31)
        ?: AndroidGlyphBatch31().also { drawCache.glyphBatch31 = it }

    result.forEachAndroidPositionedCluster(replayIndex, spans) { _, cluster, drawX, baselineY, run ->
        prepareAndroidGlyphPaint(paint, cluster, run, color, colorSpans, typefaces)
        val glyphs = replayIndex.glyphsByClusterRange[cluster.range].orEmpty()
        val canUsePlatformGlyphs = glyphs.isNotEmpty() && glyphs.all { glyph ->
            platformFontFor(glyph, drawCache) != null
        }
        if (canUsePlatformGlyphs) {
            for (glyph in glyphs) {
                val platformFont = checkNotNull(platformFontFor(glyph, drawCache))
                platformFont.applyTo(paint)
                batch.append(
                    canvas = canvas,
                    paint = paint,
                    font = platformFont.font,
                    glyphId = glyph.id.toInt(),
                    x = drawX + glyph.x,
                    y = baselineY + glyph.y,
                )
            }
            return@forEachAndroidPositionedCluster
        }

        batch.flush(canvas, paint)
        if (drawAndroidReplayGlyphs(canvas, glyphs, drawX, baselineY, run.style.fontSize, paint, drawCache)) {
            return@forEachAndroidPositionedCluster
        }
        drawAndroidClusterRun(canvas, cluster, drawX, baselineY, run, paint)
    }
    batch.flush(canvas, paint)
}

// SyntheticCjkItalicSkew (ADR 0030 Amendment 2026-08-17): CJK faces ship no real italic
// instance, so italic CJK draws the upright face + a controlled shear. -0.105 ≈ 6°
// (得意黑 / Smiley Sans design slant), unified with the Apple/Skia renderers. Shared with the
// API<31 coalesced draw plan (AndroidDrawPlan.kt), which mirrors this paint state.
internal const val SYNTHETIC_CJK_ITALIC_SKEW = -0.105f

// synthesizeCjkItalic: an italic CJK run has no real italic face → upright face + controlled shear.
internal fun synthesizeCjkItalic(role: FontRole, italic: Boolean): Boolean =
    italic && (role == FontRole.CjkText || role == FontRole.CjkPunctuation)

private fun prepareAndroidGlyphPaint(
    paint: TextPaint,
    cluster: Cluster,
    run: AndroidClusterRun,
    color: Int,
    colorSpans: List<ColorSpan>,
    typefaces: AndroidTypefaceResolver,
) {
    paint.color = colorSpans.lastOrNull {
        cluster.range.start >= it.start && cluster.range.start < it.end
    }?.argb ?: color
    paint.textSize = run.style.fontSize
    val synthesizeCjkItalic = synthesizeCjkItalic(run.role, run.style.italic)
    paint.typeface = typefaces.resolve(
        run.role,
        run.style.fontFamilies,
        run.style.fontWeight,
        italic = run.style.italic && !synthesizeCjkItalic,
    )
    paint.fontFeatureSettings = run.openTypeFeatures.toAndroidFontFeatureSettings()
    paint.isFakeBoldText = false
    paint.textSkewX = if (synthesizeCjkItalic) SYNTHETIC_CJK_ITALIC_SKEW else 0f
}

internal fun drawAndroidClusterRun(
    canvas: android.graphics.Canvas,
    cluster: Cluster,
    drawX: Float,
    baselineY: Float,
    run: AndroidClusterRun,
    paint: TextPaint,
) {
    // CjkPunctuation clusters need the full-buffer clipped draw (context GSUB);
    // plain 汉字 are context-independent and keep the cheaper sub-range draw.
    // Italic punctuation uses target-only drawing so context glyph overhang cannot leak.
    val clipToContext = run.role == FontRole.CjkPunctuation && !run.style.italic
    drawContextShapedText(canvas, cluster.displayText, drawX, baselineY, run.role, paint, clipToContext)
}

@TargetApi(31)
private fun platformFontFor(
    glyph: Glyph,
    drawCache: AndroidParagraphDrawCache,
): AndroidPlatformGlyphFont? {
    val key = glyph.renderFontKey ?: return null
    if (drawCache.platformFonts31.containsKey(key)) {
        return drawCache.platformFonts31[key] as? AndroidPlatformGlyphFont
    }
    val font = AndroidPositionedGlyphFontRegistry.fontFor(key)?.let { AndroidPlatformGlyphFont(it, fakeBold = false, textSkewX = null) }
        ?: hostReplayFaceFor(key, drawCache)?.replay?.platformFont(key)?.let { replayed ->
            AndroidPlatformGlyphFont(replayed.font as android.graphics.fonts.Font, replayed.fakeBold, replayed.textSkewX)
        }
    drawCache.platformFonts31[key] = font
    return font
}

@TargetApi(31)
internal class AndroidGlyphBatch31 {
    private var glyphIds = IntArray(32)
    private var positions = FloatArray(64)
    private var count = 0
    private var font: android.graphics.fonts.Font? = null
    private var color: Int = 0
    private var textSizeBits: Int = 0
    private var fakeBold: Boolean = false
    private var textSkewBits: Int = 0

    fun append(
        canvas: android.graphics.Canvas,
        paint: Paint,
        font: android.graphics.fonts.Font,
        glyphId: Int,
        x: Float,
        y: Float,
    ) {
        val sameRun = count > 0 &&
            this.font === font &&
            color == paint.color &&
            textSizeBits == paint.textSize.toRawBits() &&
            fakeBold == paint.isFakeBoldText &&
            textSkewBits == paint.textSkewX.toRawBits()
        if (!sameRun) {
            flush(canvas, paint)
            this.font = font
            color = paint.color
            textSizeBits = paint.textSize.toRawBits()
            fakeBold = paint.isFakeBoldText
            textSkewBits = paint.textSkewX.toRawBits()
        }
        ensureCapacity(count + 1)
        glyphIds[count] = glyphId
        positions[count * 2] = x
        positions[count * 2 + 1] = y
        count += 1
    }

    fun flush(canvas: android.graphics.Canvas, paint: Paint) {
        if (count == 0) return
        // append() prepares Paint for the incoming glyph before it flushes the
        // previous batch. Keep that pending style intact: otherwise the old
        // batch style becomes the new batch style as well.
        val pendingColor = paint.color
        val pendingTextSize = paint.textSize
        val pendingFakeBold = paint.isFakeBoldText
        val pendingTextSkew = paint.textSkewX
        try {
            paint.color = color
            paint.textSize = Float.fromBits(textSizeBits)
            paint.isFakeBoldText = fakeBold
            paint.textSkewX = Float.fromBits(textSkewBits)
            canvas.drawGlyphs(glyphIds, 0, positions, 0, count, checkNotNull(font), paint)
        } finally {
            paint.color = pendingColor
            paint.textSize = pendingTextSize
            paint.isFakeBoldText = pendingFakeBold
            paint.textSkewX = pendingTextSkew
            count = 0
            font = null
        }
    }

    private fun ensureCapacity(required: Int) {
        if (required <= glyphIds.size) return
        val capacity = max(required, glyphIds.size * 2)
        glyphIds = glyphIds.copyOf(capacity)
        positions = positions.copyOf(capacity * 2)
    }
}

@TargetApi(31)
private fun drawPositionedGlyphs31(
    canvas: android.graphics.Canvas,
    glyphs: List<Glyph>,
    originX: Float,
    originY: Float,
    paint: Paint,
    drawCache: AndroidParagraphDrawCache,
): Boolean {
    if (glyphs.isEmpty()) return false
    val fonts = glyphs.map { glyph ->
        platformFontFor(glyph, drawCache) ?: return false
    }
    val pendingFakeBold = paint.isFakeBoldText
    val pendingSkew = paint.textSkewX
    try {
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
            font.applyTo(paint)
            canvas.drawGlyphs(ids, 0, positions, 0, count, font.font, paint)
            start = end
        }
    } finally {
        paint.isFakeBoldText = pendingFakeBold
        paint.textSkewX = pendingSkew
    }
    return true
}

private fun drawAndroidDecorations(
    canvas: android.graphics.Canvas,
    result: LayoutResult,
    replayIndex: LayoutResultReplayIndex,
    color: Int,
    colorSpans: List<ColorSpan>,
    spans: List<TextSpan>,
    typefaces: AndroidTypefaceResolver,
    drawCache: AndroidParagraphDrawCache,
) {
    val fontSize = result.input.textStyle.fontSize
    val fillPaint = drawCache.decorationFillPaint
    fillPaint.color = color
    fillPaint.style = Paint.Style.FILL
    for (dot in result.debug.decorationDecisions) {
        if (dot.applied && dot.dotDiameter > 0f) {
            fillPaint.color = colorAt(dot.clusterRange.start, color, colorSpans)
            canvas.drawCircle(dot.anchorX, dot.anchorY, dot.dotDiameter / 2f, fillPaint)
        }
    }

    if (result.debug.decorationSegments.isEmpty()) return
    val strokePaint = drawCache.decorationStrokePaint
    strokePaint.color = color
    strokePaint.style = Paint.Style.STROKE
    strokePaint.strokeWidth = (fontSize / 16f).coerceAtLeast(1f)
    val skipBandPad = strokePaint.strokeWidth.coerceAtLeast(1f)
    val skipClearance = browserLikeSkipInkClearance(fontSize, strokePaint.strokeWidth)
    for (seg in result.debug.decorationSegments) {
        strokePaint.color = colorAt(seg.sourceRange.start, color, colorSpans)
        when (seg.kind) {
            DecorationKind.ProperNoun.name -> {
                drawAndroidStraightInterlinearLine(
                    canvas = canvas,
                    result = result,
                    replayIndex = replayIndex,
                    lineIndex = seg.lineIndex,
                    left = seg.left,
                    right = seg.right,
                    lineY = seg.top,
                    paint = strokePaint,
                    skipBandPad = skipBandPad,
                    skipClearance = skipClearance,
                    spans = spans,
                    typefaces = typefaces,
                    skipCache = drawCache.skipInkIntervals,
                    skipInkPaint = drawCache.skipInkPaint,
                    skipInkPath = drawCache.skipInkPath,
                    skipInkBounds = drawCache.skipInkBounds,
                )
            }
            DecorationKind.BookTitle.name -> {
                val cacheKey = skipInkCacheKey(seg.lineIndex, seg.top, skipBandPad)
                val skips = drawCache.skipInkIntervals.getOrPut(cacheKey) {
                    result.androidLineInkSkipIntervals(
                        replayIndex,
                        result.lines[seg.lineIndex],
                        seg.top - skipBandPad,
                        seg.top + skipBandPad,
                        spans,
                        typefaces,
                        drawCache.skipInkPaint,
                        drawCache.skipInkPath,
                        drawCache.skipInkBounds,
                    )
                }
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
    drawCache: AndroidParagraphDrawCache,
) {
    val paint = drawCache.richTextBackgroundPaint
    for (seg in segments) {
        val argb = when (seg.span.role) {
            RichTextRole.Background -> seg.span.paint.argb
            RichTextRole.InlineCode -> seg.span.paint.argb ?: INLINE_CODE_BACKGROUND_COLOR
            else -> null
        } ?: continue
        paint.color = argb
        val inset = when (val drawStyle = seg.span.paint.background.drawStyle) {
            RichTextBackgroundDrawStyle.Fill -> {
                paint.style = Paint.Style.FILL
                0f
            }
            is RichTextBackgroundDrawStyle.Border -> {
                paint.style = Paint.Style.STROKE
                paint.strokeWidth = drawStyle.strokeWidth
                drawStyle.strokeWidth / 2f
            }
        }
        val left = seg.left + inset
        val top = seg.top + inset
        val right = seg.right - inset
        val bottom = seg.bottom - inset
        if (right <= left || bottom <= top) continue
        val corners = seg.resolvedBackgroundCornerRadii(inset)
        if (corners.isSquare) {
            canvas.drawRect(left, top, right, bottom, paint)
        } else if (corners.isUniform) {
            canvas.drawRoundRect(left, top, right, bottom, corners.topLeft, corners.topLeft, paint)
        } else {
            val radii = drawCache.richTextBackgroundRadii
            radii[0] = corners.topLeft
            radii[1] = corners.topLeft
            radii[2] = corners.topRight
            radii[3] = corners.topRight
            radii[4] = corners.bottomRight
            radii[5] = corners.bottomRight
            radii[6] = corners.bottomLeft
            radii[7] = corners.bottomLeft
            drawCache.richTextBackgroundRect.set(left, top, right, bottom)
            drawCache.richTextBackgroundPath.reset()
            drawCache.richTextBackgroundPath.addRoundRect(
                drawCache.richTextBackgroundRect,
                radii,
                Path.Direction.CW,
            )
            canvas.drawPath(drawCache.richTextBackgroundPath, paint)
        }
    }
}

private fun drawAndroidRichTextLines(
    canvas: android.graphics.Canvas,
    result: LayoutResult,
    replayIndex: LayoutResultReplayIndex,
    color: Int,
    colorSpans: List<ColorSpan>,
    segments: List<RichTextLineSegment>,
    spans: List<TextSpan>,
    typefaces: AndroidTypefaceResolver,
    drawCache: AndroidParagraphDrawCache,
) {
    val strokePaint = drawCache.richTextLinePaint
    strokePaint.style = Paint.Style.STROKE
    for (seg in segments) {
        val role = seg.span.role
        if (role != RichTextRole.Underline && role != RichTextRole.LineThrough) continue
        when (val pattern = seg.span.paint.linePattern) {
            RichTextLinePattern.Solid -> {
                strokePaint.strokeWidth = (result.input.textStyle.fontSize / 16f).coerceAtLeast(1f)
                strokePaint.pathEffect = null
                strokePaint.strokeCap = Paint.Cap.BUTT
            }
            is RichTextLinePattern.Dashed -> {
                strokePaint.strokeWidth = pattern.strokeWidth
                strokePaint.strokeCap = Paint.Cap.ROUND
                strokePaint.pathEffect = drawCache.dashEffects.getOrPut(pattern) {
                    DashPathEffect(floatArrayOf(pattern.dashLength, pattern.gapLength), 0f)
                }
            }
            is RichTextLinePattern.Dotted -> {
                strokePaint.strokeWidth = pattern.dotDiameter
                strokePaint.strokeCap = Paint.Cap.BUTT
                strokePaint.pathEffect = null
            }
        }
        val skipBandPad = when (val pattern = seg.span.paint.linePattern) {
            is RichTextLinePattern.Dotted -> pattern.dotDiameter / 2f
            else -> strokePaint.strokeWidth.coerceAtLeast(1f)
        }
        val style = spans.lastOrNull { seg.range.start >= it.range.start && seg.range.start < it.range.end }?.style
            ?: result.input.textStyle
        val lineY = result.richTextDecorationLineY(seg, strokePaint.strokeWidth)
        strokePaint.color = seg.span.paint.argb ?: colorAt(seg.range.start, color, colorSpans)
        if (role == RichTextRole.Underline) {
            drawAndroidStraightInterlinearLine(
                canvas = canvas,
                result = result,
                replayIndex = replayIndex,
                lineIndex = seg.lineIndex,
                left = seg.left,
                right = seg.right,
                lineY = lineY,
                paint = strokePaint,
                skipBandPad = skipBandPad,
                skipClearance = browserLikeSkipInkClearance(style.fontSize, strokePaint.strokeWidth),
                linePattern = seg.span.paint.linePattern,
                spans = spans,
                typefaces = typefaces,
                skipCache = drawCache.skipInkIntervals,
                skipInkPaint = drawCache.skipInkPaint,
                skipInkPath = drawCache.skipInkPath,
                skipInkBounds = drawCache.skipInkBounds,
            )
        } else {
            canvas.drawLine(seg.left, lineY, seg.right, lineY, strokePaint)
        }
    }
    strokePaint.pathEffect = null
    strokePaint.strokeCap = Paint.Cap.BUTT
}

private fun drawAndroidStraightInterlinearLine(
    canvas: android.graphics.Canvas,
    result: LayoutResult,
    replayIndex: LayoutResultReplayIndex,
    lineIndex: Int,
    left: Float,
    right: Float,
    lineY: Float,
    paint: Paint,
    skipBandPad: Float,
    skipClearance: Float,
    linePattern: RichTextLinePattern = RichTextLinePattern.Solid,
    spans: List<TextSpan>,
    typefaces: AndroidTypefaceResolver,
    skipCache: MutableMap<Long, FloatArray>,
    skipInkPaint: TextPaint,
    skipInkPath: Path,
    skipInkBounds: RectF,
) {
    val line = result.lines.getOrNull(lineIndex) ?: return
    val cacheKey = skipInkCacheKey(lineIndex, lineY, skipBandPad)
    val skips = skipCache.getOrPut(cacheKey) {
        result.androidLineInkSkipIntervals(
            replayIndex, line, lineY - skipBandPad, lineY + skipBandPad, spans, typefaces,
            skipInkPaint, skipInkPath, skipInkBounds,
        )
    }
    keptIntervals(left, right, skips, skipClearance) { x0, x1 ->
        when (linePattern) {
            RichTextLinePattern.Solid -> canvas.drawLine(x0, lineY, x1, lineY, paint)
            is RichTextLinePattern.Dashed -> {
                paint.pathEffect = null
                val saveCount = canvas.save()
                canvas.clipRect(x0, lineY - paint.strokeWidth, x1, lineY + paint.strokeWidth)
                val dashes = fittedDashedLineSegments(
                    spanLeft = left,
                    spanRight = right,
                    dashLength = linePattern.dashLength,
                    gapLength = linePattern.gapLength,
                )
                var index = 0
                while (index + 1 < dashes.size) {
                    val dashLeft = dashes[index]
                    val dashRight = dashes[index + 1]
                    if (dashRight > x0 && dashLeft < x1) {
                        val capInset = minOf(paint.strokeWidth / 2f, (dashRight - dashLeft) / 2f)
                        canvas.drawLine(
                            dashLeft + capInset,
                            lineY,
                            dashRight - capInset,
                            lineY,
                            paint,
                        )
                    }
                    index += 2
                }
                canvas.restoreToCount(saveCount)
            }
            is RichTextLinePattern.Dotted -> {
                paint.style = Paint.Style.FILL
                fittedDottedLineCenters(
                    spanLeft = left,
                    spanRight = right,
                    keptLeft = x0,
                    keptRight = x1,
                    dotDiameter = linePattern.dotDiameter,
                    gapLength = linePattern.gapLength,
                ).forEach { center ->
                    canvas.drawCircle(center, lineY, linePattern.dotDiameter / 2f, paint)
                }
                paint.style = Paint.Style.STROKE
            }
        }
    }
}

private fun colorAt(offset: Int, color: Int, colorSpans: List<ColorSpan>): Int =
    colorSpans.lastOrNull { offset >= it.start && offset < it.end }?.argb ?: color

private fun drawAndroidRuby(
    canvas: android.graphics.Canvas,
    result: LayoutResult,
    color: Int,
    typefaces: AndroidTypefaceResolver,
    paint: TextPaint,
) {
    paint.color = color
    paint.textLocale = Locale.forLanguageTag(result.input.textStyle.locale)
    for (ruby in result.debug.rubyDecisions) {
        paint.textLocale = Locale.forLanguageTag(ruby.locale)
        paint.textSize = ruby.fontSize
        paint.fontFeatureSettings = null
        paint.typeface = typefaces.resolve(FontRole.LatinText, ruby.fontFamilies, ruby.fontWeight, italic = false)
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
    for (z in result.debug.bopomofoDecisions) {
        paint.typeface = typefaces.resolve(FontRole.CjkText, z.fontFamilies, z.fontWeight, italic = false)
        paint.textLocale = Locale.forLanguageTag(z.locale)
        for (p in z.placements) {
            paint.textSize = p.fontSize
            canvas.drawTextRun(
                p.text,
                0,
                p.text.length,
                0,
                p.text.length,
                p.drawX,
                p.baselineY,
                false,
                paint,
            )
        }
    }
}

private const val INLINE_CODE_BACKGROUND_COLOR: Int = 0x1A000000
