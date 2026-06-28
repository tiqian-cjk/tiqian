package org.tiqian.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.unit.sp
import androidx.compose.ui.use
import kotlin.test.Test
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
}
