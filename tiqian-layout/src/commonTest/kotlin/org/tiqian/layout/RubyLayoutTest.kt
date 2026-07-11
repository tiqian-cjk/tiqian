package org.tiqian.layout

import org.tiqian.core.Ic

import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.Rect
import org.tiqian.core.RubyLineHeightMode
import org.tiqian.core.RubySpan
import org.tiqian.core.TextRange
import org.tiqian.core.TiqianTextContent
import org.tiqian.shaping.ExplainableStubTextShaper
import org.tiqian.shaping.ShapingInput
import org.tiqian.shaping.ShapingResult
import org.tiqian.shaping.TextShaper
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 行间注 (拼音 ruby, ADR 0032):注文 first consumes existing inter-line space,
 * conditionally expands line height only for a deficit, and centres over the
 * base x-span.
 */
class RubyLayoutTest {

    private val engine = ExplainableStubParagraphLayoutEngine()
    private fun input(ruby: List<RubySpan>) = LayoutInput(
        content = TiqianTextContent("中文排版"),
        constraints = LayoutConstraints(maxWidth = 400f),
        paragraphStyle = ParagraphStyle(firstLineIndent = Ic(0f)),
        rubySpans = ruby,
    )

    @Test
    fun rubyDoesNotChangeLineBoxAndCentresOverBase() {
        val plain = engine.layout(input(emptyList()))
        val ruby = engine.layout(input(listOf(RubySpan(TextRange(0, 1), "zhōng"))))

        assertEquals(plain.lines.first().top, ruby.lines.first().top, 0.001f)
        assertEquals(plain.lines.first().baseline, ruby.lines.first().baseline, 0.001f)
        assertEquals(plain.lines.first().bottom, ruby.lines.first().bottom, 0.001f)
        assertEquals(plain.size.height, ruby.size.height, 0.001f)
        val lineHeightDecision = ruby.debug.rubyLineHeightDecision!!
        assertEquals("PerLine", lineHeightDecision.mode)
        assertEquals(0f, lineHeightDecision.maxExtra, 0.001f)
        assertTrue(lineHeightDecision.lineExtras.all { it == 0f })
        assertTrue(lineHeightDecision.expandedLineIndices.isEmpty())
        assertEquals("ExistingInterlineSpaceFitsRuby", lineHeightDecision.reason)
        val decisions = ruby.debug.rubyDecisions
        assertEquals(1, decisions.size)
        assertEquals("zhōng", decisions[0].text)
        // Centred over 中 (first char, no indent → roughly [0, oneCharAdvance]).
        val firstAdvance = ruby.clusters.first().advance
        assertTrue(decisions[0].centerX in 0f..firstAdvance, "centre ${decisions[0].centerX} within 中's span")
        // Stub metrics: base face top = baseline - 0.88em; ruby descent = 0.2
        // of the 0.5em ruby size. The two measured boxes touch without guessed
        // baseline offsets or extra line-box height.
        assertTrue(decisions[0].baselineY < ruby.lines.first().baseline, "ruby baseline above base baseline")
        assertEquals(
            ruby.lines.first().baseline - 16f * 0.88f,
            decisions[0].baselineY + decisions[0].fontSize * 0.2f,
            0.001f,
        )
        assertEquals(500, decisions[0].fontWeight, "ruby defaults one weight step heavier than base")
    }

    @Test
    fun rubyOnOneLineKeepsTheWholeBaselineGridStable() {
        fun layout(ruby: List<RubySpan>) = engine.layout(
            LayoutInput(
                content = TiqianTextContent("甲乙丙丁戊己庚辛"),
                constraints = LayoutConstraints(maxWidth = 64f),
                paragraphStyle = ParagraphStyle(firstLineIndent = Ic(0f)),
                rubySpans = ruby,
            ),
        )

        val plain = layout(emptyList())
        val annotated = layout(listOf(RubySpan(TextRange(4, 5), "wù")))

        assertEquals(plain.lines.size, annotated.lines.size)
        assertEquals(plain.size.height, annotated.size.height, 0.001f)
        plain.lines.zip(annotated.lines).forEach { (plainLine, annotatedLine) ->
            assertEquals(plainLine.top, annotatedLine.top, 0.001f)
            assertEquals(plainLine.baseline, annotatedLine.baseline, 0.001f)
            assertEquals(plainLine.bottom, annotatedLine.bottom, 0.001f)
        }
        assertEquals(24f, annotated.lines[1].baseline - annotated.lines[0].baseline, 0.001f)
    }

    @Test
    fun tightLineHeightRaisesOnlyTheAnnotatedLineByDefault() {
        fun layout(ruby: List<RubySpan>) = engine.layout(
            LayoutInput(
                content = TiqianTextContent("甲乙丙丁戊己庚辛壬癸子丑"),
                constraints = LayoutConstraints(maxWidth = 64f),
                paragraphStyle = ParagraphStyle(
                    firstLineIndent = Ic(0f),
                    lineHeight = 18f,
                ),
                rubySpans = ruby,
            ),
        )

        val plain = layout(emptyList())
        val annotated = layout(listOf(RubySpan(TextRange(4, 5), "wù")))

        // Stub base face = 16px, ruby box = 8px. An 18px base line leaves 2px,
        // so the line carrying ruby needs exactly 6px more before its baseline.
        assertEquals(3, annotated.lines.size)
        assertEquals(plain.size.height + 6f, annotated.size.height, 0.001f)
        assertEquals(18f, annotated.lines[0].bottom - annotated.lines[0].top, 0.001f)
        assertEquals(24f, annotated.lines[1].bottom - annotated.lines[1].top, 0.001f)
        assertEquals(18f, annotated.lines[2].bottom - annotated.lines[2].top, 0.001f)
        assertEquals(24f, annotated.lines[1].baseline - annotated.lines[0].baseline, 0.001f)
        assertEquals(18f, annotated.lines[2].baseline - annotated.lines[1].baseline, 0.001f)
        val decision = annotated.debug.rubyLineHeightDecision!!
        assertEquals("PerLine", decision.mode)
        assertEquals(6f, decision.maxExtra, 0.001f)
        assertEquals(listOf(0f, 6f, 0f), decision.lineExtras)
        assertEquals(listOf(1), decision.expandedLineIndices)
    }

    @Test
    fun uniformModeAddsTheSameDeficitToEveryLine() {
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("甲乙丙丁戊己庚辛壬癸子丑"),
                constraints = LayoutConstraints(maxWidth = 64f),
                paragraphStyle = ParagraphStyle(
                    firstLineIndent = Ic(0f),
                    lineHeight = 18f,
                    rubyLineHeightMode = RubyLineHeightMode.UniformParagraph,
                ),
                rubySpans = listOf(RubySpan(TextRange(4, 5), "wù")),
            ),
        )

        assertEquals(3, result.lines.size)
        result.lines.forEach { line ->
            assertEquals(24f, line.bottom - line.top, 0.001f)
        }
        assertEquals(24f, result.lines[1].baseline - result.lines[0].baseline, 0.001f)
        assertEquals(24f, result.lines[2].baseline - result.lines[1].baseline, 0.001f)
        assertEquals(72f, result.size.height, 0.001f)
        val decision = result.debug.rubyLineHeightDecision!!
        assertEquals("UniformParagraph", decision.mode)
        assertEquals(6f, decision.maxExtra, 0.001f)
        assertEquals(listOf(6f, 6f, 6f), decision.lineExtras)
        assertEquals(listOf(0, 1, 2), decision.expandedLineIndices)
    }

    @Test
    fun rubyVerticalGeometryUsesLatinMetricsNotReadingInk() {
        val delegate = ExplainableStubTextShaper()
        val engineWithContradictoryInk = ExplainableStubParagraphLayoutEngine(
            textShaper = object : TextShaper {
                override fun shape(input: ShapingInput): ShapingResult {
                    val result = delegate.shape(input)
                    val bounds = if (input.displayText == "pg") {
                        Rect(0f, -100f, 16f, 100f)
                    } else {
                        Rect(0f, -1f, 16f, 1f)
                    }
                    return result.copy(
                        glyphRuns = result.glyphRuns.map { run ->
                            run.copy(glyphs = run.glyphs.map { it.copy(bounds = bounds) })
                        },
                        decisions = result.decisions.map { it.copy(glyphsWithoutInkBounds = 0) },
                    )
                }
            },
        )
        fun layout(reading: String) = engineWithContradictoryInk.layout(
            LayoutInput(
                content = TiqianTextContent("甲乙丙丁"),
                constraints = LayoutConstraints(maxWidth = 64f),
                paragraphStyle = ParagraphStyle(
                    firstLineIndent = Ic(0f),
                    lineHeight = 18f,
                ),
                rubySpans = listOf(RubySpan(TextRange(0, 1), reading)),
            ),
        )

        val shallowInk = layout("he")
        val extremeInk = layout("pg")
        val shallowDecision = shallowInk.debug.rubyDecisions.single()
        val extremeDecision = extremeInk.debug.rubyDecisions.single()

        assertEquals(shallowInk.size.height, extremeInk.size.height, 0.001f)
        assertEquals(shallowInk.lines.first().top, extremeInk.lines.first().top, 0.001f)
        assertEquals(shallowInk.lines.first().baseline, extremeInk.lines.first().baseline, 0.001f)
        assertEquals(shallowInk.lines.first().bottom, extremeInk.lines.first().bottom, 0.001f)
        assertEquals(shallowDecision.baselineY, extremeDecision.baselineY, 0.001f)
        assertEquals(shallowDecision.ascent, extremeDecision.ascent, 0.001f)
        assertEquals(shallowDecision.descent, extremeDecision.descent, 0.001f)
        assertEquals(
            shallowInk.debug.rubyLineHeightDecision!!.rubyExtent,
            extremeInk.debug.rubyLineHeightDecision!!.rubyExtent,
            0.001f,
        )
    }

    @Test
    fun noRubyIsUnchanged() {
        // The default path (no ruby) emits no annotation geometry.
        val plain = engine.layout(input(emptyList()))
        assertTrue(plain.debug.rubyDecisions.isEmpty())
    }

    @Test
    fun wideAdjacentReadingsSpreadButNarrowDoNot() {
        fun totalWidth(rubyTexts: List<String>): Double {
            val spans = rubyTexts.mapIndexed { i, t -> RubySpan(TextRange(i, i + 1), t) }
            return engine.layout(
                LayoutInput(
                    content = TiqianTextContent("中文排版"),
                    constraints = LayoutConstraints(maxWidth = 4000f), // one line, no wrap
                    paragraphStyle = ParagraphStyle(firstLineIndent = Ic(0f)),
                    rubySpans = spans,
                ),
            ).clusters.sumOf { it.advance.toDouble() }
        }

        val plain = totalWidth(listOf("", "", "", ""))
        val narrow = totalWidth(listOf("yī", "rén", "yī", "rén"))
        val wide = totalWidth(listOf("zhuāng", "chuáng", "shuāng", "guāng"))

        // 避让 is MONOTONIC in reading width: the wider the adjacent 注文, the more
        // 字距 is added to keep the word-space gap. (The "narrow overhangs, no spread"
        // case needs realistic proportional metrics — the stub treats Latin as
        // full-width — and is covered by the render probe instead.)
        assertTrue(narrow >= plain, "spread never shrinks the line ($narrow vs $plain)")
        assertTrue(wide > narrow, "wider readings spread more ($wide vs $narrow)")
    }
}
