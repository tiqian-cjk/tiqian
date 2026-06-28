package org.tiqian.compose

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.em
import org.tiqian.core.DecorationKind
import org.tiqian.core.RichTextRole
import org.tiqian.core.RubyKind
import org.tiqian.core.TextRange
import org.tiqian.core.TextStyle
import kotlin.test.Test
import kotlin.test.assertEquals

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

        val spans = text.cjkRichTextSpans()

        assertEquals(
            RichTextRole.Background,
            spans.first { it.role == RichTextRole.Background }.role,
        )
        assertEquals(Color.Yellow.toArgb(), spans.first { it.role == RichTextRole.Background }.paint.argb)
        assertEquals(Color.Blue.toArgb(), spans.first { it.role == RichTextRole.Underline }.paint.argb)
        assertEquals(Color.Blue.toArgb(), spans.first { it.role == RichTextRole.LineThrough }.paint.argb)
        assertEquals(TextRange(1, 3), spans.first { it.role == RichTextRole.Underline }.range)
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
        val link = rich.first { it.role is RichTextRole.Link }
        val code = rich.first { it.role == RichTextRole.InlineCode }
        val style = text.cjkStyleSpans(TextStyle(), Density(1f)).first { it.range == code.range }

        assertEquals("读链接与code", text.text)
        assertEquals(TextRange(1, 3), link.range)
        assertEquals(RichTextRole.Link("https://example.com"), link.role)
        assertEquals(TextRange(4, 8), code.range)
        assertEquals(listOf("monospace"), style.style.fontFamilies)
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
