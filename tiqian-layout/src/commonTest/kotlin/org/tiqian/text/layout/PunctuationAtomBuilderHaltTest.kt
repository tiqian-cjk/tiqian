package org.tiqian.text.layout

import org.tiqian.text.core.Rect
import org.tiqian.text.core.TextRange
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * FontHaltDerivedBody (ADR 0014 follow-up): when the shaper reports an
 * OpenType `halt` advance, it is the font designer's own half-width body and
 * replaces the policy `0.5em`. The glue direction stays profile-derived;
 * only the body/glue split changes.
 */
class PunctuationAtomBuilderHaltTest {

    private val builder = PunctuationAtomBuilder()
    private val em = 16f

    @Test
    fun haltAdvanceReplacesPolicyBody() {
        // A font whose 。 body is 7.5 (not exactly half of the 16 advance):
        // body must follow the font, glue gets the remainder on the
        // profile-decided side (PauseOrStop → trailing in MainlandSimplified).
        val atom = builder.build(
            char = '。',
            range = TextRange(0, 1),
            em = em,
            inkInput = PunctuationInkInput(advance = 16f, haltAdvance = 7.5f),
        )!!

        assertEquals(7.5f, atom.bodyWidth)
        assertEquals(7.5f, atom.haltAdvance)
        assertEquals(0f, atom.leadingGlue.natural)
        assertEquals(8.5f, atom.trailingGlue.natural)
        assertEquals("FontHaltDerived", atom.geometrySource)
    }

    @Test
    fun haltWithInkBoundsReportsCombinedSource() {
        val atom = builder.build(
            char = '，',
            range = TextRange(0, 1),
            em = em,
            inkInput = PunctuationInkInput(
                advance = 16f,
                inkBounds = Rect(left = 2f, top = -4f, right = 5f, bottom = 1f),
                haltAdvance = 8f,
            ),
        )!!

        assertEquals(8f, atom.bodyWidth)
        assertEquals("FontHaltDerivedWithInkDiagnostics", atom.geometrySource)
    }

    @Test
    fun haltEqualToAdvanceIsIgnored() {
        // halt == full advance means the font has no alternate; fall back to
        // the policy body (defensive — the shaper already nulls this case).
        val atom = builder.build(
            char = '。',
            range = TextRange(0, 1),
            em = em,
            inkInput = PunctuationInkInput(advance = 16f, haltAdvance = 16f),
        )!!

        assertEquals(8f, atom.bodyWidth)
        assertEquals(null, atom.haltAdvance)
        assertEquals("ClassDerivedWithShapedAdvance", atom.geometrySource)
    }

    @Test
    fun haltPlacementConsistentWithProfileProducesNoWarning() {
        // MainlandSimplified + Source Han-like halt data: 。 trims trailing
        // (placement 0), （ trims leading (placement -8) — both match the
        // profile glue sides, no warning.
        val stop = builder.build(
            char = '。',
            range = TextRange(0, 1),
            em = em,
            inkInput = PunctuationInkInput(advance = 16f, haltAdvance = 8f, haltPlacementX = 0f),
        )!!
        assertEquals(null, stop.haltValidation)

        val open = builder.build(
            char = '（',
            range = TextRange(0, 1),
            em = em,
            inkInput = PunctuationInkInput(advance = 16f, haltAdvance = 8f, haltPlacementX = -8f),
        )!!
        assertEquals(null, open.haltValidation)
    }

    @Test
    fun haltPlacementContradictingProfileIsWarned() {
        // A Traditional profile centres 。 (glue BothSides), but a Mainland-
        // designed font trims the trailing side only — the cross-check must
        // flag it while geometry keeps the profile decision.
        val traditional = PunctuationAtomBuilder(
            org.tiqian.text.clreq.PunctuationGluePlacement.Traditional,
        )
        val stop = traditional.build(
            char = '。',
            range = TextRange(0, 1),
            em = em,
            inkInput = PunctuationInkInput(advance = 16f, haltAdvance = 8f, haltPlacementX = 0f),
        )!!

        assertEquals("halt-trims-trailing-but-profile-glue-both", stop.haltValidation)
        // Geometry unchanged: glue still split per profile.
        assertEquals(4f, stop.leadingGlue.natural)
        assertEquals(4f, stop.trailingGlue.natural)
    }

    @Test
    fun haltBodyFeedsCompressionAndGlueModelUnchanged() {
        // 」。 with halt bodies: compression semantics stay the same — the
        // inner gap (」 trailing glue) collapses by half-em regardless of
        // whether the body came from halt or policy.
        val closing = builder.build(
            char = '」',
            range = TextRange(0, 1),
            em = em,
            inkInput = PunctuationInkInput(advance = 16f, haltAdvance = 8f),
        )!!
        val stop = builder.build(
            char = '。',
            range = TextRange(1, 2),
            em = em,
            inkInput = PunctuationInkInput(advance = 16f, haltAdvance = 8f),
        )!!

        val plan = PunctuationSpacingCompressor().compress(listOf(closing, stop), em)
        val adj = plan.adjustments.single()
        assertEquals(8f, adj.naturalInnerGlue)
        assertEquals(0f, adj.adjustedInnerGlue)
        assertEquals(8f, adj.reduction)
    }
}
