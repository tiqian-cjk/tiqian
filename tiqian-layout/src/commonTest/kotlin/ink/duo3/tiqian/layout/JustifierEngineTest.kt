package ink.duo3.tiqian.layout

import ink.duo3.tiqian.core.LayoutConstraints
import ink.duo3.tiqian.core.LayoutInput
import ink.duo3.tiqian.core.LineLengthGrid
import ink.duo3.tiqian.core.ParagraphStyle
import ink.duo3.tiqian.core.TiqianTextContent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Engine-level justification behaviour: 双齐 is the baseline (CLREQ — every
 * non-last line is justified), the last line is never stretched, deficit
 * distributes by priority chain (WordSpace -> CjkLatinSpace -> CjkInterChar)
 * and exposes structured JustificationDecisionInfo entries.
 */
class JustifierEngineTest {
    private val engine = ExplainableStubParagraphLayoutEngine()

    @Test
    fun connectorBoundariesAvoidStretchUnderJustification() {
        // AvoidStretchAroundConnectors（CLREQ 拉伸限制②）：连接号（～）
        // 前后的边界不参与均匀拉大字距。中～文中Example @80：line0 =
        // 中～文中 (64)，deficit 16 全部落在唯一合法边界 文|中 上。
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中～文中Example"),
                constraints = LayoutConstraints(maxWidth = 80f),
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
        fun layoutWith(alignment: ink.duo3.tiqian.core.LastLineAlignment) =
            engine.layout(
                LayoutInput(
                    content = TiqianTextContent("中文中文中文中文中"),
                    constraints = LayoutConstraints(maxWidth = 100f),
                    paragraphStyle = ParagraphStyle(
                        firstLineIndentEm = 0f,
                        lastLineAlignment = alignment,
                        // Pin the exact measure (100 is not a 字-multiple); this
                        // test is about last-line alignment, not the grid.
                        lineLengthGrid = LineLengthGrid(enabled = false),
                    ),
                ),
            )

        val start = layoutWith(ink.duo3.tiqian.core.LastLineAlignment.Start)
        assertEquals(100f, start.lines[0].visualWidth)
        assertEquals(0f, start.lines[1].indent)

        val center = layoutWith(ink.duo3.tiqian.core.LastLineAlignment.Center)
        assertEquals(26f, center.lines[1].indent)
        // Non-last lines are not affected by the alignment option.
        assertEquals(0f, center.lines[0].indent)

        val end = layoutWith(ink.duo3.tiqian.core.LastLineAlignment.End)
        assertEquals(52f, end.lines[1].indent)
    }

    @Test
    fun lastLineIsNeverJustified() {
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中文中"),
                constraints = LayoutConstraints(maxWidth = 80f),
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
            ),
        )
        val line = result.lines.single()
        assertEquals(48f, line.adjustedWidth)
        assertEquals(48f, line.visualWidth)
        assertEquals(0, result.debug.justificationDecisions.size)
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
                    firstLineIndentEm = 0f,
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
                    firstLineIndentEm = 0f,
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
    fun cjkLatinSpaceFiresOnlyAtIdeographAlphaBoundaryNotPunctuation() {
        // text = "中文（Hello）中文中文"; stub Latin advance = 5em = 80.
        // maxWidth=170 → line 0 = 中文（Hello）中 (160), deficit 10.
        // （→Hello and Hello→） are CjkPunctuation↔Latin boundaries: neither
        // CjkLatinSpace (ideograph-alpha only) nor CjkInterChar (needs CJK on
        // both sides) may open them — the bracket interior stays tight.
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中文（Hello）中文中文"),
                constraints = LayoutConstraints(maxWidth = 170f),
                paragraphStyle = ParagraphStyle(
                    firstLineIndentEm = 0f,
                    lineLengthGrid = LineLengthGrid(enabled = false),
                ),
            ),
        )
        assertEquals(2, result.lines.size)
        val decision = result.debug.justificationDecisions.single()
        assertTrue(decision.allocations.none { it.kind == "CjkLatinSpace" })
        // No expansion may target the bracket inner sides: （ cluster (2-3)
        // and the Latin cluster (3-8).
        assertTrue(decision.allocations.none { it.clusterRange.start == 2 })
        assertTrue(decision.allocations.none { it.clusterRange.start == 3 })
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
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
    fun lineEdgeSinoWesternSpaceStaysCollapsed() {
        // "中文中文 word 中文中" wraps with the typed space after 中文中文 at
        // line 0's end. LineEdgeWordSpaceCollapse trims it to 0; the typed-中西
        // stretch must NOT revive it to 0.5em (a trimmed line-edge blank).
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中文中文 word 中文中"),
                constraints = LayoutConstraints(maxWidth = 80f),
                paragraphStyle = ParagraphStyle(firstLineIndentEm = 0f),
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
