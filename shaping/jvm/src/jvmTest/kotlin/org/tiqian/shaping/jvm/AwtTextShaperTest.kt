package org.tiqian.shaping.jvm

import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import org.tiqian.font.FontCandidate
import org.tiqian.font.FontDecision
import org.tiqian.font.FontRole
import org.tiqian.shaping.ShapingInput
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class AwtTextShaperTest {
    private val shaper = AwtTextShaper()

    @Test
    fun shapesLatinRunWithRealAdvanceInsteadOfNominalOneEmPerCharacter() {
        val result = shaper.shape(input(text = "Tiqian", role = FontRole.LatinText))

        assertEquals(1, result.clusters.size)
        assertEquals("Tiqian", result.clusters.single().displayText)
        assertTrue(result.clusters.single().advance > 0f)
        assertNotEquals(96f, result.clusters.single().advance)
        assertEquals(6, result.decisions.single().glyphCount)
        assertEquals("JvmAwt", result.decisions.single().source)
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
    fun exposesGlyphBoundsForInkAwarePunctuationFollowUp() {
        val result = shaper.shape(input(text = "。", role = FontRole.CjkPunctuation))

        val glyph = result.glyphRuns.single().glyphs.single()
        assertTrue(glyph.advance > 0f)
        assertNotNull(glyph.bounds)
        assertEquals(0, result.decisions.single().glyphsWithoutInkBounds)
    }

    @Test
    fun reportsGlyphsWithoutInkBoundsForBlankGlyphs() {
        // A space has empty visual bounds in AWT; the decision must count it
        // so downstream MissingInkBoundsFallback recording stays explainable.
        val result = shaper.shape(input(text = "a b", role = FontRole.LatinText))

        val glyphs = result.glyphRuns.single().glyphs
        val boundless = glyphs.count { it.bounds == null }
        assertTrue(boundless > 0, "Expected the space glyph to lack ink bounds")
        assertEquals(boundless, result.decisions.single().glyphsWithoutInkBounds)
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
