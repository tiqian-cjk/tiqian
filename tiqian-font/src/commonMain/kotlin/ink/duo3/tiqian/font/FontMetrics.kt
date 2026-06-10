package ink.duo3.tiqian.font

data class FontMetricsRequest(
    val fontKey: String,
    val fontSize: Float,
    val role: FontRole,
    val locale: String,
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
                ascent = request.fontSize * 1.15f,
                descent = request.fontSize * 0.25f,
                leading = 0f,
                source = FontMetricSource.RawTables,
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
            -> LayoutFontMetrics(
                ascent = request.fontSize * 0.5f,
                descent = request.fontSize * 0.5f,
                baselineOffset = 0f,
                policy = FontMetricsPolicy.IdeographicBox,
                baselinePolicy = BaselinePolicy.CenteredCjkVisual,
                baselineClass = BaselineClass.IdeographicCentered,
                metricBox = MetricBox.IdeographicEmBox,
                source = FontMetricSource.SynthesizedIdeographicBox,
                reason = "ScriptAwareFontMetricsNormalizer:${request.role}:ideographic-centered",
            )

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

