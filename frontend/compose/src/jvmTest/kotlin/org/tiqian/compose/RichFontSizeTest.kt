package org.tiqian.compose

import org.tiqian.clreq.ClreqProfile
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.TextRange
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.shaping.skia.SkiaFontMetricsResolver
import org.tiqian.shaping.skia.SkiaTextShaper
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Rich-text per-span 字号 (ADR 0030 B 档): a sized span SHAPES and is MEASURED at
 * its own size — the cluster advance scales and the line grows taller, both
 * driven through the real Skia shaper/metrics (not a render-only trick).
 */
class RichFontSizeTest {

    private val measurer = ParagraphMeasurer(
        ExplainableStubParagraphLayoutEngine(
            lineBreaker = LookaheadLineBreaker(),
            textShaper = SkiaTextShaper(),
            fontMetricsResolver = SkiaFontMetricsResolver(),
            clreqProfileResolver = { ClreqProfile.MainlandHorizontal },
        ),
    )

    @Test
    fun sizedSpanScalesAdvanceAndLineHeight() {
        val constraints = LayoutConstraints(maxWidth = 4000f)
        val base = measurer.measure("汉字测试", constraints, TextStyle(fontSize = 20f))
        val sized = measurer.measure(
            "汉字测试",
            constraints,
            TextStyle(fontSize = 20f),
            spans = listOf(TextSpan(TextRange(2, 4), TextStyle(fontSize = 40f))), // 测试 at 2×
        )

        val baseGlyph = base.clusters.first { it.range.start == 2 }.advance
        val sizedGlyph = sized.clusters.first { it.range.start == 2 }.advance
        // 测 shaped at 40 vs 20 → ~2× the advance (full-width CJK ≈ 1em either way).
        assertTrue(
            sizedGlyph in baseGlyph * 1.8f..baseGlyph * 2.2f,
            "sized 测 advance $sizedGlyph should be ~2× base $baseGlyph",
        )
        // The unsized head keeps its size.
        val baseHead = base.clusters.first { it.range.start == 0 }.advance
        val sizedHead = sized.clusters.first { it.range.start == 0 }.advance
        assertTrue(sizedHead in baseHead * 0.98f..baseHead * 1.02f, "unsized 汉 must keep its advance")
        // The 2× cluster lifts the line height (paragraph-wide max metrics).
        assertTrue(sized.size.height > base.size.height, "a 2× span must grow the line height")
    }

    @Test
    fun boldSpanWidensLatinWord() {
        val constraints = LayoutConstraints(maxWidth = 4000f)
        val style = TextStyle(fontSize = 40f)
        val regular = measurer.measure("Hamburgers", constraints, style)
        val bold = measurer.measure(
            "Hamburgers",
            constraints,
            style,
            spans = listOf(TextSpan(TextRange(0, 10), TextStyle(fontSize = 40f, fontWeight = 700))),
        )
        fun latinWidth(r: org.tiqian.core.LayoutResult) =
            r.clusters.filter { it.range.start < 10 }.sumOf { it.advance.toDouble() }
        // Bold shapes the bold typeface → the word measures wider (real advances,
        // not synthetic). If the system lacks a distinct bold it ties, not fails.
        assertTrue(latinWidth(bold) >= latinWidth(regular), "bold must not be narrower than regular")
        assertTrue(latinWidth(bold) > latinWidth(regular), "bold ${latinWidth(bold)} should exceed regular ${latinWidth(regular)}")
    }
}
