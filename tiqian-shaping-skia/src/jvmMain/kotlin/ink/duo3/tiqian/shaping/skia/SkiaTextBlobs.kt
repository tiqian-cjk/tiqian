package ink.duo3.tiqian.shaping.skia

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
