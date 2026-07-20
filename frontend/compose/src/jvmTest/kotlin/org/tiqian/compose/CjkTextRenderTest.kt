package org.tiqian.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.use
import androidx.compose.ui.unit.sp
import org.tiqian.core.Cluster
import org.tiqian.core.LayoutInput
import org.tiqian.core.LineEndReason
import org.tiqian.core.LineBox
import org.tiqian.core.LayoutResult
import org.tiqian.core.Size
import org.tiqian.core.TextRange
import org.tiqian.core.ic
import org.tiqian.layout.ParagraphLayoutEngine
import org.jetbrains.skia.EncodedImageFormat
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * `CjkText` stacks paragraphs and sections (CLREQ §6.2.1). PNGs are written for
 * eyeballing the 段首缩排/凸排/段落缩排 styles; the assertion guards the wiring.
 */
@OptIn(ExperimentalComposeUiApi::class)
class CjkTextRenderTest {

    private val article = listOf(
        "咖啡馆比咖啡更早地改变了城里人的作息与谈吐，读报、辩论、写作都在这里发生。",
        "最初它被当作药物出售，价格高得吓人，真正让它流行的是随后遍地开花的咖啡馆。",
        "有人说先有咖啡馆，后有启蒙运动。这话说得夸张，但也不算太离谱。",
    )

    private fun render(name: String, content: @androidx.compose.runtime.Composable () -> Unit): Int {
        var ink = 0
        ImageComposeScene(width = 380, height = 760) {
            Box(Modifier.fillMaxSize().background(Color.White).padding(16.dp)) { content() }
        }.use { scene ->
            val image = scene.render()
            File("build/reports/tiqian-compose").apply { mkdirs() }
            image.encodeToData(EncodedImageFormat.PNG)?.bytes?.let {
                File("build/reports/tiqian-compose", "cjk-text-$name.png").writeBytes(it)
            }
            val pixels = image.toComposeImageBitmap().toPixelMap()
            for (y in 0 until pixels.height) for (x in 0 until pixels.width) {
                val c = pixels[x, y]
                if (c.red < 0.5f && c.green < 0.5f && c.blue < 0.5f) ink++
            }
        }
        return ink
    }

    @Test
    fun documentBlocksRenderAllParagraphs() {
        val blocks = article.map { CjkBlock.Paragraph(it, ParagraphIndent.FirstLine) }
        val ink = render("document-blocks") {
            CjkText(
                blocks = blocks,
                modifier = Modifier.width(320.dp),
                textStyle = CjkTextStyle(fontSize = 30.sp),
            )
        }
        assertTrue(ink > 2_000, "Expected substantial ink for document blocks, got $ink")
    }

    @Test
    fun mixedBlocksRenderHangingQuoteAndSection() {
        val blocks = listOf(
            CjkBlock.Paragraph(
                "张三说道：今天天气不错，咱们出去走走吧，顺便买点咖啡豆回来配下午茶。",
                ParagraphIndent.Hanging(2.ic),
            ),
            CjkBlock.Section,
            CjkBlock.Paragraph(
                "他引用一句诗：采菊东篱下，悠然见南山，此中有真意，欲辨已忘言。",
                ParagraphIndent.Block(2.ic),
            ),
            CjkBlock.Paragraph(
                "回到正文，咖啡馆比咖啡更早地改变了城里人的作息与谈吐与往来。",
                ParagraphIndent.FirstLine,
            ),
        )
        val ink = render("mixed") {
            CjkText(blocks = blocks, modifier = Modifier.width(320.dp), textStyle = CjkTextStyle(fontSize = 30.sp))
        }
        assertTrue(ink > 2_000, "Expected substantial ink for mixed blocks, got $ink")
    }

    @Test
    fun composeTextReplacementRendersSingleUnindentedParagraph() {
        var layout: LayoutResult? = null
        val ink = render("compose-replacement") {
            CjkText(
                text = "替代 Compose Text 的正文 English typography。",
                modifier = Modifier.width(320.dp),
                style = TextStyle(fontSize = 30.sp),
                fontWeight = FontWeight.Bold,
                textDecoration = TextDecoration.Underline,
                onTextLayout = { layout = it },
            )
        }

        assertTrue(ink > 1_000, "Expected substantial ink for Compose Text replacement, got $ink")
        assertEquals(0f, layout?.lines?.firstOrNull()?.indent)
    }

    @Test
    fun composeTextReplacementHonorsLineControls() {
        var limited: LayoutResult? = null
        val text = "中文 English typography 混排会自然换行，第二行不应该在 maxLines=1 的结果里出现。"

        render("compose-line-controls") {
            CjkText(
                text = text,
                modifier = Modifier.width(180.dp),
                style = TextStyle(fontSize = 24.sp),
                maxLines = 1,
                minLines = 1,
                overflow = TextOverflow.Clip,
                onTextLayout = { limited = it },
            )
        }

        assertEquals(1, limited?.lines?.size)
    }

    @Test
    fun clipOverflowStillPaintsEngineHangingPunctuationWithoutGlyphBounds() {
        val text = "中文中文，"
        var measuredWidth = 0
        val measurer = ParagraphMeasurer(
            object : ParagraphLayoutEngine {
                override fun layout(input: LayoutInput): LayoutResult {
                    val clusters = listOf(
                        Cluster(TextRange(0, 1), "中", fontKey = "cjk", advance = 16f),
                        Cluster(TextRange(1, 2), "文", fontKey = "cjk", advance = 16f),
                        Cluster(TextRange(2, 3), "中", fontKey = "cjk", advance = 16f),
                        Cluster(TextRange(3, 4), "文", fontKey = "cjk", advance = 16f),
                        Cluster(TextRange(4, 5), "，", fontKey = "cjk", advance = 8f),
                    )
                    return LayoutResult(
                        input = input,
                        size = Size(72f, 24f),
                        clusters = clusters,
                        glyphRuns = emptyList(),
                        lines = listOf(
                            LineBox(
                                range = TextRange(0, text.length),
                                clusterRange = clusters.indices,
                                baseline = 18f,
                                top = 0f,
                                bottom = 24f,
                                naturalWidth = 72f,
                                adjustedWidth = 64f,
                                visualWidth = 72f,
                                hangingPunctuationAdvance = 8f,
                                endReason = LineEndReason.AutoWrap,
                            ),
                        ),
                    )
                }
            },
        )

        val image = ImageComposeScene(width = 120, height = 64) {
            Box(Modifier.fillMaxSize().background(Color.White).padding(8.dp)) {
                CjkText(
                    text = text,
                    modifier = Modifier.width(64.dp).onSizeChanged { measuredWidth = it.width },
                    textStyle = CjkTextStyle(fontSize = 16.sp),
                    overflow = TextOverflow.Clip,
                    measurer = measurer,
                )
            }
        }.use { scene -> scene.render().toComposeImageBitmap().toPixelMap() }

        var overhangInk = 0
        for (y in 0 until image.height) {
            for (x in 72 until 82) {
                val c = image[x, y]
                if (c.red < 0.5f && c.green < 0.5f && c.blue < 0.5f) overhangInk++
            }
        }

        assertEquals(64, measuredWidth)
        assertTrue(overhangInk > 0, "Expected hung punctuation ink beyond the measured 64px box")
    }

    @Test
    fun hangingPunctuationClipUsesItsFinalVisualEdgeOnlyWhenExplicitlyAuthorized() {
        val hanging = LineBox(
            range = TextRange(0, 2),
            clusterRange = 0..1,
            baseline = 18f,
            top = 0f,
            bottom = 24f,
            naturalWidth = 111f,
            adjustedWidth = 95f,
            visualWidth = 116f,
            hangingPunctuationAdvance = 16f,
        )

        assertEquals(116f, legalHangingPunctuationClipEdge(hanging, drawClipWidth = 100f))
        assertEquals(
            100f,
            legalHangingPunctuationClipEdge(
                hanging.copy(hangingPunctuationAdvance = 0f),
                drawClipWidth = 100f,
            ),
            "ordinary over-wide text must remain clipped",
        )
    }

    @Test
    fun clipOverflowDoesNotPaintOrdinaryUnwrappedTextPastWidth() {
        val image = ImageComposeScene(width = 260, height = 100) {
            Box(Modifier.fillMaxSize().background(Color.White).padding(8.dp)) {
                CjkText(
                    text = "中文中文中文中文中文中文中文中文",
                    modifier = Modifier.width(60.dp),
                    style = TextStyle(fontSize = 24.sp),
                    softWrap = false,
                    overflow = TextOverflow.Clip,
                )
            }
        }.use { scene -> scene.render().toComposeImageBitmap().toPixelMap() }

        var leakedInk = 0
        for (y in 0 until image.height) {
            for (x in 72 until image.width) {
                val c = image[x, y]
                if (c.red < 0.5f && c.green < 0.5f && c.blue < 0.5f) leakedInk++
            }
        }

        assertEquals(0, leakedInk, "TextOverflow.Clip leaked ordinary unwrapped text past the width")
    }

    @Test
    fun clipOverflowDoesNotPaintLaterLinesPastHeight() {
        val image = ImageComposeScene(width = 140, height = 180) {
            Box(Modifier.fillMaxSize().background(Color.White).padding(8.dp)) {
                CjkText(
                    text = "中文中文中文中文中文中文中文中文",
                    modifier = Modifier.width(80.dp).height(30.dp),
                    style = TextStyle(fontSize = 24.sp),
                    overflow = TextOverflow.Clip,
                )
            }
        }.use { scene -> scene.render().toComposeImageBitmap().toPixelMap() }

        var leakedInk = 0
        for (y in 42 until image.height) {
            for (x in 0 until image.width) {
                val c = image[x, y]
                if (c.red < 0.5f && c.green < 0.5f && c.blue < 0.5f) leakedInk++
            }
        }

        assertEquals(0, leakedInk, "TextOverflow.Clip leaked later lines past the height")
    }

    @Test
    fun composeTextReplacementMaxLinesReturnsVisibleLayoutResult() {
        var layout: LayoutResult? = null

        render("compose-maxlines-visible-result") {
            CjkText(
                text = "甲\n中文中文中文中文中文中文",
                modifier = Modifier.width(320.dp),
                style = TextStyle(fontSize = 24.sp),
                maxLines = 1,
                overflow = TextOverflow.Visible,
                onTextLayout = { layout = it },
            )
        }

        val result = layout ?: error("onTextLayout was not called")
        val line = result.lines.single()
        val visibleEnd = line.range.end
        assertEquals(LineEndReason.MandatoryBreak, line.endReason)
        assertEquals(line.indent + line.visualWidth + line.hyphenAdvance, result.size.width)
        // MaxLinesLineTruncation is an ENGINE decision: only the emitted line boxes
        // are capped; the result stays source-faithful (full clusters + full line
        // dump) and the cut itself is recorded instead of silently applied.
        val decision = result.debug.maxLinesDecision ?: error("expected maxLinesDecision")
        assertEquals(2, decision.laidOutLines)
        assertEquals(1, decision.visibleLines)
        assertEquals(2, result.debug.lineDecisions.size)
        assertTrue(result.clusters.any { it.range.start >= visibleEnd })
    }

    @Test
    fun maxLinesKeepsFontDecisionForVisibleSplitLatinCluster() {
        var layout: LayoutResult? = null
        val text = "internationalization 中文"

        render("compose-maxlines-latin-role") {
            CjkText(
                text = text,
                modifier = Modifier.width(120.dp),
                style = TextStyle(fontSize = 24.sp),
                maxLines = 1,
                overflow = TextOverflow.Visible,
                onTextLayout = { layout = it },
            )
        }

        val result = layout ?: error("onTextLayout was not called")
        val visibleLatin = result.clusters.firstOrNull { cluster ->
            cluster.text.any { it in 'A'..'Z' || it in 'a'..'z' }
        } ?: error("expected first visible line to include a Latin cluster: ${result.clusters}")
        assertTrue(
            result.debug.fontDecisions.any {
                it.role == "LatinText" &&
                    visibleLatin.range.start >= it.range.start &&
                    visibleLatin.range.end <= it.range.end
            },
            "visible Latin cluster lost its font decision: cluster=$visibleLatin font=${result.debug.fontDecisions}",
        )
    }

    @Test
    fun composeTextReplacementCanDisableSoftWrapAndReserveMinLines() {
        var wrapped: LayoutResult? = null
        var unwrapped: LayoutResult? = null
        var reserved: LayoutResult? = null
        val text = "中文中文中文中文中文 EnglishTypography"

        render("compose-softwrap") {
            CjkText(
                text = text,
                modifier = Modifier.width(150.dp),
                style = TextStyle(fontSize = 24.sp),
                onTextLayout = { wrapped = it },
            )
        }
        render("compose-no-softwrap") {
            CjkText(
                text = text,
                modifier = Modifier.width(150.dp),
                style = TextStyle(fontSize = 24.sp),
                softWrap = false,
                overflow = TextOverflow.Visible,
                onTextLayout = { unwrapped = it },
            )
        }
        var reservedBoxHeight = 0
        render("compose-min-lines") {
            CjkText(
                text = "短句。",
                modifier = Modifier.width(150.dp).onSizeChanged { reservedBoxHeight = it.height },
                style = TextStyle(fontSize = 24.sp),
                minLines = 3,
                onTextLayout = { reserved = it },
            )
        }

        assertTrue((wrapped?.lines?.size ?: 0) > 1, "expected wrapped text to use multiple lines")
        assertEquals(1, unwrapped?.lines?.size)
        // MinLinesHeightReservation is a NODE sizing concern: the LayoutResult stays
        // the natural single line; the composable box reserves 3 line heights.
        val reservedResult = reserved ?: error("onTextLayout was not called")
        assertEquals(1, reservedResult.lines.size)
        val lineHeight = reservedResult.lines.single().let { it.bottom - it.top }
        assertTrue(
            reservedBoxHeight >= (lineHeight * 3f).toInt(),
            "minLines must reserve 3 line heights, got $reservedBoxHeight for lineHeight=$lineHeight",
        )
    }

    @Test
    fun composeTextReplacementPreservesSourceMandatoryBreaks() {
        var layout: LayoutResult? = null

        render("compose-mandatory-breaks") {
            CjkText(
                text = "甲\n\n乙\n",
                modifier = Modifier.width(180.dp),
                style = TextStyle(fontSize = 24.sp),
                onTextLayout = { layout = it },
            )
        }

        val lines = layout?.lines.orEmpty()
        assertEquals(4, lines.size)
        assertEquals(
            listOf(
                LineEndReason.MandatoryBreak,
                LineEndReason.MandatoryBreak,
                LineEndReason.MandatoryBreak,
                LineEndReason.ParagraphEnd,
            ),
            lines.map { it.endReason },
        )
        assertEquals(0f, lines[1].visualWidth)
    }
}
