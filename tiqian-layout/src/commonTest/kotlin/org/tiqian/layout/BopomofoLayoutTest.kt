package org.tiqian.layout

import org.tiqian.core.Ic

import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.RubyKind
import org.tiqian.core.RubySpan
import org.tiqian.core.TextRange
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.core.BopomofoGlyphRole
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** 注音 (ADR 0033): right-side ㄅㄆㄇ symbols + parsed tone, with annotated-base reservation. */
class BopomofoLayoutTest {

    private val engine = ExplainableStubParagraphLayoutEngine()

    private fun layout(
        bopomofo: List<RubySpan>,
        spans: List<TextSpan> = emptyList(),
    ) = engine.layout(
        LayoutInput(
            content = TiqianTextContent("中文", spans = spans),
            constraints = LayoutConstraints(maxWidth = 4000f),
            paragraphStyle = ParagraphStyle(firstLineIndent = Ic(0f)),
            rubySpans = bopomofo,
        ),
    )

    @Test
    fun symbolsAndToneRightOfBase() {
        val result = layout(
            listOf(
                RubySpan(TextRange(0, 1), "ㄓㄨㄥ", kind = RubyKind.Bopomofo), // 阴平, 3 symbols
                RubySpan(TextRange(1, 2), "ㄔㄤˊ", kind = RubyKind.Bopomofo), // 阳平, 2 symbols
            ),
        )
        val z = result.debug.bopomofoDecisions
        assertEquals(2, z.size)

        val zhong = z.first { it.baseRange.start == 0 }
        assertEquals(700, zhong.fontWeight, "bopomofo defaults three weight steps heavier than base")
        assertEquals(3, zhong.placements.count { it.role == BopomofoGlyphRole.Symbol }) // ㄓㄨㄥ
        assertTrue(zhong.placements.none { it.role == BopomofoGlyphRole.Tone }) // 阴平 no mark
        // 注音 sits to the RIGHT of the 1em base char.
        assertTrue(zhong.placements.all { it.left >= 15.9f }, "symbols right of base: ${zhong.placements.map { it.left }}")

        val chang = z.first { it.baseRange.start == 1 }
        assertEquals(2, chang.placements.count { it.role == BopomofoGlyphRole.Symbol })
        assertEquals(1, chang.placements.count { it.role == BopomofoGlyphRole.Tone }) // 阳平 ˊ
    }

    @Test
    fun annotatedBaseReservesHalfEmOnly() {
        val plain = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中文"),
                constraints = LayoutConstraints(maxWidth = 4000f),
                paragraphStyle = ParagraphStyle(firstLineIndent = Ic(0f)),
            ),
        )
        val withBopomofo = layout(listOf(RubySpan(TextRange(0, 1), "ㄓㄨㄥ", kind = RubyKind.Bopomofo)))

        assertTrue(
            withBopomofo.clusters[0].advance > plain.clusters[0].advance,
            "bopomofo reserves advance on annotated base (${withBopomofo.clusters[0].advance} vs ${plain.clusters[0].advance})",
        )
        assertEquals(
            plain.clusters[1].advance,
            withBopomofo.clusters[1].advance,
            "current v1 does not reserve the unannotated adjacent char",
        )
    }

    @Test
    fun fontWeightFollowsAnnotatedBasePlusThreeSteps() {
        val result = layout(
            bopomofo = listOf(
                RubySpan(TextRange(0, 1), "ㄓㄨㄥ", kind = RubyKind.Bopomofo),
                RubySpan(TextRange(1, 2), "ㄨㄣˊ", kind = RubyKind.Bopomofo),
            ),
            spans = listOf(
                TextSpan(TextRange(0, 1), TextStyle(fontWeight = 500)),
                TextSpan(TextRange(1, 2), TextStyle(fontWeight = 700)),
            ),
        )

        val zhong = result.debug.bopomofoDecisions.first { it.baseRange == TextRange(0, 1) }
        val wen = result.debug.bopomofoDecisions.first { it.baseRange == TextRange(1, 2) }
        assertEquals(800, zhong.fontWeight)
        assertEquals(900, wen.fontWeight, "bopomofo weight clamps at 900")
    }

    @Test
    fun decisionKeepsSourceReadingForCopy() {
        val result = layout(listOf(RubySpan(TextRange(0, 1), "˙ㄉㄜ", kind = RubyKind.Bopomofo)))
        val decision = result.debug.bopomofoDecisions.single()

        assertEquals("˙ㄉㄜ", decision.text)
        assertEquals(listOf("˙", "ㄉ", "ㄜ"), decision.placements.map { it.text })
        assertEquals(BopomofoGlyphRole.Neutral, decision.placements.first().role)
    }
}
