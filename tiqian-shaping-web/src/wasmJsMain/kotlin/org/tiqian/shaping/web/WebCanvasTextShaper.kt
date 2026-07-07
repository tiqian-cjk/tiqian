package org.tiqian.shaping.web

import kotlinx.browser.document
import org.tiqian.core.Cluster
import org.tiqian.core.Glyph
import org.tiqian.core.GlyphRun
import org.tiqian.core.Rect
import org.tiqian.core.ShapingDecisionInfo
import org.tiqian.font.FontRole
import org.tiqian.shaping.ShapingInput
import org.tiqian.shaping.ShapingResult
import org.tiqian.shaping.TextShaper
import org.w3c.dom.CanvasRenderingContext2D
import org.w3c.dom.HTMLCanvasElement

/**
 * The CJK and Latin CSS font stacks, supplied by the APPLICATION — Tiqian does
 * not pick fonts. This SAME instance MUST feed both the shaper (measure) and the
 * DOM renderer (draw), or advances won't match the drawn glyphs (measure == draw
 * is the whole point; a mismatch is what made an earlier prototype's dash tofu).
 */
class WebFontFamilies(
    /** CSS `font-family` for CJK text / punctuation / symbols. */
    val cjk: String,
    /** CSS `font-family` for Latin text runs. */
    val latin: String,
) {
    fun forRole(role: FontRole): String = if (role == FontRole.LatinText) latin else cjk

    /** For callers holding only the serialized role name (LayoutResult dumps). */
    fun forRoleName(name: String?): String = if (name == FontRole.LatinText.name) latin else cjk
}

/**
 * `OffscreenMeasureTextShaping` (ADR 0039): the web shaping adapter. It MEASURES
 * with an offscreen 2D canvas — `measureText` for advance, `TextMetrics`
 * ink-box extents for ink bounds — and never rasterizes to screen (that's the
 * DOM renderer's job). The measuring [fonts] MUST be the SAME instance the DOM
 * renderer draws with.
 *
 * Slice 1 scope: plain per-segment advance + ink. `halt` half-width body and
 * Han-context `locl` are unavailable on web canvas (no `fontFeatureSettings`,
 * `ctx.lang` doesn't affect `measureText`), so the engine degrades to
 * policy-derived punctuation geometry exactly as the AWT adapter does (ADR 0014)
 * — a platform limit, not a model change.
 */
class WebCanvasTextShaper(
    private val fonts: WebFontFamilies,
) : TextShaper {

    private val ctx: CanvasRenderingContext2D by lazy {
        val canvas = document.createElement("canvas") as HTMLCanvasElement
        canvas.getContext("2d") as CanvasRenderingContext2D
    }

    override fun shape(input: ShapingInput): ShapingResult {
        val size = input.style.fontSize
        val key = input.fontDecision.candidate.key
        val source = input.text.substring(input.range.start, input.range.end)
        val display = input.displayText

        ctx.font = "${size}px ${fonts.forRole(input.fontDecision.role)}"
        val m = ctx.measureText(display)
        val advance = m.width.toFloat()
        // TextMetrics ink extents are distances from the text ORIGIN: left/ascent
        // point back/up (positive), so negate to get an origin-relative Rect.
        val bounds = Rect(
            left = -m.actualBoundingBoxLeft.toFloat(),
            top = -m.actualBoundingBoxAscent.toFloat(),
            right = m.actualBoundingBoxRight.toFloat(),
            bottom = m.actualBoundingBoxDescent.toFloat(),
        )

        val cluster = Cluster(
            range = input.range,
            text = source,
            displayText = display,
            fontKey = key,
            advance = advance,
        )
        val glyph = Glyph(
            id = 0u,
            clusterRange = input.range,
            advance = advance,
            x = 0f,
            bounds = bounds,
        )
        val run = GlyphRun(range = input.range, fontKey = key, glyphs = listOf(glyph), advance = advance)
        val decision = ShapingDecisionInfo(
            range = input.range,
            sourceText = source,
            displayText = display,
            fontKey = key,
            glyphCount = 1,
            advance = advance,
            source = "OffscreenMeasureTextShaping",
            reason = "web-canvas-measureText",
            glyphsWithoutInkBounds = 0,
        )
        return ShapingResult(listOf(cluster), listOf(run), listOf(decision))
    }
}
