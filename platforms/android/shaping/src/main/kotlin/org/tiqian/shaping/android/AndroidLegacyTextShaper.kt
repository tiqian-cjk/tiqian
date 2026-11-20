package org.tiqian.shaping.android

import android.graphics.Path
import android.graphics.RectF as AndroidRectF
import android.os.Build
import android.text.TextPaint
import org.tiqian.core.Cluster
import org.tiqian.core.Glyph
import org.tiqian.core.GlyphRun
import org.tiqian.core.Rect
import org.tiqian.core.ShapingDecisionInfo
import org.tiqian.font.FontRole
import org.tiqian.shaping.ShapingInput
import org.tiqian.shaping.ShapingResult
import org.tiqian.shaping.ShapingSource
import org.tiqian.shaping.TextShaper
import java.util.Locale

/**
 * Android 6-11 platform text adapter.
 *
 * Those releases expose contextual run measurement and drawing but not the glyph ids and physical
 * fallback fonts chosen by Minikin. `LegacyPlatformRunReplay` therefore keeps each input cluster as
 * one replayable platform run: layout receives the exact contextual advance and ink box, while the
 * renderer replays the same display text, typeface, locale and OpenType features with drawTextRun.
 */
class AndroidLegacyTextShaper(
    private val typefaceResolver: AndroidTypefaceResolver = AndroidTypefaceResolverRegistry.current,
    private val paintConfigurator: (TextPaint, ShapingInput) -> Unit = { _, _ -> },
) : TextShaper {
    private val measurementCache = BoundedLegacyPlatformRunMeasurementCache()

    override fun shape(input: ShapingInput): ShapingResult {
        val sourceText = input.text.substring(input.range.start, input.range.end)
        val displayText = input.displayText
        val paint = newPaint(input)
        val useHanContext = requiresHanShapingContext(displayText, input.fontDecision.role)
        val measured = measurePlatformRun(paint, displayText, useHanContext)
        val halt = measureHalt(input, displayText, measured)
        val glyphs = if (displayText.isEmpty()) {
            emptyList()
        } else {
            listOf(
                Glyph(
                    id = 0,
                    clusterRange = input.range,
                    advance = measured.advance,
                    bounds = measured.bounds,
                    haltAdvance = halt?.first,
                    haltPlacementX = halt?.second,
                ),
            )
        }
        return ShapingResult(
            clusters = listOf(
                Cluster(
                    range = input.range,
                    text = sourceText,
                    displayText = displayText,
                    fontKey = input.fontDecision.candidate.key,
                    advance = measured.advance,
                ),
            ),
            glyphRuns = listOf(
                GlyphRun(
                    range = input.range,
                    fontKey = input.fontDecision.candidate.key,
                    glyphs = glyphs,
                    advance = measured.advance,
                    openTypeFeatures = input.openTypeFeatures,
                ),
            ),
            decisions = listOf(
                ShapingDecisionInfo(
                    range = input.range,
                    sourceText = sourceText,
                    displayText = displayText,
                    fontKey = input.fontDecision.candidate.key,
                    glyphCount = glyphs.size,
                    advance = measured.advance,
                    source = ShapingSource.AndroidPaint.name,
                    reason = "LegacyPlatformRunReplay:api23-30;lang=${input.style.locale}",
                    glyphsWithoutInkBounds = glyphs.count { it.bounds == null },
                    missingGlyphs = measured.missingGlyphs,
                ),
            ),
        )
    }

    private fun measurePlatformRun(
        paint: TextPaint,
        text: String,
        useHanContext: Boolean,
    ): PlatformRunMeasurement {
        if (text.isEmpty()) return PlatformRunMeasurement(0f, null, 0)
        val key = LegacyPlatformRunMeasurementKey.from(paint, text, useHanContext)
        return measurementCache.getOrPut(key) {
            measurePlatformRunUncached(paint, text, useHanContext)
        }
    }

    private fun measurePlatformRunUncached(
        paint: TextPaint,
        text: String,
        useHanContext: Boolean,
    ): PlatformRunMeasurement {
        val missingGlyphs = paint.countMissingCodePoints(text)
        if (!useHanContext) {
            val advance = paint.getRunAdvance(text, 0, text.length, 0, text.length, false, text.length)
            return paint.withMissingGlyphBody(
                PlatformRunMeasurement(advance, paint.textPathBounds(text, 0f), missingGlyphs),
            )
        }

        val buffer = "中${text}中"
        val start = 1
        val end = 1 + text.length
        val penStart = paint.getRunAdvance(buffer, 0, buffer.length, 0, buffer.length, false, start)
        val penEnd = paint.getRunAdvance(buffer, 0, buffer.length, 0, buffer.length, false, end)
        val path = Path()
        paint.getTextPath(buffer, 0, buffer.length, 0f, 0f, path)
        val clip = Path().apply {
            addRect(penStart, -paint.textSize * 2f, penEnd, paint.textSize, Path.Direction.CW)
        }
        path.op(clip, Path.Op.INTERSECT)
        path.offset(-penStart, 0f)
        return paint.withMissingGlyphBody(
            PlatformRunMeasurement(penEnd - penStart, path.toCoreBounds(), missingGlyphs),
        )
    }

    private fun measureHalt(
        input: ShapingInput,
        text: String,
        defaultMeasurement: PlatformRunMeasurement,
    ): Pair<Float, Float>? {
        if (text.isEmpty() || input.fontDecision.role != FontRole.CjkPunctuation) return null
        val paint = newPaint(input).apply { fontFeatureSettings = "'halt' on" }
        val measured = measurePlatformRun(paint, text, useHanContext = true)
        if (measured.advance <= 0f || measured.advance >= defaultMeasurement.advance) return null
        val placementX = if (measured.bounds != null && defaultMeasurement.bounds != null) {
            measured.bounds.left - defaultMeasurement.bounds.left
        } else {
            0f
        }
        return measured.advance to placementX
    }

    private fun newPaint(input: ShapingInput): TextPaint = TextPaint().apply {
        isAntiAlias = true
        textSize = input.style.fontSize
        textLocale = Locale.forLanguageTag(input.style.locale)
        typeface = typefaceResolver.resolve(input)
        input.openTypeFeatures.toAndroidFontFeatureSettings()?.let { fontFeatureSettings = it }
        paintConfigurator(this, input)
    }

    private fun TextPaint.textPathBounds(text: String, originX: Float): Rect? {
        val path = Path()
        getTextPath(text, 0, text.length, originX, 0f, path)
        return path.toCoreBounds()
    }

    private fun TextPaint.withMissingGlyphBody(
        measured: PlatformRunMeasurement,
    ): PlatformRunMeasurement {
        if (measured.missingGlyphs == 0 || measured.advance > 0f) return measured
        return measured.copy(
            advance = textSize,
            bounds = measured.bounds ?: Rect(0f, -textSize * 0.88f, textSize, textSize * 0.12f),
        )
    }

    private fun Path.toCoreBounds(): Rect? {
        if (isEmpty) return null
        val bounds = AndroidRectF()
        computeBounds(bounds, true)
        if (bounds.isEmpty) return null
        return Rect(bounds.left, bounds.top, bounds.right, bounds.bottom)
    }
}

private data class PlatformRunMeasurement(
    val advance: Float,
    val bounds: Rect?,
    val missingGlyphs: Int,
)

/**
 * `BoundedLegacyPlatformMeasurementReuse`: platform run geometry depends on the final
 * [TextPaint], display text and whether the synthetic Han context is active, but not on the
 * paragraph's source range. Reuse that exact native measurement across repeated characters in one
 * Compose document while keeping the same getRunAdvance/getTextPath evidence used by drawing.
 *
 * The cache is deliberately owned by one shaper (and therefore by one UI-thread-confined Compose
 * measurer) and bounded so reading many documents cannot retain every glyph seen by the process.
 */
private class BoundedLegacyPlatformRunMeasurementCache(
    private val maxEntries: Int = DEFAULT_LEGACY_PLATFORM_MEASUREMENT_CACHE_ENTRIES,
) {
    init {
        require(maxEntries > 0) { "maxEntries must be positive" }
    }

    private val values = LinkedHashMap<LegacyPlatformRunMeasurementKey, PlatformRunMeasurement>()

    fun getOrPut(
        key: LegacyPlatformRunMeasurementKey,
        create: () -> PlatformRunMeasurement,
    ): PlatformRunMeasurement {
        values[key]?.let { return it }
        return create().also { value ->
            if (values.size >= maxEntries) values.remove(values.keys.first())
            values[key] = value
        }
    }
}

private data class LegacyPlatformRunMeasurementKey(
    val text: String,
    val useHanContext: Boolean,
    val typeface: android.graphics.Typeface?,
    val textSizeBits: Int,
    val textScaleXBits: Int,
    val textSkewXBits: Int,
    val letterSpacingBits: Int,
    val flags: Int,
    val localeTag: String,
    val fontFeatureSettings: String?,
    val fontVariationSettings: String?,
    val wordSpacingBits: Int?,
) {
    companion object {
        fun from(paint: TextPaint, text: String, useHanContext: Boolean) =
            LegacyPlatformRunMeasurementKey(
                text = text,
                useHanContext = useHanContext,
                typeface = paint.typeface,
                textSizeBits = paint.textSize.toBits(),
                textScaleXBits = paint.textScaleX.toBits(),
                textSkewXBits = paint.textSkewX.toBits(),
                letterSpacingBits = paint.letterSpacing.toBits(),
                flags = paint.flags,
                localeTag = paint.textLocale.toLanguageTag(),
                fontFeatureSettings = paint.fontFeatureSettings,
                fontVariationSettings = if (Build.VERSION.SDK_INT >= 26) paint.fontVariationSettings else null,
                wordSpacingBits = if (Build.VERSION.SDK_INT >= 29) paint.wordSpacing.toBits() else null,
            )
    }
}

private const val DEFAULT_LEGACY_PLATFORM_MEASUREMENT_CACHE_ENTRIES = 2_048

private fun TextPaint.countMissingCodePoints(text: String): Int {
    var missing = 0
    var index = 0
    while (index < text.length) {
        val codePoint = text.codePointAt(index)
        if (!hasGlyph(String(Character.toChars(codePoint)))) missing += 1
        index += Character.charCount(codePoint)
    }
    return missing
}
