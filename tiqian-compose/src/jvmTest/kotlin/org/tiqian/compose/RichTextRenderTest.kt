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
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.use
import org.jetbrains.skia.EncodedImageFormat
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Rich-text paint roles are rendered from Tiqian layout geometry, not by routing back to Compose
 * Text. The pixel assertions only guard wiring; glyph shapes stay covered by shaping goldens.
 */
@OptIn(ExperimentalComposeUiApi::class)
class RichTextRenderTest {

    @Test
    fun backgroundAndTextDecorationPaintFromRichTextSpans() {
        var yellow = 0
        var blue = 0
        ImageComposeScene(width = 520, height = 180) {
            Box(Modifier.fillMaxSize().background(Color.White).padding(16.dp)) {
                CjkText(
                    buildAnnotatedString {
                        append("普通")
                        withStyle(SpanStyle(background = Color(0xFFFFEA00))) { append("高亮背景") }
                        append("，")
                        withStyle(SpanStyle(color = Color.Blue, textDecoration = TextDecoration.Underline)) {
                            append("蓝色下划线")
                        }
                        append("，")
                        inlineCode { append("code") }
                    },
                    modifier = Modifier.width(480.dp),
                    textStyle = CjkTextStyle(fontSize = 40.sp),
                )
            }
        }.use { scene ->
            val image = scene.render()
            File("build/reports/tiqian-compose").mkdirs()
            image.encodeToData(EncodedImageFormat.PNG)?.bytes?.let {
                File("build/reports/tiqian-compose/rich-text.png").writeBytes(it)
            }
            val px = image.toComposeImageBitmap().toPixelMap()
            for (y in 0 until px.height) for (x in 0 until px.width) {
                val c = px[x, y]
                if (c.red > 0.85f && c.green > 0.75f && c.blue < 0.25f) yellow++
                if (c.blue > 0.65f && c.red < 0.35f && c.green < 0.45f) blue++
            }
        }
        assertTrue(yellow > 600, "expected yellow background pixels, got $yellow")
        assertTrue(blue > 200, "expected blue text/underline pixels, got $blue")
    }
}
