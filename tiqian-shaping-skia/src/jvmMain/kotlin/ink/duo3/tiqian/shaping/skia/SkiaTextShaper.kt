package ink.duo3.tiqian.shaping.skia

import org.jetbrains.skia.Font
import org.jetbrains.skia.FontMgr
import org.jetbrains.skia.FontStyle
import org.jetbrains.skia.Point
import org.jetbrains.skia.Typeface
import org.jetbrains.skia.shaper.RunHandler
import org.jetbrains.skia.shaper.RunInfo
import org.jetbrains.skia.shaper.Shaper
import org.jetbrains.skia.shaper.ShapingOptions
import org.jetbrains.skia.shaper.TrivialBidiRunIterator
import org.jetbrains.skia.shaper.TrivialFontRunIterator
import org.jetbrains.skia.shaper.TrivialLanguageRunIterator
import org.jetbrains.skia.shaper.TrivialScriptRunIterator
import ink.duo3.tiqian.core.Cluster
import ink.duo3.tiqian.core.Glyph
import ink.duo3.tiqian.core.GlyphRun
import ink.duo3.tiqian.core.Rect
import ink.duo3.tiqian.core.ShapingDecisionInfo
import ink.duo3.tiqian.font.FontRole
import ink.duo3.tiqian.shaping.ShapingInput
import ink.duo3.tiqian.shaping.ShapingResult
import ink.duo3.tiqian.shaping.ShapingSource
import ink.duo3.tiqian.shaping.TextShaper
import kotlin.math.max

/**
 * Skia (Skiko) shaping adapter — the second real-measurement adapter next to
 * `AwtTextShaper` (ADR 0013/0015). Same contract: consume the layout-decided
 * `displayText` with a single resolved font, emit one cluster + one glyph run
 * with real advances and glyph-local ink bounds. No fallback, no CLREQ
 * substitution, no punctuation decisions — those stay upstream.
 *
 * Named heuristic: `LocaleTaggedShaping`. Shaping runs through the full
 * SkShaper pipeline with [ShapingInput.style]'s locale as the HarfBuzz
 * language tag, so OpenType `locl` variants activate. Pan-CJK fonts (Source
 * Han Sans) draw `—` / `⸺` at the Western baseline-aligned height by
 * default and only swap in the CJK vertically-centred variants under
 * `zh-Hans` — without the tag the dash visibly sits at Latin height. AWT has
 * no equivalent capability, which is a documented cross-adapter divergence
 * (see `AwtSkiaShapingComparisonTest`).
 *
 * Glyph bounds come from [Font.getBounds] and are already glyph-local
 * (origin at the glyph's pen position, negative top above the baseline),
 * matching the convention `AwtTextShaper` produces via origin subtraction.
 */
class SkiaTextShaper(
    private val fontResolver: SkiaFontResolver = SystemSkiaFontResolver(),
) : TextShaper {
    private val shaper: Shaper = Shaper.makeShaperDrivenWrapper()

    override fun shape(input: ShapingInput): ShapingResult {
        val sourceText = input.text.substring(input.range.start, input.range.end)
        val displayText = input.displayText
        val font = fontResolver.resolve(input)
        val language = input.style.locale

        val collector = GlyphCollectingRunHandler()
        if (displayText.isNotEmpty()) {
            runShaper(displayText, font, language, ShapingOptions.DEFAULT, collector)
        }
        val glyphIds = collector.glyphIds.toShortArray()
        val xPositions = collector.xPositions
        val glyphCount = glyphIds.size
        val advance = collector.advance

        // FontHaltMeasurement: a second feature-tagged pass measures the
        // font's `halt` (alternate half-width) metrics for punctuation
        // clusters. The feature is NOT applied to the rendered geometry —
        // the engine owns blank-trimming via the glue model; halt only
        // tells us the font-defined body width (ADR 0014 follow-up).
        // Single-glyph clusters take the run advance directly (immune to
        // the placement shift halt applies to opening brackets); multi-
        // glyph punctuation clusters (`⋯⋯` etc.) are never halt-affected.
        val haltCollector = if (
            input.fontDecision.role == FontRole.CjkPunctuation &&
            glyphCount == 1
        ) {
            GlyphCollectingRunHandler().also {
                runShaper(displayText, font, language, ShapingOptions.DEFAULT.withFeatures("halt=1"), it)
            }
        } else {
            null
        }
        val haltAdvance = haltCollector?.advance
            ?.takeIf { haltCollector.glyphIds.size == 1 && it > 0f && it < advance }
        val haltPlacementX = if (haltAdvance != null) haltCollector.xPositions.firstOrNull() else null

        val cluster = Cluster(
            range = input.range,
            text = sourceText,
            displayText = displayText,
            fontKey = input.fontDecision.candidate.key,
            advance = advance,
        )
        val inkBounds = font.getBounds(glyphIds)
        val glyphs = (0 until glyphCount).map { glyphIndex ->
            val startX = xPositions[glyphIndex]
            val endX = if (glyphIndex + 1 < glyphCount) xPositions[glyphIndex + 1] else advance
            Glyph(
                id = glyphIds[glyphIndex].toUShort().toUInt(),
                clusterRange = input.range,
                advance = max(0f, endX - startX),
                bounds = inkBounds.getOrNull(glyphIndex)?.toGlyphLocalRectOrNull(),
                haltAdvance = haltAdvance,
                haltPlacementX = haltPlacementX,
            )
        }
        val run = GlyphRun(
            range = input.range,
            fontKey = input.fontDecision.candidate.key,
            glyphs = glyphs,
            advance = advance,
        )
        val decision = ShapingDecisionInfo(
            range = input.range,
            sourceText = sourceText,
            displayText = displayText,
            fontKey = input.fontDecision.candidate.key,
            glyphCount = glyphCount,
            advance = advance,
            source = ShapingSource.Skia.name,
            reason = "SkiaTextShaper:${font.typeface?.familyName ?: "default"}:lang=$language",
            glyphsWithoutInkBounds = glyphs.count { it.bounds == null },
            missingGlyphs = glyphIds.count { it == NOTDEF_GLYPH },
        )
        return ShapingResult(
            clusters = listOf(cluster),
            glyphRuns = listOf(run),
            decisions = listOf(decision),
        )
    }

    private fun runShaper(
        text: String,
        font: Font,
        language: String,
        options: ShapingOptions,
        handler: RunHandler,
    ) {
        shaper.shape(
            text,
            TrivialFontRunIterator(text, font),
            TrivialBidiRunIterator(text, 0),
            TrivialScriptRunIterator(text, "Hani"),
            TrivialLanguageRunIterator(text, language),
            options,
            Float.MAX_VALUE,
            handler,
        )
    }

    /**
     * Collects shaped glyphs across runs. For Tiqian inputs the trivial
     * font/script/language iterators yield exactly one run, but multi-run
     * output is still accumulated correctly via the pen offset returned
     * from [runOffset].
     */
    private class GlyphCollectingRunHandler : RunHandler {
        val glyphIds = mutableListOf<Short>()
        val xPositions = mutableListOf<Float>()
        var advance: Float = 0f
            private set
        private var penX = 0f

        override fun beginLine() {}

        override fun runInfo(info: RunInfo?) {}

        override fun commitRunInfo() {}

        override fun runOffset(info: RunInfo?): Point = Point(penX, 0f)

        override fun commitRun(info: RunInfo?, glyphs: ShortArray?, positions: Array<Point?>?, clusters: IntArray?) {
            if (info == null || glyphs == null || positions == null) return
            glyphs.forEachIndexed { index, glyphId ->
                glyphIds += glyphId
                xPositions += (positions.getOrNull(index)?.x ?: penX)
            }
            penX += info.advanceX
            advance = penX
        }

        override fun commitLine() {}
    }

    private companion object {
        const val NOTDEF_GLYPH: Short = 0
    }
}

interface SkiaFontResolver {
    fun resolve(input: ShapingInput): Font
}

/**
 * Probes [FontMgr.default] for the first available CJK / Latin family from
 * the same preference lists `SystemAwtFontResolver` uses, so AWT ↔ Skia
 * comparisons measure the same physical font whenever possible.
 *
 * Named heuristic: `SystemSkiaFontProbe`.
 */
class SystemSkiaFontResolver(
    private val fontMgr: FontMgr = FontMgr.default,
) : SkiaFontResolver {
    private val cjkTypeface: Typeface? =
        CJK_CANDIDATES.firstNotNullOfOrNull { fontMgr.matchFamilyStyle(it, FontStyle.NORMAL) }
    private val latinTypeface: Typeface? =
        LATIN_CANDIDATES.firstNotNullOfOrNull { fontMgr.matchFamilyStyle(it, FontStyle.NORMAL) }

    override fun resolve(input: ShapingInput): Font {
        val requestedFamily = input.style.fontFamilies.firstOrNull()
            ?: input.fontDecision.candidate.family.takeUnless { it == input.fontDecision.candidate.key }
        val typeface = requestedFamily?.let { fontMgr.matchFamilyStyle(it, FontStyle.NORMAL) }
            ?: input.fontDecision.role.resolvedTypeface()
        return Font(typeface, input.style.fontSize)
    }

    private fun FontRole.resolvedTypeface(): Typeface? =
        when (this) {
            FontRole.CjkText,
            FontRole.CjkPunctuation,
            -> cjkTypeface

            FontRole.LatinText,
            FontRole.Symbol,
            FontRole.Emoji,
            FontRole.Unknown,
            -> latinTypeface
        }

    companion object {
        /** Ordered by preference; first match wins. Mirrors `SystemAwtFontProbe`. */
        private val CJK_CANDIDATES = listOf(
            "Source Han Sans CN",
            "Source Han Sans CN VF",
            "Noto Sans CJK SC",
            "PingFang SC",
            "Hiragino Sans GB",
            "Sarasa UI SC",
            "Heiti SC",
            "STHeiti",
        )

        private val LATIN_CANDIDATES = listOf(
            "Inter Variable",
            "Inter",
            "SF Pro Text",
            "SF Pro",
            "Roboto",
            "Helvetica Neue",
        )
    }
}

private fun org.jetbrains.skia.Rect.toGlyphLocalRectOrNull(): Rect? {
    if (width <= 0f || height <= 0f) return null
    return Rect(
        left = left,
        top = top,
        right = right,
        bottom = bottom,
    )
}
