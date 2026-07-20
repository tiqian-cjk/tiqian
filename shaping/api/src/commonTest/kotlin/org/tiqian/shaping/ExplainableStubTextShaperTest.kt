package org.tiqian.shaping

import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import org.tiqian.font.FontCandidate
import org.tiqian.font.FontDecision
import org.tiqian.font.FontRole
import kotlin.test.Test
import kotlin.test.assertEquals

class ExplainableStubTextShaperTest {
    private val shaper = ExplainableStubTextShaper()

    @Test
    fun shapesSingleCjkClusterWithOneEmAdvance() {
        val result = shaper.shape(input(text = "中", role = FontRole.CjkText))

        assertEquals(1, result.clusters.size)
        assertEquals("中", result.clusters.single().text)
        assertEquals("中", result.clusters.single().displayText)
        assertEquals(16f, result.clusters.single().advance)
        assertEquals(1, result.glyphRuns.single().glyphs.size)
        assertEquals("Stub", result.decisions.single().source)
    }

    @Test
    fun keepsLatinRunAsSingleShapedClusterWithNominalGlyphs() {
        val result = shaper.shape(input(text = "Hello", role = FontRole.LatinText))

        assertEquals(1, result.clusters.size)
        assertEquals("Hello", result.clusters.single().text)
        assertEquals(80f, result.clusters.single().advance)
        assertEquals(5, result.glyphRuns.single().glyphs.size)
        assertEquals(5, result.decisions.single().glyphCount)
    }

    @Test
    fun shapesClreqDashSubstitutionAsTwoEmDisplayCluster() {
        val result = shaper.shape(
            input(
                text = "——",
                role = FontRole.CjkPunctuation,
                displayText = "⸺",
            ),
        )

        assertEquals("——", result.clusters.single().text)
        assertEquals("⸺", result.clusters.single().displayText)
        assertEquals(32f, result.clusters.single().advance)
        assertEquals(1, result.glyphRuns.single().glyphs.size)
        assertEquals(32f, result.glyphRuns.single().glyphs.single().advance)
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
                    key = "test-font",
                    family = "test-font",
                    role = role,
                ),
                role = role,
                reason = "test",
            ),
            displayText = displayText,
        )
}
