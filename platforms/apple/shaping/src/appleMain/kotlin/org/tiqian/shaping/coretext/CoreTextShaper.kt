package org.tiqian.shaping.coretext

import kotlinx.cinterop.allocArray
import kotlinx.cinterop.convert
import kotlinx.cinterop.get
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.reinterpret
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
import platform.CoreFoundation.CFArrayGetCount
import platform.CoreFoundation.CFArrayGetValueAtIndex
import platform.CoreGraphics.CGGlyphVar
import platform.CoreGraphics.CGPoint
import platform.CoreGraphics.CGRect
import platform.CoreText.CTFontGetBoundingRectsForGlyphs
import platform.CoreText.CTFontRef
import platform.CoreText.CTLineGetGlyphRuns
import platform.CoreText.CTLineGetTypographicBounds
import platform.CoreText.CTRunGetGlyphCount
import platform.CoreText.CTRunGetGlyphs
import platform.CoreText.CTRunGetPositions
import platform.CoreText.CTRunRef
import platform.CoreText.kCTFontOrientationHorizontal

const val CORE_TEXT_OPEN_TYPE_FEATURE_UNAVAILABLE: String = "CoreTextOpenTypeFeatureUnavailable"

/**
 * Core Text shaping adapter (Apple / Kotlin-Native), the Native peer of `SkiaTextShaper`
 * / `AwtTextShaper` (ADR 0013/0015). Same contract: consume the layout-decided
 * [ShapingInput.displayText] with a single resolved font, emit one cluster + one glyph run
 * with real advances and glyph-local ink bounds. No fallback, no CLREQ substitution, no
 * punctuation decisions — those stay upstream. `measure == draw` (AGENTS.md #5): the
 * Core Text frontend replays these glyph ids against the same cached CTFont.
 *
 * Font resolution + the CF helpers live in [CoreTextSupport] (shared with the metrics
 * resolver and the renderer). Fonts are borrowed from its cache — never CFRelease'd here.
 *
 * Shaping goes through the ONE shared line entry ([CoreTextSupport.line]) the renderer replays
 * with, so measure and draw resolve to the same cached `CTLine` — including the paragraph
 * **language** ([ShapingInput.style] locale) and explicit OpenType features such as `fwid=1`.
 */
class CoreTextShaper(
    private val cjkFamily: String = CoreTextSupport.DEFAULT_CJK_FAMILY,
    private val latinFamily: String = CoreTextSupport.DEFAULT_LATIN_FAMILY,
) : TextShaper {

    override fun shape(input: ShapingInput): ShapingResult {
        val sourceText = input.text.substring(input.range.start, input.range.end)
        val displayText = input.displayText
        val fontKey = input.fontDecision.candidate.key

        val family = input.style.fontFamilies.firstOrNull()
            ?: input.fontDecision.candidate.family.takeUnless { it == fontKey }
            ?: if (input.fontDecision.role.usesLatinFace()) latinFamily else cjkFamily

        // Borrowed from the shared cache — do NOT CFRelease. Honour the per-span weight/italic
        // (rich text, ADR 0030) so bold/oblique runs are MEASURED with the face they'll draw with.
        val font = CoreTextSupport.font(family, input.style.fontSize.toDouble(), input.style.fontWeight, input.style.italic)
            ?: return degenerate(input, sourceText, displayText, fontKey, fontMissing = true)
        if (displayText.isEmpty()) {
            return degenerate(input, sourceText, displayText, fontKey, fontMissing = false)
        }

        val canonicalFeatures = CoreTextSupport.canonicalOpenTypeFeatures(input.openTypeFeatures)
        var capabilityIssue = if (canonicalFeatures == null) CORE_TEXT_OPEN_TYPE_FEATURE_UNAVAILABLE else null
        var appliedFeatures = canonicalFeatures.orEmpty()
        var shaped = shapeLine(displayText, font, input.style.locale, appliedFeatures)
        if (shaped == null && appliedFeatures.isNotEmpty()) {
            // A requested feature that Core Text cannot instantiate is an explicit capability
            // degrade. Shape without it only after recording the issue, and make the GlyphRun carry
            // the actually-applied feature set so the renderer replays exactly this fallback.
            capabilityIssue = CORE_TEXT_OPEN_TYPE_FEATURE_UNAVAILABLE
            appliedFeatures = emptyList()
            shaped = shapeLine(displayText, font, input.style.locale, appliedFeatures)
        }
        shaped ?: return degenerate(
            input = input,
            sourceText = sourceText,
            displayText = displayText,
            fontKey = fontKey,
            fontMissing = true,
            openTypeFeatures = appliedFeatures,
            capabilityIssue = capabilityIssue,
        )
        val advance = shaped.advance
        val count = shaped.glyphIds.size
        val cluster = Cluster(
            range = input.range,
            text = sourceText,
            displayText = displayText,
            fontKey = fontKey,
            advance = advance,
        )
        val glyphs = (0 until count).map { i ->
            val startX = shaped.xs[i]
            val endX = if (i + 1 < count) shaped.xs[i + 1] else advance
            Glyph(
                id = shaped.glyphIds[i],
                clusterRange = input.range,
                advance = if (shaped.verticalForms) {
                    advance / count
                } else {
                    (endX - startX).coerceAtLeast(0f)
                },
                x = startX,
                y = shaped.ys[i],
                bounds = shaped.bounds[i],
            )
        }
        val run = GlyphRun(
            range = input.range,
            fontKey = fontKey,
            glyphs = glyphs,
            advance = advance,
            openTypeFeatures = appliedFeatures,
        )
        val decision = ShapingDecisionInfo(
            range = input.range,
            sourceText = sourceText,
            displayText = displayText,
            fontKey = fontKey,
            glyphCount = count,
            advance = advance,
            source = ShapingSource.CoreText.name,
            reason = "CoreTextShaper:$family",
            glyphsWithoutInkBounds = glyphs.count { it.bounds == null },
            missingGlyphs = shaped.glyphIds.count { it == 0 },
            language = input.style.locale,
            featureEvidence = appliedFeatures.takeIf { it.isNotEmpty() }
                ?.let { "CoreTextFontDescriptor:${it.joinToString(",")}" },
            capabilityIssue = capabilityIssue,
        )
        return ShapingResult(listOf(cluster), listOf(run), listOf(decision))
    }

    private class Shaped(
        val glyphIds: List<Int>,
        val xs: List<Float>,
        val ys: List<Float>,
        val bounds: List<Rect?>,
        val advance: Float,
        val verticalForms: Boolean,
    )

    /**
     * Measure [displayText] via the SHARED cached line entry ([CoreTextSupport.line]) — the SAME call
     * the renderer replays with — passing [language] so `locl` glyph selection is applied identically
     * on both sides. Because measure and draw resolve to the very same cached `CTLine`, `measure ==
     * draw` (AGENTS.md #5) is guaranteed, not merely coincidental. The line is borrowed — NOT released.
     */
    private fun shapeLine(
        displayText: String,
        font: CTFontRef,
        language: String?,
        openTypeFeatures: List<String>,
    ): Shaped? {
        val verticalForms = openTypeFeatures.contains("vert=1")
        val line = CoreTextSupport.line(
            text = displayText,
            font = font,
            vertical = verticalForms,
            language = language,
            openTypeFeatures = openTypeFeatures,
        ) ?: return null
        val advance = CTLineGetTypographicBounds(line, null, null, null).toFloat()
        val glyphIds = mutableListOf<Int>()
        val xs = mutableListOf<Float>()
        val ys = mutableListOf<Float>()
        val bounds = mutableListOf<Rect?>()
        val runs = CTLineGetGlyphRuns(line)
        val runCount = if (runs != null) CFArrayGetCount(runs).toInt() else 0
        for (r in 0 until runCount) {
            val run: CTRunRef = CFArrayGetValueAtIndex(runs, r.convert())!!.reinterpret()
            collectRun(run, font, glyphIds, xs, ys, bounds)
        }
        return Shaped(glyphIds, xs, ys, bounds, advance, verticalForms)
    }

    private fun collectRun(
        run: CTRunRef,
        fallbackFont: CTFontRef,
        glyphIds: MutableList<Int>,
        xs: MutableList<Float>,
        ys: MutableList<Float>,
        bounds: MutableList<Rect?>,
    ) {
        val gcount = CTRunGetGlyphCount(run).toInt()
        if (gcount <= 0) return
        val runFont: CTFontRef = CoreTextSupport.runFontOf(run) ?: fallbackFont
        memScoped {
            val gbuf = allocArray<CGGlyphVar>(gcount)
            val pbuf = allocArray<CGPoint>(gcount)
            val rbuf = allocArray<CGRect>(gcount)
            CTRunGetGlyphs(run, CoreTextSupport.cfRange(0, 0), gbuf)
            CTRunGetPositions(run, CoreTextSupport.cfRange(0, 0), pbuf)
            CTFontGetBoundingRectsForGlyphs(runFont, kCTFontOrientationHorizontal, gbuf, rbuf, gcount.convert())
            for (i in 0 until gcount) {
                glyphIds += gbuf[i].toInt()
                xs += pbuf[i].x.toFloat()
                ys += -pbuf[i].y.toFloat()
                bounds += rbuf[i].toGlyphLocalRect()
            }
        }
    }

    /** CG bounding rect (+y up, baseline-relative) → core Rect (+y down, top negative above baseline). */
    private fun CGRect.toGlyphLocalRect(): Rect? {
        val w = size.width
        val h = size.height
        if (w <= 0.0 || h <= 0.0) return null
        val bottomUp = origin.y
        return Rect(
            left = origin.x.toFloat(),
            top = (-(bottomUp + h)).toFloat(),
            right = (origin.x + w).toFloat(),
            bottom = (-bottomUp).toFloat(),
        )
    }

    private fun degenerate(
        input: ShapingInput,
        sourceText: String,
        displayText: String,
        fontKey: String,
        fontMissing: Boolean,
        openTypeFeatures: List<String> = emptyList(),
        capabilityIssue: String? = null,
    ): ShapingResult {
        val cluster = Cluster(
            range = input.range,
            text = sourceText,
            fontKey = fontKey,
            advance = 0f,
            displayText = displayText,
        )
        val run = GlyphRun(input.range, fontKey, emptyList(), 0f, openTypeFeatures)
        val decision = ShapingDecisionInfo(
            range = input.range,
            sourceText = sourceText,
            displayText = displayText,
            fontKey = fontKey,
            glyphCount = 0,
            advance = 0f,
            source = ShapingSource.CoreText.name,
            reason = if (fontMissing) "CoreTextShaper:font-unavailable" else "CoreTextShaper:empty",
            language = input.style.locale,
            capabilityIssue = capabilityIssue,
        )
        return ShapingResult(listOf(cluster), listOf(run), listOf(decision))
    }
}
