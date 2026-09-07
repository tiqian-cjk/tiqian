package org.tiqian.clreq;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

/**
 * Regional glue placement per CLREQ 3.1.3 (Punctuation Position):
 * Mainland Simplified anchors the body to one side; Traditional centres it.
 * The model supports three glue directions, not two.
 */
class PunctuationGluePlacementTest {
    @:test
    public static function mainlandAnchorsClosingAndPauseStopToTrailing():Void {
        new TestTraceRecorder("PunctuationGluePlacementTest").section("mainlandAnchorsClosingAndPauseStopToTrailing");
        final placement = PunctuationGluePlacement.MainlandSimplified;
        TracedAssertions.assertEqualsGlueSide(GlueSide.TrailingOnly, PunctuationGluePlacements.glueSideFor(placement, PunctuationClass.Closing));
        TracedAssertions.assertEqualsGlueSide(GlueSide.TrailingOnly, PunctuationGluePlacements.glueSideFor(placement, PunctuationClass.PauseOrStop));
    }

    @:test
    public static function mainlandAnchorsOpeningToLeading():Void {
        new TestTraceRecorder("PunctuationGluePlacementTest").section("mainlandAnchorsOpeningToLeading");
        final placement = PunctuationGluePlacement.MainlandSimplified;
        TracedAssertions.assertEqualsGlueSide(GlueSide.LeadingOnly, PunctuationGluePlacements.glueSideFor(placement, PunctuationClass.Opening));
    }

    @:test
    public static function mainlandSplitsSymmetricPunctuationOnBothSides():Void {
        new TestTraceRecorder("PunctuationGluePlacementTest").section("mainlandSplitsSymmetricPunctuationOnBothSides");
        final placement = PunctuationGluePlacement.MainlandSimplified;
        TracedAssertions.assertEqualsGlueSide(GlueSide.BothSides, PunctuationGluePlacements.glueSideFor(placement, PunctuationClass.MiddleDot));
        TracedAssertions.assertEqualsGlueSide(GlueSide.BothSides, PunctuationGluePlacements.glueSideFor(placement, PunctuationClass.Ellipsis));
        TracedAssertions.assertEqualsGlueSide(GlueSide.BothSides, PunctuationGluePlacements.glueSideFor(placement, PunctuationClass.Dash));
    }

    @:test
    public static function traditionalCentresClosingAndPauseStop():Void {
        new TestTraceRecorder("PunctuationGluePlacementTest").section("traditionalCentresClosingAndPauseStop");
        // The key regional distinction: Traditional centres the pause marks,
        // so glue splits on BOTH sides instead of all trailing.
        final placement = PunctuationGluePlacement.Traditional;
        TracedAssertions.assertEqualsGlueSide(GlueSide.BothSides, PunctuationGluePlacements.glueSideFor(placement, PunctuationClass.PauseOrStop));
        TracedAssertions.assertEqualsGlueSide(GlueSide.BothSides, PunctuationGluePlacements.glueSideFor(placement, PunctuationClass.Closing));
    }

    @:test
    public static function traditionalCentresOpening():Void {
        new TestTraceRecorder("PunctuationGluePlacementTest").section("traditionalCentresOpening");
        final placement = PunctuationGluePlacement.Traditional;
        TracedAssertions.assertEqualsGlueSide(GlueSide.BothSides, PunctuationGluePlacements.glueSideFor(placement, PunctuationClass.Opening));
    }

    @:test
    public static function forRegionMapsClreqRegionsToCorrectPlacement():Void {
        new TestTraceRecorder("PunctuationGluePlacementTest").section("forRegionMapsClreqRegionsToCorrectPlacement");
        TracedAssertions.assertEqualsPunctuationGluePlacement(PunctuationGluePlacement.MainlandSimplified,
            PunctuationGluePlacements.forRegion(ClreqRegion.Mainland));
        TracedAssertions.assertEqualsPunctuationGluePlacement(PunctuationGluePlacement.Traditional, PunctuationGluePlacements.forRegion(ClreqRegion.Taiwan));
        TracedAssertions.assertEqualsPunctuationGluePlacement(PunctuationGluePlacement.Traditional, PunctuationGluePlacements.forRegion(ClreqRegion.HongKong));
        // Custom defaults to Mainland Simplified until overridden by profile.
        TracedAssertions.assertEqualsPunctuationGluePlacement(PunctuationGluePlacement.MainlandSimplified,
            PunctuationGluePlacements.forRegion(ClreqRegion.Custom));
    }

    @:test
    public static function builtInTaiwanAndHongKongProfilesUseTraditionalPlacement():Void {
        new TestTraceRecorder("PunctuationGluePlacementTest").section("builtInTaiwanAndHongKongProfilesUseTraditionalPlacement");
        TracedAssertions.assertEqualsPunctuationGluePlacement(PunctuationGluePlacement.Traditional, ClreqProfile.TaiwanHorizontal.gluePlacement);
        TracedAssertions.assertEqualsPunctuationGluePlacement(PunctuationGluePlacement.Traditional, ClreqProfile.HongKongHorizontal.gluePlacement);
        TracedAssertions.assertEqualsPunctuationGluePlacement(PunctuationGluePlacement.MainlandSimplified, ClreqProfile.MainlandHorizontal.gluePlacement);
    }
}
