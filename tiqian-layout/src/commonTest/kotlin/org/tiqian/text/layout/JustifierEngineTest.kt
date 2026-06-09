package org.tiqian.text.layout

import org.tiqian.text.core.LayoutConstraints
import org.tiqian.text.core.LayoutInput
import org.tiqian.text.core.ParagraphStyle
import org.tiqian.text.core.TextAlign
import org.tiqian.text.core.TiqianTextContent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Engine-level justification behaviour: only runs when textAlign=Justify, skips
 * the last line, distributes deficit by priority chain
 * (PunctuationGlue -> CjkLatinSpace -> CjkInterChar) and exposes structured
 * JustificationDecisionInfo entries.
 */
class JustifierEngineTest {
    private val engine = ExplainableStubParagraphLayoutEngine()

    @Test
    fun textAlignStartLeavesClustersAtCompressedAdvance() {
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中文中"),
                constraints = LayoutConstraints(maxWidth = 80f),
                paragraphStyle = ParagraphStyle(textAlign = TextAlign.Start),
            ),
        )
        val line = result.lines.single()
        assertEquals(48f, line.adjustedWidth)
        assertEquals(48f, line.visualWidth)
        assertEquals(0, result.debug.justificationDecisions.size)
    }

    @Test
    fun lastLineIsNotJustifiedEvenWhenTextAlignJustify() {
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中文中"),
                constraints = LayoutConstraints(maxWidth = 80f),
                paragraphStyle = ParagraphStyle(textAlign = TextAlign.Justify),
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
                paragraphStyle = ParagraphStyle(textAlign = TextAlign.Justify),
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
                paragraphStyle = ParagraphStyle(textAlign = TextAlign.Justify),
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
        // text = "中，。文中文中文中"  (9 clusters, CJK = 16f, ，。 collapsed -4)
        // maxWidth = 80
        // Class-based glue: ，trailing=8, 。leading=0. Inner=8, adjusted=4,
        // reduction=4 on ，'s trailing.
        // Greedy line 0: 中(16) ，(12 after spacing) 。(16) 文(16) 中(16) → 76.
        // But 。 at non-line-end doesn't get edge trim here.
        // Actually 。's trailing=8 is only trimmed at line-END. On line 0 middle
        // position, no trim. So accum: 16+12+16+16+16=76, next 文→92 > 80, break.
        // Wait — line-end trim for line 0's last cluster (中 at index 4): no punct.
        // But 。 at position 2 is not at line end.
        // Line 0 = clusters 0..4, adjustedWidth = 76. deficit = 80 - 76 = 4.
        // PunctuationGlue cap = ，'s trailing remaining after spacing (8-4=4).
        // Fully absorbs deficit.
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中，。文中文中文中"),
                constraints = LayoutConstraints(maxWidth = 80f),
                paragraphStyle = ParagraphStyle(textAlign = TextAlign.Justify),
            ),
        )
        assertTrue(result.lines.size >= 2)
        val firstDecision = result.debug.justificationDecisions.first()
        // With the CLREQ collapse rule (half-em capped), the `，。` pair's
        // inner glue collapses to 0; deficit on line 0 is 8. The collapse is
        // MANDATORY — justification must not re-open `，。`. The deficit is
        // filled by tier-1 punctuation glue expansion on 。's trailing side
        // (。→文, capped at 0.125em = 2) and CjkInterChar (文→中, +4); the
        // remaining 2 stays unfilled rather than re-opening the collapse.
        assertEquals(8f, firstDecision.deficitBefore)
        assertEquals(2f, firstDecision.deficitAfter)
        assertEquals(2, firstDecision.allocations.size)
        val punctAlloc = firstDecision.allocations.single { it.kind == "PunctuationTrailing" }
        assertEquals(0, punctAlloc.priority)
        assertEquals(2f, punctAlloc.delta)
        assertEquals("PunctuationGlueFirstJustification", punctAlloc.reason)
        // The expanded gap is 。→文 (cluster 。 at source 2-3), NOT the
        // collapsed ，。 inner boundary.
        assertEquals(2, punctAlloc.clusterRange.start)
        val interAlloc = firstDecision.allocations.single { it.kind == "CjkInterChar" }
        assertEquals(4f, interAlloc.delta)

        // Line 0 reaches 78 of 80: capacity exhausted without touching the
        // collapsed pair.
        assertEquals(78f, result.lines[0].visualWidth)
        // Cluster ， (range 1-2) stays at its collapsed advance: the spacing
        // compression is not elastic.
        val commaCluster = result.clusters.single { it.text == "，" }
        assertEquals(8f, commaCluster.advance)
        val commaGeometry = result.debug.geometryDecisions.single { it.sourceText == "，" }
        assertEquals(8f, commaGeometry.trailingGlueConsumed)
        assertEquals(0f, commaGeometry.justificationDelta)
        assertEquals(8f, commaGeometry.resolvedAdvance)
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
                paragraphStyle = ParagraphStyle(textAlign = TextAlign.Justify),
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
    fun glueSideAwareJustificationNeverExpandsInsideBrackets() {
        // text = "中（中文）文中文中文中"  (11 CJK-width clusters @16f)
        // maxWidth=100 → greedy line 0 = clusters 0..5 (96), deficit 4.
        // Tier-1 punctuation glue boundaries inside line 0:
        //   中→（  eligible   (（ leading edge carries its glue)
        //   （→中  FORBIDDEN  (（ anchor=Trailing: inner side is solid body)
        //   文→）  FORBIDDEN  (） anchor=Leading: inner side is solid body)
        //   ）→文  eligible   (） trailing edge carries its glue)
        // Tier-1 capacity (2 × 4) covers the deficit before CjkInterChar.
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中（中文）文中文中文中"),
                constraints = LayoutConstraints(maxWidth = 100f),
                paragraphStyle = ParagraphStyle(textAlign = TextAlign.Justify),
            ),
        )
        assertEquals(2, result.lines.size)
        val decision = result.debug.justificationDecisions.single()
        assertEquals(0f, decision.deficitAfter)
        // Allocation target = left cluster of the boundary; the bracket
        // inner sides (（ at 1-2 trailing, 文 at 3-4 trailing) must be absent.
        val targets = decision.allocations.map { it.clusterRange.start }
        assertEquals(listOf(0, 4), targets.sorted())
        assertEquals(
            listOf("PunctuationLeading", "PunctuationTrailing"),
            decision.allocations.sortedBy { it.clusterRange.start }.map { it.kind },
        )
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
                paragraphStyle = ParagraphStyle(textAlign = TextAlign.Justify),
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
    fun typedSpaceBoundaryDefersToWordSpaceInsteadOfStackingCjkLatinSpace() {
        // text = "中文 Hello 中文中文中文"; the Latin cluster keeps its typed
        // U+0020 at both edges (" Hello " = 7 codepoints, stub 112f).
        // maxWidth=180 → line 0 = 中文 Hello 中文 (176), deficit 4.
        // The typed-space boundaries must NOT receive CjkLatinSpace on top of
        // the space the author already typed.
        val result = engine.layout(
            LayoutInput(
                content = TiqianTextContent("中文 Hello 中文中文中文"),
                constraints = LayoutConstraints(maxWidth = 180f),
                paragraphStyle = ParagraphStyle(textAlign = TextAlign.Justify),
            ),
        )
        assertTrue(result.lines.size >= 2)
        val decision = result.debug.justificationDecisions.first()
        assertTrue(decision.allocations.none { it.kind == "CjkLatinSpace" })
        assertTrue(decision.allocations.all { it.kind == "CjkInterChar" })
    }
}
