package org.tiqian.text.layout

import org.tiqian.text.clreq.CjkPunctuationGlyphPolicy
import org.tiqian.text.clreq.ClreqProfile
import org.tiqian.text.clreq.ClreqProfileResolver
import org.tiqian.text.core.LayoutConstraints
import org.tiqian.text.core.LayoutInput
import org.tiqian.text.core.TiqianTextContent
import org.tiqian.text.font.FontRole
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ExplainableStubParagraphLayoutEngineTest {
    @Test
    fun returnsDebuggableSingleLineResult() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("提椠"),
                constraints = LayoutConstraints(maxWidth = 240f),
            ),
        )

        assertEquals(2, result.clusters.size)
        assertEquals(1, result.lines.size)
        assertEquals("greedy", result.debug.lineDecisions.single().kind)
    }

    @Test
    fun recordsFallbackDecisionsPerCluster() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("提椠……English——世界。"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        assertTrue(
            result.debug.fontDecisions.any {
                it.sourceText == "……" &&
                    it.displayText == "⋯⋯" &&
                    it.role == FontRole.CjkPunctuation.name &&
                    it.fontKey == "cjk-primary"
            },
        )
        assertTrue(
            result.debug.fontDecisions.any {
                it.sourceText == "——" &&
                    it.displayText == "⸺" &&
                    it.role == FontRole.CjkPunctuation.name &&
                    it.fontKey == "cjk-primary"
            },
        )
        assertTrue(
            result.debug.fontDecisions.any {
                it.sourceText == "English" &&
                    it.role == FontRole.LatinText.name &&
                    it.fontKey == "latin-primary"
            },
        )
        assertEquals("English", result.clusters.first { it.text == "English" }.text)
    }

    @Test
    fun preservesSourceTextWhenUsingClreqRecommendedDisplayGlyphs() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("……——・／"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val ellipsis = result.clusters.first { it.text == "……" }
        val dash = result.clusters.first { it.text == "——" }
        val interpunct = result.clusters.first { it.text == "・" }
        val solidus = result.clusters.first { it.text == "／" }

        assertEquals("……", ellipsis.text)
        assertEquals("⋯⋯", ellipsis.displayText)
        assertEquals("——", dash.text)
        assertEquals("⸺", dash.displayText)
        assertEquals("・", interpunct.text)
        assertEquals("·", interpunct.displayText)
        assertEquals("／", solidus.text)
        assertEquals("／", solidus.displayText)
        assertEquals("cjk-primary", ellipsis.fontKey)
        assertEquals("cjk-primary", dash.fontKey)
        assertEquals("cjk-primary", interpunct.fontKey)
        assertEquals("cjk-primary", solidus.fontKey)
    }

    @Test
    fun honorsProfilePunctuationGlyphPolicy() {
        val engine = ExplainableStubParagraphLayoutEngine(
            clreqProfileResolver = ClreqProfileResolver {
                ClreqProfile.MainlandHorizontal.copy(
                    punctuationGlyphPolicy = CjkPunctuationGlyphPolicy.PreserveInput,
                )
            },
        )

        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("……——"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        assertEquals("……", result.clusters.first { it.text == "……" }.displayText)
        assertEquals("——", result.clusters.first { it.text == "——" }.displayText)
    }

    @Test
    fun coalesceSetIsDrivenByProfile() {
        // Profile with empty coalesce set should split "——" into two clusters of "—"
        val engine = ExplainableStubParagraphLayoutEngine(
            clreqProfileResolver = ClreqProfileResolver {
                ClreqProfile.MainlandHorizontal.copy(
                    punctuationGlyphPolicy = CjkPunctuationGlyphPolicy.PreserveInput,
                    coalesceRepeatablePunctuation = emptySet(),
                )
            },
        )

        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("——"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        assertEquals(2, result.clusters.size)
        assertEquals("—", result.clusters[0].text)
        assertEquals("—", result.clusters[1].text)
    }

    @Test
    fun usesTwoEmAdvanceForRecommendedDashCodepoint() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("⸺"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        assertEquals(32f, result.clusters.single().advance)
        assertEquals(32f, result.size.width)
    }

    @Test
    fun keepsLatinTechnicalPunctuationInLatinRun() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("well-known/path"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        assertEquals("well-known/path", result.clusters.single().text)
        assertEquals("latin-primary", result.clusters.single().fontKey)
    }

    @Test
    fun keepsTextStartLatinQuotePairInLatinRun() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("“Hello” world"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val quoted = result.clusters.first()

        assertEquals("“Hello”", quoted.text)
        assertEquals("latin-primary", quoted.fontKey)
        assertTrue(
            result.debug.fontDecisions.any {
                it.sourceText == "“Hello”" && it.role == FontRole.LatinText.name
            },
        )
    }

    @Test
    fun skipsNeutralDashBeforeLatinQuotePairInLayout() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("English — “hello”"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val quoted = result.clusters.first { it.text == "“hello”" }

        assertEquals("latin-primary", quoted.fontKey)
    }

    @Test
    fun recordsRoleOverridesForResolvedQuotePairs() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("“Hello” world"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        // QuotePair resolves both quotes to LatinText. Without the override the
        // standalone classifier would label "“" at position 0 as CjkPunctuation
        // (text boundary, no Latin context).
        val openQuoteOverride = result.debug.roleOverrides.firstOrNull { it.range.start == 0 }
        val closeQuoteOverride = result.debug.roleOverrides.firstOrNull { it.range.start == 6 }
        assertEquals("LatinText", openQuoteOverride?.overriddenRole)
        assertEquals("CjkPunctuation", openQuoteOverride?.originalRole)
        assertEquals("QuotePairAwareLatinContext", openQuoteOverride?.source)
        assertEquals("LatinText", closeQuoteOverride?.overriddenRole)
    }

    @Test
    fun buildsTwoEmPunctuationAtomForRecommendedDashCodepoint() {
        val atom = PunctuationAtomBuilder().build("⸺", index = 0, em = 16f)

        requireNotNull(atom)
        assertEquals(32f, atom.advance)
        assertEquals(32f, atom.bodyWidth)
    }

    @Test
    fun recordsPunctuationAtomsInLayoutDebug() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("你好，世界。——"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val comma = result.debug.punctuationDecisions.single { it.char == '，' }
        assertEquals(2, comma.range.start)
        assertEquals(3, comma.range.end)
        assertEquals("PauseOrStop", comma.punctuationClass)
        assertEquals(16f, comma.advance)
        assertEquals(8f, comma.bodyWidth)
        assertEquals(4f, comma.leadingGlueNatural)
        assertEquals(4f, comma.trailingGlueNatural)
        assertEquals("Center", comma.anchor)

        val stop = result.debug.punctuationDecisions.single { it.char == '。' }
        assertEquals(5, stop.range.start)
        assertEquals(6, stop.range.end)

        val dash = result.debug.punctuationDecisions.single { it.char == '⸺' }
        assertEquals(6, dash.range.start)
        assertEquals(8, dash.range.end)
        assertEquals("Dash", dash.punctuationClass)
        assertEquals(32f, dash.advance)

        assertEquals(3, result.debug.punctuationDecisions.size)
    }

    @Test
    fun appliesAdjacentPunctuationCompressionToDrawableGeometry() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("你好，。"),
                constraints = LayoutConstraints(maxWidth = 320f),
            ),
        )

        val line = result.lines.single()
        val stop = result.clusters.first { it.text == "。" }

        assertEquals(64f, line.naturalWidth)
        assertEquals(60f, line.adjustedWidth)
        assertEquals(60f, line.visualWidth)
        assertEquals(60f, result.size.width)
        assertEquals(12f, stop.advance)
        assertEquals(60f, result.clusters.sumOf { it.advance.toDouble() }.toFloat())
        assertEquals(60f, result.glyphRuns.sumOf { it.advance.toDouble() }.toFloat())
        assertEquals(4f, result.debug.spacingDecisions.sumOf { it.reduction.toDouble() }.toFloat())

        val spacing = result.debug.spacingDecisions.single()
        assertEquals(2, spacing.range.start)
        assertEquals(4, spacing.range.end)
        assertEquals('，', spacing.leftChar)
        assertEquals('。', spacing.rightChar)
        assertEquals(8f, spacing.naturalInnerGlue)
        assertEquals(4f, spacing.adjustedInnerGlue)
        assertEquals(4f, spacing.reduction)
        assertEquals(3, spacing.reductionTargetRange.start)
        assertEquals(4, spacing.reductionTargetRange.end)
        assertEquals("collapse-adjacent-punctuation-inner-glue", spacing.reason)
    }

    @Test
    fun greedyBreakerProducesMultipleLinesWhenWidthOverflows() {
        // 8 CJK clusters * 16f = 128f natural; maxWidth=64f -> 4 clusters per line -> 2 lines.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文排版引擎测试"),
                constraints = LayoutConstraints(maxWidth = 64f),
            ),
        )

        assertEquals(2, result.lines.size)
        assertEquals(8, result.clusters.size)

        val first = result.lines[0]
        val second = result.lines[1]
        assertEquals(0, first.range.start)
        assertEquals(4, first.range.end)
        assertEquals(64f, first.adjustedWidth)
        assertEquals(0f, first.top)
        assertEquals(16f, first.bottom)

        assertEquals(4, second.range.start)
        assertEquals(8, second.range.end)
        assertEquals(64f, second.adjustedWidth)
        assertEquals(16f, second.top)
        assertEquals(32f, second.bottom)

        assertEquals(2, result.debug.lineDecisions.size)
        assertTrue(result.debug.lineDecisions.all { it.kind == "greedy" })
        assertEquals(32f, result.size.height)
    }

    @Test
    fun greedyBreakerKeepsLatinRunAsSingleClusterEvenWhenLineOverflows() {
        // "中" (16f) + "English" cluster (7*16=112f) > maxWidth=80f.
        // First line should be "中" alone (16f), "English" goes to line 2 (overflows but
        // can't be split further at cluster level in this slice).
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中English"),
                constraints = LayoutConstraints(maxWidth = 80f),
            ),
        )

        assertEquals(2, result.lines.size)
        assertEquals("中", result.clusters[result.lines[0].range.start.coerceAtMost(0)].text)
        assertEquals("English", result.clusters.first { it.text == "English" }.text)
    }

    @Test
    fun kinsokuCarriesPreviousClusterWhenLineWouldStartWithForbiddenPunctuation() {
        // Pure greedy at maxWidth=64 -> line 0: 中文中文 (clusters 0..3), line 1: 。
        // 。 is PauseOrStop, forbidden at line start, so CarryPrevious pulls
        // 文 (cluster 3) to line 1: line 0 = 中文中, line 1 = 文。.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文中文。"),
                constraints = LayoutConstraints(maxWidth = 64f),
            ),
        )

        assertEquals(2, result.lines.size)
        assertEquals(0, result.lines[0].range.start)
        assertEquals(3, result.lines[0].range.end)
        assertEquals(3, result.lines[1].range.start)
        assertEquals(5, result.lines[1].range.end)
        assertEquals(48f, result.lines[0].adjustedWidth)
        assertEquals(32f, result.lines[1].adjustedWidth)

        assertEquals(null, result.debug.lineDecisions[0].repair)
        assertEquals("CarryPrevious", result.debug.lineDecisions[1].repair)
        assertEquals(10, result.debug.lineDecisions[1].repairPenalty)
        assertTrue(
            result.debug.lineDecisions[1].notes.any {
                it.contains("ForbiddenAtLineStart:。") && it.contains("carried=文")
            },
        )
    }

    @Test
    fun kinsokuPushesLineStartPunctuationIntoPreviousLineWhenTrailingGlueCanShrink() {
        // Pure greedy at maxWidth=60 -> line 0: 中文中 (48f), line 1: 。
        // 。 can become line-end half-width by shrinking its trailing glue 4f,
        // so PushIn keeps the punctuation on the previous line instead of
        // carrying 中 down.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文中。"),
                constraints = LayoutConstraints(maxWidth = 60f),
            ),
        )

        assertEquals(1, result.lines.size)
        val line = result.lines.single()
        assertEquals(0, line.range.start)
        assertEquals(4, line.range.end)
        assertEquals(64f, line.naturalWidth)
        assertEquals(60f, line.adjustedWidth)
        assertEquals(60f, line.visualWidth)
        assertEquals(60f, result.clusters.sumOf { it.advance.toDouble() }.toFloat())
        assertEquals(60f, result.glyphRuns.sumOf { it.advance.toDouble() }.toFloat())

        val stop = result.clusters.single { it.text == "。" }
        assertEquals(12f, stop.advance)
        assertEquals("PushIn", result.debug.lineDecisions.single().repair)
        assertEquals(2, result.debug.lineDecisions.single().repairPenalty)
        assertTrue(
            result.debug.lineDecisions.single().notes.any {
                it.contains("ForbiddenAtLineStart:。") && it.contains("pushed-in=4.0")
            },
        )
    }

    @Test
    fun kinsokuLeavesGreedyBreakAloneWhenNoForbiddenPunctAtLineStart() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("中文中文哈哈"),
                constraints = LayoutConstraints(maxWidth = 64f),
            ),
        )

        assertEquals(2, result.lines.size)
        assertEquals(0, result.lines[0].range.start)
        assertEquals(4, result.lines[0].range.end)
        assertEquals(4, result.lines[1].range.start)
        assertEquals(6, result.lines[1].range.end)
        assertEquals(null, result.debug.lineDecisions[0].repair)
        assertEquals(null, result.debug.lineDecisions[1].repair)
    }

    @Test
    fun kinsokuFallsBackToLeaveRaggedWhenPreviousLineCannotSpareACluster() {
        // English is one cluster (7 chars, 112f). At maxWidth=96, greedy keeps it on
        // line 0 alone (i > lineStart guard) and pushes 。 to line 1. Previous line
        // has only one cluster, so CarryPrevious cannot apply -> LeaveRagged.
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("English。"),
                constraints = LayoutConstraints(maxWidth = 96f),
            ),
        )

        assertEquals(2, result.lines.size)
        assertEquals("English", result.clusters.first { it.text == "English" }.text)
        assertEquals("LeaveRagged", result.debug.lineDecisions[1].repair)
        assertEquals(20, result.debug.lineDecisions[1].repairPenalty)
        assertTrue(
            result.debug.lineDecisions[1].notes.any {
                it.contains("ForbiddenAtLineStart:。") && it.contains("no-room-to-carry")
            },
        )
    }

    @Test
    fun usesNormalizedIdeographicMetricsForCjkLineBox() {
        val result = ExplainableStubParagraphLayoutEngine().layout(
            LayoutInput(
                content = TiqianTextContent("提椠"),
                constraints = LayoutConstraints(maxWidth = 240f),
            ),
        )

        val line = result.lines.single()
        assertEquals(8f, line.baseline)
        assertEquals(16f, line.bottom)
        val cjk = result.debug.metricDecisions.first { it.role == "CjkText" }
        assertEquals(18.4f, cjk.rawAscent)
        assertEquals(8f, cjk.layoutAscent)
        assertEquals(8f, cjk.layoutDescent)
        assertEquals("IdeographicCentered", cjk.baselineClass)
        assertEquals("IdeographicEmBox", cjk.metricBox)
    }
}
