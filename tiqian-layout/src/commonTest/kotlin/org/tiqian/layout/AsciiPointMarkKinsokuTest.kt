package org.tiqian.layout

import org.tiqian.clreq.ClreqProfile
import org.tiqian.clreq.ClreqProfileResolver
import org.tiqian.clreq.HangingPunctuationStyle
import org.tiqian.clreq.KinsokuLevel
import org.tiqian.clreq.KinsokuMode
import org.tiqian.core.Ic
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LayoutResult
import org.tiqian.core.LineLengthGrid
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.RubyKind
import org.tiqian.core.RubySpan
import org.tiqian.core.TextRange
import org.tiqian.core.TextSpan
import org.tiqian.core.TextStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.linebreak.NoHyphenator
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AsciiPointMarkKinsokuTest {
    @Test
    fun cjkAttachedAsciiPointMarksCannotStartWrappedLinesAndStayLatin() {
        for (mark in listOf(',', '.', ':', ';', '!', '?')) {
            for ((label, breaker) in breakers()) {
                val text = "中文中文${mark}中文"
                val result = layout(text, maxWidth = 64f, breaker = breaker)
                val lineTexts = result.lineTexts(text)

                assertTrue(
                    lineTexts.none { it.startsWith(mark) },
                    "$label placed '$mark' at line start: $lineTexts",
                )
                val pointMark = result.clusters.single { it.text == mark.toString() }
                assertEquals("latin-primary", pointMark.fontKey, "$label '$mark' face")
                assertEquals(
                    "LatinText",
                    result.debug.fontDecisions.single { it.range == pointMark.range }.role,
                    "$label '$mark' role",
                )
                assertTrue(
                    result.debug.punctuationDecisions.none { it.range == pointMark.range },
                    "$label '$mark' must not enter CJK punctuation geometry",
                )
                val contextual = result.debug.contextualKinsokuDecisions.single { it.range == pointMark.range }
                assertEquals("LineStart", contextual.forbiddenPosition)
                assertEquals("AttachedAsciiPointMarkKinsoku", contextual.reason)
            }
        }
    }

    @Test
    fun leadingPointMarkRunIsSplitFromFollowingLatinText() {
        val text = "中文,anyway继续"
        for ((label, breaker) in breakers()) {
            val result = layout(text, maxWidth = 64f, breaker = breaker)
            val lineTexts = result.lineTexts(text)

            assertTrue(lineTexts.none { it.startsWith(',') }, "$label lines: $lineTexts")
            assertTrue(result.clusters.any { it.text == "," }, "$label comma cluster: ${result.clusters}")
            assertTrue(
                result.debug.fontDecisions.any { it.sourceText == "anyway" },
                "$label Latin decision: ${result.debug.fontDecisions}",
            )
            assertFalse(result.clusters.any { it.text == ",anyway" }, "$label bound the word to the comma")
        }
    }

    @Test
    fun LatinTokensAndAmbiguousAsciiCharactersKeepExistingSegmentation() {
        val text = "foo,bar 1,234 50% \"quoted\""
        val result = layout(text, maxWidth = 1_000f, breaker = GreedyLineBreaker())
        val clusterTexts = result.clusters.map { it.text }

        assertTrue("foo,bar" in clusterTexts)
        assertTrue("1,234" in clusterTexts)
        assertTrue("50%" in clusterTexts)
        assertTrue("\"quoted\"" in clusterTexts)
        assertTrue(result.debug.contextualKinsokuDecisions.isEmpty())
    }

    @Test
    fun pointMarkSplitFromAnOverlongLatinTokenStillCannotStartALine() {
        val text = "anyway,你"
        for (width in listOf(32f, 36f, 40f, 48f)) {
            for ((label, breaker) in breakers()) {
                val result = layout(text, width, breaker)
                val lineTexts = result.lineTexts(text)
                assertTrue(
                    lineTexts.none { it.startsWith(',') },
                    "$label width=$width lines: $lineTexts",
                )
            }
        }
    }

    @Test
    fun pointMarkExposedByASecondStageLatinCutIsSplitFromItsSuffix() {
        val text = ".,A中"
        for ((label, breaker) in breakers()) {
            val result = layout(text, maxWidth = 32f, breaker = breaker)
            val lineTexts = result.lineTexts(text)

            assertTrue(lineTexts.none { it.startsWith(',') }, "$label lines: $lineTexts")
            assertEquals(".,", lineTexts.first(), "$label should keep the avoidable pair together")
            assertTrue(result.clusters.any { it.text == "," }, "$label clusters: ${result.clusters}")
            assertFalse(result.clusters.any { it.text == ",A" }, "$label kept the post-cut suffix attached")
        }
    }

    @Test
    fun impossibleMeasureHangsThePointMarkInsteadOfLeavingItAtLineStart() {
        val text = "中,文"
        for (width in listOf(1f, 8f, 15f, 23f, 31f)) {
            for ((label, breaker) in breakers()) {
                val result = layout(text, maxWidth = width, breaker = breaker)
                val lineTexts = result.lineTexts(text)

                assertTrue(
                    lineTexts.none { it.startsWith(',') },
                    "$label width=$width lines: $lineTexts",
                )
                val contextual = result.debug.contextualKinsokuDecisions.single()
                assertEquals(
                    "AttachedAsciiPointMarkImpossibleMeasureHang",
                    contextual.impossibleMeasureFallback,
                    "$label width=$width fallback",
                )
                assertTrue(
                    result.debug.lineDecisions.any { it.repair == "Hang" },
                    "$label width=$width repairs: ${result.debug.lineDecisions}",
                )
            }
        }
    }

    @Test
    fun firstLineIndentUsesTheSameImpossibleMeasureFallback() {
        val text = "中,文"
        for ((label, breaker) in breakers()) {
            val result = layout(
                text = text,
                maxWidth = 32f,
                breaker = breaker,
                firstLineIndent = null,
            )

            assertTrue(result.lineTexts(text).none { it.startsWith(',') }, "$label lines: ${result.lineTexts(text)}")
            assertEquals(
                "AttachedAsciiPointMarkImpossibleMeasureHang",
                result.debug.contextualKinsokuDecisions.single().impossibleMeasureFallback,
                "$label adaptive first-line indent",
            )
        }
    }

    @Test
    fun lineBreakGeometryIncludesBopomofoSpreadWhenChoosingTheFallback() {
        val text = "中,文"
        for ((label, breaker) in breakers()) {
            val result = layout(
                text = text,
                maxWidth = 32f,
                breaker = breaker,
                rubySpans = listOf(
                    RubySpan(TextRange(0, 1), "ㄅ", kind = RubyKind.Bopomofo),
                ),
            )

            assertTrue(result.lineTexts(text).none { it.startsWith(',') }, "$label lines: ${result.lineTexts(text)}")
            assertEquals(
                "AttachedAsciiPointMarkImpossibleMeasureHang",
                result.debug.contextualKinsokuDecisions.single().impossibleMeasureFallback,
                "$label must use post-spread line-break geometry",
            )
        }
    }

    @Test
    fun styledPointMarkRunCanExtendOneImpossibleMeasureHang() {
        val text = "中!,文"
        val spans = listOf(TextSpan(TextRange(2, 3), TextStyle(fontWeight = 700)))
        for ((label, breaker) in breakers()) {
            val result = layout(
                text = text,
                maxWidth = 15f,
                breaker = breaker,
                spans = spans,
            )
            val lineTexts = result.lineTexts(text)

            assertTrue(
                lineTexts.none { line -> line.firstOrNull() in listOf('!', ',') },
                "$label lines: $lineTexts",
            )
            assertTrue(result.clusters.any { it.text == "!" }, "$label exclamation cluster")
            assertTrue(result.clusters.any { it.text == "," }, "$label comma cluster")
            assertEquals(
                2,
                result.debug.contextualKinsokuDecisions.count {
                    it.impossibleMeasureFallback == "AttachedAsciiPointMarkImpossibleMeasureHang"
                },
                "$label applied fallbacks: ${result.debug.contextualKinsokuDecisions}",
            )
            val hangingLine = result.lines.single { it.hangingPunctuationAdvance > 0f }
            val expectedAdvance = result.clusters
                .filter { it.text == "!" || it.text == "," }
                .sumOf { it.advance.toDouble() }
                .toFloat()
            assertEquals(expectedAdvance, hangingLine.hangingPunctuationAdvance, "$label run advance")
        }
    }

    @Test
    fun contextualRunCanExtendAProfileHangOnlyWithinTheSameProtectedGroup() {
        val text = "中，,文"
        for ((label, breaker) in breakers()) {
            val result = layout(
                text = text,
                maxWidth = 15f,
                breaker = breaker,
                hanging = HangingPunctuationStyle.PauseStops,
            )
            val lineTexts = result.lineTexts(text)

            assertTrue(
                lineTexts.none { it.startsWith(',') || it.startsWith('，') },
                "$label lines: $lineTexts",
            )
            assertEquals(
                "AttachedAsciiPointMarkImpossibleMeasureHang",
                result.debug.contextualKinsokuDecisions.single().impossibleMeasureFallback,
                "$label contextual extension",
            )
        }
    }

    @Test
    fun adjacentImpossibleGroupsDoNotShareHangProvenance() {
        val text = "中!，?"
        for ((label, breaker) in breakers()) {
            val result = layout(
                text = text,
                maxWidth = 15f,
                breaker = breaker,
                hanging = HangingPunctuationStyle.PauseStops,
            )

            assertEquals(
                2,
                result.lines.count { it.hangingPunctuationAdvance > 0f },
                "$label must keep the adjacent protected groups separate: ${result.lines}",
            )
            assertTrue(
                result.lineTexts(text).none { it.startsWith('!') || it.startsWith('?') },
                "$label lines: ${result.lineTexts(text)}",
            )
        }
    }

    @Test
    fun compressedClosingAndPointMarkPairDoesNotReportAnUnusedHangFallback() {
        val text = "）,文"
        for ((label, breaker) in breakers()) {
            val result = layout(
                text = text,
                maxWidth = 24f,
                breaker = breaker,
                lineLengthGrid = LineLengthGrid(enabled = false),
            )

            assertEquals(text.substring(0, 2), result.lineTexts(text).first(), "$label lines: ${result.lineTexts(text)}")
            assertTrue(result.debug.lineDecisions.none { it.repair == "Hang" }, "$label repairs: ${result.debug.lineDecisions}")
            assertEquals(null, result.debug.contextualKinsokuDecisions.single().impossibleMeasureFallback)
        }
    }

    @Test
    fun kinsokuNoneExplicitlyAllowsTheAsciiPointMarkAtLineStart() {
        val text = "中文中文,中文"
        for ((label, breaker) in breakers()) {
            val result = layout(
                text = text,
                maxWidth = 64f,
                breaker = breaker,
                level = KinsokuLevel.None,
            )

            assertTrue(result.lineTexts(text).any { it.startsWith(',') }, "$label lines: ${result.lineTexts(text)}")
            assertTrue(result.debug.contextualKinsokuDecisions.isEmpty(), label)
        }
    }

    @Test
    fun authoredWhitespaceAndMandatoryBreakDoNotCreateContextualKinsoku() {
        for (text in listOf("中 ,文", "中\n,文", ",中文")) {
            for ((label, breaker) in breakers()) {
                val result = layout(text, maxWidth = 1_000f, breaker = breaker)
                assertTrue(
                    result.debug.contextualKinsokuDecisions.isEmpty(),
                    "$label text=${text.replace("\n", "\\n")} decisions=${result.debug.contextualKinsokuDecisions}",
                )
            }
        }
    }

    @Test
    fun mandatoryBreakControlAfterAHungPointMarkStaysInTheTrailingSuffix() {
        val text = "中,\n文"
        for ((label, breaker) in breakers()) {
            val result = layout(text, maxWidth = 15f, breaker = breaker)

            assertTrue(result.lineTexts(text).none { it.startsWith(',') }, "$label lines: ${result.lineTexts(text)}")
            assertEquals(
                "AttachedAsciiPointMarkImpossibleMeasureHang",
                result.debug.contextualKinsokuDecisions.single().impossibleMeasureFallback,
            )
        }
    }

    @Test
    fun reportedRealWorldParagraphNeverWrapsDirectlyBeforeAnAsciiComma() {
        for (width in listOf(36f, 40f, 160f, 240f, 320f)) {
            for ((label, breaker) in breakers()) {
                val result = layout(REPORTED_PARAGRAPH, width, breaker)
                val lineTexts = result.lineTexts(REPORTED_PARAGRAPH)
                assertTrue(
                    lineTexts.none { it.startsWith(',') },
                    "$label width=$width still starts a line with comma:\n${lineTexts.joinToString("\n")}",
                )
            }
        }
    }

    private fun layout(
        text: String,
        maxWidth: Float,
        breaker: LineBreaker,
        level: KinsokuLevel = KinsokuLevel.Basic,
        hanging: HangingPunctuationStyle = HangingPunctuationStyle.Disabled,
        firstLineIndent: Ic? = Ic.Zero,
        rubySpans: List<RubySpan> = emptyList(),
        spans: List<TextSpan> = emptyList(),
        lineLengthGrid: LineLengthGrid = LineLengthGrid(),
    ): LayoutResult =
        ExplainableStubParagraphLayoutEngine(
            lineBreaker = breaker,
            hyphenator = NoHyphenator,
            clreqProfileResolver = ClreqProfileResolver {
                ClreqProfile.MainlandHorizontal.copy(
                    kinsokuMode = KinsokuMode.Fixed(level, hanging),
                )
            },
        ).layout(
            LayoutInput(
                paragraphStyle = ParagraphStyle(
                    firstLineIndent = firstLineIndent,
                    lineLengthGrid = lineLengthGrid,
                ),
                content = TiqianTextContent(text, spans = spans),
                constraints = LayoutConstraints(maxWidth = maxWidth),
                rubySpans = rubySpans,
            ),
        )

    private fun LayoutResult.lineTexts(source: String): List<String> =
        lines.map { source.substring(it.range.start, it.range.end) }

    private fun breakers(): List<Pair<String, LineBreaker>> =
        listOf(
            "greedy" to GreedyLineBreaker(),
            "lookahead" to LookaheadLineBreaker(),
        )

    private companion object {
        val REPORTED_PARAGRAPH =
            "对于你冒犯的断言不敢苟同,你以一种理所当然的语气声明\"明显的已经越过了人际尊重的基本门槛\"," +
                "如此注重逻辑推导的作者居然会对论断的前提条件如此宽松以至于不留回旋余地?当然不是,在回复的一开头," +
                "聪明的作者就已经强调了自己作为被冒犯者有权力定义自己的感受,当然有权力!,但是这种感受是否可以无限扩展到" +
                "\"人际尊重的基本门槛\",还是值得商榷的,逻辑严谨如你岂能放过如此基础的逻辑漏洞?也许我们可以采用更加自洽的解释," +
                " 这种愤怒来源于作者遭到否定是的第一反应,一篇让你耿耿于怀三年的留言需要你通过反复打磨的语言和极致构思的反讽," +
                "只为了冷嘲热讽一个逻辑甚至不大通顺的留言.\" 我一定要用最严密的逻辑反驳回去,这是关乎我尊严的网络论战\",也许你心里确实这么想," +
                " 可是承认这件事情在你的内心是一件丢脸的事情,倘若承认了自己的三年的耿耿于怀, 就等同于认可自己与对方与自己处于同一水平对话," +
                " “居然要和一个沙文主义在相提并论, 这怎么可以接受”.但事实上,如此自视清高反而令人啼笑皆非,如果你可以大方承认自己的傲慢," +
                "我大可因为你的心胸宽广\"对你致上最高的敬意\".别急着找我的逻辑漏洞,因为我也会大大方方的承认我就是在玩," +
                "我乐意这种伪装成思辨的娱乐,这比大部分辩论赛有意思多了 .anyway,你完全有机会在一开始就讲清楚自己愤怒的来源," +
                "而不是强行带上无所谓的面具却又如此的用力过猛,希望下一次你可以清晰表述,就像你自己提到的那样," +
                "不要\"把解读的权利拱手让给对方\""
    }
}
