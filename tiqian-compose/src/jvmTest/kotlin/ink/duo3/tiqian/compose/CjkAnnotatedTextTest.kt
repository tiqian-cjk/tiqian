package ink.duo3.tiqian.compose

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import ink.duo3.tiqian.core.DecorationKind
import ink.duo3.tiqian.core.TextRange
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
            cjkEmphasis { append("豆子新鲜最要紧") }
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
}
