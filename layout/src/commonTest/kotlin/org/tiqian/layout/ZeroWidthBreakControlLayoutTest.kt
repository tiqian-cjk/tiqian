package org.tiqian.layout

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.tiqian.core.Ic
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LineLengthGrid
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TextRange
import org.tiqian.core.TiqianTextContent
import org.tiqian.linebreak.NoHyphenator

class ZeroWidthBreakControlLayoutTest {
    private val style = ParagraphStyle(
        firstLineIndent = Ic(0f),
        lineLengthGrid = LineLengthGrid(enabled = false),
    )

    @Test
    fun zeroWidthSpaceIsUnshapedAndProvidesASoftBreakAfterIt() {
        for (breaker in listOf(GreedyLineBreaker(), LookaheadLineBreaker())) {
            val result = layout("foo\u200Bbar", maxWidth = 48f, breaker = breaker)
            val control = result.clusters.single { it.text == "\u200B" }

            assertEquals("", control.displayText, breaker.strategyName)
            assertEquals(0f, control.advance, 0.001f, breaker.strategyName)
            assertTrue(
                result.glyphRuns.flatMap { it.glyphs }.none { it.clusterRange == control.range },
                breaker.strategyName,
            )
            assertEquals(TextRange(0, 4), result.lines[0].range, breaker.strategyName)
            assertEquals(TextRange(4, 7), result.lines[1].range, breaker.strategyName)
            assertEquals(
                "ZeroWidthSpaceSoftBreakNoShape",
                result.debug.shapingDecisions.single { it.range == control.range }.reason,
                breaker.strategyName,
            )
            assertEquals(
                control.range,
                result.debug.zeroWidthBreakDecisions.single().range,
                breaker.strategyName,
            )
        }
    }

    @Test
    fun leadingZeroWidthSpaceCannotCreateAnEmptyAutoWrappedLine() {
        for (breaker in listOf(GreedyLineBreaker(), LookaheadLineBreaker())) {
            val result = layout("\u200B中", maxWidth = 8f, breaker = breaker)

            assertEquals(1, result.lines.size, breaker.strategyName)
            assertEquals(TextRange(0, 2), result.lines.single().range, breaker.strategyName)
        }
    }

    private fun layout(text: String, maxWidth: Float, breaker: LineBreaker) =
        ExplainableStubParagraphLayoutEngine(
            lineBreaker = breaker,
            hyphenator = NoHyphenator,
        ).layout(
            LayoutInput(
                content = TiqianTextContent(text),
                constraints = LayoutConstraints(maxWidth = maxWidth),
                paragraphStyle = style,
            ),
        )
}
