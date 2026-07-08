package org.tiqian.shaping.web

import kotlin.js.ExperimentalWasmJsInterop
import kotlinx.browser.document
import org.tiqian.core.Cluster
import org.tiqian.core.Glyph
import org.tiqian.core.GlyphRun
import org.tiqian.core.Rect
import org.tiqian.core.ShapingDecisionInfo
import org.tiqian.font.FontMetricSource
import org.tiqian.font.FontMetricsRequest
import org.tiqian.font.FontMetricsResolver
import org.tiqian.font.FontRole
import org.tiqian.font.RawFontMetrics
import org.tiqian.font.StubFontMetricsResolver
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
    /** CSS `font-family` for generic Latin monospace spans such as inline code. */
    val latinMonospace: String = "\"SFMono-Regular\", Menlo, Consolas, \"Liberation Mono\", monospace",
    /** CSS `font-family` for generic CJK serif spans. */
    val cjkSerif: String = "\"Songti SC\", \"Noto Serif CJK SC\", serif",
    /** CSS `font-family` for generic Latin serif spans. */
    val latinSerif: String = "Georgia, \"Times New Roman\", serif",
    /**
     * CSS `font-family` for 注音 (ADR 0033): prefer Traditional Chinese system
     * faces, because they expose the full-size vertical U+02CA/02C7/02CB/02D9 tone
     * forms through the browser's vertical text path. Dedicated Bopomofo fonts stay
     * after TC sans faces: many machines do not ship them, and their metrics are not
     * the fallback profile the web renderer mirrors.
     */
    val bopomofo: String = BOPOMOFO_FALLBACK_FAMILIES.joinToString(", ") { it.cssFamilyToken() },
) {
    fun forRole(role: FontRole, preferredFamilies: List<String> = emptyList()): String {
        val default = if (role == FontRole.LatinText) latin else cjk
        return when (preferredFamilies.firstOrNull()) {
            "monospace" -> if (role == FontRole.LatinText) latinMonospace else cjk
            "serif" -> if (role == FontRole.LatinText) latinSerif else cjkSerif
            "sans-serif", "sansserif" -> default
            else -> default
        }
    }

    /** Ruby defaults to the application-provided Latin stack; explicit families override it. */
    fun forRuby(preferredFamilies: List<String> = emptyList()): String =
        forRole(FontRole.LatinText, preferredFamilies)

    /** 注音 face — explicit RubySpan families first, then the 注音-capable [bopomofo] stack. */
    fun forBopomofo(preferredFamilies: List<String> = emptyList()): String =
        if (preferredFamilies.isEmpty()) {
            bopomofo
        } else {
            preferredFamilies.joinToString(", ") { it.cssFamilyToken() } + ", $bopomofo"
        }

    /** For callers holding only the serialized role name (LayoutResult dumps). */
    fun forRoleName(name: String?, preferredFamilies: List<String> = emptyList()): String {
        val role = if (name == FontRole.LatinText.name) FontRole.LatinText else FontRole.CjkText
        return forRole(role, preferredFamilies)
    }

}

private val BOPOMOFO_FALLBACK_FAMILIES = listOf(
    // Traditional Chinese system sans first: they carry the vertical tone glyphs.
    "PingFang TC",
    "Hiragino Sans CNS",
    "Heiti TC",
    "Microsoft JhengHei UI",
    "Microsoft JhengHei",
    "Noto Sans CJK TC",
    "Source Han Sans TC",
    // Dedicated 注音 fonts remain valid explicit fallbacks, but are not the default
    // metric profile used by the web renderer.
    "Noto Sans Bopomofo",
    "Noto Serif Bopomofo",
    "BpmfGenYoGothic",
    "BpmfGenSenRounded",
    // Ming/Song fallbacks still usually have correct 注音 marks.
    "Apple LiGothic",
    "Apple LiSung",
    "PMingLiU",
    "MingLiU",
    "Noto Serif CJK TC",
    "Source Han Serif TC",
    "sans-serif",
)

private fun String.cssFamilyToken(): String = when (lowercase()) {
    "serif", "sans-serif", "sansserif", "monospace", "cursive", "fantasy", "system-ui" -> this
    else -> if (startsWith("\"") || startsWith("'")) this else "\"$this\""
}

/**
 * Web font metrics paired with [WebCanvasTextShaper].
 *
 * Canvas exposes the browser's actual font box. For CJK roles we derive Tiqian's
 * 字身框 from `ideographicBaseline` when available; for ruby/Latin, the font
 * descent is the edge aligned to the base 字身框 top (ADR 0032). Missing browser
 * metrics fall back to the common stub rather than inventing another constant.
 */
@OptIn(ExperimentalWasmJsInterop::class)
class WebCanvasFontMetricsResolver(
    private val fonts: WebFontFamilies,
) : FontMetricsResolver {

    private val fallback = StubFontMetricsResolver()

    private val ctx: CanvasRenderingContext2D by lazy {
        val canvas = document.createElement("canvas") as HTMLCanvasElement
        canvas.getContext("2d") as CanvasRenderingContext2D
    }

    override fun resolve(request: FontMetricsRequest): RawFontMetrics {
        ctx.font = "normal 400 ${request.fontSize}px " + fonts.forRole(request.role, request.fontFamilies)
        val cjkBox = request.role == FontRole.CjkText || request.role == FontRole.CjkPunctuation
        val m = ctx.measureText(if (cjkBox) CJK_METRIC_PROBE_TEXT else LATIN_METRIC_PROBE_TEXT)

        val ascent = m.fontBoundingBoxAscent.toFloatOrNull()
            ?: m.actualBoundingBoxAscent.toFloatOrNull()
            ?: return fallback.resolve(request)
        val descent = m.fontBoundingBoxDescent.toFloatOrNull()
            ?: m.actualBoundingBoxDescent.toFloatOrNull()
            ?: return fallback.resolve(request)

        val ideographicDescent = (-m.ideographicBaseline).toFloatOrNull()
        val typoAscent = if (cjkBox && ideographicDescent != null) {
            (request.fontSize - ideographicDescent).coerceAtLeast(0f)
        } else {
            null
        }
        val typoDescent = if (cjkBox && ideographicDescent != null) {
            ideographicDescent.coerceAtLeast(0f)
        } else {
            null
        }

        return RawFontMetrics(
            ascent = ascent,
            descent = descent,
            leading = 0f,
            source = FontMetricSource.GlyphSampling,
            typoAscent = typoAscent,
            typoDescent = typoDescent,
        )
    }

    private fun Double.toFloatOrNull(): Float? =
        if (isFinite() && this > 0.0) toFloat() else null

    private companion object {
        private const val CJK_METRIC_PROBE_TEXT = "中"
        private const val LATIN_METRIC_PROBE_TEXT = "Hg"
    }
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
@OptIn(ExperimentalWasmJsInterop::class)
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

        val style = if (input.style.italic) "italic" else "normal"
        ctx.font = "$style ${input.style.fontWeight} ${size}px " +
            fonts.forRole(input.fontDecision.role, input.style.fontFamilies)
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
