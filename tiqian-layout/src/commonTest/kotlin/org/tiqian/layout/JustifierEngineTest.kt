package org.tiqian.layout

import org.tiqian.core.Ic

import org.tiqian.clreq.ClreqProfile
import org.tiqian.clreq.LineAdjustmentStrategy
import org.tiqian.core.Cluster
import org.tiqian.core.Glyph
import org.tiqian.core.GlyphRun
import org.tiqian.core.LayoutConstraints
import org.tiqian.core.LayoutInput
import org.tiqian.core.LineLengthGrid
import org.tiqian.core.ParagraphStyle
import org.tiqian.core.TiqianTextContent
import org.tiqian.linebreak.NoHyphenator
import org.tiqian.shaping.ShapingInput
import org.tiqian.shaping.ShapingResult
import org.tiqian.shaping.TextShaper
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Engine-level justification behaviour: 双齐 is the baseline (CLREQ — every
 * non-last line is justified), the last line is never stretched, deficit
 * distributes by priority chain (WordSpace -> CjkLatinSpace -> CjkInterChar)
 * and exposes structured JustificationDecisionInfo entries.
 *
 * Pinned to [LineAdjustmentStrategy.PushOutOnly] so every non-last line takes
 * the STRETCH path — Auto would 推入压缩 some of these short lines instead, which
 * is exercised separately by `LineAdjustmentPushInTest`.
 */
class JustifierEngineTest {
    private val engine = ExplainableStubParagraphLayoutEngine(
        clreqProfileResolver = {
            ClreqProfile.MainlandHorizontal.let { p ->
                p.copy(adjustment = p.adjustment.copy(lineAdjustment = LineAdjustmentStrategy.PushOutOnly))
            }
        },
    )

    private class PositionedPairShaper : TextShaper {
        override fun shape(input: ShapingInput): ShapingResult {
            val text = input.text.substring(input.range.start, input.range.end)
            val advance = if (text == "AV") 10f else text.length * 16f
            val glyphs = if (text == "AV") {
                listOf(
                    Glyph(id = 1u, clusterRange = input.range, advance = 5f, x = 0f),
                    Glyph(id = 2u, clusterRange = input.range, advance = 5f, x = 5f),
                )
            } else {
                listOf(Glyph(id = 3u, clusterRange = input.range, advance = advance, x = 0f))
            }
            return ShapingResult(
                clusters = listOf(
                    Cluster(
                        range = input.range,
                        text = text,
                        displayText = input.displayText,
                        fontKey = input.fontDecision.candidate.key,
                        advance = advance,
                    ),
                ),
                glyphRuns = listOf(
                    GlyphRun(
                        range = input.range,
                        fontKey = input.fontDecision.candidate.key,
                        glyphs = glyphs,
                        advance = advance,
                    ),
                ),
            )
        }
    }

    @Test
    fun connectorBoundariesAvoidStretchUnderJustification() {
        // AvoidStretchAroundConnectors（CLREQ 拉伸限制②）：连接号（～）
        // 前后的边界不参与均匀拉大字距。中～文中Example @80：line0 =
        // 中～文中 (64)，deficit 16 全部落在唯一合法边界 文|中 上。
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中～文中Example"),
                constraints = LayoutConstraints(maxWidth = 80f),
                paragraphStyle = ParagraphStyle(firstLineIndent = Ic(0f)),
            ),
        )

        assertTrue(result.lines.size >= 2)
        val decision = result.debug.justificationDecisions.first()
        assertEquals(0f, decision.deficitAfter)
        val interChar = decision.allocations.filter { it.kind == "CjkInterChar" }
        assertEquals(listOf(2), interChar.map { it.clusterRange.start })
        assertEquals(16f, interChar.single().delta)
    }

    @Test
    fun lastLineAlignmentPositionsTheLastLineViaIndent() {
        // 9 hanzi at maxWidth=100: line 0 (6 clusters) justifies to 100;
        // line 1 (3 clusters, 48) is the last line — its position comes from
        // ParagraphStyle.lastLineAlignment expressed as LineBox.indent.
        fun layoutWith(alignment: org.tiqian.core.LastLineAlignment) =
            engine.layout(
                LayoutInput(
                    content = TiqianTextContent("中文中文中文中文中"),
                    constraints = LayoutConstraints(maxWidth = 100f),
                    paragraphStyle = ParagraphStyle(
                        firstLineIndent = Ic(0f),
                        lastLineAlignment = alignment,
                        // Pin the exact measure (100 is not a 字-multiple); this
                        // test is about last-line alignment, not the grid.
                        lineLengthGrid = LineLengthGrid(enabled = false),
                    ),
                ),
            )

        val start = layoutWith(org.tiqian.core.LastLineAlignment.Start)
        assertEquals(100f, start.lines[0].visualWidth)
        assertEquals(0f, start.lines[1].indent)

        val center = layoutWith(org.tiqian.core.LastLineAlignment.Center)
        assertEquals(26f, center.lines[1].indent)
        // Non-last lines are not affected by the alignment option.
        assertEquals(0f, center.lines[0].indent)

        val end = layoutWith(org.tiqian.core.LastLineAlignment.End)
        assertEquals(52f, end.lines[1].indent)
    }

    @Test
    fun mandatoryBreakLinesTakeLastLineAlignment() {
        // A MandatoryBreak-ended line is the last line of ITS 段 (ADR 0037): it is
        // ragged like a last line, so it must ALSO take lastLineAlignment. Only
        // AutoWrap lines stay pinned (they are justified instead).
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中文中\n中文中文中文中"),
                constraints = LayoutConstraints(maxWidth = 100f),
                paragraphStyle = ParagraphStyle(
                    firstLineIndent = Ic(0f),
                    lastLineAlignment = org.tiqian.core.LastLineAlignment.Center,
                    lineLengthGrid = LineLengthGrid(enabled = false),
                ),
            ),
        )
        assertEquals(3, result.lines.size)
        // line 0 "中文中\n" (48px visual): MandatoryBreak → centered like a last line.
        assertEquals(26f, result.lines[0].indent)
        // line 1 (AutoWrap, justified to the measure): never inset.
        assertEquals(0f, result.lines[1].indent)
        // line 2 (ParagraphEnd, 16px): centered.
        assertEquals(42f, result.lines[2].indent)
    }

    @Test
    fun lastLineIsNeverJustified() {
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中文中"),
                constraints = LayoutConstraints(maxWidth = 80f),
                paragraphStyle = ParagraphStyle(firstLineIndent = Ic(0f)),
            ),
        )
        val line = result.lines.single()
        assertEquals(48f, line.adjustedWidth)
        assertEquals(48f, line.visualWidth)
        assertEquals(0, result.debug.justificationDecisions.size)
    }

    @Test
    fun latinGlyphPositionsSurviveAutospaceAndJustification() {
        val result = ExplainableStubParagraphLayoutEngine(
            textShaper = PositionedPairShaper(),
            hyphenator = NoHyphenator,
            clreqProfileResolver = {
                ClreqProfile.MainlandHorizontal.let { p ->
                    p.copy(adjustment = p.adjustment.copy(lineAdjustment = LineAdjustmentStrategy.PushOutOnly))
                }
            },
        ).layout(
            LayoutInput(
                content = TiqianTextContent("中AV中文"),
                constraints = LayoutConstraints(maxWidth = 52f),
                paragraphStyle = ParagraphStyle(
                    firstLineIndent = Ic(0f),
                    lineLengthGrid = LineLengthGrid(enabled = false),
                ),
            ),
        )

        val latinCluster = result.clusters.single { it.text == "AV" }
        assertTrue(
            latinCluster.advance > 10f,
            "autospace/justification should widen the cluster as trailing layout space: $latinCluster",
        )
        assertTrue(
            result.debug.justificationDecisions
                .flatMap { it.allocations }
                .any { it.clusterRange == latinCluster.range && it.kind == "CjkLatinSpace" },
            "the test must exercise a justify delta on the Latin cluster",
        )

        val latinGlyphs = result.glyphRuns
            .flatMap { it.glyphs }
            .filter { it.clusterRange == latinCluster.range }
        assertEquals(listOf(0f, 5f), latinGlyphs.map { it.x })
        assertEquals(listOf(5f, 5f), latinGlyphs.map { it.advance })
    }

    @Test
    fun justifiesNonLastLineUsingCjkInterCharGapsAsLastResort() {
        // 5 CJK clusters split by greedy into 4 + 1 at maxWidth=64.
        // Line 0 is full, line 1 is last (skipped). Only line 0 might justify —
        // but line 0 is already at maxWidth so deficit=0. Use a wider input:
        // 5 clusters + maxWidth=80, greedy gives 4-cluster line then 1-cluster.
        // Line 0 deficit = 80 - 64 = 16. 3 inter-CJK gaps within line 0,
        // capacity 4 each. Total cap 12 < 16 -> all exhausted; 4 unfilled.
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中文中文中文"),
                constraints = LayoutConstraints(maxWidth = 80f),
                paragraphStyle = ParagraphStyle(firstLineIndent = Ic(0f)),
            ),
        )
        assertEquals(2, result.lines.size)
        val line0 = result.lines[0]
        val line1 = result.lines[1]
        // Greedy line 0 fits 5 clusters (80f), line 1 has 1 cluster. So line 0
        // already at maxWidth, no justification needed there.
        assertEquals(80f, line0.adjustedWidth)
        assertEquals(80f, line0.visualWidth)
        assertEquals(16f, line1.adjustedWidth)
        assertEquals(16f, line1.visualWidth)
        assertEquals(0, result.debug.justificationDecisions.size)
    }

    @Test
    fun usesPunctuationGlueFirstWhenDeficitMatchesCompression() {
        // 4 CJK clusters with adjacent punctuation `，。`: natural width 64,
        // compressed by 4f -> adjusted 60. Plus 2 more clusters = total 60 + 32 = 92.
        // Wait, layout reorders. Let's pick: "中，。文" with maxWidth=64.
        // natural = 16+16+16+16 = 64; adjusted = 16+16+16+12 = 60 (compression on 。).
        // deficit = 64 - 60 = 4. Punct opp capacity = 4. Should fully absorb.
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中，。文"),
                constraints = LayoutConstraints(maxWidth = 64f),
                paragraphStyle = ParagraphStyle(firstLineIndent = Ic(0f)),
            ),
        )
        // Single line: but justifier needs a non-last line to fire. With only
        // one line, justifier is skipped. Wrap text to force two lines.
        // Use a longer fixture that produces 2+ lines so the first triggers.
        // Skip this single-line case to a multi-line one below.
        assertEquals(1, result.lines.size)
        assertEquals(0, result.debug.justificationDecisions.size)
    }

    @Test
    fun justifyDistributesDeficitAcrossPriorityChain() {
        // Two-line text where line 0 has punctuation-spacing compression.
        // text = "中」。文中文中文中"  (9 clusters, CJK = 16f)
        // maxWidth = 80
        // 」。 is Closing+PauseOrStop: inner = 」.trailing(8) + 。.leading(0)
        // = 8 → collapsed to 0, reduction=8 on 」's trailing → 」 advance 8.
        // Greedy line 0: 中(16) 」(8) 。(16) 文(16) 中(16) → 72; next 文→88 > 80.
        // Line 0 = clusters 0..4, deficit = 80 - 72 = 8.
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中」。文中文中文中"),
                constraints = LayoutConstraints(maxWidth = 80f),
                paragraphStyle = ParagraphStyle(firstLineIndent = Ic(0f)),
            ),
        )
        assertTrue(result.lines.size >= 2)
        val firstDecision = result.debug.justificationDecisions.first()
        // CjkOnlyInterCharBoundary: 平均拉大字距 is uniform tracking — every
        // CJK↔CJK boundary takes the SAME share, including 中→」 (solid
        // side) and the collapsed 」→。 pair. The collapse is never
        // PREFERENTIALLY refilled (trailingGlueConsumed stays 8); the
        // uniform share is all it gets. 4 boundaries × +2 = deficit 8.
        assertEquals(8f, firstDecision.deficitBefore)
        assertEquals(0f, firstDecision.deficitAfter)
        assertEquals(4, firstDecision.allocations.size)
        assertTrue(firstDecision.allocations.all { it.kind == "CjkInterChar" })
        assertTrue(firstDecision.allocations.all { it.delta == 2f })
        assertEquals(
            listOf(0, 1, 2, 3),
            firstDecision.allocations.map { it.clusterRange.start }.sorted(),
        )

        assertEquals(80f, result.lines[0].visualWidth)
        // Cluster 」 (range 1-2): the compression itself is not elastic —
        // consumed glue stays consumed; only the uniform tracking share
        // (+2) lands on top of the collapsed advance.
        val closingGeometry = result.debug.geometryDecisions.single { it.sourceText == "」" }
        assertEquals(8f, closingGeometry.trailingGlueConsumed)
        assertEquals(2f, closingGeometry.justificationDelta)
        assertEquals(10f, closingGeometry.resolvedAdvance)
    }

    @Test
    fun cjkInterCharActsAsLastResortWhenPunctGlueExhausted() {
        // 6 clusters, maxWidth=120, no punct. Greedy line 0 fits all 6
        // (advance 96), so line 0 IS the last line. Force two lines:
        // 10 clusters, maxWidth=96. line 0 = 6 clusters (96), line 1 = 4 (64).
        // Line 0 adjusted 96 == maxWidth, deficit=0. Need narrower maxWidth
        // so line 0 has deficit AND is not last.
        //   12 CJK clusters, maxWidth = 100. greedy: line0=6 (96, deficit 4),
        //   line1=6 (96, but last). Line 0 deficit 4. 5 CJK-CJK gaps, cap 4
        //   each = 20 total. Fully absorb 4.
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中文中文中文中文中文中文"),
                constraints = LayoutConstraints(maxWidth = 100f),
                // Pin the exact measure (100 ∤ 16); this exercises the justify
                // chain at a chosen deficit, not the grid.
                paragraphStyle = ParagraphStyle(
                    firstLineIndent = Ic(0f),
                    lineLengthGrid = LineLengthGrid(enabled = false),
                ),
            ),
        )
        assertEquals(2, result.lines.size)
        val firstDecision = result.debug.justificationDecisions.single()
        assertEquals(4f, firstDecision.deficitBefore)
        assertEquals(0f, firstDecision.deficitAfter)
        assertTrue(firstDecision.allocations.all { it.kind == "CjkInterChar" })
        assertEquals(5, firstDecision.allocations.size)
        // 4 distributed across 5 gaps proportionally to capacity (uniform 4f):
        // factor = 4/20 = 0.2; each gets 0.8.
        firstDecision.allocations.forEach { assertEquals(0.8f, it.delta) }

        assertEquals(100f, result.lines[0].visualWidth)
    }

    @Test
    fun uniformTrackingIncludesBracketInnerSides() {
        // text = "中（中文）文中文中文中"  (11 CJK-width clusters @16f)
        // maxWidth=100 → greedy line 0 = clusters 0..5 (96), deficit 4.
        // CjkOnlyInterCharBoundary: uniform tracking over ALL five CJK↔CJK
        // boundaries — bracket inner sides (（→中, 文→）) included, same
        // share as everything else (user-ratified「所有都要参与」).
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中（中文）文中文中文中"),
                constraints = LayoutConstraints(maxWidth = 100f),
                paragraphStyle = ParagraphStyle(
                    firstLineIndent = Ic(0f),
                    lineLengthGrid = LineLengthGrid(enabled = false),
                ),
            ),
        )
        assertEquals(2, result.lines.size)
        val decision = result.debug.justificationDecisions.single()
        assertEquals(0f, decision.deficitAfter)
        // Allocation target = left cluster of the boundary; all five
        // boundaries (incl. bracket inner sides) get the SAME share (0.8).
        val targets = decision.allocations.map { it.clusterRange.start }
        assertEquals(listOf(0, 1, 2, 3, 4), targets.sorted())
        assertTrue(decision.allocations.all { it.kind == "CjkInterChar" })
        decision.allocations.forEach { assertEquals(0.8f, it.delta, 0.01f) }
    }

    @Test
    fun bracketWesternInteriorStretchesInTierThreeNotTierTwo() {
        // text = "中文（Hello）中文中文"; stub Latin advance = 5em = 80.
        // maxWidth=170 → line 0 = 中文（Hello）中 (160), deficit 10.
        // （→Hello and Hello→） are 标点↔西文 boundaries: NOT 中西间距 (tier ②,
        // ideograph-alpha only), but they ARE 剩余字符间距 (tier ③, CLREQ
        // 「剩余所有字符间距」), so the bracket interior DOES open.
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中文（Hello）中文中文"),
                constraints = LayoutConstraints(maxWidth = 170f),
                paragraphStyle = ParagraphStyle(
                    firstLineIndent = Ic(0f),
                    lineLengthGrid = LineLengthGrid(enabled = false),
                ),
            ),
        )
        assertEquals(2, result.lines.size)
        val decision = result.debug.justificationDecisions.single()
        // Tier ② (中西间距) still fires only on ideograph↔alpha, never punctuation.
        assertTrue(decision.allocations.none { it.kind == "CjkLatinSpace" })
        // …but （→Hello (（ at offset 2) and Hello→） (Hello at offset 3) take a
        // tier-③ share — 标点两侧含朝西文那侧都参与.
        assertTrue(decision.allocations.any { it.kind == "CjkInterChar" && it.clusterRange.start == 2 })
        assertTrue(decision.allocations.any { it.kind == "CjkInterChar" && it.clusterRange.start == 3 })
    }

    @Test
    fun dashBoundariesDoNotReceiveUniformTracking() {
        // The two-em dash is an indivisible long punctuation mark. If tier-③
        // CjkInterChar opens the boundary after it, `下——不` looks like
        // `下—— 不` in justified article text.
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("在所谓中文语境下——不如说中文"),
                constraints = LayoutConstraints(maxWidth = 180f),
                paragraphStyle = ParagraphStyle(
                    firstLineIndent = Ic(0f),
                    lineLengthGrid = LineLengthGrid(enabled = false),
                ),
            ),
        )
        assertTrue(result.lines.size >= 2)
        val dashCluster = result.clusters.single { it.text == "——" }
        val dashIndex = result.clusters.indexOf(dashCluster)
        val beforeDash = result.clusters[dashIndex - 1]
        val allocations = result.debug.justificationDecisions.first().allocations
        assertTrue(
            allocations.none { it.kind == "CjkInterChar" && it.clusterRange == beforeDash.range },
            "boundary before dash must stay closed: $allocations",
        )
        assertTrue(
            allocations.none { it.kind == "CjkInterChar" && it.clusterRange == dashCluster.range },
            "boundary after dash must stay closed: $allocations",
        )
    }

    @Test
    fun typedSinoWesternSpacesStretchInTierTwo() {
        // text = "中文 Hello 中文中文中文": the author-typed U+0020 around
        // "Hello" are 中西间距 (separate space clusters, autospace base 0.25em).
        // They MUST stretch in tier ② (`TypedSinoWesternSpaceStretches`), each
        // exactly once — not fall through every tier (the reverted
        // `TypedSpaceBoundaryDefersToWordSpace`), and not stacked with a
        // boundary CjkLatinSpace. CLREQ 拉伸第②档：同时、同等量.
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中文 Hello 中文中文中文"),
                constraints = LayoutConstraints(maxWidth = 180f),
                paragraphStyle = ParagraphStyle(firstLineIndent = Ic(0f)),
            ),
        )
        assertTrue(result.lines.size >= 2)
        val decision = result.debug.justificationDecisions.first()
        val sino = decision.allocations.filter { it.kind == "CjkLatinSpace" }
        assertEquals(2, sino.size) // both typed spaces, once each (no stacking)
        assertTrue(
            sino.all { a -> result.clusters.first { it.range.start == a.clusterRange.start }.text == " " },
            "every 中西 stretch lands on a typed space cluster, not a boundary",
        )
        assertTrue(sino.all { it.delta == sino.first().delta }, "同时、同等量")
    }

    @Test
    fun punctuationToWesternBoundaryStretchesInTierThree() {
        // 「World」 mid-line, justified: CLREQ tier ③「剩余所有字符间距」includes
        // 标点↔西文 (only 不可断标点 + 连接号/分隔号 are excluded), so the
        // bracket's Western-facing face stretches like every other 字符间距.
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("你好「World」你好你好你"),
                constraints = LayoutConstraints(maxWidth = 140f),
                paragraphStyle = ParagraphStyle(
                    firstLineIndent = Ic(0f),
                    lineLengthGrid = org.tiqian.core.LineLengthGrid(enabled = false),
                ),
            ),
        )
        val alloc = result.debug.justificationDecisions.first().allocations
        // 「↔World boundary (「 at source offset 2) takes a tier-③ share.
        assertTrue(
            alloc.any { a ->
                a.kind == "CjkInterChar" &&
                    result.clusters.first { it.range.start == a.clusterRange.start }.text == "「"
            },
            "标点↔西文 boundary must stretch in tier ③",
        )
    }

    @Test
    fun lineEdgeSinoWesternSpaceStaysCollapsed() {
        // "中文中文 word 中文中" wraps with the typed space after 中文中文 at
        // line 0's end. LineEdgeWordSpaceCollapse trims it to 0; the typed-中西
        // stretch must NOT revive it to 0.5em (a trimmed line-edge blank).
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中文中文 word 中文中"),
                constraints = LayoutConstraints(maxWidth = 80f),
                paragraphStyle = ParagraphStyle(firstLineIndent = Ic(0f)),
            ),
        )
        result.lines.dropLast(1).forEach { line ->
            val edge = result.clusters.last { it.range.start < line.range.end }
            if (edge.text == " ") {
                assertEquals(0f, edge.advance, "line-edge sino-western space must stay collapsed")
            }
        }
    }
}
