package org.tiqian.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.use
import kotlin.math.roundToInt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import org.tiqian.core.LayoutResult

@OptIn(ExperimentalComposeUiApi::class)
class CjkInlineObjectTest {
    @Test
    fun renderOnlyObjectsPreserveLogicalCopyAndBidirectionalOffsets() {
        val projected = AnnotatedString.Builder("a￼b￼c￼").apply {
            addCjkRenderOnlyInlineObject(1, 2)
            addCjkRenderOnlyInlineObject(5, 6)
        }.toAnnotatedString()
        val logical = projected.cjkInlineLogicalText()
        assertEquals("ab￼c", logical.text, "authored object characters must remain copyable")
        val offsets = CjkInlineObjectOffsetMapping(logical)
        for (offset in 0..logical.length) assertEquals(offset, offsets.toLogical(offsets.toLayout(offset)))
        assertEquals(1, offsets.toLogical(1))
        assertEquals(1, offsets.toLogical(2))
        assertEquals(6, offsets.toLayout(logical.length))
        assertEquals("ab￼c", offsets.layoutRanges(org.tiqian.core.TextRange(0, logical.length)).joinToString("") {
            projected.text.substring(it.start, it.end)
        })
        assertEquals("b", offsets.layoutRanges(org.tiqian.core.TextRange(1, 2)).joinToString("") {
            projected.text.substring(it.start, it.end)
        })
    }

    @Test
    fun composeObjectUsesItsMeasuredBaselineInTheTiqianLineBox() {
        val ascent = 30
        val descent = 7
        var result: LayoutResult? = null

        val image = ImageComposeScene(width = 180, height = 100) {
            CjkText(
                text = AnnotatedString("中图片文"),
                textStyle = CjkTextStyle(fontSize = 16.sp),
                inlineObjects = listOf(
                    CjkInlineObject(
                        range = TextRange(1, 3),
                        advance = 20.dp,
                        ascent = ascent.dp,
                        descent = descent.dp,
                    ) {
                        Box(Modifier.fillMaxSize().background(Color.Red))
                    },
                ),
                onTextLayout = { result = it },
            )
        }.use { scene -> scene.render() }

        val layout = assertNotNull(result)
        val baseline = layout.lines.single().baseline.roundToInt()
        val pixels = image.toComposeImageBitmap().toPixelMap()
        val redRows = buildList {
            for (y in 0 until pixels.height) {
                if ((0 until pixels.width).any { x ->
                        val color = pixels[x, y]
                        color.red > 0.9f && color.green < 0.1f && color.blue < 0.1f
                    }
                ) {
                    add(y)
                }
            }
        }

        assertEquals(baseline - ascent, redRows.first(), "object top must be baseline - ascent")
        assertEquals(baseline + descent - 1, redRows.last(), "object bottom must be baseline + descent")
    }
}
