package org.tiqian.compose

import org.tiqian.clreq.ClreqProfile
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.core.ic
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import org.tiqian.shaping.skia.SkiaFontMetricsResolver
import org.tiqian.shaping.skia.SkiaTextShaper
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * A missing glyph in CJK body must render as a full-em 字身框 豆腐, not a narrow Latin
 * `.notdef`. Regression: the Skia shaper measured `Unknown` in the Latin face
 * (≈0.65em) while the renderer drew it in the CJK face (full-em) — the box overflowed
 * its slot and collided with the next cluster. `LatinVsCjkFaceSelection` unifies them.
 */
class MissingGlyphTofuTest {
    @Test
    fun missingGlyphIsFullEmTofu() {
        val engine = ExplainableStubParagraphLayoutEngine(
            lineBreaker = LookaheadLineBreaker(),
            textShaper = SkiaTextShaper(),
            fontMetricsResolver = SkiaFontMetricsResolver(),
            clreqProfileResolver = { ClreqProfile.MainlandHorizontal },
        )
        val fontSize = 40f
        // 中 [U+10FFFD — Plane-16 PUA, no font covers it → .notdef] 文
        val r = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中􏿽文"),
                textStyle = TextStyle(fontSize = fontSize, locale = "zh-Hans"),
                paragraphStyle = ParagraphStyle(firstLineIndent = 0.ic),
                constraints = LayoutConstraints(maxWidth = 9999f),
            ),
        )
        val cjk = r.clusters.first { it.text == "中" }
        val missing = r.clusters.single { it.range.start == 1 }
        // Full-em tofu: same advance as a CJK ideograph (was a ~0.65em Latin .notdef).
        assertEquals(cjk.advance, missing.advance, 0.5f)
        // measure == draw: glyph advances sum to the cluster advance (no overflow/overlap).
        val glyphSum = r.glyphRuns.flatMap { it.glyphs }
            .filter { it.clusterRange == missing.range }
            .sumOf { it.advance.toDouble() }.toFloat()
        assertEquals(missing.advance, glyphSum, 0.5f)
    }
}
