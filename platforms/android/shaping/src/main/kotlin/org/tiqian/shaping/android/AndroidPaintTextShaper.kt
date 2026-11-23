package org.tiqian.shaping.android

import android.annotation.TargetApi
import android.graphics.RectF as AndroidRectF
import android.os.Build
import android.graphics.Typeface
import android.graphics.text.PositionedGlyphs
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
 * - Per-glyph ink bounds come from `Font.getGlyphBounds`, using the same
 *   [PositionedGlyphs] glyph ids/fonts as drawing. This keeps skip-ink at
 *   glyph granularity instead of collapsing a whole Latin word to one bounds box.
 */
@TargetApi(31)
class AndroidPaintTextShaper(
    private val typefaceResolver: AndroidTypefaceResolver = AndroidTypefaceResolverRegistry.current,
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
        val useHanContext = requiresHanShapingContext(displayText, input.fontDecision.role)
        val measured = measureRun(paint, displayText, useHanContext)
        val advance = measured.advance

        val haltMetrics = measureHalt(input, displayText, advance, measured.glyphIds.size)

        // ContextConsistentGlyphCapture: ligature fallback glyphs that do not add
        // up to the context advance must not be replayed glyph-by-glyph — dropping
        // the render keys makes the renderer fall back to context-shaped STRING
        // drawing (correct ink).
        val contextFreeAdvance =
            paint.getRunAdvance(displayText, 0, displayText.length, 0, displayText.length, false, displayText.length)
        val advanceConsistent = kotlin.math.abs(contextFreeAdvance - advance) <= 1f
        val replayable = measured.contextSliced || advanceConsistent

        val glyphCount = measured.glyphIds.size
        val glyphs = (0 until glyphCount).map { glyphIndex ->
            val startX = measured.glyphXs[glyphIndex]
            val endX = if (glyphIndex + 1 < glyphCount) measured.glyphXs[glyphIndex + 1] else advance
            Glyph(
                id = measured.glyphIds[glyphIndex],
                clusterRange = input.range,
                advance = max(0f, endX - startX),
                x = startX,
                y = measured.glyphYs[glyphIndex],
                renderFontKey = if (replayable) measured.renderFontKeys[glyphIndex] else null,
                bounds = measured.glyphBounds[glyphIndex],
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
            openTypeFeatures = input.openTypeFeatures,
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
            missingGlyphs = measured.glyphIds.count { it == 0 },
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
        /** Glyph-local ink bounds from the shaped Android font, one per glyph. */
        val glyphBounds: List<Rect?>,
        /** True when the glyphs were sliced out of the Han-context shape (same world as [advance]). */
        val contextSliced: Boolean = false,
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
        if (displayText.isEmpty()) {
            return MeasuredRun(0f, IntArray(0), FloatArray(0), FloatArray(0), emptyList(), emptyList(), contextSliced = true)
        }

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
                val bounds = List(displayText.length) { shaped.glyphBounds(runStart + it, paint) }
                // NoGlyphReplayInHanContext: TextRunShaper's glyph ids are NOT what
                // drawTextRun renders for context-sensitive CJK (measured on Pixel:
                // `⸺` drawTextRun ink = 1.84em, drawGlyphs of the reported id =
                // 1.58em — locl applies to the advance but not the reported id).
                // No render keys → the renderer draws these clusters as Han-context
                // STRINGS, which is pixel-faithful; ids stay for debug/tests only.
                val fonts = List<String?>(displayText.length) { null }
                return MeasuredRun(advance, ids, xs, ys, fonts, bounds, contextSliced = true)
            }
        }

        val advance =
            paint.getRunAdvance(displayText, 0, displayText.length, 0, displayText.length, false, displayText.length)
        val shaped =
            TextRunShaper.shapeTextRun(displayText, 0, displayText.length, 0, displayText.length, 0f, 0f, false, paint)
        val glyphCount = shaped.glyphCount()
        val ids = IntArray(glyphCount) { shaped.getGlyphId(it) }
        val xs = FloatArray(glyphCount) { shaped.getGlyphX(it) }
        val ys = FloatArray(glyphCount) { shaped.getGlyphY(it) }
        // RepeatedGlyphMetricReuse: glyph bounds and the font-registry key are pure in
        // (font, glyph id) under this call's fixed paint, and long runs repeat a small glyph
        // alphabet. Per-call memoisation with one JNI read per glyph keeps a 100K-char
        // pathological token at a few dozen metric calls.
        val boundsByFont = HashMap<android.graphics.fonts.Font, HashMap<Int, Rect?>>()
        val fontKeyByFont = HashMap<android.graphics.fonts.Font, String?>()
        val bounds = ArrayList<Rect?>(glyphCount)
        val fonts = ArrayList<String?>(glyphCount)
        for (index in 0 until glyphCount) {
            val font = shaped.getFont(index)
            val glyphId = ids[index]
            val perFont = boundsByFont.getOrPut(font) { HashMap() }
            bounds += if (glyphId in perFont) {
                perFont.getValue(glyphId)
            } else {
                font.glyphLocalBounds(glyphId, paint).also { perFont[glyphId] = it }
            }
            fonts += if (font in fontKeyByFont) {
                fontKeyByFont.getValue(font)
            } else {
                AndroidPositionedGlyphFontRegistry.keyFor(font).also { fontKeyByFont[font] = it }
            }
        }
        return MeasuredRun(advance, ids, xs, ys, fonts, bounds)
    }

    private fun PositionedGlyphs.glyphBounds(index: Int, paint: TextPaint): Rect? =
        getFont(index).glyphLocalBounds(getGlyphId(index), paint)

    private fun android.graphics.fonts.Font.glyphLocalBounds(glyphId: Int, paint: TextPaint): Rect? {
        val bounds = AndroidRectF()
        getGlyphBounds(glyphId, paint, bounds)
        return bounds.toGlyphLocalRectOrNull()
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
            input.openTypeFeatures.toAndroidFontFeatureSettings()?.let { fontFeatureSettings = it }
            paintConfigurator(this, input)
        }

    private fun AndroidRectF.toGlyphLocalRectOrNull(): Rect? {
        if (isEmpty) return null
        return Rect(
            left = left,
            top = top,
            right = right,
            bottom = bottom,
        )
    }
}

internal fun List<String>.toAndroidFontFeatureSettings(): String? {
    if (isEmpty()) return null
    return joinToString(",") { feature ->
        val pieces = feature.split('=', limit = 2)
        val tag = pieces[0].trim().take(4)
        val value = pieces.getOrNull(1)?.trim()?.toIntOrNull() ?: 1
        "'$tag' $value"
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
 * Named heuristic: `SystemAndroidFontProbe`. Anchor face evidence, in order:
 * `PlatformDefaultHanFaceReadback` (API 31+) shapes one Han character per
 * requested (weight, italic) with the styled default typeface and anchors to
 * the `Font` the platform fallback chain actually selected — OEM/user theme
 * fonts and variable-font weight instances are both honored; the well-known
 * file paths remain the API 26–30 path and the readback fallback.
 */
class SystemAndroidTypefaceResolver : AndroidTypefaceResolver {
    private val platformHanTypefaces = HashMap<Pair<Int, Boolean>, Typeface?>()

    private val wellKnownHanTypeface: Typeface? by lazy {
        if (Build.VERSION.SDK_INT >= 26) wellKnownPathHanTypeface() else null
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
            cjkTypefaceFor(family, fontWeight, italic) ?: android.graphics.Typeface.DEFAULT
        }
        return if (Build.VERSION.SDK_INT >= 28) {
            Typeface.create(base, fontWeight.coerceIn(1, 1000), italic)
        } else {
            val bold = fontWeight >= 600
            val style = when {
                bold && italic -> Typeface.BOLD_ITALIC
                bold -> Typeface.BOLD
                italic -> Typeface.ITALIC
                else -> Typeface.NORMAL
            }
            Typeface.create(base, style)
        }
    }

    private fun cjkTypefaceFor(family: String?, fontWeight: Int, italic: Boolean): Typeface? =
        when (family?.lowercase()) {
            null, "sans", "sans-serif", "sansserif" -> defaultHanTypeface(fontWeight, italic)
            // Android does not expose a role-aware CJK generic resolver; these
            // generics are still honored for gallery typography, then styled.
            "serif" -> Typeface.SERIF
            "monospace", "mono" -> Typeface.MONOSPACE
            else -> Typeface.create(family, Typeface.NORMAL)
        }

    private fun defaultHanTypeface(fontWeight: Int, italic: Boolean): Typeface? {
        if (Build.VERSION.SDK_INT < 31) return wellKnownHanTypeface
        val key = fontWeight.coerceIn(1, 1000) to italic
        synchronized(platformHanTypefaces) {
            if (platformHanTypefaces.containsKey(key)) return platformHanTypefaces[key]
        }
        val probed = platformDefaultHanTypeface(key.first, key.second) ?: wellKnownHanTypeface
        synchronized(platformHanTypefaces) {
            return platformHanTypefaces.getOrPut(key) { probed }
        }
    }

    private fun latinTypefaceFor(family: String?): Typeface =
        when (family?.lowercase()) {
            null, "sans", "sans-serif", "sansserif" -> Typeface.DEFAULT
            "serif" -> Typeface.SERIF
            "monospace", "mono" -> Typeface.MONOSPACE
            else -> Typeface.create(family, Typeface.NORMAL)
        }

    @TargetApi(31)
    private fun platformDefaultHanTypeface(fontWeight: Int, italic: Boolean): Typeface? = runCatching {
        val paint = TextPaint().apply {
            textSize = HAN_PROBE_TEXT_SIZE
            textLocale = Locale.forLanguageTag("zh-Hans")
            typeface = Typeface.create(Typeface.DEFAULT, fontWeight, italic)
        }
        val shaped = TextRunShaper.shapeTextRun(
            HAN_PROBE,
            0,
            HAN_PROBE.length,
            0,
            HAN_PROBE.length,
            0f,
            0f,
            false,
            paint,
        )
        if (shaped.glyphCount() != 1 || shaped.getGlyphId(0) == 0) return@runCatching null
        Typeface.CustomFallbackBuilder(
            android.graphics.fonts.FontFamily.Builder(shaped.getFont(0)).build(),
        )
            .setSystemFallback("sans-serif")
            .build()
    }.getOrNull()

    private fun wellKnownPathHanTypeface(): Typeface? =
        CJK_FONT_FILES.firstNotNullOfOrNull { (path, ttcIndex) ->
            val file = java.io.File(path)
            if (!file.exists()) return@firstNotNullOfOrNull null
            runCatching {
                android.graphics.Typeface.Builder(file)
                    .setTtcIndex(ttcIndex)
                    .build()
            }.getOrNull()
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

        const val HAN_PROBE = "中"
        const val HAN_PROBE_TEXT_SIZE = 32f
    }
}
