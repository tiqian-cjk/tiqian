package org.tiqian.compose

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle as ComposeTextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.sp
import org.tiqian.core.Ic
import org.tiqian.core.LastLineAlignment
import org.tiqian.core.LayoutConstraints
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.LookaheadLineBreaker
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class CjkTextPreLayoutInteropTest {

    private val measurer = ParagraphMeasurer(
        ExplainableStubParagraphLayoutEngine(
            lineBreaker = LookaheadLineBreaker(),
        ),
    )
    private val density = Density(1f)
    private val constraints = LayoutConstraints(maxWidth = 160f)

    @Test
    fun annotatedStringMeasureUsesComposeTextNoIndentDefault() {
        val result = measurer.measure(
            text = AnnotatedString("正文"),
            constraints = constraints,
            density = density,
            textStyle = CjkTextStyle(fontSize = 16.sp),
        )

        assertEquals(Ic.Zero, result.input.paragraphStyle.firstLineIndent)
        assertEquals("Explicit", result.debug.firstLineIndentDecision?.source)
        assertEquals(0f, result.lines.single().indent)
    }

    @Test
    fun composeTextStyleMeasureLowersParagraphControlsLikeCjkText() {
        val result = measurer.measure(
            text = AnnotatedString("正文"),
            constraints = constraints,
            density = density,
            style = ComposeTextStyle(fontSize = 16.sp, textAlign = TextAlign.End),
        )

        assertEquals(Ic.Zero, result.input.paragraphStyle.firstLineIndent)
        assertEquals(LastLineAlignment.End, result.input.paragraphStyle.lastLineAlignment)
        assertEquals("Explicit", result.debug.firstLineIndentDecision?.source)
        assertTrue(result.lines.single().indent > 0f)
    }
}
