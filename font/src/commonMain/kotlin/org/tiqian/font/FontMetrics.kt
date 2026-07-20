package org.tiqian.font

data class FontMetricsRequest(
    val fontKey: String,
    val fontSize: Float,
    val role: FontRole,
    val locale: String,
    /**
     * Per-span font family preference (rich text). The resolver measures THIS family's
     * 字身框 so a serif/mono run aligns by its own ideographic box, not the base font's.
     * Empty = the role default.
     */
    val fontFamilies: List<String> = emptyList(),
    /** The exact OpenType weight instance whose declared metrics are requested. */
    val fontWeight: Int = 400,
    /** Whether the italic/oblique face instance, rather than the upright face, is requested. */
    val italic: Boolean = false,
    /**
     * Source text used only to resolve which concrete face in [fontFamilies]
     * owns this metric decision. Metrics remain face-level; the text is part of
     * the fallback-selection evidence, not a glyph-bounds sample.
     */
    val faceSelectionText: String = "",
)

interface FontMetricsResolver {
    fun resolve(request: FontMetricsRequest): RawFontMetrics
}

class StubFontMetricsResolver : FontMetricsResolver {
    override fun resolve(request: FontMetricsRequest): RawFontMetrics =
        when (request.role) {
            FontRole.CjkText,
            FontRole.CjkPunctuation,
            -> RawFontMetrics(
                // hhea-style inflated box (kept for the no-OS/2 fallback path);
                // typo* is the font-declared ideographic em the layout uses.
                // Mirrors Source Han Sans CN (see FontProvidedMetricsProbe).
                ascent = request.fontSize * 1.16f,
                descent = request.fontSize * 0.288f,
                leading = 0f,
                source = FontMetricSource.RawTables,
                typoAscent = request.fontSize * 0.88f,
                typoDescent = request.fontSize * 0.12f,
            )

            FontRole.LatinText -> RawFontMetrics(
                ascent = request.fontSize * 0.8f,
                descent = request.fontSize * 0.2f,
                leading = 0f,
                source = FontMetricSource.RawTables,
            )

            FontRole.Symbol,
            FontRole.Emoji,
            FontRole.Unknown,
            -> RawFontMetrics(
                ascent = request.fontSize * 0.9f,
                descent = request.fontSize * 0.25f,
                leading = 0f,
                source = FontMetricSource.RawTables,
            )
        }
}

data class FontMetricsNormalizationInput(
    val request: FontMetricsRequest,
    val rawMetrics: RawFontMetrics,
)

interface FontMetricsNormalizer {
    fun normalize(input: FontMetricsNormalizationInput): LayoutFontMetrics
}

class ScriptAwareFontMetricsNormalizer : FontMetricsNormalizer {
    override fun normalize(input: FontMetricsNormalizationInput): LayoutFontMetrics {
        val request = input.request
        return when (request.role) {
            FontRole.CjkText,
            FontRole.CjkPunctuation,
            -> {
                // ADR 0002 amendment: the CJK line box is the font's DECLARED
                // ideographic em (OS/2 sTypo), on the real baseline — not a
                // synthesized symmetric square centred on a fake baseline. When
                // the font lacks OS/2 typo metrics, fall back to the (inflated)
                // hhea box rather than inventing one; ink sampling is a separate
                // bad-font fallback, not this path.
                val typo = input.rawMetrics.typoAscent != null && input.rawMetrics.typoDescent != null
                LayoutFontMetrics(
                    ascent = input.rawMetrics.typoAscent ?: input.rawMetrics.ascent,
                    descent = input.rawMetrics.typoDescent ?: input.rawMetrics.descent,
                    baselineOffset = 0f,
                    policy = if (typo) FontMetricsPolicy.IdeographicBox else FontMetricsPolicy.Raw,
                    baselinePolicy = BaselinePolicy.Ideographic,
                    baselineClass = BaselineClass.IdeographicLow,
                    metricBox = MetricBox.IdeographicEmBox,
                    source = input.rawMetrics.source,
                    reason = "ScriptAwareFontMetricsNormalizer:${request.role}:" +
                        if (typo) "font-typo-box" else "hhea-fallback-no-os2",
                )
            }

            FontRole.LatinText -> LayoutFontMetrics(
                ascent = input.rawMetrics.ascent,
                descent = input.rawMetrics.descent,
                baselineOffset = 0f,
                policy = FontMetricsPolicy.Raw,
                baselinePolicy = BaselinePolicy.Alphabetic,
                baselineClass = BaselineClass.Roman,
                metricBox = MetricBox.RawFontBox,
                source = input.rawMetrics.source,
                reason = "ScriptAwareFontMetricsNormalizer:${request.role}:roman-raw",
            )

            FontRole.Symbol,
            FontRole.Emoji,
            FontRole.Unknown,
            -> LayoutFontMetrics(
                ascent = input.rawMetrics.ascent,
                descent = input.rawMetrics.descent,
                baselineOffset = 0f,
                policy = FontMetricsPolicy.Raw,
                baselinePolicy = BaselinePolicy.Alphabetic,
                baselineClass = BaselineClass.Roman,
                metricBox = MetricBox.RawFontBox,
                source = input.rawMetrics.source,
                reason = "ScriptAwareFontMetricsNormalizer:${request.role}:fallback-raw",
            )
        }
    }
}

enum class BaselineClass {
    Roman,
    IdeographicCentered,
    IdeographicLow,
    Math,
    Hanging,
}

enum class MetricBox {
    RawFontBox,
    IdeographicEmBox,
    IdeographicCharacterFace,
    SampledInkBox,
}

enum class FontMetricSource {
    RawTables,
    OpenTypeBase,
    GlyphSampling,
    ManualOverride,
    SynthesizedIdeographicBox,
}
