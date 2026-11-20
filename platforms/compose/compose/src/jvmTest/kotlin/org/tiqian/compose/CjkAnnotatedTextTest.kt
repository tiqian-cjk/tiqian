package org.tiqian.compose

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import org.tiqian.core.DecorationKind
import org.tiqian.core.InlineAttachment
import org.tiqian.core.LineBreakPolicy
import org.tiqian.core.RichTextRole
import org.tiqian.core.RichTextBackgroundDrawStyle
import org.tiqian.core.RichTextLinePattern
import org.tiqian.core.RichTextSpan
import org.tiqian.core.RubyKind
import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import org.tiqian.core.layoutAutoSpaceSuppressedRanges
import org.tiqian.core.layoutInlineBoxes
import org.tiqian.core.layoutLineBreakSpans
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The attributed-text builders compute decoration ranges from the builder
 * structure — no hand-counted source offsets.
 */
class CjkAnnotatedTextTest {

    @Test
    fun emphasisBuilderComputesRangeFromStructure() {
        val text = buildAnnotatedString {
            append("他强调：")
            emphasis { append("豆子新鲜最要紧") }
            append("，烘焙其次。")
        }
        assertEquals("他强调：豆子新鲜最要紧，烘焙其次。", text.text) // source unchanged
        val decos = text.cjkDecorations()
        assertEquals(1, decos.size)
        assertEquals(DecorationKind.Emphasis, decos[0].kind)
        assertEquals(TextRange(4, 11), decos[0].range) // 豆子新鲜最要紧
    }

    @Test
    fun multipleDecorationKindsCoexist() {
        val text = buildAnnotatedString {
            append("悼念：")
            mourning { append("张三") }
            append("，读过")
            bookTitle { append("红楼梦") }
            append("。")
        }
        val byKind = text.cjkDecorations().associateBy { it.kind }
        assertEquals(TextRange(3, 5), byKind.getValue(DecorationKind.Mourning).range)
        assertEquals(TextRange(8, 11), byKind.getValue(DecorationKind.BookTitle).range)
    }

    @Test
    fun styleSpansFlattenSizeWeightAndGenericFamily() {
        val base = TextStyle(fontSize = 20f)
        val text = buildAnnotatedString {
            append("正")
            withStyle(SpanStyle(fontWeight = FontWeight.Bold, fontSize = 1.5.em, fontFamily = FontFamily.Serif)) {
                append("强调")
            }
            append("文")
        }
        val spans = text.cjkStyleSpans(base, Density(1f))
        val span = spans.first { it.range.start == 1 }
        assertEquals(3, span.range.end) // 强调
        assertEquals(30f, span.style.fontSize) // 1.5 × 20 (em relative to base)
        assertEquals(700, span.style.fontWeight)
        assertEquals(listOf("serif"), span.style.fontFamilies) // generic token, role-resolved later
    }

    @Test
    fun styleSpansLowerBaselineShiftAgainstResolvedFontSize() {
        val base = TextStyle(fontSize = 20f)
        val text = buildAnnotatedString {
            append("正文")
            withStyle(SpanStyle(fontSize = 0.75.em, baselineShift = BaselineShift.Superscript)) {
                append("[1]")
            }
        }

        val span = text.cjkStyleSpans(base, Density(1f)).single()

        assertEquals(TextRange(2, 5), span.range)
        assertEquals(15f, span.style.fontSize)
        assertEquals(-BaselineShift.Superscript.multiplier * 15f, span.style.baselineShift, 0.001f)
    }

    @Test
    fun inlineAttachmentCreatesAnExactLayoutSpanWithoutChangingSource() {
        val text = buildAnnotatedString {
            append("正文[1]后文")
            addCjkInlineAttachment(InlineAttachment.Previous, start = 2, end = 5)
        }

        val span = text.cjkStyleSpans(TextStyle(fontSize = 20f), Density(1f)).single()

        assertEquals("正文[1]后文", text.text)
        assertEquals(TextRange(2, 5), span.range)
        assertEquals(InlineAttachment.Previous, span.style.inlineAttachment)
        assertTrue(2 in text.cjkSourceBoundaries())
        assertTrue(5 in text.cjkSourceBoundaries())
    }

    @Test
    fun colorSpansExtractedFromSpanStyle() {
        val text = buildAnnotatedString {
            append("黑")
            withStyle(SpanStyle(color = Color.Red)) { append("红字") }
            append("黑")
        }
        val spans = text.cjkColorSpans()
        assertEquals(1, spans.size)
        assertEquals(1, spans[0].start)
        assertEquals(3, spans[0].end)
        assertEquals(Color.Red.toArgb(), spans[0].argb)
    }

    @Test
    fun baseLinkStyleOverridesAuthoredSpansForRendering() {
        val text = buildAnnotatedString {
            withStyle(SpanStyle(color = Color.Red)) {
                withLink(
                    LinkAnnotation.Url(
                        url = "https://example.com",
                        styles = TextLinkStyles(
                            style = SpanStyle(color = Color.Blue, fontWeight = FontWeight.Bold),
                        ),
                    ),
                ) {
                    append("链接")
                }
            }
        }

        val renderText = text.withBaseLinkStyles()

        assertEquals(Color.Blue.toArgb(), renderText.cjkColorSpans().last().argb)
        assertEquals(700, renderText.cjkStyleSpans(TextStyle(), Density(1f)).single().style.fontWeight)
        assertEquals(1, renderText.getLinkAnnotations(0, renderText.length).size)
    }

    @Test
    fun richTextSpansExtractBackgroundAndTextDecorations() {
        val text = buildAnnotatedString {
            append("前")
            withStyle(
                SpanStyle(
                    color = Color.Blue,
                    background = Color.Yellow,
                    textDecoration = TextDecoration.Underline + TextDecoration.LineThrough,
                ),
            ) {
                append("样式")
            }
            append("后")
        }

        val spans = text.cjkRichTextSpans(adjacentSameStyleClearance = 1.5f)

        assertEquals(
            org.tiqian.core.Background.instance,
            spans.first { it.role == org.tiqian.core.Background.instance }.role,
        )
        assertEquals(Color.Yellow.toArgb(), spans.first { it.role == org.tiqian.core.Background.instance }.paint.argb)
        assertEquals(Color.Blue.toArgb(), spans.first { it.role == org.tiqian.core.Underline.instance }.paint.argb)
        assertEquals(Color.Blue.toArgb(), spans.first { it.role == org.tiqian.core.LineThrough.instance }.paint.argb)
        assertEquals(TextRange(1, 3), spans.first { it.role == org.tiqian.core.Underline.instance }.range)
        assertTrue(spans.all { it.paint.adjacentSameStyleClearance == 1.5f })
    }

    @Test
    fun linkAndInlineCodeRolesKeepSourceRanges() {
        val text = buildAnnotatedString {
            append("读")
            withLink(LinkAnnotation.Url("https://example.com")) { append("链接") }
            append("与")
            inlineCode { append("code") }
        }

        val rich = text.cjkRichTextSpans()
        val link = rich.first { it.role is org.tiqian.core.Link }
        val code = rich.first { it.role == org.tiqian.core.InlineCode.instance }
        val style = text.cjkStyleSpans(TextStyle(), Density(1f)).first { it.range == code.range }

        assertEquals("读链接与code", text.text)
        assertEquals(TextRange(1, 3), link.range)
        assertEquals(org.tiqian.core.Link("https://example.com"), link.role)
        assertEquals(TextRange(4, 8), code.range)
        assertEquals(listOf("monospace"), style.style.fontFamilies)
        assertEquals(14f, style.style.fontSize)

        // LinkAddressDisplayGate: "链接" is not the address, so only the code range
        // takes the technical break policy.
        val breakSpans = rich.layoutLineBreakSpans(text.text)
        assertEquals(listOf(code.range), breakSpans.map { it.range })
        assertTrue(breakSpans.all { it.policy == LineBreakPolicy.ProgressiveTechnical })
    }

    @Test
    fun linkDisplayingItsOwnAddressKeepsTheTechnicalBreakPolicy() {
        val text = buildAnnotatedString {
            append("见")
            withLink(LinkAnnotation.Url("https://example.com/a")) { append("https://example.com/a") }
            append("与")
            withLink(LinkAnnotation.Url("https://example.com/b")) { append("example.com/b") }
            append("与")
            withLink(LinkAnnotation.Url("https://example.com")) { append("示例站") }
        }

        val rich = text.cjkRichTextSpans()
        val breakSpans = rich.layoutLineBreakSpans(text.text)
        assertEquals(
            listOf(TextRange(1, 22), TextRange(23, 36)),
            breakSpans.map { it.range },
        )
    }

    @Test
    fun inlineCodeAndTechnicalRangesSuppressInternalAutoSpace() {
        val text = buildAnnotatedString {
            append("跑")
            inlineCode { append("print你好") }
            append("完")
            val technicalStart = length
            append("Ctrl")
            addTechnicalInlineAnnotation(technicalStart, length)
            append("与")
            withLink(LinkAnnotation.Url("https://example.com")) { append("链接") }
        }

        val rich = text.cjkRichTextSpans()
        assertEquals(
            listOf(TextRange(1, 8), TextRange(9, 13)),
            rich.layoutAutoSpaceSuppressedRanges(),
        )
    }

    @Test
    fun rendererOwnedTechnicalInlineHasNoPaintAndInteractionOnlyClickableIsNotALink() {
        val text = buildAnnotatedString {
            append("中")
            val technicalStart = length
            append("Ctrl")
            addTechnicalInlineAnnotation(technicalStart, length)
            append("与")
            val footnoteStart = length
            withLink(LinkAnnotation.Clickable(tag = "footnote", linkInteractionListener = {})) {
                append("[1]")
            }
            addCjkInteractionOnlyAnnotation(footnoteStart, length)
            append("及")
            withLink(LinkAnnotation.Clickable(tag = "generic", linkInteractionListener = {})) {
                append("action")
            }
        }

        val rich = text.cjkRichTextSpans()
        val technical = rich.single { it.role == org.tiqian.core.TechnicalInline.instance }
        val link = rich.single { it.role is org.tiqian.core.Link }

        assertEquals(TextRange(1, 5), technical.range)
        assertEquals(TextRange(10, 16), link.range)
        assertEquals(org.tiqian.core.Link("generic"), link.role)
        assertTrue(technical.paint.background.horizontalPadding == 0f)
        assertTrue(rich.layoutInlineBoxes().isEmpty())
        // LinkAddressDisplayGate: the clickable's tag is not its visible text, so only
        // the technical range takes the break policy.
        assertEquals(
            listOf(TextRange(1, 5)),
            rich.layoutLineBreakSpans(text.text).map { it.range },
        )
        assertTrue(TextRange(6, 9) !in rich.layoutLineBreakSpans(text.text).map { it.range })
    }

    @Test
    fun dashedUnderlineLowersToTheNormalUnderlineRole() {
        val span = CjkInlineDecoration(
            range = androidx.compose.ui.text.TextRange(1, 3),
            style = CjkInlineDecorationStyle.DashedUnderline(
                color = Color.Red,
                strokeWidth = 1.dp,
                dashLength = 6.dp,
                gapLength = 4.dp,
            ),
        ).toCore(Density(2f))

        assertEquals(TextRange(1, 3), span.range)
        assertEquals(org.tiqian.core.Underline.instance, span.role)
        assertEquals(Color.Red.toArgb(), span.paint.argb)
        assertEquals(
            org.tiqian.core.Dashed(strokeWidth = 2f, dashLength = 12f, gapLength = 8f),
            span.paint.linePattern,
        )
        assertEquals(2f, span.paint.adjacentSameStyleClearance)
    }

    @Test
    fun roundedBackgroundLowersUniformMetricGeometry() {
        val span = CjkInlineBackground(
            range = androidx.compose.ui.text.TextRange(1, 4),
            color = Color.Yellow,
            verticalPadding = 1.dp,
            cornerRadius = 2.dp,
        ).toCore(Density(2f))

        assertEquals(TextRange(1, 4), span.range)
        assertEquals(org.tiqian.core.Background.instance, span.role)
        assertEquals(Color.Yellow.toArgb(), span.paint.argb)
        assertEquals(0f, span.paint.background.horizontalPadding)
        assertEquals(2f, span.paint.background.verticalPadding)
        assertEquals(4f, span.paint.background.cornerRadius)
        assertEquals(4f, span.paint.background.continuationCornerRadius)
        assertEquals(2f, span.paint.adjacentSameStyleClearance)
        assertEquals(
            org.tiqian.core.RichTextBackgroundMetricPolicy.UniformTextStyle,
            span.paint.background.metricPolicy,
        )
    }

    @Test
    fun outlinedBackgroundKeepsItsStrokeInsideTheSameBoxGeometry() {
        val span = CjkInlineBackground(
            range = androidx.compose.ui.text.TextRange(1, 4),
            color = Color.Gray,
            horizontalPadding = 4.dp,
            drawStyle = CjkInlineBackgroundDrawStyle.Border(1.dp),
        ).toCore(Density(2f))

        assertEquals(8f, span.paint.background.horizontalPadding)
        assertEquals(
            org.tiqian.core.Border(strokeWidth = 2f),
            span.paint.background.drawStyle,
        )
    }

    @Test
    fun inlineCodeDefaultsReserveACompactRoundedBox() {
        val paint = defaultInlineCodePaint(Density(2f))
        val span = RichTextSpan(TextRange(1, 5), org.tiqian.core.InlineCode.instance, paint)

        assertEquals(8f, paint.background.horizontalPadding)
        assertEquals(6f, paint.background.verticalPadding)
        assertEquals(6f, paint.background.cornerRadius)
        assertEquals(2f, paint.background.continuationCornerRadius)
        assertEquals(2f, paint.adjacentSameStyleClearance)
        assertEquals(
            org.tiqian.core.RichTextBackgroundMetricPolicy.UniformParagraphStyle,
            paint.background.metricPolicy,
        )
        assertEquals(
            org.tiqian.core.InlineBoxSpan(TextRange(1, 5), inlineStart = 8f, inlineEnd = 8f),
            listOf(span).layoutInlineBoxes().single(),
        )
    }

    @Test
    fun dottedUnderlineLowersToTheNormalUnderlineRole() {
        val span = CjkInlineDecoration(
            range = androidx.compose.ui.text.TextRange(0, 5),
            style = CjkInlineDecorationStyle.DottedUnderline(
                dotDiameter = 1.dp,
                gapLength = 2.dp,
            ),
        ).toCore(Density(2f))

        assertEquals(TextRange(0, 5), span.range)
        assertEquals(org.tiqian.core.Underline.instance, span.role)
        assertEquals(null, span.paint.argb)
        assertEquals(
            org.tiqian.core.Dotted(dotDiameter = 2f, gapLength = 4f),
            span.paint.linePattern,
        )
        assertEquals(2f, span.paint.adjacentSameStyleClearance)
    }

    @Test
    fun rubySpansCarryReadingAndOptionalFont() {
        val text = buildAnnotatedString {
            append("我爱")
            ruby("北京", "Běijīng")
            ruby("咖啡", "coffee", fontFamily = "Literata")
        }
        assertEquals("我爱北京咖啡", text.text) // readings are NOT in the source
        val spans = text.cjkRubySpans().sortedBy { it.baseRange.start }
        assertEquals(2, spans.size)
        assertEquals(TextRange(2, 4), spans[0].baseRange) // 北京
        assertEquals("Běijīng", spans[0].text)
        assertEquals(RubyKind.Pinyin, spans[0].kind)
        assertEquals(emptyList(), spans[0].fontFamilies) // default font
        assertEquals("coffee", spans[1].text)
        assertEquals(RubyKind.Pinyin, spans[1].kind)
        assertEquals(listOf("Literata"), spans[1].fontFamilies)
    }

    @Test
    fun bopomofoSpansCarryReadingKindAndOptionalFont() {
        val text = buildAnnotatedString {
            append("我读")
            bopomofo("中", "ㄓㄨㄥ", fontFamily = "BpmfGenYoMin")
        }
        assertEquals("我读中", text.text)
        val span = text.cjkRubySpans().single()
        assertEquals(TextRange(2, 3), span.baseRange)
        assertEquals("ㄓㄨㄥ", span.text)
        assertEquals(RubyKind.Bopomofo, span.kind)
        assertEquals(listOf("BpmfGenYoMin"), span.fontFamilies)
    }
}
