package org.tiqian.text.layout

import org.tiqian.text.clreq.ClreqPunctuationPolicies
import org.tiqian.text.clreq.PunctuationGluePlacement
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * CLREQ rule for adjacent half-width punctuation marks: collapse the inner
 * gap by exactly **one half-em**, capped at zero. The previous halving
 * implementation (`natural / 2`) was wrong for closing+closing and
 * opening+opening pairs — see the rule table below.
 *
 * Test grid (all at fontSize=16, half-em=8, MainlandSimplified):
 *
 * | left + right    | natural inner | adjusted | reduction |
 * |-----------------|---------------|----------|-----------|
 * | 」+。 closing+closing  | 8 + 0 = 8  | 0  | 8 |
 * | 「+（ opening+opening  | 0 + 8 = 8  | 0  | 8 |
 * | 。+「 closing+opening  | 8 + 8 = 16 | 8  | 8 |
 * | ，+ opening (e.g. 「)  | 8 + 8 = 16 | 8  | 8 |
 *
 * Reduction is always **half-em** at fontSize=16 (= 8 px), never half of
 * the natural inner glue.
 */
class PunctuationSpacingRuleTest {

    private val builder = PunctuationAtomBuilder(PunctuationGluePlacement.MainlandSimplified)
    private val compressor = PunctuationSpacingCompressor()
    private val em = 16f

    @Test
    fun closingPlusClosingCollapsesInnerToZero() {
        // 」 (Closing) + 。 (PauseOrStop): both trailing-anchored.
        // Natural inner = 」.trailing(8) + 。.leading(0) = 8.
        // CLREQ wants bodies to touch: adjusted=0, reduction=8.
        val atoms = listOf(atom('」', 0), atom('。', 1))
        val plan = compressor.compress(atoms, em)
        val adj = plan.adjustments.single()
        assertEquals(8f, adj.naturalInnerGlue)
        assertEquals(0f, adj.adjustedInnerGlue)
        assertEquals(8f, adj.reduction)
    }

    @Test
    fun openingPlusOpeningCollapsesInnerToZero() {
        // 「 (Opening) + （ (Opening): both leading-anchored.
        // Natural inner = 「.trailing(0) + （.leading(8) = 8.
        val atoms = listOf(atom('「', 0), atom('（', 1))
        val plan = compressor.compress(atoms, em)
        val adj = plan.adjustments.single()
        assertEquals(8f, adj.naturalInnerGlue)
        assertEquals(0f, adj.adjustedInnerGlue)
        assertEquals(8f, adj.reduction)
    }

    @Test
    fun closingPlusOpeningKeepsHalfEmGap() {
        // 。 (PauseOrStop) + 「 (Opening): both faces toward each other.
        // Natural inner = 。.trailing(8) + 「.leading(8) = 16.
        // CLREQ wants half-em gap between bodies: adjusted=8, reduction=8.
        val atoms = listOf(atom('。', 0), atom('「', 1))
        val plan = compressor.compress(atoms, em)
        val adj = plan.adjustments.single()
        assertEquals(16f, adj.naturalInnerGlue)
        assertEquals(8f, adj.adjustedInnerGlue)
        assertEquals(8f, adj.reduction)
    }

    @Test
    fun pauseStopPlusOpeningCollapsesByHalfEm() {
        // ， + 「: symmetric to 。「 above.
        val atoms = listOf(atom('，', 0), atom('「', 1))
        val plan = compressor.compress(atoms, em)
        val adj = plan.adjustments.single()
        assertEquals(16f, adj.naturalInnerGlue)
        assertEquals(8f, adj.adjustedInnerGlue)
        assertEquals(8f, adj.reduction)
    }

    @Test
    fun nonAdjacentPunctuationAtomsAreNotCompressed() {
        // atoms whose ranges don't touch (different chars) are ignored.
        val a = atom('，', 0)
        val b = atom('。', 5) // non-adjacent range
        val plan = compressor.compress(listOf(a, b), em)
        assertEquals(0, plan.adjustments.size)
    }

    private fun atom(char: Char, index: Int): PunctuationAtom {
        val range = org.tiqian.text.core.TextRange(index, index + 1)
        return builder.build(char = char, range = range, em = em)!!
            .also {
                // Sanity: every atom we use in this test has at least one side of glue.
                val polClass = ClreqPunctuationPolicies.classify(char)
                check(polClass != org.tiqian.text.clreq.PunctuationClass.Other) {
                    "unexpected punctuation class for $char"
                }
            }
    }
}
