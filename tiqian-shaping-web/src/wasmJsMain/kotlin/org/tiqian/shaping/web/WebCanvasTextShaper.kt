package org.tiqian.shaping.web

import kotlin.JsFun
import kotlin.js.ExperimentalWasmJsInterop
import kotlin.js.JsAny
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
import org.w3c.dom.HTMLElement

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
    private val roleFamilyCache = mutableMapOf<Pair<FontRole, List<String>>, String>()

    fun forRole(role: FontRole, preferredFamilies: List<String> = emptyList()): String {
        val key = role to preferredFamilies
        roleFamilyCache[key]?.let { return it }
        val default = if (role == FontRole.LatinText) latin else cjk
        val resolved = if (preferredFamilies.isEmpty()) {
            default
        } else {
            when (preferredFamilies.singleOrNull()?.lowercase()) {
                "monospace" -> if (role == FontRole.LatinText) latinMonospace else cjk
                "serif" -> if (role == FontRole.LatinText) latinSerif else cjkSerif
                "sans-serif", "sansserif" -> default
                else -> preferredFamilies.joinToString(", ") { it.cssFamilyToken() }
            }
        }
        roleFamilyCache[key] = resolved
        return resolved
    }

    /**
     * Canvas occasionally accepts a webfont as the selected face even when that
     * face intentionally maps an unsupported character to zero advance. DOM text
     * continues through the CSS stack in that case, so measurement must probe the
     * same suffixes instead of hard-coding a family name to exclude.
     */
    fun fallbackStacks(role: FontRole, preferredFamilies: List<String> = emptyList()): List<String> {
        if (preferredFamilies.size <= 1) return listOf(forRole(role, preferredFamilies))
        return preferredFamilies.indices
            .map { index -> preferredFamilies.subList(index, preferredFamilies.size) }
            .map { families -> families.joinToString(", ") { it.cssFamilyToken() } }
            .distinct()
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

/** A CSSOM-resolved HarfBuzz session prepared asynchronously by `@tiqian/prose`. */
data class WebCjkDashCapability(
    val status: String,
    val sessionId: String? = null,
    val detail: String? = null,
)

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
    private val cache = mutableMapOf<FontMetricsRequest, RawFontMetrics>()
    private var currentCanvasFont: String? = null

    private val ctx: CanvasRenderingContext2D by lazy {
        val canvas = document.createElement("canvas") as HTMLCanvasElement
        canvas.getContext("2d") as CanvasRenderingContext2D
    }

    override fun resolve(request: FontMetricsRequest): RawFontMetrics {
        // Canvas selects metrics from the role probe and CSS stack, not from
        // the source cluster. Excluding faceSelectionText keeps the cache at
        // one entry per actual typography instance instead of per ideograph.
        val cacheKey = request.copy(faceSelectionText = "")
        cache[cacheKey]?.let { return it }
        val cjkBox = request.role == FontRole.CjkText || request.role == FontRole.CjkPunctuation
        val probe = if (cjkBox) CJK_METRIC_PROBE_TEXT else LATIN_METRIC_PROBE_TEXT
        for (family in fonts.fallbackStacks(request.role, request.fontFamilies)) {
            val cssStyle = if (request.italic) "italic" else "normal"
            val cssFont = "$cssStyle ${request.fontWeight} ${request.fontSize}px $family"
            if (cssFont != currentCanvasFont) {
                ctx.font = cssFont
                currentCanvasFont = ctx.font
            }
            val m = ctx.measureText(probe)
            if (!m.width.isFinite() || m.width <= ZERO_ADVANCE_EPSILON) continue

            val ascent = m.fontBoundingBoxAscent.toFloatOrNull()
                ?: m.actualBoundingBoxAscent.toFloatOrNull()
                ?: continue
            val descent = m.fontBoundingBoxDescent.toFloatOrNull()
                ?: m.actualBoundingBoxDescent.toFloatOrNull()
                ?: continue
            val ideographicDescent = (-m.ideographicBaseline).toFloatOrNull()
            val result = RawFontMetrics(
                ascent = ascent,
                descent = descent,
                leading = 0f,
                source = FontMetricSource.GlyphSampling,
                typoAscent = if (cjkBox && ideographicDescent != null) {
                    (request.fontSize - ideographicDescent).coerceAtLeast(0f)
                } else {
                    null
                },
                typoDescent = if (cjkBox && ideographicDescent != null) {
                    ideographicDescent.coerceAtLeast(0f)
                } else {
                    null
                },
            )
            cache[cacheKey] = result
            return result
        }
        return fallback.resolve(request).also { cache[cacheKey] = it }
    }

    private fun Double.toFloatOrNull(): Float? =
        if (isFinite() && this > 0.0) toFloat() else null

    private companion object {
        private const val CJK_METRIC_PROBE_TEXT = "中"
        private const val LATIN_METRIC_PROBE_TEXT = "Hg"
        private const val ZERO_ADVANCE_EPSILON = 0.01
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
    private val cjkDashCapability: WebCjkDashCapability? = null,
) : TextShaper {

    private data class MeasuredText(
        val advance: Float,
        val bounds: Rect,
        val requestedFont: String,
        val actualFont: String,
    )

    private data class MeasurementKey(
        val actualFont: String,
        val display: String,
        val featureSignature: String,
    )

    private val measurementCache = mutableMapOf<MeasurementKey, MeasuredText>()
    private var currentCanvasFont: String? = null

    private val ctx: CanvasRenderingContext2D by lazy {
        val canvas = document.createElement("canvas") as HTMLCanvasElement
        canvas.getContext("2d") as CanvasRenderingContext2D
    }

    private val featureMeasureProbe: HTMLElement by lazy {
        (document.createElement("span") as HTMLElement).also { probe ->
            probe.setAttribute("aria-hidden", "true")
            probe.style.apply {
                setProperty("position", "absolute", "important")
                setProperty("left", "-100000px", "important")
                setProperty("top", "0", "important")
                setProperty("visibility", "hidden", "important")
                setProperty("white-space", "pre", "important")
                setProperty("margin", "0", "important")
                setProperty("padding", "0", "important")
                setProperty("border", "0", "important")
            }
            document.body?.appendChild(probe)
        }
    }

    override fun shape(input: ShapingInput): ShapingResult {
        val source = input.text.substring(input.range.start, input.range.end)
        if (source == CJK_DASH_SOURCE || input.displayText == TWO_EM_DASH) {
            return shapePreparedCjkDash(input, source)
                ?: shapeWithCanvas(input, capabilityIssue = dashCapabilityIssue())
        }
        return shapeWithCanvas(input)
    }

    private fun shapePreparedCjkDash(input: ShapingInput, source: String): ShapingResult? {
        val capability = cjkDashCapability ?: return null
        if (capability.status != "conforming") return null
        val sessionId = capability.sessionId ?: return null
        val shaped = preparedCjkDashShape(
            sessionId,
            input.style.fontSize.toDouble(),
            input.style.fontWeight.toDouble(),
            input.style.italic,
        ) ?: return null
        if (dashShapeString(shaped, "status") != "conforming") return null

        val glyphCount = dashShapeGlyphCount(shaped)
        val advance = dashShapeNumber(shaped, "advance").toFloat()
        val display = dashShapeString(shaped, "displayText") ?: return null
        val cssFontFamily = dashShapeString(shaped, "cssFontFamily") ?: return null
        if (glyphCount <= 0 || !advance.isFinite() || advance <= ZERO_ADVANCE_EPSILON) return null
        val glyphs = buildList {
            for (index in 0 until glyphCount) {
                val glyphAdvance = dashShapeGlyphNumber(shaped, index, "advance").toFloat()
                val glyphId = dashShapeGlyphNumber(shaped, index, "id")
                if (!glyphAdvance.isFinite() || glyphAdvance < 0f || !glyphId.isFinite()) return null
                val bounds = if (dashShapeGlyphHasBounds(shaped, index)) {
                    Rect(
                        left = dashShapeGlyphBoundsNumber(shaped, index, "left").toFloat(),
                        top = dashShapeGlyphBoundsNumber(shaped, index, "top").toFloat(),
                        right = dashShapeGlyphBoundsNumber(shaped, index, "right").toFloat(),
                        bottom = dashShapeGlyphBoundsNumber(shaped, index, "bottom").toFloat(),
                    ).takeIf { rect ->
                        rect.left.isFinite() && rect.top.isFinite() &&
                            rect.right.isFinite() && rect.bottom.isFinite()
                    }
                } else {
                    null
                }
                add(
                    Glyph(
                        id = glyphId.toUInt(),
                        clusterRange = input.range,
                        advance = glyphAdvance,
                        x = dashShapeGlyphNumber(shaped, index, "x").toFloat(),
                        y = dashShapeGlyphNumber(shaped, index, "y").toFloat(),
                        renderFontKey = cssFontFamily,
                        bounds = bounds,
                    ),
                )
            }
        }
        val fontKey = input.fontDecision.candidate.key
        val strategy = dashShapeString(shaped, "strategy")
        val face = dashShapeString(shaped, "faceId")
        val loclEvidence = dashShapeString(shaped, "loclEvidence")
        val decision = ShapingDecisionInfo(
            range = input.range,
            sourceText = source,
            displayText = display,
            fontKey = fontKey,
            glyphCount = glyphs.size,
            advance = advance,
            source = "HarfBuzzWebFontData",
            reason = buildString {
                append("HarfBuzzWebFontData")
                append("; strategy=")
                append(strategy)
                append("; face=")
                append(face)
                append("; script=Hani; language=zh-Hans; locl=")
                append(loclEvidence)
                append("; inkCoverage=")
                append(dashShapeNumber(shaped, "inkCoverage"))
                append("; horizontalCenterDelta=")
                append(dashShapeNumber(shaped, "horizontalCenterDelta"))
                append("; verticalCenterDelta=")
                append(dashShapeNumber(shaped, "verticalCenterDelta"))
                append("; seamGap=")
                append(dashShapeNumber(shaped, "seamGap"))
            },
            glyphsWithoutInkBounds = glyphs.count { it.bounds == null },
            missingGlyphs = glyphs.count { it.id == 0u },
            resolvedFace = face,
            script = dashShapeString(shaped, "script"),
            language = dashShapeString(shaped, "language"),
            strategy = strategy,
            featureEvidence = loclEvidence,
        )
        return ShapingResult(
            clusters = listOf(
                Cluster(
                    range = input.range,
                    text = source,
                    displayText = display,
                    fontKey = fontKey,
                    advance = advance,
                ),
            ),
            glyphRuns = listOf(
                GlyphRun(
                    range = input.range,
                    fontKey = fontKey,
                    glyphs = glyphs,
                    advance = advance,
                ),
            ),
            decisions = listOf(decision),
        )
    }

    private fun dashCapabilityIssue(): Pair<String, String> {
        val capability = cjkDashCapability
        return "NoConformingCjkDashGlyph" to when {
            capability == null -> "CjkDashFontShapingNotPrepared"
            capability.detail.isNullOrBlank() -> "status=${capability.status}"
            else -> "status=${capability.status}; ${capability.detail}"
        }
    }

    private fun shapeWithCanvas(
        input: ShapingInput,
        capabilityIssue: Pair<String, String>? = null,
    ): ShapingResult {
        val size = input.style.fontSize
        val key = input.fontDecision.candidate.key
        val source = input.text.substring(input.range.start, input.range.end)
        val display = input.displayText

        val style = if (input.style.italic) "italic" else "normal"
        val stacks = fonts.fallbackStacks(input.fontDecision.role, input.style.fontFamilies)
        val openTypeFeatures = contextualWebOpenTypeFeatures(
            role = input.fontDecision.role,
            display = display,
        )
        var chosenIndex = 0
        val requiresAdvance = display.isNotEmpty() && display.none { it == '\n' || it == '\r' }
        var measured = measure(
            display,
            "$style ${input.style.fontWeight} ${size}px ${stacks.first()}",
            openTypeFeatures,
        )
        if (requiresAdvance && !measured.hasUsableAdvance()) {
            for (index in 1 until stacks.size) {
                val candidate = measure(
                    display,
                    "$style ${input.style.fontWeight} ${size}px ${stacks[index]}",
                    openTypeFeatures,
                )
                measured = candidate
                chosenIndex = index
                if (candidate.hasUsableAdvance()) break
            }
        }
        val advance = measured.advance
        val bounds = measured.bounds

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
        val run = GlyphRun(
            range = input.range,
            fontKey = key,
            glyphs = listOf(glyph),
            advance = advance,
            openTypeFeatures = openTypeFeatures,
        )
        val decision = ShapingDecisionInfo(
            range = input.range,
            sourceText = source,
            displayText = display,
            fontKey = key,
            glyphCount = 1,
            advance = advance,
            source = "OffscreenMeasureTextShaping",
            reason = buildString {
                append("web-canvas-measureText")
                append("; stackIndex=")
                append(chosenIndex)
                append("; requestedFont=")
                append(measured.requestedFont)
                append("; actualFont=")
                append(measured.actualFont)
                if (openTypeFeatures.isNotEmpty()) {
                    append("; features=")
                    append(openTypeFeatures.joinToString(","))
                    append("; featureMeasure=HiddenDomRange")
                }
                capabilityIssue?.let { (_, detail) ->
                    append("; ")
                    append(detail)
                }
            },
            glyphsWithoutInkBounds = 0,
            capabilityIssue = capabilityIssue?.first,
            featureEvidence = openTypeFeatures.takeIf { it.isNotEmpty() }?.joinToString(","),
        )
        return ShapingResult(listOf(cluster), listOf(run), listOf(decision))
    }

    private fun measure(
        display: String,
        cssFont: String,
        openTypeFeatures: List<String> = emptyList(),
    ): MeasuredText {
        if (cssFont != currentCanvasFont) {
            ctx.font = cssFont
            currentCanvasFont = ctx.font
        }
        val actualFont = ctx.font
        val featureSignature = openTypeFeatures.joinToString(",")
        return measurementCache.getOrPut(MeasurementKey(actualFont, display, featureSignature)) {
            val m = ctx.measureText(display)
            val advance = if (featureSignature == PROPORTIONAL_CURLY_QUOTE_FEATURE_SIGNATURE) {
                measureProportionalCurlyQuote(display, cssFont)
            } else {
                m.width
            }
            MeasuredText(
                advance = advance.toFloat(),
                bounds = Rect(
                    left = -m.actualBoundingBoxLeft.toFloat(),
                    top = -m.actualBoundingBoxAscent.toFloat(),
                    right = m.actualBoundingBoxRight.toFloat(),
                    bottom = m.actualBoundingBoxDescent.toFloat(),
                ),
                requestedFont = cssFont,
                actualFont = actualFont,
            )
        }
    }

    private fun measureProportionalCurlyQuote(display: String, cssFont: String): Double {
        val probe = featureMeasureProbe
        if (probe.parentNode == null) document.body?.appendChild(probe)
        probe.textContent = display
        probe.style.apply {
            setProperty("font", cssFont, "important")
            setProperty("font-variant-east-asian", "proportional-width", "important")
            setProperty("font-feature-settings", "\"palt\" 1", "important")
        }
        return probe.getBoundingClientRect().width
    }

    private fun MeasuredText.hasUsableAdvance(): Boolean =
        advance.isFinite() && advance > ZERO_ADVANCE_EPSILON

    private companion object {
        private const val CJK_DASH_SOURCE = "——"
        private const val TWO_EM_DASH = "⸺"
        private const val ZERO_ADVANCE_EPSILON = 0.01f
        private const val PROPORTIONAL_CURLY_QUOTE_FEATURE_SIGNATURE = "pwid,palt"
    }
}

/**
 * ContextualWebCurlyQuoteFeatures: the common classifier has already resolved
 * whether a shared curly quote belongs to Latin or CJK context. The browser
 * adapter requests proportional forms only for the Latin decision and reports
 * that feature list in GlyphRun so DOM paint can replay the same measurement.
 */
private fun contextualWebOpenTypeFeatures(role: FontRole, display: String): List<String> =
    if (role == FontRole.LatinText && display.any { it in '\u2018'..'\u201D' }) {
        listOf("pwid", "palt")
    } else {
        emptyList()
    }

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(sessionId, fontSize, fontWeight, italic) => globalThis.__TiqianWebFontShaping?.shapeCjkDash?.(sessionId, fontSize, fontWeight, italic) ?? null")
private external fun preparedCjkDashShape(
    sessionId: String,
    fontSize: Double,
    fontWeight: Double,
    italic: Boolean,
): JsAny?

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(value, name) => value?.[name] == null ? null : String(value[name])")
private external fun dashShapeString(value: JsAny, name: String): String?

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(value, name) => { const number = Number(value?.[name]); return Number.isFinite(number) ? number : NaN; }")
private external fun dashShapeNumber(value: JsAny, name: String): Double

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(value) => Array.isArray(value?.glyphs) ? value.glyphs.length : 0")
private external fun dashShapeGlyphCount(value: JsAny): Int

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(value, index, name) => { const number = Number(value?.glyphs?.[index]?.[name]); return Number.isFinite(number) ? number : NaN; }")
private external fun dashShapeGlyphNumber(value: JsAny, index: Int, name: String): Double

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(value, index) => value?.glyphs?.[index]?.bounds != null")
private external fun dashShapeGlyphHasBounds(value: JsAny, index: Int): Boolean

@OptIn(ExperimentalWasmJsInterop::class)
@JsFun("(value, index, name) => { const number = Number(value?.glyphs?.[index]?.bounds?.[name]); return Number.isFinite(number) ? number : NaN; }")
private external fun dashShapeGlyphBoundsNumber(value: JsAny, index: Int, name: String): Double
