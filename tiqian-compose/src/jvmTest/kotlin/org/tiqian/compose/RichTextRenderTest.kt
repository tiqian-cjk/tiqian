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
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.use
import org.jetbrains.skia.EncodedImageFormat
import org.tiqian.core.LayoutResult
import org.tiqian.core.RichTextRole
import org.tiqian.core.TextRange
import org.tiqian.core.getBoundingBoxes
import org.tiqian.core.positionedClusters
import org.tiqian.core.positionedRichTextSegments
import org.tiqian.layout.ExplainableStubParagraphLayoutEngine
import java.io.File
import kotlin.math.roundToInt
import kotlin.test.Test
import kotlin.test.assertEquals
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

    @Test
    fun cjkUnderlineReusesInterlinearLineAndIsNotSkippedAway() {
        var layout: LayoutResult? = null
        val text = buildAnnotatedString {
            withStyle(SpanStyle(color = Color.Blue, textDecoration = TextDecoration.Underline)) {
                append("中文链接文字")
            }
        }
        val fontSize = 40f

        val image = ImageComposeScene(width = 360, height = 120) {
            Box(Modifier.fillMaxSize().background(Color.White)) {
                CjkText(
                    text,
                    modifier = Modifier.width(340.dp),
                    textStyle = CjkTextStyle(fontSize = fontSize.sp),
                    onTextLayout = { layout = it },
                )
            }
        }.use { it.render() }

        val result = layout ?: error("onTextLayout not called")
        val boxes = result.getBoundingBoxes(0, text.length)
        val left = boxes.minOf { it.left }.roundToInt().coerceAtLeast(0)
        val right = boxes.maxOf { it.right }.roundToInt().coerceAtMost(image.width)
        val y = (result.lines.single().baseline + fontSize * INTERLINEAR_UNDERLINE_OFFSET_EM_FOR_TEST)
            .roundToInt()
            .coerceIn(0, image.height - 1)

        val px = image.toComposeImageBitmap().toPixelMap()
        var underlinePixels = 0
        for (yy in (y - 1).coerceAtLeast(0)..(y + 1).coerceAtMost(px.height - 1)) {
            for (x in left until right) {
                val c = px[x, yy]
                if (c.blue > 0.65f && c.red < 0.35f && c.green < 0.45f) underlinePixels++
            }
        }

        assertTrue(
            underlinePixels > (right - left),
            "expected CJK underline to survive skip-ink at interlinear-line y, got $underlinePixels",
        )
    }

    @Test
    fun underlineEndingBeforeLatinPunctuationUsesSourceBoundaryCluster() {
        val text = buildAnnotatedString {
            withStyle(SpanStyle(textDecoration = TextDecoration.Underline)) {
                append("template")
            }
            append(".")
        }
        val result = ParagraphMeasurer(ExplainableStubParagraphLayoutEngine()).measure(
            text = text,
            constraints = org.tiqian.core.LayoutConstraints(maxWidth = 400f),
            density = Density(1f),
            textStyle = CjkTextStyle(fontSize = 16.sp),
        )

        val positioned = result.positionedClusters()
        val punctuationCluster = positioned.single { it.range == TextRange("template".length, text.length) }
        val templateRight = positioned
            .filter { it.range.start >= 0 && it.range.end <= "template".length }
            .maxOf { it.right }
        val underline = result.positionedRichTextSegments(text.cjkRichTextSpans())
            .single { it.span.role == RichTextRole.Underline }

        assertEquals(TextRange(0, "template".length), underline.range)
        assertEquals(templateRight, underline.right, absoluteTolerance = 0.01f)
        assertEquals(punctuationCluster.left, underline.right, absoluteTolerance = 0.01f)
    }
}

private const val INTERLINEAR_UNDERLINE_OFFSET_EM_FOR_TEST = 0.18f
