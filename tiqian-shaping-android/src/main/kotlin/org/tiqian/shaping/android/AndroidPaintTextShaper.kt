package org.tiqian.shaping.android

import android.graphics.Rect as AndroidRect
import android.graphics.Typeface
import android.graphics.text.TextRunShaper
import android.text.TextPaint
import org.tiqian.core.Cluster
import org.tiqian.core.Glyph
import org.tiqian.core.GlyphRun
import org.tiqian.core.Rect
import org.tiqian.core.ShapingDecisionInfo
import org.tiqian.font.usesLatinFace
import org.tiqian.shaping.ShapingInput
import org.tiqian.shaping.ShapingResult
import org.tiqian.shaping.ShapingSource
import org.tiqian.shaping.TextShaper
import java.util.Locale
import kotlin.math.max

/**
 * Android platform adapter — the third real-measurement shaper next to AWT
 * (ADR 0013) and Skia (ADR 0015). Same contract: consume the layout-decided
 * `displayText` with one paint configuration, emit one cluster + one glyph
 * run with real advances and ink bounds. No CLREQ substitution and no layout
 * decisions here.
 *
 * Platform notes:
 * - `LocaleTaggedShaping`: [TextPaint.setTextLocale] carries the
 *   `TextStyle.locale` tag, so OpenType `locl` variants (CJK dash forms)
 *   activate exactly like the Skia adapter.
 * - `FontHaltMeasurement`: a second measurement with
 *   `fontFeatureSettings = "'halt' on"` provides the font-defined half-width
 *   body for punctuation clusters; the feature never touches rendered
 *   geometry.
 * - Unlike AWT/Skia, Android typefaces always carry an internal fallback
 *   chain that cannot be disabled; the adapter therefore measures "the
 *   platform text stack with this locale", not a single physical font file.
 *   Cross-adapter goldens must tolerate that (see ADR 0016).
 * - Per-glyph ink bounds come from [TextPaint.getTextBounds] and are only
 *   attributed for single-glyph clusters; multi-glyph clusters report null
 *   bounds and surface as `MissingInkBoundsFallback` downstream.
 */
class AndroidPaintTextShaper(
    private val typefaceResolver: AndroidTypefaceResolver = SystemAndroidTypefaceResolver(),
    private val paintConfigurator: (TextPaint, ShapingInput) -> Unit = { _, _ -> },
) : TextShaper {

    override fun shape(input: ShapingInput): ShapingResult {
        val sourceText = input.text.substring(input.range.start, input.range.end)
        val displayText = input.displayText
        val paint = newPaint(input)

        // HanContextShaping: a lone `—` is script-COMMON; HarfBuzz resolves
        // an isolated buffer to the OpenType DFLT script, where Noto Sans
        // CJK does NOT register its `locl` rules — context-free shaping
        // silently keeps the Western dash. Desktop adapters force
        // script=Hani; Android has no public script control, so CJK-role
        // clusters are shaped inside the buffer `中<cluster>中` (the same
        // Han-run environment Minikin gives them in real paragraphs) and
        // the cluster's glyphs/advance are sliced back out by offset.
        val useHanContext = displayText.isNotEmpty() &&
            (
                input.fontDecision.role == org.tiqian.font.FontRole.CjkText ||
                    input.fontDecision.role == org.tiqian.font.FontRole.CjkPunctuation
                )
        val measured = measureRun(paint, displayText, useHanContext)
        val advance = measured.advance

        val haltMetrics = measureHalt(input, displayText, advance, measured.glyphIds.size)

        val singleGlyphBounds = if (measured.glyphIds.size == 1) {
            val bounds = AndroidRect()
            paint.getTextBounds(displayText, 0, displayText.length, bounds)
            bounds.toGlyphLocalRectOrNull()
        } else {
            null
        }

        val glyphCount = measured.glyphIds.size
        val glyphs = (0 until glyphCount).map { glyphIndex ->
            val startX = measured.glyphXs[glyphIndex]
            val endX = if (glyphIndex + 1 < glyphCount) measured.glyphXs[glyphIndex + 1] else advance
            Glyph(
                id = measured.glyphIds[glyphIndex].toUInt(),
                clusterRange = input.range,
                advance = max(0f, endX - startX),
                x = startX,
                y = measured.glyphYs[glyphIndex],
                renderFontKey = measured.renderFontKeys[glyphIndex],
                bounds = if (glyphCount == 1) singleGlyphBounds else null,
                haltAdvance = haltMetrics?.first,
                haltPlacementX = haltMetrics?.second,
            )
        }
        val cluster = Cluster(
            range = input.range,
            text = sourceText,
            displayText = displayText,
            fontKey = input.fontDecision.candidate.key,
            advance = advance,
        )
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
            source = ShapingSource.AndroidPaint.name,
            reason = "AndroidPaintTextShaper:lang=${input.style.locale}",
            glyphsWithoutInkBounds = glyphs.count { it.bounds == null },
            missingGlyphs = if (displayText.isNotEmpty() && !paint.hasGlyph(displayText)) 1 else 0,
        )
        return ShapingResult(
            clusters = listOf(cluster),
            glyphRuns = listOf(run),
            decisions = listOf(decision),
        )
    }

    private class MeasuredRun(
        val advance: Float,
        val glyphIds: IntArray,
        /** Glyph x positions normalised to the cluster's pen origin. */
        val glyphXs: FloatArray,
        /** Glyph y positions relative to the cluster baseline. */
        val glyphYs: FloatArray,
        /** Opaque Android Font keys for drawing these glyph ids later. */
        val renderFontKeys: List<String?>,
    )

    /**
     * Shapes [displayText] (optionally inside the `中…中` buffer) and slices
     * the cluster's glyphs back out. If glyph→character attribution inside
     * the Han buffer is ambiguous (ligatures), falls back to context-free
     * shaping — the Western forms are then honestly what gets measured.
     */
    private fun measureRun(
        paint: TextPaint,
        displayText: String,
        useHanContext: Boolean,
    ): MeasuredRun {
        if (displayText.isEmpty()) return MeasuredRun(0f, IntArray(0), FloatArray(0), FloatArray(0), emptyList())

        if (useHanContext) {
            val buffer = "中${displayText}中"
            val shaped = TextRunShaper.shapeTextRun(buffer, 0, buffer.length, 0, buffer.length, 0f, 0f, false, paint)
            // 1:1 glyph attribution: one glyph per UTF-16 unit of the buffer
            // (true for all CJK punctuation and Han text we feed here).
            if (shaped.glyphCount() == buffer.length) {
                val runStart = 1
                val runEnd = 1 + displayText.length
                // Pen origin from getRunAdvance, NOT from glyph x — features
                // like `halt` shift glyph placement away from the pen, and
                // that shift is exactly what haltPlacementX must report.
                val penOrigin =
                    paint.getRunAdvance(buffer, 0, buffer.length, 0, buffer.length, false, runStart)
                val advance =
                    paint.getRunAdvance(buffer, 0, buffer.length, 0, buffer.length, false, runEnd) - penOrigin
                val ids = IntArray(displayText.length) { shaped.getGlyphId(runStart + it) }
                val xs = FloatArray(displayText.length) { shaped.getGlyphX(runStart + it) - penOrigin }
                val ys = FloatArray(displayText.length) { shaped.getGlyphY(runStart + it) }
                val fonts = List(displayText.length) { index ->
                    AndroidPositionedGlyphFontRegistry.keyFor(shaped.getFont(runStart + index))
                }
                return MeasuredRun(advance, ids, xs, ys, fonts)
            }
        }

        val advance =
            paint.getRunAdvance(displayText, 0, displayText.length, 0, displayText.length, false, displayText.length)
        val shaped =
            TextRunShaper.shapeTextRun(displayText, 0, displayText.length, 0, displayText.length, 0f, 0f, false, paint)
        val ids = IntArray(shaped.glyphCount()) { shaped.getGlyphId(it) }
        val xs = FloatArray(shaped.glyphCount()) { shaped.getGlyphX(it) }
        val ys = FloatArray(shaped.glyphCount()) { shaped.getGlyphY(it) }
        val fonts = List(shaped.glyphCount()) { index ->
            AndroidPositionedGlyphFontRegistry.keyFor(shaped.getFont(index))
        }
        return MeasuredRun(advance, ids, xs, ys, fonts)
    }

    /**
     * FontHaltMeasurement (Android side): re-measure the cluster with the
     * `halt` feature for CjkPunctuation single-glyph clusters. Returns
     * (halt advance, halt placement x) or null when the font has no
     * alternate (halt advance == default advance).
     */
    private fun measureHalt(
        input: ShapingInput,
        displayText: String,
        defaultAdvance: Float,
        glyphCount: Int,
    ): Pair<Float, Float>? {
        if (glyphCount != 1) return null
        if (input.fontDecision.role != org.tiqian.font.FontRole.CjkPunctuation) return null
        val haltPaint = newPaint(input).apply { fontFeatureSettings = "'halt' on" }
        val measured = measureRun(haltPaint, displayText, useHanContext = true)
        if (measured.glyphIds.size != 1) return null
        val haltAdvance = measured.advance
        if (haltAdvance <= 0f || haltAdvance >= defaultAdvance) return null
        return haltAdvance to measured.glyphXs[0]
    }

    private fun newPaint(input: ShapingInput): TextPaint =
        TextPaint().apply {
            isAntiAlias = true
            textSize = input.style.fontSize
            textLocale = Locale.forLanguageTag(input.style.locale)
            typeface = typefaceResolver.resolve(input)
            paintConfigurator(this, input)
        }

    private fun AndroidRect.toGlyphLocalRectOrNull(): Rect? {
        if (isEmpty) return null
        return Rect(
            left = left.toFloat(),
            top = top.toFloat(),
            right = right.toFloat(),
            bottom = bottom.toFloat(),
        )
    }
}

interface AndroidTypefaceResolver {
    fun resolve(
        role: org.tiqian.font.FontRole,
        fontFamilies: List<String> = emptyList(),
        fontWeight: Int = 400,
        italic: Boolean = false,
    ): Typeface

    fun resolve(input: ShapingInput): android.graphics.Typeface
}

/**
 * Mirrors `SystemAwtFontResolver` / `SystemSkiaFontResolver`: CJK roles get
 * an explicit CJK typeface so codepoints that Roboto also covers (`—` `…`)
 * resolve from the CJK font instead of the Latin head of the system
 * fallback chain — `textLocale` alone only reorders the CJK tail.
 *
 * Named heuristic: `SystemAndroidFontProbe`.
 */
class SystemAndroidTypefaceResolver : AndroidTypefaceResolver {
    private val cjkTypeface: android.graphics.Typeface? =
        CJK_FONT_FILES.firstNotNullOfOrNull { (path, ttcIndex) ->
            val file = java.io.File(path)
            if (!file.exists()) return@firstNotNullOfOrNull null
            runCatching {
                android.graphics.Typeface.Builder(file)
                    .setTtcIndex(ttcIndex)
                    .build()
            }.getOrNull()
        }

    override fun resolve(input: ShapingInput): android.graphics.Typeface =
        resolve(
            role = input.fontDecision.role,
            fontFamilies = input.style.fontFamilies,
            fontWeight = input.style.fontWeight,
            italic = input.style.italic,
        )

    override fun resolve(
        role: org.tiqian.font.FontRole,
        fontFamilies: List<String>,
        fontWeight: Int,
        italic: Boolean,
    ): android.graphics.Typeface {
        val family = fontFamilies.firstOrNull()
        // LatinVsCjkFaceSelection (shared rule): only real Latin text uses the Latin
        // face; Symbol/Emoji/Unknown fall back to CJK so a missing glyph is a full-em
        // 字身框 豆腐 and measure==draw, matching the Skia/AWT resolvers.
        val base = if (role.usesLatinFace()) {
            latinTypefaceFor(family)
        } else {
            cjkTypefaceFor(family) ?: android.graphics.Typeface.DEFAULT
        }
        return Typeface.create(base, fontWeight.coerceIn(1, 1000), italic)
    }

    private fun cjkTypefaceFor(family: String?): Typeface? =
        when (family?.lowercase()) {
            null, "sans", "sans-serif", "sansserif" -> cjkTypeface
            // Android does not expose a role-aware CJK generic resolver; these
            // generics are still honored for gallery typography, then styled.
            "serif" -> Typeface.SERIF
            "monospace", "mono" -> Typeface.MONOSPACE
            else -> Typeface.create(family, Typeface.NORMAL)
        }

    private fun latinTypefaceFor(family: String?): Typeface =
        when (family?.lowercase()) {
            null, "sans", "sans-serif", "sansserif" -> Typeface.DEFAULT
            "serif" -> Typeface.SERIF
            "monospace", "mono" -> Typeface.MONOSPACE
            else -> Typeface.create(family, Typeface.NORMAL)
        }

    private companion object {
        /**
         * (path, ttcIndex) ordered by preference; first existing file wins.
         * The AOSP NotoSansCJK collection orders faces jp/kr/sc/tc — index 2
         * is the Simplified Chinese face (same index AOSP fonts.xml maps to
         * zh-Hans), whose DEFAULT dash/ellipsis forms are already the CJK
         * ones without relying on `locl` re-tagging.
         */
        val CJK_FONT_FILES = listOf(
            "/system/fonts/NotoSansCJK-Regular.ttc" to 2,
            "/system/fonts/NotoSansSC-Regular.otf" to 0,
            "/system/fonts/NotoSansCJKsc-Regular.otf" to 0,
        )
    }
}
