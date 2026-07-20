package org.tiqian.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.use
import org.jetbrains.skia.EncodedImageFormat
import java.io.File
import kotlin.math.roundToInt
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Rich-text 颜色 (ADR 0030 A 档, render-only): a `SpanStyle.color` span paints
 * its clusters in that color, the rest stay default — layout is unchanged.
 */
@OptIn(ExperimentalComposeUiApi::class)
class RichColorRenderTest {

    @Test
    fun spanColorsPaintTheirClusters() {
        var red = 0
        var blue = 0
        ImageComposeScene(width = 520, height = 170) {
            Box(Modifier.fillMaxSize().background(Color.White).padding(16.dp)) {
                CjkText(
                    buildAnnotatedString {
                        append("普通的黑字，")
                        withStyle(SpanStyle(color = Color.Red)) { append("红色强调") }
                        append("，再来")
                        withStyle(SpanStyle(color = Color(0xFF0066FF))) { append("蓝色") }
                        append("。")
                    },
                    modifier = Modifier.width(480.dp),
                    textStyle = CjkTextStyle(fontSize = 40.sp),
                )
            }
        }.use { scene ->
            val image = scene.render()
            File("build/reports/tiqian-compose").mkdirs()
            image.encodeToData(EncodedImageFormat.PNG)?.bytes?.let {
                File("build/reports/tiqian-compose/rich-color.png").writeBytes(it)
            }
            val px = image.toComposeImageBitmap().toPixelMap()
            for (y in 0 until px.height) for (x in 0 until px.width) {
                val c = px[x, y]
                if (c.red > 0.6f && c.green < 0.3f && c.blue < 0.3f) red++
                if (c.blue > 0.6f && c.red < 0.3f && c.green < 0.5f) blue++
            }
        }
        assertTrue(red > 200, "expected red ink from the 红色 span, got $red")
        assertTrue(blue > 200, "expected blue ink from the 蓝色 span, got $blue")
    }

    @Test
    fun cjkDecorationsUseTheCoveredSpanColor() {
        var layout: org.tiqian.core.LayoutResult? = null
        val image = ImageComposeScene(width = 260, height = 130) {
            Box(Modifier.fillMaxSize().background(Color.White)) {
                CjkText(
                    buildAnnotatedString {
                        withStyle(SpanStyle(color = Color.Red)) {
                            emphasis { append("强调") }
                        }
                        withStyle(SpanStyle(color = Color(0xFF0066FF))) {
                            properNoun { append("专名") }
                        }
                    },
                    modifier = Modifier.width(240.dp),
                    textStyle = CjkTextStyle(fontSize = 40.sp),
                    onTextLayout = { layout = it },
                )
            }
        }.use { scene -> scene.render().toComposeImageBitmap().toPixelMap() }

        val result = layout ?: error("onTextLayout was not called")
        val dot = result.debug.decorationDecisions.first { it.applied && it.dotDiameter > 0f }
        val line = result.debug.decorationSegments.single { it.kind == "ProperNoun" }

        fun hasColorNear(x: Float, y: Float, predicate: (Color) -> Boolean): Boolean {
            val centerX = x.roundToInt()
            val centerY = y.roundToInt()
            for (py in (centerY - 2).coerceAtLeast(0)..(centerY + 2).coerceAtMost(image.height - 1)) {
                for (px in (centerX - 2).coerceAtLeast(0)..(centerX + 2).coerceAtMost(image.width - 1)) {
                    if (predicate(image[px, py])) return true
                }
            }
            return false
        }

        assertTrue(
            hasColorNear(dot.anchorX, dot.anchorY) { it.red > 0.7f && it.green < 0.3f && it.blue < 0.3f },
            "Expected the emphasis dot to inherit its red span",
        )
        assertTrue(
            hasColorNear((line.left + line.right) / 2f, line.top) {
                it.blue > 0.7f && it.red < 0.3f && it.green < 0.6f
            },
            "Expected the proper-noun line to inherit its blue span",
        )
    }
}
