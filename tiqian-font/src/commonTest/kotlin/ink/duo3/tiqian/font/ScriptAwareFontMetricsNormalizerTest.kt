package ink.duo3.tiqian.font

import kotlin.test.Test
import kotlin.test.assertEquals

class ScriptAwareFontMetricsNormalizerTest {
    private val resolver = StubFontMetricsResolver()
    private val normalizer = ScriptAwareFontMetricsNormalizer()

    @Test
    fun cjkTextUsesIdeographicCenteredMetricsInsteadOfInflatedRawMetrics() {
        val request = FontMetricsRequest(
            fontKey = "cjk-primary",
            fontSize = 16f,
            role = FontRole.CjkText,
            locale = "zh-Hans",
        )
        val raw = resolver.resolve(request)
        val layout = normalizer.normalize(FontMetricsNormalizationInput(request, raw))

        assertEquals(18.4f, raw.ascent)
        assertEquals(4f, raw.descent)
        assertEquals(8f, layout.ascent)
        assertEquals(8f, layout.descent)
        assertEquals(BaselineClass.IdeographicCentered, layout.baselineClass)
        assertEquals(MetricBox.IdeographicEmBox, layout.metricBox)
        assertEquals(FontMetricSource.SynthesizedIdeographicBox, layout.source)
    }

    @Test
    fun latinTextKeepsRomanRawMetrics() {
        val request = FontMetricsRequest(
            fontKey = "latin-primary",
            fontSize = 16f,
            role = FontRole.LatinText,
            locale = "en",
        )
        val raw = resolver.resolve(request)
        val layout = normalizer.normalize(FontMetricsNormalizationInput(request, raw))

        assertEquals(raw.ascent, layout.ascent)
        assertEquals(raw.descent, layout.descent)
        assertEquals(BaselineClass.Roman, layout.baselineClass)
        assertEquals(MetricBox.RawFontBox, layout.metricBox)
    }
}

