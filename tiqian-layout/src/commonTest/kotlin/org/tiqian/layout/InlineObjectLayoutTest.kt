package org.tiqian.layout

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.tiqian.core.Ic
import org.tiqian.core.INLINE_OBJECT_REPLACEMENT_CHAR
import org.tiqian.core.InlineObjectSpan
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LineLengthGrid
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent

class InlineObjectLayoutTest {
    private val style = ParagraphStyle(
        firstLineIndent = Ic(0f),
        lineHeight = 24f,
        lineLengthGrid = LineLengthGrid(enabled = false),
    )

    @Test
    fun inlineObjectSkipsFontShapingAndExpandsItsOwnLineMetrics() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中${INLINE_OBJECT_REPLACEMENT_CHAR}文"),
                textStyle = TextStyle(fontSize = 16f),
                constraints = LayoutConstraints(maxWidth = 120f),
                paragraphStyle = style,
                inlineObjects = listOf(
                    InlineObjectSpan(
                        range = TextRange(1, 2),
                        advance = 20f,
                        ascent = 30f,
                        descent = 4f,
                    ),
                ),
            ),
        )

        val objectCluster = result.clusters.single { it.range == TextRange(1, 2) }
        assertEquals(20f, objectCluster.advance, 0.001f)
        assertTrue(result.glyphRuns.flatMap { it.glyphs }.none { it.clusterRange == objectCluster.range })

        val shaping = result.debug.shapingDecisions.single { it.range == objectCluster.range }
        assertEquals(0, shaping.glyphCount)
        assertEquals("MeasurableOpaqueInlineObject:no-font-shaping", shaping.reason)

        val line = result.lines.single()
        assertTrue(line.baseline - line.top >= 30f)
        assertTrue(line.bottom - line.baseline >= 4f)
        val decision = result.debug.inlineObjectDecisions.single()
        assertEquals(0, decision.lineIndex)
        assertEquals("MeasurableOpaqueInlineObject", decision.reason)
    }

    @Test
    fun inlineObjectIsOneIndivisibleBreakCluster() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中${INLINE_OBJECT_REPLACEMENT_CHAR}文"),
                textStyle = TextStyle(fontSize = 16f),
                constraints = LayoutConstraints(maxWidth = 35f),
                paragraphStyle = style,
                inlineObjects = listOf(
                    InlineObjectSpan(TextRange(1, 2), advance = 20f, ascent = 16f, descent = 4f),
                ),
            ),
        )

        val objectIndex = result.clusters.indexOfFirst { it.range == TextRange(1, 2) }
        val objectLine = result.lines.single { objectIndex in it.clusterRange }
        assertEquals(objectIndex..objectIndex, objectLine.clusterRange)
    }
}
