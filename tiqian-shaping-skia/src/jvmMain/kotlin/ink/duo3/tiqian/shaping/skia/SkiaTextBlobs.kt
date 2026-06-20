package ink.duo3.tiqian.shaping.skia

import ink.duo3.tiqian.core.Cluster
import ink.duo3.tiqian.core.ColorSpan
import ink.duo3.tiqian.core.LayoutResult
import ink.duo3.tiqian.core.LineBox
import ink.duo3.tiqian.core.TextSpan
import ink.duo3.tiqian.core.TextStyle
import org.jetbrains.skia.Canvas
import org.jetbrains.skia.Font
import org.jetbrains.skia.FontFeature
import org.jetbrains.skia.FontMgr
import org.jetbrains.skia.FontSlant
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
    vertical: Boolean = false,
): TextBlob? {
    if (text.isEmpty()) return null
    val glyphIds = mutableListOf<Short>()
    val xPositions = mutableListOf<Float>()
    // 注音 (ADR 0033) draws ㄅㄆㄇ in a VERTICAL mini-column → enable the `vert`
    // OpenType feature so ㄧ etc. take their vertical-writing glyph forms.
    val options = if (vertical) {
        ShapingOptions.DEFAULT.withFeatures(arrayOf(FontFeature("vert", 1)))
    } else {
        ShapingOptions.DEFAULT
    }
    shaper.shape(
        text,
        TrivialFontRunIterator(text, font),
        TrivialBidiRunIterator(text, 0),
        TrivialScriptRunIterator(text, "Hani"),
        TrivialLanguageRunIterator(text, language),
        options,
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
 * Glyph ids for [text] shaped with the `vert` feature — so注音 tone ink-detection
 * (`Font.getBounds`) measures the SAME 竖排 glyph the renderer draws (ADR 0033).
 */
fun vertGlyphIds(typeface: Typeface, shaper: Shaper, text: String, language: String): ShortArray {
    if (text.isEmpty()) return ShortArray(0)
    val font = Font(typeface, 100f) // size irrelevant for glyph identity
    val ids = mutableListOf<Short>()
    shaper.shape(
        text,
        TrivialFontRunIterator(text, font),
        TrivialBidiRunIterator(text, 0),
        TrivialScriptRunIterator(text, "Hani"),
        TrivialLanguageRunIterator(text, language),
        ShapingOptions.DEFAULT.withFeatures(arrayOf(FontFeature("vert", 1))),
        Float.MAX_VALUE,
        object : RunHandler {
            override fun beginLine() {}
            override fun runInfo(info: RunInfo?) {}
            override fun commitRunInfo() {}
            override fun runOffset(info: RunInfo?): Point = Point(0f, 0f)
            override fun commitRun(info: RunInfo?, glyphs: ShortArray?, positions: Array<Point?>?, clusters: IntArray?) {
                glyphs?.forEach { ids += it }
            }
            override fun commitLine() {}
        },
    )
    return ids.toShortArray()
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
/**
 * The Skia [FontStyle] for a layout-affecting [TextStyle] (ADR 0030 B 档): the
 * OpenType weight axis + italic slant. Default (400, upright) equals
 * [FontStyle.NORMAL], so unstyled clusters resolve the same typeface as before.
 */
fun TextStyle.toSkiaFontStyle(): FontStyle =
    FontStyle(fontWeight, FontStyle.NORMAL.width, if (italic) FontSlant.ITALIC else FontSlant.UPRIGHT)

fun drawTiqianGlyphs(
    canvas: Canvas,
    result: LayoutResult,
    cjkFont: Font,
    latinFont: Font,
    paint: org.jetbrains.skia.Paint,
    shaper: Shaper,
    baselineOffset: Float = 0f,
    colorSpans: List<ColorSpan> = emptyList(),
    spans: List<TextSpan> = emptyList(),
) {
    val language = result.input.textStyle.locale
    // Color is render-only (no advance change), so it never touches the walk's
    // positioning — just the paint per cluster, by source offset.
    val paintByColor = HashMap<Int, org.jetbrains.skia.Paint>()
    result.forEachPositionedCluster(cjkFont, latinFont, baselineOffset, spans) { _, cluster, drawX, baselineY, font ->
        val argb = if (colorSpans.isEmpty()) {
            null
        } else {
            colorSpans.lastOrNull { cluster.range.start >= it.start && cluster.range.start < it.end }?.argb
        }
        val clusterPaint = if (argb == null) paint else paintByColor.getOrPut(argb) {
            org.jetbrains.skia.Paint().apply { color = argb }
        }
        shapeTextBlob(shaper, cluster.displayText, font, language)?.let { blob ->
            canvas.drawTextBlob(blob, drawX, baselineY, clusterPaint)
        }
    }
    // LineEndHangingHyphen (ADR 0029): a hyphen hangs just past the content at a
    // mid-word line end (content end x = indent + visualWidth).
    for (line in result.lines) {
        if (line.hyphenAdvance > 0f) {
            shapeTextBlob(shaper, "-", latinFont, language)?.let { blob ->
                canvas.drawTextBlob(blob, line.indent + line.visualWidth, line.baseline + baselineOffset, paint)
            }
        }
    }
}

/**
 * The single positioned-cluster walk shared by drawing and skip-ink intercepts
 * (they must not drift). Yields each non-empty cluster with its canvas draw
 * origin: x stepping is the engine's resolved `cluster.advance`; a CJK↔Latin
 * Insert gap (autospace leading) shifts right a quarter em; consumed leading
 * glue shifts left.
 */
internal inline fun LayoutResult.forEachPositionedCluster(
    cjkFont: Font,
    latinFont: Font,
    baselineOffset: Float,
    spans: List<TextSpan> = emptyList(),
    action: (line: LineBox, cluster: Cluster, drawX: Float, baselineY: Float, font: Font) -> Unit,
) {
    val autoSpaceGap = 0.25f * input.textStyle.fontSize
    val baseStyle = input.textStyle
    // A cluster covered by a layout-affecting span draws through a font at THAT
    // size + weight + slant (the engine shaped it so), keyed to reuse instances.
    val styledFonts = HashMap<String, Font>()
    // BilingualEmphasisWesternItalic: a Latin run inside an 着重号 span renders
    // italic (the engine shaped it so) — mirror that here from the SAME roles +
    // decorations the engine used, so glyphs match the measured advances.
    val emphasisRanges = input.decorations
        .filter { it.kind == ink.duo3.tiqian.core.DecorationKind.Emphasis }
        .map { it.range }
    val leadingConsumed = debug.geometryDecisions
        .filter { it.leadingGlueConsumed > 0f }
        .associate { it.range to it.leadingGlueConsumed }
    for (line in lines) {
        val lineClusters = clusters.filter { it.range.start >= line.range.start && it.range.end <= line.range.end }
        var x = line.indent
        val baselineY = line.baseline + baselineOffset
        for ((indexInLine, cluster) in lineClusters.withIndex()) {
            val role = debug.fontDecisions.firstOrNull {
                cluster.range.start >= it.range.start && cluster.range.end <= it.range.end
            }?.role
            val isLatin = role == "LatinText"
            val baseFont = if (isLatin) latinFont else cjkFont
            val style = spans.lastOrNull { cluster.range.start >= it.range.start && cluster.range.start < it.range.end }?.style
            val size = style?.fontSize ?: baseStyle.fontSize
            val weight = style?.fontWeight ?: 400
            val italic = (style?.italic ?: false) ||
                (isLatin && emphasisRanges.any { cluster.range.start >= it.start && cluster.range.start < it.end })
            val family = style?.fontFamilies?.firstOrNull()
            val font = if (size == baseStyle.fontSize && weight == 400 && !italic && family == null) {
                baseFont
            } else {
                styledFonts.getOrPut("$isLatin:$size:$weight:$italic:$family") {
                    val tf = if (weight == 400 && !italic && family == null) {
                        baseFont.typeface
                    } else {
                        SkiaSystemTypefaces.typeface(
                            isLatin,
                            family,
                            FontStyle(weight, FontStyle.NORMAL.width, if (italic) FontSlant.ITALIC else FontSlant.UPRIGHT),
                        ) ?: baseFont.typeface
                    }
                    Font(tf, size)
                }
            }
            val hasLeadingGap = debug.autoSpaceDecisions.any { it.clusterRange == cluster.range && it.side == "leading" }
            val leadingGap = if (hasLeadingGap && indexInLine != 0) autoSpaceGap else 0f
            if (cluster.displayText.isNotEmpty()) {
                action(line, cluster, x + leadingGap - (leadingConsumed[cluster.range] ?: 0f), baselineY, font)
            }
            x += cluster.advance
        }
    }
}

/**
 * Canvas x-intervals where glyph ink on [line] crosses the horizontal band
 * `[bandTop, bandBottom]` (canvas y) — Skia's own `TextBlob.getIntercepts`,
 * which is the `text-decoration-skip-ink` primitive (precise, glyph-outline
 * based). Returns a flat `[s0, e0, s1, e1, …]` so the renderer can break an
 * underline/wavy line around descenders that cross it.
 */
fun LayoutResult.lineInkSkipIntervals(
    line: LineBox,
    cjkFont: Font,
    latinFont: Font,
    shaper: Shaper,
    bandTop: Float,
    bandBottom: Float,
): FloatArray {
    val language = input.textStyle.locale
    val out = mutableListOf<Float>()
    forEachPositionedCluster(cjkFont, latinFont, 0f) { l, cluster, drawX, baselineY, font ->
        if (l !== line) return@forEachPositionedCluster
        val blob = shapeTextBlob(shaper, cluster.displayText, font, language) ?: return@forEachPositionedCluster
        // getIntercepts wants the band in the blob's baseline-relative y; the
        // returned x is blob-local → offset by the cluster's draw origin.
        val cuts = blob.getIntercepts(bandTop - baselineY, bandBottom - baselineY)
            ?: return@forEachPositionedCluster
        var i = 0
        while (i + 1 < cuts.size) {
            out += drawX + cuts[i]
            out += drawX + cuts[i + 1]
            i += 2
        }
    }
    return out.toFloatArray()
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

    /** 衬线 (serif) candidates — CJK 宋/明体, Latin Times-like (rich-text fontFamily). */
    val SERIF_CJK_CANDIDATES: List<String> = listOf(
        "Source Han Serif CN", "Noto Serif CJK SC", "Songti SC", "STSong", "SimSun", "Songti TC",
    )
    val SERIF_LATIN_CANDIDATES: List<String> = listOf(
        "Times New Roman", "Times", "Georgia", "Charter", "Iowan Old Style",
    )

    /** 等宽 (monospace) candidates. Most CJK is full-width already → falls back to sans CJK. */
    val MONO_CJK_CANDIDATES: List<String> = listOf("Sarasa Mono SC", "Noto Sans Mono CJK SC")
    val MONO_LATIN_CANDIDATES: List<String> = listOf(
        "Menlo", "SF Mono", "Monaco", "Consolas", "Roboto Mono", "Courier New",
    )

    private val GENERIC_SANS = setOf("sans-serif", "sans", "sansserif")
    private val GENERIC_SERIF = setOf("serif")
    private val GENERIC_MONO = setOf("monospace", "mono")

    /**
     * Candidate family list for a [family] token under the cluster's role. A
     * generic (`serif`/`sans-serif`/`monospace`) maps to the role-matched list;
     * a concrete name is tried first then falls back to the role default — so an
     * unavailable custom family degrades to the system font instead of tofu.
     */
    private fun candidatesFor(isLatin: Boolean, family: String?): List<String> {
        val fallback = if (isLatin) LATIN_CANDIDATES else CJK_CANDIDATES
        return when (family?.lowercase()) {
            null -> fallback
            in GENERIC_SANS -> fallback
            in GENERIC_SERIF -> (if (isLatin) SERIF_LATIN_CANDIDATES else SERIF_CJK_CANDIDATES) + fallback
            in GENERIC_MONO -> (if (isLatin) MONO_LATIN_CANDIDATES else MONO_CJK_CANDIDATES) + fallback
            else -> listOf(family) + fallback
        }
    }

    private val typefaceCache = HashMap<Triple<Boolean, String?, FontStyle>, Typeface?>()

    /**
     * Resolve the typeface for a cluster's role + [family] token + [style] —
     * the SINGLE family resolver shared by the shaper (advances) and renderer
     * (glyphs) so they never pick different fonts. `family` null = role default.
     * CJK rarely ships italic → `matchFamilyStyle` returns the nearest upright.
     */
    fun typeface(isLatin: Boolean, family: String?, style: FontStyle): Typeface? =
        typefaceCache.getOrPut(Triple(isLatin, family?.lowercase(), style)) {
            candidatesFor(isLatin, family).firstNotNullOfOrNull { FontMgr.default.matchFamilyStyle(it, style) }
        }

    /** Role default at [style] (weight/italic) — `typeface(isLatin, null, style)`. */
    fun styled(isLatin: Boolean, style: FontStyle): Typeface? = typeface(isLatin, null, style)
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
