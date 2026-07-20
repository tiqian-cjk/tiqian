package org.tiqian.clreq

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Regional glue placement per CLREQ 3.1.3 (Punctuation Position):
 * Mainland Simplified anchors body to one side (lower-left for `。 ，`, etc.);
 * Traditional centres the body for the same punctuation. The model must
 * support three glue directions, not two.
 */
class PunctuationGluePlacementTest {

    @Test
    fun mainlandAnchorsClosingAndPauseStopToTrailing() {
        val placement = PunctuationGluePlacement.MainlandSimplified
        assertEquals(GlueSide.TrailingOnly, placement.glueSideFor(PunctuationClass.Closing))
        assertEquals(GlueSide.TrailingOnly, placement.glueSideFor(PunctuationClass.PauseOrStop))
    }

    @Test
    fun mainlandAnchorsOpeningToLeading() {
        val placement = PunctuationGluePlacement.MainlandSimplified
        assertEquals(GlueSide.LeadingOnly, placement.glueSideFor(PunctuationClass.Opening))
    }

    @Test
    fun mainlandSplitsSymmetricPunctuationOnBothSides() {
        val placement = PunctuationGluePlacement.MainlandSimplified
        assertEquals(GlueSide.BothSides, placement.glueSideFor(PunctuationClass.MiddleDot))
        assertEquals(GlueSide.BothSides, placement.glueSideFor(PunctuationClass.Ellipsis))
        assertEquals(GlueSide.BothSides, placement.glueSideFor(PunctuationClass.Dash))
        assertEquals(GlueSide.BothSides, placement.glueSideFor(PunctuationClass.Quote))
    }

    @Test
    fun traditionalCentresClosingAndPauseStop() {
        // The key regional distinction: Traditional places 。 ， in the
        // middle of the em box, so glue is split on BOTH sides — not all on
        // the trailing side like Mainland.
        val placement = PunctuationGluePlacement.Traditional
        assertEquals(GlueSide.BothSides, placement.glueSideFor(PunctuationClass.PauseOrStop))
        assertEquals(GlueSide.BothSides, placement.glueSideFor(PunctuationClass.Closing))
    }

    @Test
    fun traditionalCentresOpening() {
        val placement = PunctuationGluePlacement.Traditional
        assertEquals(GlueSide.BothSides, placement.glueSideFor(PunctuationClass.Opening))
    }

    @Test
    fun forRegionMapsClreqRegionsToCorrectPlacement() {
        assertEquals(PunctuationGluePlacement.MainlandSimplified, PunctuationGluePlacement.forRegion(ClreqRegion.Mainland))
        assertEquals(PunctuationGluePlacement.Traditional, PunctuationGluePlacement.forRegion(ClreqRegion.Taiwan))
        assertEquals(PunctuationGluePlacement.Traditional, PunctuationGluePlacement.forRegion(ClreqRegion.HongKong))
        // Custom defaults to Mainland Simplified until overridden by profile.
        assertEquals(PunctuationGluePlacement.MainlandSimplified, PunctuationGluePlacement.forRegion(ClreqRegion.Custom))
    }

    @Test
    fun builtInTaiwanAndHongKongProfilesUseTraditionalPlacement() {
        assertEquals(PunctuationGluePlacement.Traditional, ClreqProfile.TaiwanHorizontal.gluePlacement)
        assertEquals(PunctuationGluePlacement.Traditional, ClreqProfile.HongKongHorizontal.gluePlacement)
        assertEquals(PunctuationGluePlacement.MainlandSimplified, ClreqProfile.MainlandHorizontal.gluePlacement)
    }
}
