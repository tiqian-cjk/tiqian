package org.tiqian.shaping.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.core.ic
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * On-device guard for `LatinVsCjkFaceSelection`: a missing glyph in CJK body must
 * resolve through the CJK face (full-em 字身框 豆腐), not the narrow Latin Roboto
 * `.notdef`. Before the fix the Android resolver sent `Unknown → Latin`, so the
 * measured slot (≈0.65em) disagreed with the drawn box and clipped/collided.
 */
@RunWith(AndroidJUnit4::class)
class AndroidMissingGlyphTofuTest {
    private val typefaces = SystemAndroidTypefaceResolver()
    private val engine = ExplainableStubParagraphLayoutEngine(
        lineBreaker = LookaheadLineBreaker(),
        textShaper = AndroidPaintTextShaper(typefaceResolver = typefaces),
        fontMetricsResolver = AndroidFontMetricsResolver(typefaceResolver = typefaces),
    )

    @Test
    fun missingGlyphIsFullEmTofu() {
        val fontSize = 48f
        // 中 [U+10FFFD — Plane-16 PUA, no font covers it → .notdef] 文
        val r = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中􏿽文"),
                textStyle = TextStyle(fontSize = fontSize, locale = "zh-Hans"),
                paragraphStyle = ParagraphStyle(firstLineIndent = 0.ic),
                constraints = LayoutConstraints(maxWidth = 2000f),
            ),
        )
        val cjk = r.clusters.first { it.text == "中" }
        val missing = r.clusters.single { it.range.start == 1 }
        // Full-em (CJK) tofu, not a narrow Latin .notdef (~0.65em).
        assertTrue(
            missing.advance >= 0.8f * cjk.advance,
            "missing-glyph advance ${missing.advance} should be ~full-em (中=${cjk.advance})",
        )
        // measure == draw: glyph advances sum to the cluster advance (no overflow/overlap).
        val glyphSum = r.glyphRuns.flatMap { it.glyphs }
            .filter { it.clusterRange == missing.range }
            .sumOf { it.advance.toDouble() }.toFloat()
        assertEquals(missing.advance, glyphSum, 0.5f)
    }
}
