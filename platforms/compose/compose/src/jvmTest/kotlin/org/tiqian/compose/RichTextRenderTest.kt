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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.ui.use
import org.jetbrains.skia.EncodedImageFormat
import org.tiqian.core.LayoutResult
import org.tiqian.core.RichTextRole
import org.tiqian.core.TextRange
import org.tiqian.core.getBoundingBoxes
import org.tiqian.core.getCursorRect
import org.tiqian.core.positionedClusters
import org.tiqian.core.positionedRichTextSegments
import org.tiqian.core.resolvedBackgroundCornerRadii
import org.tiqian.core.toReplayIndex
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
        ImageComposeScene(width = 760, height = 180) {
            Box(Modifier.fillMaxSize().background(Color.White).padding(16.dp)) {
                CjkText(
                    buildAnnotatedString {
                        append("普通")
                        withStyle(SpanStyle(background = Color(0xFFFFEA00))) { append("高亮 A B 背景") }
                        append("，")
                        withStyle(SpanStyle(color = Color.Blue, textDecoration = TextDecoration.Underline)) {
                            append("蓝色下划线")
                        }
                        append("，")
                        inlineCode { append("code") }
                    },
                    modifier = Modifier.width(720.dp),
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
    fun explicitInlineBackgroundPaintsRoundedCorners() {
        var layout: LayoutResult? = null
        val backgrounds = listOf(
            CjkInlineBackground(
                range = androidx.compose.ui.text.TextRange(0, 2),
                color = Color(0xFFFFE58F),
            ),
            CjkInlineBackground(
                range = androidx.compose.ui.text.TextRange(2, 8),
                color = Color(0xFFFFE58F),
            ),
        )
        val image = ImageComposeScene(width = 420, height = 120) {
            Box(Modifier.fillMaxSize().background(Color.White).padding(12.dp)) {
                CjkText(
                    text = androidx.compose.ui.text.AnnotatedString("高亮中文 A B"),
                    textStyle = CjkTextStyle(fontSize = 40.sp),
                    inlineBackgrounds = backgrounds,
                    onTextLayout = { layout = it },
                )
            }
        }.use { scene -> scene.render() }

        File("build/reports/tiqian-compose").mkdirs()
        image.encodeToData(EncodedImageFormat.PNG)?.bytes?.let {
            File("build/reports/tiqian-compose/rounded-background.png").writeBytes(it)
        }
        val pixels = image.toComposeImageBitmap().toPixelMap()
        val yellowByRow = (0 until pixels.height).map { y ->
            (0 until pixels.width).count { x ->
                val color = pixels[x, y]
                color.red > 0.8f && color.green > 0.65f && color.blue < 0.7f
            }
        }
        val paintedRows = yellowByRow.filter { it > 0 }
        val segments = (layout ?: error("onTextLayout not called"))
            .toReplayIndex(backgrounds.map { it.toCore(Density(1f)) })
            .richTextBackgroundSegments

        assertEquals(2, segments.size)
        assertEquals(segments[0].top, segments[1].top, absoluteTolerance = 0.01f)
        assertEquals(segments[0].bottom, segments[1].bottom, absoluteTolerance = 0.01f)
        assertEquals(1f, segments[1].left - segments[0].right, absoluteTolerance = 0.01f)

        assertTrue(paintedRows.isNotEmpty(), "expected a painted inline background")
        assertTrue(
            paintedRows.first() < paintedRows.max(),
            "expected the first painted row to be inset by rounded corners",
        )
        assertTrue(
            paintedRows.last() < paintedRows.max(),
            "expected the last painted row to be inset by rounded corners",
        )
    }

    @Test
    fun inlineCodePaddingIsInsideTheBoxWhileOuterGapUsesCjkWesternSpacing() {
        var layout: LayoutResult? = null
        val background = CjkInlineBackground(
            range = androidx.compose.ui.text.TextRange(1, 5),
            color = Color(0xFFF1F3F5),
            horizontalPadding = 4.dp,
        )
        ImageComposeScene(width = 320, height = 96) {
            Box(Modifier.fillMaxSize().background(Color.White).padding(12.dp)) {
                CjkText(
                    text = androidx.compose.ui.text.AnnotatedString("中code中"),
                    textStyle = CjkTextStyle(fontSize = 24.sp),
                    inlineBackgrounds = listOf(background),
                    onTextLayout = { layout = it },
                )
            }
        }.use { scene -> scene.render() }

        val result = layout ?: error("onTextLayout not called")
        val inlineBox = result.debug.inlineBoxDecisions.single()
        assertEquals(TextRange(1, 5), inlineBox.range)
        assertEquals(4f, inlineBox.inlineStart, 0.01f)
        assertEquals(4f, inlineBox.inlineEnd, 0.01f)
        assertEquals("Narrow", inlineBox.outerSpacing)
        assertEquals(2, result.debug.autoSpaceDecisions.size)
        assertEquals(
            setOf(
                "InlineBoxOuterAutoSpace:leading-W-N",
                "InlineBoxOuterAutoSpace:trailing-N-W",
            ),
            result.debug.autoSpaceDecisions.map { it.reason }.toSet(),
        )
        assertTrue(result.debug.autoSpaceDecisions.all { it.boundaryRole == "InlineBox.Narrow" })
    }

    @Test
    fun markdownParagraphJustifiesAroundWrappedInlineCodeAndUsesContinuationCorners() {
        var layout: LayoutResult? = null
        val annotated = buildAnnotatedString {
            append("准备发布前，请先在终端运行")
            inlineCode { append("./gradlew :demo:android:assembleRelease") }
            append("，然后打开输出目录核对签名与版本号；若任务失败，就根据报告里的诊断信息逐项处理。")
        }
        val image = ImageComposeScene(width = 420, height = 260) {
            Box(Modifier.fillMaxSize().background(Color(0xFFF8F8F6)).padding(24.dp)) {
                CjkText(
                    text = annotated,
                    modifier = Modifier.width(372.dp),
                    textStyle = CjkTextStyle(fontSize = 22.sp, lineHeight = 1.65.em),
                    onTextLayout = { layout = it },
                )
            }
        }.use { scene -> scene.render() }

        File("build/reports/tiqian-compose").mkdirs()
        image.encodeToData(EncodedImageFormat.PNG)?.bytes?.let {
            File("build/reports/tiqian-compose/markdown-inline-code-real-effect.png").writeBytes(it)
        }

        val density = Density(1f)
        val spans = annotated.cjkRichTextSpans(inlineCodePaint = defaultInlineCodePaint(density))
        val result = layout ?: error("onTextLayout not called")
        val codeRanges = spans.filter { it.role == org.tiqian.core.InlineCode.instance }.map { it.range }
        assertTrue(
            result.debug.autoSpaceDecisions.any {
                it.reason == "InlineBoxOuterAutoSpace:leading-W-N"
            },
            "inline-code background must keep its outer sino-western gap: ${result.debug.autoSpaceDecisions}",
        )
        val wrappedCodeLines = result.lines.filter { line ->
            codeRanges.any { code -> line.range.end > code.start && line.range.end < code.end }
        }
        assertTrue(wrappedCodeLines.isNotEmpty(), "expected an inline-code technical break")
        assertTrue(
            result.debug.lineDecisions.any { decision ->
                wrappedCodeLines.any { it.range == decision.range } &&
                    decision.notes.contains("technical-break:Emergency")
            },
            "expected the zero-threshold policy to reach a rightmost emergency cut: " +
                "lines=${result.lines} breaks=${result.debug.breakOpportunityDecisions}",
        )
        assertTrue(
            wrappedCodeLines.any { line ->
                result.debug.justificationDecisions
                    .firstOrNull { it.lineRange == line.range }
                    ?.allocations
                    ?.isNotEmpty() == true
            },
            "expected ordinary paragraph spacing outside inline code to remain justified",
        )
        wrappedCodeLines.forEach { line ->
            val adjustment = result.debug.justificationDecisions.firstOrNull { it.lineRange == line.range }
            if (adjustment == null) {
                assertEquals(352f, line.visualWidth, 0.01f, "compressed technical line must fill measure")
                assertTrue(
                    line.debug.repair?.startsWith("PushIn:") == true || line.naturalWidth == 352f,
                    "a non-justified wrapped technical line must carry its compression repair or exactly match measure: $line",
                )
            } else {
                assertEquals(
                    0f,
                    adjustment.deficitAfter,
                    0.01f,
                    "${line.range}: '${annotated.text.substring(line.range.start, line.range.end)}' $adjustment",
                )
            }
        }
        result.debug.justificationDecisions.flatMap { it.allocations }.forEach { allocation ->
            val insideCode = codeRanges.any { code ->
                allocation.clusterRange.start >= code.start && allocation.clusterRange.end <= code.end
            }
            if (insideCode) {
                val target = result.clusters.first { it.range == allocation.clusterRange }
                val exitsCodeAfterTarget = codeRanges.any { code -> target.range.end == code.end }
                assertTrue(
                    target.text.all(Char::isWhitespace) || exitsCodeAfterTarget ||
                        (
                            allocation.kind == "EmergencyGraphemeTracking" &&
                                allocation.reason.startsWith("TerminalTechnicalEmergencyTracking")
                            ),
                    "technical justification must use source whitespace or an authorized terminal gap: $allocation",
                )
            }
        }
        val segments = result
            .toReplayIndex(spans)
            .richTextBackgroundSegments
            .filter { it.span.role == org.tiqian.core.InlineCode.instance }
        assertTrue(segments.size >= 2, "expected wrapped inline code, got ${segments.size} segment")
        val firstCodeSegment = segments.first()
        val positioned = result.positionedClusters()
        val precedingBodyCluster = positioned
            .last { it.lineIndex == firstCodeSegment.lineIndex && it.range.end == firstCodeSegment.range.start }
        assertTrue(
            firstCodeSegment.left - precedingBodyCluster.right >= 22f * 0.125f - 0.01f,
            "inline-code background painted over its outer sino-western gap: " +
                "bodyRight=${precedingBodyCluster.right}, boxLeft=${firstCodeSegment.left}",
        )

        val first = segments.first().resolvedBackgroundCornerRadii()
        val middle = segments.getOrNull(1)?.takeIf { segments.size > 2 }?.resolvedBackgroundCornerRadii()
        val last = segments.last().resolvedBackgroundCornerRadii()
        assertEquals(3f, first.topLeft)
        assertEquals(1f, first.topRight)
        middle?.let {
            assertEquals(1f, it.topLeft)
            assertEquals(1f, it.topRight)
        }
        assertEquals(1f, last.topLeft)
        assertEquals(3f, last.topRight)
    }

    @Test
    fun highlightInlineCodeAndKeyboardReuseOneVerticalBoxGeometry() {
        var layout: LayoutResult? = null
        val boxes = listOf(
            CjkInlineBackground(
                range = androidx.compose.ui.text.TextRange(0, 2),
                color = Color(0xFFFFE58F),
            ),
            CjkInlineBackground(
                range = androidx.compose.ui.text.TextRange(3, 7),
                color = Color(0xFFF1F3F5),
                horizontalPadding = 4.dp,
                metricPolicy = CjkInlineBackgroundMetricPolicy.ParagraphTextStyle,
            ),
            CjkInlineBackground(
                range = androidx.compose.ui.text.TextRange(8, 12),
                color = Color(0xFF7A828A),
                horizontalPadding = 4.dp,
                drawStyle = CjkInlineBackgroundDrawStyle.Border(1.dp),
                metricPolicy = CjkInlineBackgroundMetricPolicy.ParagraphTextStyle,
            ),
        )
        val image = ImageComposeScene(width = 420, height = 112) {
            Box(Modifier.fillMaxSize().background(Color.White).padding(12.dp)) {
                CjkText(
                    text = buildAnnotatedString {
                        append("高亮 code Ctrl")
                        addStyle(
                            SpanStyle(fontFamily = FontFamily.Monospace, fontSize = 0.875.em),
                            3,
                            7,
                        )
                        addStyle(
                            SpanStyle(fontFamily = FontFamily.Monospace, fontSize = 0.875.em),
                            8,
                            12,
                        )
                    },
                    textStyle = CjkTextStyle(fontSize = 32.sp),
                    inlineBackgrounds = boxes,
                    onTextLayout = { layout = it },
                )
            }
        }.use { scene -> scene.render() }

        File("build/reports/tiqian-compose").mkdirs()
        image.encodeToData(EncodedImageFormat.PNG)?.bytes?.let {
            File("build/reports/tiqian-compose/inline-box-styles.png").writeBytes(it)
        }

        val segments = (layout ?: error("onTextLayout not called"))
            .toReplayIndex(boxes.map { it.toCore(Density(1f)) })
            .richTextBackgroundSegments
        assertEquals(3, segments.size)
        assertEquals(segments[0].height, segments[1].height, absoluteTolerance = 0.01f)
        assertEquals(segments[0].height, segments[2].height, absoluteTolerance = 0.01f)
        assertEquals(segments[0].top, segments[1].top, absoluteTolerance = 0.01f)
        assertEquals(segments[0].top, segments[2].top, absoluteTolerance = 0.01f)
        assertEquals(segments[0].bottom, segments[1].bottom, absoluteTolerance = 0.01f)
        assertEquals(segments[0].bottom, segments[2].bottom, absoluteTolerance = 0.01f)
        assertEquals(3f, segments[0].span.paint.background.verticalPadding)
        assertEquals(3f, segments[1].span.paint.background.verticalPadding)
        assertEquals(3f, segments[2].span.paint.background.verticalPadding)

        val pixels = image.toComposeImageBitmap().toPixelMap()
        val borderPixels = (0 until pixels.height).sumOf { y ->
            (0 until pixels.width).count { x ->
                val color = pixels[x, y]
                color.red in 0.35f..0.65f && color.green in 0.35f..0.65f && color.blue in 0.35f..0.65f
            }
        }
        assertTrue(borderPixels > 30, "expected outlined keyboard box pixels, got $borderPixels")
    }

    @Test
    fun dottedUnderlinePaintsSeparatedRoundMarksOnTheTiqianLine() {
        var layout: LayoutResult? = null
        val decoration = CjkInlineDecoration(
            range = androidx.compose.ui.text.TextRange(0, 5),
            style = CjkInlineDecorationStyle.DottedUnderline(
                color = Color.Red,
                dotDiameter = 2.dp,
                gapLength = 5.dp,
            ),
        )
        val image = ImageComposeScene(width = 260, height = 120) {
            Box(Modifier.fillMaxSize().background(Color.White).padding(12.dp)) {
                CjkText(
                    text = androidx.compose.ui.text.AnnotatedString("CLREQ"),
                    textStyle = CjkTextStyle(fontSize = 40.sp),
                    inlineDecorations = listOf(decoration),
                    onTextLayout = { layout = it },
                )
            }
        }.use { scene -> scene.render() }

        File("build/reports/tiqian-compose").mkdirs()
        image.encodeToData(EncodedImageFormat.PNG)?.bytes?.let {
            File("build/reports/tiqian-compose/dotted-underline.png").writeBytes(it)
        }
        val result = layout ?: error("onTextLayout not called")
        result.toReplayIndex(listOf(decoration.toCore(Density(1f))))
            .richTextDecorationSegments.single()
        val pixels = image.toComposeImageBitmap().toPixelMap()
        val redAt = { x: Int, y: Int ->
            val color = pixels[x, y]
            color.red > 0.7f && color.green < 0.4f && color.blue < 0.4f
        }
        val y = (0 until pixels.height).maxBy { row ->
            (0 until pixels.width).count { x -> redAt(x, row) }
        }
        val samples = (0 until pixels.width).map { x -> redAt(x, y) }
        val paintedRuns = samples.zipWithNext().count { (left, right) -> !left && right }

        assertTrue(samples.any { it }, "expected dotted underline pixels")
        assertTrue(paintedRuns >= 3, "expected separated dots, got $paintedRuns painted runs")
    }

    @Test
    fun dashedUnderlineFitsCompleteDashesToBothDecorationEdges() {
        var layout: LayoutResult? = null
        val decoration = CjkInlineDecoration(
            range = androidx.compose.ui.text.TextRange(0, 4),
            style = CjkInlineDecorationStyle.DashedUnderline(
                color = Color.Red,
                strokeWidth = 2.dp,
                dashLength = 8.dp,
                gapLength = 5.dp,
            ),
        )
        val image = ImageComposeScene(width = 260, height = 120) {
            Box(Modifier.fillMaxSize().background(Color.White).padding(12.dp)) {
                CjkText(
                    text = androidx.compose.ui.text.AnnotatedString("虚线标记"),
                    textStyle = CjkTextStyle(fontSize = 40.sp),
                    inlineDecorations = listOf(decoration),
                    onTextLayout = { layout = it },
                )
            }
        }.use { scene -> scene.render() }

        File("build/reports/tiqian-compose").mkdirs()
        image.encodeToData(EncodedImageFormat.PNG)?.bytes?.let {
            File("build/reports/tiqian-compose/dashed-underline.png").writeBytes(it)
        }
        val result = layout ?: error("onTextLayout not called")
        val segment = result.toReplayIndex(listOf(decoration.toCore(Density(1f))))
            .richTextDecorationSegments.single()
        val pixels = image.toComposeImageBitmap().toPixelMap()
        val redAt = { x: Int, y: Int ->
            val color = pixels[x, y]
            color.red > 0.7f && color.green < 0.4f && color.blue < 0.4f
        }
        val y = (0 until pixels.height).maxBy { row ->
            (0 until pixels.width).count { x -> redAt(x, row) }
        }
        val samples = (0 until pixels.width).map { x -> redAt(x, y) }
        val paintedRuns = samples.zipWithNext().count { (left, right) -> !left && right }
        val leftEdge = (12f + segment.left).toInt()
        val rightEdge = (12f + segment.right).toInt()

        assertTrue(paintedRuns >= 4, "expected fitted separated dashes, got $paintedRuns painted runs")
        assertTrue(
            (leftEdge..leftEdge + 2).any { x -> redAt(x.coerceIn(0, pixels.width - 1), y) },
            "expected a complete first dash at the decoration left edge",
        )
        assertTrue(
            (rightEdge - 2..rightEdge).any { x -> redAt(x.coerceIn(0, pixels.width - 1), y) },
            "expected a complete final dash at the decoration right edge",
        )
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
            .single { it.span.role == org.tiqian.core.Underline.instance }

        assertEquals(TextRange(0, "template".length), underline.range)
        assertEquals(templateRight, underline.right, absoluteTolerance = 0.01f)
        assertEquals(punctuationCluster.left, underline.right, absoluteTolerance = 0.01f)
    }

    @Test
    fun underlineIncludingPunctuationTrimsOpeningAndClosingGlue() {
        val text = buildAnnotatedString {
            append("甲")
            withStyle(SpanStyle(textDecoration = TextDecoration.Underline)) {
                append("（乙）")
            }
            append("丙")
        }
        val result = ParagraphMeasurer(ExplainableStubParagraphLayoutEngine()).measure(
            text = text,
            constraints = org.tiqian.core.LayoutConstraints(maxWidth = 400f),
            density = Density(1f),
            textStyle = CjkTextStyle(fontSize = 16.sp),
        )
        val underlineSpan = text.cjkRichTextSpans().single { it.role == org.tiqian.core.Underline.instance }
        val replayIndex = result.toReplayIndex(listOf(underlineSpan))
        val occupied = replayIndex.richTextSegments.single()
        val underline = replayIndex.richTextDecorationSegments.single()
        val openingGeometry = result.debug.geometryDecisions.single { it.range == TextRange(1, 2) }
        val closingGeometry = result.debug.geometryDecisions.single { it.range == TextRange(3, 4) }
        val leadingGlue = openingGeometry.leadingGlueNatural - openingGeometry.leadingGlueConsumed
        val trailingGlue = closingGeometry.trailingGlueNatural - closingGeometry.trailingGlueConsumed

        assertTrue(leadingGlue > 0f, "test requires remaining opening-punctuation glue")
        assertTrue(trailingGlue > 0f, "test requires remaining closing-punctuation glue")
        assertEquals(occupied.left + leadingGlue, underline.left, absoluteTolerance = 0.01f)
        assertEquals(occupied.right - trailingGlue, underline.right, absoluteTolerance = 0.01f)
    }

    @Test
    fun underlineDoesNotOvershootCompressedLineEndPunctuation() {
        // Real shaping: a full-width comma compressed to half width at a line end keeps its
        // full-width glyph advance, which is wider than the cluster's occupied box. The underline
        // must hug the occupied box (the line's visual edge), not the glyph advance — otherwise it
        // juts a stray stub into the trimmed half (划线凭空凸出来一条).
        var layout: LayoutResult? = null
        val text = buildAnnotatedString {
            withStyle(SpanStyle(textDecoration = TextDecoration.Underline)) {
                append("甲乙（template）丙，丁戊己庚辛")
            }
        }
        ImageComposeScene(width = 240, height = 260) {
            Box(Modifier.fillMaxSize().background(Color.White)) {
                CjkText(
                    text,
                    modifier = Modifier.width(150.dp),
                    textStyle = CjkTextStyle(fontSize = 24.sp),
                    onTextLayout = { layout = it },
                )
            }
        }.use { it.render() }
        val result = layout ?: error("onTextLayout not called")
        val comma = result.positionedClusters().single { text.text.substring(it.range.start, it.range.end) == "，" }
        assertTrue(comma.lineIndex in result.lines.indices, "comma should be placed")
        val commaLine = result.lines[comma.lineIndex]
        // The comma sits at the end of its line and was compressed: its occupied box is the visual edge.
        assertEquals(commaLine.indent + commaLine.visualWidth, comma.right, absoluteTolerance = 0.5f)
        val decoration = result.toReplayIndex(text.cjkRichTextSpans())
            .richTextDecorationSegments.single { it.lineIndex == comma.lineIndex }
        assertTrue(
            decoration.right <= commaLine.indent + commaLine.visualWidth + 0.5f,
            "underline overshoots the compressed comma: ${decoration.right} > ${commaLine.indent + commaLine.visualWidth}",
        )
    }

    @Test
    fun caretInsideProportionalLatinWordFollowsGlyphAdvances() {
        // "template" is one cluster; linear interpolation over its box would space every letter
        // equally. Real per-glyph stops must make narrow letters (t, l) narrower than wide ones
        // (m), so consecutive caret gaps are not uniform.
        var layout: LayoutResult? = null
        val text = buildAnnotatedString { append("template") }
        ImageComposeScene(width = 320, height = 120) {
            Box(Modifier.fillMaxSize().background(Color.White)) {
                CjkText(
                    text,
                    modifier = Modifier.width(300.dp),
                    textStyle = CjkTextStyle(fontSize = 24.sp),
                    onTextLayout = { layout = it },
                )
            }
        }.use { it.render() }
        val result = layout ?: error("onTextLayout not called")
        val x = (0..text.length).map { result.getCursorRect(it).left }
        val gaps = (1..text.length).map { x[it] - x[it - 1] }
        // 't' is narrower than 'm': a linear split would make every gap identical.
        val tWidth = gaps[0]
        val mWidth = gaps[2]
        assertTrue(mWidth > tWidth + 1f, "expected proportional letter widths, got t=$tWidth m=$mWidth")
    }
}

private const val INTERLINEAR_UNDERLINE_OFFSET_EM_FOR_TEST = 0.18f
