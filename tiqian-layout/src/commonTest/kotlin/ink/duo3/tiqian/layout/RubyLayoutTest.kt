package ink.duo3.tiqian.layout

import ink.duo3.tiqian.core.LayoutConstraints
import ink.duo3.tiqian.core.LayoutInput
import ink.duo3.tiqian.core.ParagraphStyle
import ink.duo3.tiqian.core.RubySpan
import ink.duo3.tiqian.core.TextRange
import ink.duo3.tiqian.core.TiqianTextContent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 行间注 (拼音 ruby, ADR 0032): the注文 reserves a uniform line-height band and
 * the engine centres it over the base x-span. No ruby = zero change.
 */
class RubyLayoutTest {

    private val engine = ExplainableStubParagraphLayoutEngine()
    private fun input(ruby: List<RubySpan>) = LayoutInput(
        content = TiqianTextContent("中文排版"),
        constraints = LayoutConstraints(maxWidth = 400f),
        paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
        rubySpans = ruby,
    )

    @Test
    fun rubyReservesLineHeightAndCentresOverBase() {
        val plain = engine.layout(input(emptyList()))
        val ruby = engine.layout(input(listOf(RubySpan(TextRange(0, 1), "zhōng"))))

        // The ruby band grows the line height (uniform — CLREQ「行距不随标注与否变」).
        assertTrue(
            ruby.size.height > plain.size.height,
            "ruby line should be taller (${ruby.size.height} vs ${plain.size.height})",
        )
        val decisions = ruby.debug.rubyDecisions
        assertEquals(1, decisions.size)
        assertEquals("zhōng", decisions[0].text)
        // Centred over 中 (first char, no indent → roughly [0, oneCharAdvance]).
        val firstAdvance = ruby.clusters.first().advance
        assertTrue(decisions[0].centerX in 0f..firstAdvance, "centre ${decisions[0].centerX} within 中's span")
        // 注文 sits ABOVE the baseline.
        assertTrue(decisions[0].baselineY < ruby.lines.first().baseline, "ruby baseline above base baseline")
    }

    @Test
    fun noRubyIsUnchanged() {
        // The default path (no ruby) must not reserve any band.
        val plain = engine.layout(input(emptyList()))
        assertTrue(plain.debug.rubyDecisions.isEmpty())
    }
}
