package org.tiqian.android.view

import org.tiqian.core.IntRange
import org.tiqian.core.LineBox
import org.tiqian.core.Rect
import org.tiqian.core.TextRange
import kotlin.test.Test
import kotlin.test.assertEquals

class CjkNativeSelectionGeometryTest {
    @Test
    fun selectedSeparatorPaintsFromParagraphEndToViewportEdge() {
        assertEquals(
            listOf(Rect(40f, 0f, 100f, 20f)),
            expandNativeSelectionBoxes(
                lines = listOf(line(top = 0f, bottom = 20f, visualWidth = 40f)),
                characterBoxes = emptyList(),
                firstLine = 0,
                lastLine = 0,
                continuesFromPreviousFragment = false,
                continuesOnNextFragment = true,
                viewportWidth = 100f,
            ),
        )
    }

    @Test
    fun selectedSeparatorPaintsLeadingIndentAtNextParagraphStart() {
        assertEquals(
            listOf(Rect(0f, 0f, 16f, 20f)),
            expandNativeSelectionBoxes(
                lines = listOf(line(top = 0f, bottom = 20f, visualWidth = 40f, indent = 16f)),
                characterBoxes = emptyList(),
                firstLine = 0,
                lastLine = 0,
                continuesFromPreviousFragment = true,
                continuesOnNextFragment = false,
                viewportWidth = 100f,
            ),
        )
    }

    @Test
    fun nativeMultilineSelectionFillsLineTailInteriorLinesAndLineLead() {
        val lines = listOf(
            line(top = 0f, bottom = 20f, visualWidth = 50f),
            line(top = 20f, bottom = 40f, visualWidth = 60f),
            line(top = 40f, bottom = 60f, visualWidth = 30f),
        )

        assertEquals(
            listOf(
                Rect(10f, 0f, 100f, 20f),
                Rect(0f, 20f, 100f, 40f),
                Rect(0f, 40f, 20f, 60f),
            ),
            expandNativeSelectionBoxes(
                lines = lines,
                characterBoxes = listOf(
                    Rect(10f, 0f, 30f, 20f),
                    Rect(5f, 20f, 45f, 40f),
                    Rect(0f, 40f, 20f, 60f),
                ),
                firstLine = 0,
                lastLine = 2,
                continuesFromPreviousFragment = false,
                continuesOnNextFragment = false,
                viewportWidth = 100f,
            ),
        )
    }

    @Test
    fun fullySelectedInteriorFragmentProducesOneNonOverlappingFullWidthBox() {
        assertEquals(
            listOf(Rect(0f, 0f, 100f, 20f)),
            expandNativeSelectionBoxes(
                lines = listOf(line(top = 0f, bottom = 20f, visualWidth = 40f, indent = 12f)),
                characterBoxes = listOf(Rect(12f, 0f, 52f, 20f)),
                firstLine = 0,
                lastLine = 0,
                continuesFromPreviousFragment = true,
                continuesOnNextFragment = true,
                viewportWidth = 100f,
            ),
        )
    }

    private fun line(
        top: Float,
        bottom: Float,
        visualWidth: Float,
        indent: Float = 0f,
    ): LineBox = LineBox(
        range = TextRange(0, 1),
        clusterRange = IntRange(0, 0),
        baseline = bottom - 4f,
        top = top,
        bottom = bottom,
        naturalWidth = visualWidth,
        adjustedWidth = visualWidth,
        visualWidth = visualWidth,
        indent = indent,
    )
}
