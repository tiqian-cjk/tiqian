package org.tiqian.font

import kotlin.test.Test
import kotlin.test.assertEquals

class ScriptAwareFontMetricsNormalizerTest {
    private val resolver = StubFontMetricsResolver()
    private val normalizer = ScriptAwareFontMetricsNormalizer()

    @Test
    fun cjkTextUsesFontDeclaredTypoBoxInsteadOfSynthesizedSquare() {
        val request = FontMetricsRequest(
            fontKey = "cjk-primary",
            fontSize = 16f,
            role = FontRole.CjkText,
            locale = "zh-Hans",
        )
        val raw = resolver.resolve(request)
        val layout = normalizer.normalize(FontMetricsNormalizationInput(request, raw))

        // ADR 0002 amendment: lay the box on the font's OS/2 sTypo (0.88/0.12),
        // not the inflated hhea box and not a synthesized 0.5/0.5 square.
        assertEquals(14.08f, raw.typoAscent)
        assertEquals(1.92f, raw.typoDescent)
        assertEquals(14.08f, layout.ascent)
        assertEquals(1.92f, layout.descent)
        assertEquals(BaselineClass.IdeographicLow, layout.baselineClass)
        assertEquals(MetricBox.IdeographicEmBox, layout.metricBox)
        assertEquals(FontMetricSource.RawTables, layout.source)
    }

    @Test
    fun cjkTextFallsBackToHheaWhenFontHasNoTypoMetrics() {
        val request = FontMetricsRequest(
            fontKey = "cjk-bad",
            fontSize = 16f,
            role = FontRole.CjkText,
            locale = "zh-Hans",
        )
        val raw = RawFontMetrics(ascent = 18.4f, descent = 4f)
        val layout = normalizer.normalize(FontMetricsNormalizationInput(request, raw))

        assertEquals(18.4f, layout.ascent)
        assertEquals(4f, layout.descent)
        assertEquals(FontMetricsPolicy.Raw, layout.policy)
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

