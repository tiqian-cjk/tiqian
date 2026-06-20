package ink.duo3.tiqian.compose

import ink.duo3.tiqian.clreq.ClreqProfile
import ink.duo3.tiqian.core.ParagraphStyle
import ink.duo3.tiqian.core.TextStyle
import ink.duo3.tiqian.core.ic
import ink.duo3.tiqian.layout.ExplainableStubParagraphLayoutEngine
import ink.duo3.tiqian.layout.LookaheadLineBreaker
import ink.duo3.tiqian.shaping.skia.SkiaFontMetricsResolver
import ink.duo3.tiqian.shaping.skia.SkiaTextShaper
import kotlin.test.Test
import kotlin.test.assertEquals

/** 凸排列表 (CLREQ §6.2.1.1): marker formatting + auto 标记列宽. */
class CjkListTest {

    private val measurer = ParagraphMeasurer(
        ExplainableStubParagraphLayoutEngine(
            lineBreaker = LookaheadLineBreaker(),
            textShaper = SkiaTextShaper(),
            fontMetricsResolver = SkiaFontMetricsResolver(),
            clreqProfileResolver = { ClreqProfile.MainlandHorizontal },
        ),
    )

    @Test
    fun markersFormatPerKind() {
        assertEquals("1.", ListMarker.Decimal.format(1))
        assertEquals("10.", ListMarker.Decimal.format(10))
        assertEquals("一、", ListMarker.CjkNumber().format(1))
        assertEquals("十、", ListMarker.CjkNumber().format(10))
        assertEquals("二十一、", ListMarker.CjkNumber().format(21))
        assertEquals("一）", ListMarker.CjkNumber(suffix = "）").format(1))
        assertEquals("①", ListMarker.Circled.format(1))
        assertEquals("⑳", ListMarker.Circled.format(20))
        assertEquals("21.", ListMarker.Circled.format(21)) // out of circled range → decimal
        assertEquals("•", ListMarker.Bullet().format(7))
    }

    @Test
    fun gutterDefaultsToOneZiAndBumpsForTwoDigits() {
        val ts = TextStyle(fontSize = 24f)
        val ps = ParagraphStyle()
        fun gutter(count: Int) =
            autoListGutterEm(CjkBlock.List.ofStrings((1..count).map { "项" }, ListMarker.Decimal), ts, ps, measurer)

        assertEquals(1.ic, gutter(9), "1.–9. fit one 字")
        assertEquals(2.ic, gutter(10), "10. forces the whole列 to two 字")
    }

    @Test
    fun explicitIndentOverridesAuto() {
        // The List carries the override; auto is only consulted when indent == null.
        val list = CjkBlock.List.ofStrings(listOf("a", "b"), ListMarker.Decimal, indent = 3.ic)
        assertEquals(3.ic, list.indent)
    }
}
