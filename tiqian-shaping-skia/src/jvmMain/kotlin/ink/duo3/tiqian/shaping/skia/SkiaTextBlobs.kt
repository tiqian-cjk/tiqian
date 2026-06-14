package ink.duo3.tiqian.shaping.skia

import ink.duo3.tiqian.core.LayoutResult
import org.jetbrains.skia.Canvas
import org.jetbrains.skia.Font
import org.jetbrains.skia.FontMgr
import org.jetbrains.skia.FontStyle
import org.jetbrains.skia.Point
import org.jetbrains.skia.TextBlob
import org.jetbrains.skia.TextBlobBuilder
import org.jetbrains.skia.Typeface
import org.jetbrains.skia.shaper.RunHandler
import org.jetbrains.skia.shaper.RunInfo
import org.jetbrains.skia.shaper.Shaper
import org.jetbrains.skia.shaper.ShapingOptions
import org.jetbrains.skia.shaper.TrivialBidiRunIterator
import org.jetbrains.skia.shaper.TrivialFontRunIterator
import org.jetbrains.skia.shaper.TrivialLanguageRunIterator
import org.jetbrains.skia.shaper.TrivialScriptRunIterator

/**
 * Shapes [text] with the same language tag `SkiaTextShaper` uses
 * (`LocaleTaggedShaping`) and builds a draw-ready [TextBlob] whose baseline
 * sits at y=0. Renderers (playground raster, Compose desktop) MUST draw
 * through this so glyph forms stay identical to what the engine measured —
 * e.g. the `locl` zh-Hans dash variants.
 *
 * The blob is built manually: Skia's own TextBlobBuilderRunHandler is a
 * line-WRAPPING handler that places the first baseline at `-ascent`, which
 * shifts every run down by its own font's ascent (Latin runs visibly float
 * above CJK runs).
 */
fun shapeTextBlob(
    shaper: Shaper,
    text: String,
    font: Font,
    language: String,
): TextBlob? {
    if (text.isEmpty()) return null
    val glyphIds = mutableListOf<Short>()
    val xPositions = mutableListOf<Float>()
    shaper.shape(
        text,
        TrivialFontRunIterator(text, font),
        TrivialBidiRunIterator(text, 0),
        TrivialScriptRunIterator(text, "Hani"),
        TrivialLanguageRunIterator(text, language),
        ShapingOptions.DEFAULT,
        Float.MAX_VALUE,
        object : RunHandler {
            override fun beginLine() {}
            override fun runInfo(info: RunInfo?) {}
            override fun commitRunInfo() {}
            override fun runOffset(info: RunInfo?): Point = Point(0f, 0f)
            override fun commitRun(
                info: RunInfo?,
                glyphs: ShortArray?,
                positions: Array<Point?>?,
                clusters: IntArray?,
            ) {
                if (glyphs == null || positions == null) return
                glyphs.forEachIndexed { index, glyphId ->
                    glyphIds += glyphId
                    xPositions += (positions.getOrNull(index)?.x ?: 0f)
                }
            }
            override fun commitLine() {}
        },
    )
    if (glyphIds.isEmpty()) return null
    return TextBlobBuilder()
        .appendRunPosH(font, glyphIds.toShortArray(), xPositions.toFloatArray(), 0f)
        .build()
}

/**
 * Draws a [LayoutResult]'s glyphs onto a Skia [canvas] — the single shared
 * cluster-walk for the Compose renderer and the playground skia raster (they
 * had drifting copies; the role-containment and leading-glue-shift bugs each
 * had to be fixed in both). Pure presentation: x stepping is the engine's
 * resolved `cluster.advance`; glyphs come from [shapeTextBlob] so forms match
 * the measured layout. [baselineOffset] lets the raster add its canvas top
 * padding (Compose passes 0).
 *
 * - `role` lookup is by CONTAINMENT (a word cluster sits inside its font
 *   decision's range after `LatinWordSegmentation`).
 * - A CJK↔Latin Insert gap (autospace side leading) shifts the glyph right by
 *   a quarter em; the trailing gap is already inside `cluster.advance`.
 * - Consumed LEADING glue (line-start 开标点 trim, 间隔号 push-in) shifts the
 *   glyph LEFT — the blob keeps the font's built-in leading blank.
 */
fun drawTiqianGlyphs(
    canvas: Canvas,
    result: LayoutResult,
    cjkFont: Font,
    latinFont: Font,
    paint: org.jetbrains.skia.Paint,
    shaper: Shaper,
    baselineOffset: Float = 0f,
) {
    val language = result.input.textStyle.locale
    val autoSpaceGap = 0.25f * result.input.textStyle.fontSize
    val leadingConsumed = result.debug.geometryDecisions
        .filter { it.leadingGlueConsumed > 0f }
        .associate { it.range to it.leadingGlueConsumed }
    for (line in result.lines) {
        val lineClusters = result.clusters.filter {
            it.range.start >= line.range.start && it.range.end <= line.range.end
        }
        var x = line.indent
        val baselineY = line.baseline + baselineOffset
        for ((indexInLine, cluster) in lineClusters.withIndex()) {
            val role = result.debug.fontDecisions.firstOrNull {
                cluster.range.start >= it.range.start && cluster.range.end <= it.range.end
            }?.role
            val font = if (role == "LatinText") latinFont else cjkFont
            val hasLeadingGap = result.debug.autoSpaceDecisions
                .any { it.clusterRange == cluster.range && it.side == "leading" }
            val leadingGap = if (hasLeadingGap && indexInLine != 0) autoSpaceGap else 0f
            if (cluster.displayText.isNotEmpty()) {
                val leadingShift = leadingConsumed[cluster.range] ?: 0f
                shapeTextBlob(shaper, cluster.displayText, font, language)?.let { blob ->
                    canvas.drawTextBlob(blob, x + leadingGap - leadingShift, baselineY, paint)
                }
            }
            x += cluster.advance
        }
        // LineEndHangingHyphen (ADR 0029): a hyphen hangs just past the content
        // at a mid-word line end. x is now indent + visualWidth (content end).
        if (line.hyphenAdvance > 0f) {
            shapeTextBlob(shaper, "-", latinFont, language)?.let { blob ->
                canvas.drawTextBlob(blob, x, baselineY, paint)
            }
        }
    }
}

/**
 * System CJK / Latin typefaces from the shared candidate lists
 * (`SystemSkiaFontProbe`) — the same physical fonts `SystemSkiaFontResolver`
 * measures with, exposed for renderers that pick per-cluster fonts by role.
 */
object SkiaSystemTypefaces {
    /** Ordered by preference; first match wins. Mirrors `SystemAwtFontProbe`. */
    val CJK_CANDIDATES: List<String> = listOf(
        "Source Han Sans CN",
        "Source Han Sans CN VF",
        "Noto Sans CJK SC",
        "PingFang SC",
        "Hiragino Sans GB",
        "Sarasa UI SC",
        "Heiti SC",
        "STHeiti",
    )

    val LATIN_CANDIDATES: List<String> = listOf(
        "Inter Variable",
        "Inter",
        "SF Pro Text",
        "SF Pro",
        "Roboto",
        "Helvetica Neue",
    )

    val cjk: Typeface? by lazy {
        CJK_CANDIDATES.firstNotNullOfOrNull { FontMgr.default.matchFamilyStyle(it, FontStyle.NORMAL) }
    }

    val latin: Typeface? by lazy {
        LATIN_CANDIDATES.firstNotNullOfOrNull { FontMgr.default.matchFamilyStyle(it, FontStyle.NORMAL) }
    }
}

/**
 * 书名号甲式 wavy underline path (ADR 0024): quad waves with ~0.25em
 * wavelength and ~0.06em amplitude, sized to the annotated text's font.
 * Shared by the Compose renderer and the playground raster, like
 * [shapeTextBlob].
 */
fun wavyLinePath(left: Float, right: Float, y: Float, fontSize: Float): org.jetbrains.skia.Path {
    val builder = org.jetbrains.skia.PathBuilder()
    val halfWave = (fontSize * 0.125f).coerceAtLeast(1f)
    val amplitude = fontSize * 0.06f
    builder.moveTo(left, y)
    var x = left
    var up = true
    while (x < right) {
        val nextX = (x + halfWave).coerceAtMost(right)
        val controlY = if (up) y - amplitude * 2f else y + amplitude * 2f
        builder.quadTo((x + nextX) / 2f, controlY, nextX, y)
        x = nextX
        up = !up
    }
    return builder.detach()
}
