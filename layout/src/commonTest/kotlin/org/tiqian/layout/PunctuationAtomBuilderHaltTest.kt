package org.tiqian.layout

import org.tiqian.clreq.InteriorPunctuationStyle
import org.tiqian.clreq.PunctuationWidthPolicy
import org.tiqian.core.Rect
import org.tiqian.core.TextRange
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

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
        assertEquals("ProfileDerivedWithShapedAdvance", atom.geometrySource)
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
            org.tiqian.clreq.PunctuationGluePlacement.Traditional,
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

    @Test
    fun bookTitleBracketsKeepInkInsideCompressedAnchoredBodies() {
        val opening = builder.build(
            char = '《',
            range = TextRange(0, 1),
            em = em,
            inkInput = PunctuationInkInput(
                advance = 16f,
                inkBounds = Rect(left = 6.5f, top = -12f, right = 15.5f, bottom = 2f),
            ),
        )!!
        val closing = builder.build(
            char = '》',
            range = TextRange(1, 2),
            em = em,
            inkInput = PunctuationInkInput(
                advance = 16f,
                inkBounds = Rect(left = 0.5f, top = -12f, right = 9.5f, bottom = 2f),
            ),
        )!!

        assertEquals(9.5f, opening.bodyWidth)
        assertEquals(6.5f, opening.leadingGlue.natural)
        assertEquals(0f, opening.trailingGlue.natural)
        assertEquals(9.5f, closing.bodyWidth)
        assertEquals(0f, closing.leadingGlue.natural)
        assertEquals(6.5f, closing.trailingGlue.natural)
        assertTrue(opening.inkContainmentApplied)
        assertTrue(closing.inkContainmentApplied)

        // Fully consuming the opening mark's leading glue shifts its raw glyph
        // left by 6.5px: ink 6.5..15.5 becomes 0..9 and fits the 9.5px body.
        assertTrue(15.5f - opening.leadingGlue.natural <= opening.bodyWidth)
        assertTrue(9.5f <= closing.bodyWidth)
    }

    @Test
    fun forcedHalfWidthExpandsAndAnchorsWhenBookTitleInkDoesNotFit() {
        val atom = builder.build(
            char = '《',
            range = TextRange(0, 1),
            em = em,
            inkInput = PunctuationInkInput(
                advance = 16f,
                inkBounds = Rect(left = 6.5f, top = -12f, right = 15.5f, bottom = 2f),
            ),
            widthPolicy = PunctuationWidthPolicy(interior = InteriorPunctuationStyle.Kaiming),
        )!!

        assertEquals(9.5f, atom.advance)
        assertEquals(9.5f, atom.bodyWidth)
        assertEquals(-6.5f, atom.glyphInlineShift)
        assertEquals("ForcedHalfWidthGlyphAnchorShift", atom.glyphPlacementReason)
        assertTrue(atom.inkContainmentApplied)
    }

    @Test
    fun openingInkOverhangIsShiftedInsideItsCompressedBody() {
        val atom = builder.build(
            char = '《',
            range = TextRange(0, 1),
            em = em,
            inkInput = PunctuationInkInput(
                advance = 16f,
                inkBounds = Rect(left = 6.5f, top = -12f, right = 17f, bottom = 2f),
            ),
        )!!

        assertEquals(10.5f, atom.inkContainmentBodyFloor)
        assertEquals(10.5f, atom.bodyWidth)
        assertEquals(-1f, atom.glyphInlineShift)
        assertEquals("InkContainmentGlyphShift", atom.glyphPlacementReason)

        val compressedOrigin = atom.glyphInlineShift - atom.leadingGlue.natural
        assertEquals(0f, 6.5f + compressedOrigin, 0.001f)
        assertEquals(atom.bodyWidth, 17f + compressedOrigin, 0.001f)
    }

    @Test
    fun forcedHalfWidthReportsInkClampWhenItChangesTheAnchorShift() {
        val atom = builder.build(
            char = '《',
            range = TextRange(0, 1),
            em = em,
            inkInput = PunctuationInkInput(
                advance = 16f,
                inkBounds = Rect(left = 6.5f, top = -12f, right = 17f, bottom = 2f),
            ),
            widthPolicy = PunctuationWidthPolicy(interior = InteriorPunctuationStyle.Kaiming),
        )!!

        assertEquals(10.5f, atom.bodyWidth)
        assertEquals(-6.5f, atom.glyphInlineShift)
        assertEquals("InkContainmentGlyphShift", atom.glyphPlacementReason)
        assertEquals(0f, 6.5f + atom.glyphInlineShift, 0.001f)
        assertEquals(atom.bodyWidth, 17f + atom.glyphInlineShift, 0.001f)
    }

    @Test
    fun negativeClosingInkBearingCannotEscapeTheLeadingBody() {
        val atom = builder.build(
            char = '》',
            range = TextRange(0, 1),
            em = em,
            inkInput = PunctuationInkInput(
                advance = 16f,
                inkBounds = Rect(left = -1f, top = -12f, right = 8f, bottom = 2f),
            ),
        )!!

        assertEquals(9f, atom.inkContainmentBodyFloor)
        assertEquals(9f, atom.bodyWidth)
        assertEquals(1f, atom.glyphInlineShift)
        assertEquals("InkContainmentGlyphShift", atom.glyphPlacementReason)
        assertEquals(0f, -1f + atom.glyphInlineShift, 0.001f)
        assertEquals(atom.bodyWidth, 8f + atom.glyphInlineShift, 0.001f)
    }
}
