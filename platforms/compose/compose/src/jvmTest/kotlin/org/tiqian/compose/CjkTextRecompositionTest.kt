package org.tiqian.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.width
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.Snapshot
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
import org.tiqian.core.ColorSpan
import org.tiqian.core.LayoutResult
import org.tiqian.core.TextStyle
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import org.tiqian.layout.ParagraphLayoutEngine
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Regression: editing the `text` state must repaint the paragraph. The earlier
 * non-snapshot `ParagraphLayoutHolder` broke this — drawBehind read a plain field,
 * so a measure-time write didn't invalidate the draw and same-size edits (e.g. one
 * CJK char → another) showed stale glyphs. The two readings below are the same
 * width/height, so only a real draw-invalidation makes the pixels differ.
 */
@OptIn(ExperimentalComposeUiApi::class)
class CjkTextRecompositionTest {

    @Test
    fun reusingLayoutDuringRemeasurePaintsTheCurrentRichText() {
        val session = ParagraphMeasurementSession()
        val first = createPlatformParagraphMeasurer(session = session)
        val second = createPlatformParagraphMeasurer(session = session)
        val text = AnnotatedString("AB")
        var updated by mutableStateOf(false)

        ImageComposeScene(width = 200, height = 120) {
            CjkText(
                text = text,
                modifier = Modifier.width(160.dp),
                textStyle = CjkTextStyle(fontSize = 30.sp),
                minLines = if (updated) 2 else 1,
                measurer = if (updated) second else first,
                inlineBackgrounds = listOf(CjkInlineBackground(TextRange(0, text.length), if (updated) Color.Blue else Color.Red)),
            )
        }.use { scene ->
            val before = scene.render(0L).use { it.toComposeImageBitmap().toPixelMap() }
            val y = (0 until before.height).first { row -> (0 until before.width).any { before[it, row] == Color.Red } }
            val x = (0 until before.width).first { before[it, y] == Color.Red }
            updated = true
            Snapshot.sendApplyNotifications()
            val after = scene.render(100_000_000L).use { it.toComposeImageBitmap().toPixelMap() }
            assertEquals(Color.Blue, after[x, y], "the old background must not survive a layout cache hit")
        }
    }

    @Test
    fun outerMinLinesRemeasureReusesExactEngineResult() {
        var minLines by mutableStateOf(1)
        var measuredHeight = 0
        var layoutCalls = 0
        val delegate = ExplainableStubParagraphLayoutEngine()
        val measurer = ParagraphMeasurer(
            object : ParagraphLayoutEngine {
                override fun layout(input: org.tiqian.core.LayoutInput): LayoutResult {
                    layoutCalls += 1
                    return delegate.layout(input)
                }
            },
        )

        ImageComposeScene(width = 240, height = 180) {
            CjkText(
                text = "缓存只复用完全相同的引擎输入。",
                modifier = Modifier.width(200.dp).onSizeChanged { measuredHeight = it.height },
                textStyle = CjkTextStyle(fontSize = 20.sp),
                minLines = minLines,
                measurer = measurer,
            )
        }.use { scene ->
            scene.render(0L)
            assertEquals(1, layoutCalls)
            val oneLineHeight = measuredHeight

            minLines = 3
            Snapshot.sendApplyNotifications()
            scene.render(100_000_000L)

            assertEquals(1, layoutCalls, "minLines only changes the outer Compose box")
            assertTrue(measuredHeight > oneLineHeight)
        }
    }

    @Test
    fun widthChangeInvalidatesExactEngineResult() {
        var width by mutableStateOf(200.dp)
        var layoutCalls = 0
        val delegate = ExplainableStubParagraphLayoutEngine()
        val measurer = ParagraphMeasurer(
            object : ParagraphLayoutEngine {
                override fun layout(input: org.tiqian.core.LayoutInput): LayoutResult {
                    layoutCalls += 1
                    return delegate.layout(input)
                }
            },
        )

        ImageComposeScene(width = 240, height = 180) {
            CjkText(
                text = "宽度跨越约束时必须重新运行真实布局。",
                modifier = Modifier.width(width),
                textStyle = CjkTextStyle(fontSize = 20.sp),
                measurer = measurer,
            )
        }.use { scene ->
            scene.render(0L)
            assertEquals(1, layoutCalls)

            width = 160.dp
            Snapshot.sendApplyNotifications()
            scene.render(100_000_000L)

            assertEquals(2, layoutCalls)
        }
    }

    @Test
    fun editingTextStateRepaints() {
        var text by mutableStateOf("天")
        val measured = mutableListOf<String>()
        ImageComposeScene(width = 160, height = 120) {
            Box(Modifier.fillMaxSize().background(Color.White)) {
                CjkText(
                    text = text,
                    textStyle = CjkTextStyle(fontSize = 80.sp),
                    onTextLayout = { measured += it.input.content.text },
                )
            }
        }.use { scene ->
            val before = scene.render(0L).toComposeImageBitmap().toPixelMap()
            text = "地" // same advance, different glyph (the hard case)
            Snapshot.sendApplyNotifications() // propagate the state write to the recomposer
            val after = scene.render(100_000_000L).toComposeImageBitmap().toPixelMap()

            fun ink(pm: androidx.compose.ui.graphics.PixelMap): Int {
                var n = 0
                for (x in 0 until pm.width) for (y in 0 until pm.height) {
                    if (pm[x, y] != Color.White) n++
                }
                return n
            }
            // 1) the edit must reach the engine (recomposition + remeasure)
            assertTrue("地" in measured, "no remeasure after edit; measured=$measured")
            // 2) and the new glyph must actually be painted (draw invalidation)
            var changed = false
            loop@ for (x in 0 until before.width) {
                for (y in 0 until before.height) {
                    if (before[x, y] != after[x, y]) { changed = true; break@loop }
                }
            }
            assertTrue(changed, "remeasured=$measured beforeInk=${ink(before)} afterInk=${ink(after)}")
        }
    }

    @Test
    fun renderRangeBoundariesAreForwardedWithMeasuredInput() {
        var mode by mutableStateOf(0)
        val measuredBoundaries = mutableListOf<Set<Int>>()
        ImageComposeScene(width = 240, height = 120) {
            val layoutCallback = remember {
                { result: LayoutResult -> measuredBoundaries += result.input.content.sourceBoundaries.toSet() }
            }
            Box(Modifier.fillMaxSize().background(Color.White)) {
                CjkTextLayout(
                    text = "template.",
                    modifier = Modifier.width(220.dp),
                    textStyle = TextStyle(fontSize = 32f),
                    colorSpans = when (mode) {
                        0 -> listOf(ColorSpan(0, 8, 0xff0000ff.toInt()))
                        1 -> listOf(ColorSpan(0, 8, 0xffff0000.toInt()))
                        else -> listOf(ColorSpan(0, 4, 0xffff0000.toInt()))
                    },
                    onTextLayout = layoutCallback,
                )
            }
        }.use { scene ->
            scene.render(0L)
            val initialMeasureCount = measuredBoundaries.size
            assertTrue(initialMeasureCount > 0, "initial render did not measure")
            assertEquals(setOf(8), measuredBoundaries.last())

            mode = 1
            Snapshot.sendApplyNotifications()
            scene.render(100_000_000L)
            assertEquals(setOf(8), measuredBoundaries.last(), "paint-only changes must keep the same source boundary")
            val paintChangeMeasureCount = measuredBoundaries.size

            mode = 2
            Snapshot.sendApplyNotifications()
            scene.render(200_000_000L)
            assertTrue(
                measuredBoundaries.size > paintChangeMeasureCount,
                "changed source boundaries must re-run layout",
            )
            assertEquals(setOf(4), measuredBoundaries.last())
        }
    }
}
