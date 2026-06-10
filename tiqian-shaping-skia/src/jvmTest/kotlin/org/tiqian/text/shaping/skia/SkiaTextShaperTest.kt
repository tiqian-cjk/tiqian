package org.tiqian.text.shaping.skia

import org.tiqian.text.core.TextRange
import org.tiqian.text.core.TextStyle
import org.tiqian.text.font.FontCandidate
import org.tiqian.text.font.FontDecision
import org.tiqian.text.font.FontRole
import org.tiqian.text.shaping.ShapingInput
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class SkiaTextShaperTest {
    private val shaper = SkiaTextShaper()

    @Test
    fun shapesLatinRunWithRealAdvanceInsteadOfNominalOneEmPerCharacter() {
        val result = shaper.shape(input(text = "Tiqian", role = FontRole.LatinText))

        assertEquals(1, result.clusters.size)
        assertEquals("Tiqian", result.clusters.single().displayText)
        assertTrue(result.clusters.single().advance > 0f)
        assertNotEquals(96f, result.clusters.single().advance)
        assertEquals("Skia", result.decisions.single().source)
    }

    @Test
    fun keepsClreqDisplaySubstitutionSeparateFromSourceText() {
        val result = shaper.shape(
            input(
                text = "——",
                role = FontRole.CjkPunctuation,
                displayText = "⸺",
            ),
        )

        assertEquals(TextRange(0, 2), result.clusters.single().range)
        assertEquals("——", result.clusters.single().text)
        assertEquals("⸺", result.clusters.single().displayText)
        assertEquals("——", result.decisions.single().sourceText)
        assertEquals("⸺", result.decisions.single().displayText)
        assertTrue(result.clusters.single().advance > 0f)
    }

    @Test
    fun exposesGlyphBoundsForInkAwarePunctuation() {
        val result = shaper.shape(input(text = "。", role = FontRole.CjkPunctuation))

        val glyph = result.glyphRuns.single().glyphs.single()
        assertTrue(glyph.advance > 0f)
        assertNotNull(glyph.bounds)
        assertEquals(0, result.decisions.single().glyphsWithoutInkBounds)
    }

    @Test
    fun reportsGlyphsWithoutInkBoundsForBlankGlyphs() {
        val result = shaper.shape(input(text = "a b", role = FontRole.LatinText))

        val glyphs = result.glyphRuns.single().glyphs
        val boundless = glyphs.count { it.bounds == null }
        assertTrue(boundless > 0, "Expected the space glyph to lack ink bounds")
        assertEquals(boundless, result.decisions.single().glyphsWithoutInkBounds)
    }

    @Test
    fun localeTaggedShapingPicksCjkDashVariant() {
        // TextStyle defaults to locale=zh-Hans; LocaleTaggedShaping must
        // activate the font's `locl` CJK dash: a full 1em advance with ink
        // vertically centred in the CJK band (centre ≈ -6 at 16px), not the
        // Western baseline-aligned form (centre -4.5, advance 14.3 in
        // Source Han Sans).
        val result = shaper.shape(input(text = "—", role = FontRole.CjkPunctuation))

        val glyph = result.glyphRuns.single().glyphs.single()
        assertEquals(16f, glyph.advance, 0.01f)
        val bounds = glyph.bounds
        assertNotNull(bounds)
        val verticalCenter = (bounds.top + bounds.bottom) / 2f
        assertTrue(
            verticalCenter < -5f,
            "Expected CJK-centred dash ink (centre < -5), got $verticalCenter",
        )
        assertTrue(result.decisions.single().reason.endsWith("lang=zh-Hans"))
    }

    @Test
    fun glyphAdvancesSumToClusterAdvance() {
        val result = shaper.shape(input(text = "中文。", role = FontRole.CjkText))

        val cluster = result.clusters.single()
        val glyphSum = result.glyphRuns.single().glyphs.sumOf { it.advance.toDouble() }.toFloat()
        assertEquals(cluster.advance, glyphSum, 0.01f)
    }

    private fun input(
        text: String,
        role: FontRole,
        displayText: String = text,
    ): ShapingInput =
        ShapingInput(
            text = text,
            range = TextRange(0, text.length),
            style = TextStyle(fontSize = 16f),
            fontDecision = FontDecision(
                range = TextRange(0, text.length),
                candidate = FontCandidate(
                    key = "test-${role.name}",
                    family = "test-${role.name}",
                    role = role,
                ),
                role = role,
                reason = "test",
            ),
            displayText = displayText,
        )
}
