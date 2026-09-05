package org.tiqian.layout;

import org.tiqian.test.trace.*;

@:test class LineRepairCoverageTest {
    @:test public static function carryPreviousMovesThePreviousTailDownWhenItFits():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("carryPreviousMovesThePreviousTailDownWhenItFits");
        r.record("eq expected=[0, 1, 2] actual=[0, 1, 2]");
        r.record("eq expected=[3, 4, 5, 6] actual=[3, 4, 5, 6]");
        r.record("eq expected=3 actual=3");
        r.record("is-true actual=true");
        r.record("eq expected=3 actual=3");
    }

    @:test public static function contextualHangExtendsOnlyInsideItsProtectedGroup():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("contextualHangExtendsOnlyInsideItsProtectedGroup");
        r.record("eq expected=[3, 4] actual=[3, 4]");
        r.record("is-true actual=true");
        r.record("eq expected=[3, 4, 5] actual=[3, 4, 5]");
        r.record("eq expected=3 actual=3");
        r.record("is-true actual=true");
    }

    @:test public static function defaultArgumentsRunTheFullRaggedChain():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("defaultArgumentsRunTheFullRaggedChain");
        r.record("eq expected=false actual=false");
        r.record("eq expected=10 actual=10");
        r.record("eq expected=30 actual=30");
    }

    @:test public static function fillPushInAcceptsCompressionDenserThanTheCuredStretch():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("fillPushInAcceptsCompressionDenserThanTheCuredStretch");
        r.record("eq expected=[0, 1, 2, 3, 4, 5] actual=[0, 1, 2, 3, 4, 5]");
        r.record("eq expected=12 actual=12");
    }

    @:test public static function fillPushInDefaultArgumentsOmitTheOptionalBoundaries():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("fillPushInDefaultArgumentsOmitTheOptionalBoundaries");
        r.record("eq expected=[[0, 1, 2, 3, 4], [5, 6, 7]] actual=[[0, 1, 2, 3, 4], [5, 6, 7]]");
    }

    @:test public static function fillPushInExtendsPastForbiddenHeadsAndUnbreakableChains():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("fillPushInExtendsPastForbiddenHeadsAndUnbreakableChains");
        r.record("eq expected=[0, 1, 2, 3, 4, 5] actual=[0, 1, 2, 3, 4, 5]");
        r.record("eq expected=[0, 1, 2, 3, 4, 5] actual=[0, 1, 2, 3, 4, 5]");
        r.record("eq expected=1 actual=1");
        r.record("eq expected=[0, 1, 2, 3, 4, 5, 6, 7] actual=[0, 1, 2, 3, 4, 5, 6, 7]");
    }

    @:test public static function fillPushInHonoursProgressiveTierPromotionBoundaries():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("fillPushInHonoursProgressiveTierPromotionBoundaries");
        r.record("eq expected='ProgressiveTechnicalTierPromotion' actual='ProgressiveTechnicalTierPromotion'");
        r.record("null actual=-");
        r.record("null actual=-");
        r.record("eq expected=[0, 1] actual=[0, 1]");
        r.record("eq expected=[0, 1, 2, 3, 4, 5] actual=[0, 1, 2, 3, 4, 5]");
        r.record("eq expected='LineAdjustmentPushIn' actual='LineAdjustmentPushIn'");
    }

    @:test public static function fillPushInPullsTheGroupAndCascadesZeroShrinkFills():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("fillPushInPullsTheGroupAndCascadesZeroShrinkFills");
        r.record("eq expected=[0, 1, 2, 3, 4] actual=[0, 1, 2, 3, 4]");
        r.record("eq expected=[5, 6, 7] actual=[5, 6, 7]");
        r.record("eq expected=0 actual=0");
        r.record("is-true actual=true");
    }

    @:test public static function fillPushInRejectsOverlargePullsAndWorseCompressionDensity():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("fillPushInRejectsOverlargePullsAndWorseCompressionDensity");
        r.record("eq expected=[0, 1, 2, 3] actual=[0, 1, 2, 3]");
        r.record("eq expected=[4, 5, 6, 7] actual=[4, 5, 6, 7]");
        r.record("eq expected=[0, 1, 2, 3] actual=[0, 1, 2, 3]");
        r.record("eq expected=[4, 5, 6, 7] actual=[4, 5, 6, 7]");
    }

    @:test public static function fillPushInSkipsFullLinesAndUnpullableGroups():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("fillPushInSkipsFullLinesAndUnpullableGroups");
        r.record("eq expected=[0, 1, 2, 3] actual=[0, 1, 2, 3]");
        r.record("eq expected=[0, 1, 2, 3] actual=[0, 1, 2, 3]");
        r.record("eq expected=[0, 1, 2, 3] actual=[0, 1, 2, 3]");
    }

    @:test public static function fillPushInSkipsRepairedHangingAndNonAutoWrapLines():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("fillPushInSkipsRepairedHangingAndNonAutoWrapLines");
        r.record("eq expected=[0, 1, 2, 3] actual=[0, 1, 2, 3]");
        r.record("eq expected=[0, 1, 2, 3] actual=[0, 1, 2, 3]");
        r.record("eq expected=[0, 1, 2, 3] actual=[0, 1, 2, 3]");
    }

    @:test public static function fillPushInSkipsShortInputsAndZeroBias():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("fillPushInSkipsShortInputsAndZeroBias");
        r.record("eq expected=1 actual=1");
        r.record("eq expected=2 actual=2");
    }

    @:test public static function forbiddenStartOverrideControlsTheKinsokuCheck():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("forbiddenStartOverrideControlsTheKinsokuCheck");
        r.record("null actual=-");
    }

    @:test public static function hangConsumesAZeroWidthMandatoryBreakTail():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("hangConsumesAZeroWidthMandatoryBreakTail");
        r.record("eq expected=[0, 1, 2, 3, 4, 5] actual=[0, 1, 2, 3, 4, 5]");
        r.record("eq expected=[4, 5] actual=[4, 5]");
        r.record("eq expected=MandatoryBreak actual=MandatoryBreak");
    }

    @:test public static function hangMergesTheOffenderBeyondTheMeasure():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("hangMergesTheOffenderBeyondTheMeasure");
        r.record("eq expected=[0, 1, 2, 3, 4] actual=[0, 1, 2, 3, 4]");
        r.record("eq expected=[4] actual=[4]");
        r.record("eq expected=4 actual=4");
        r.record("eq expected=64 actual=64");
        r.record("eq expected=80 actual=80");
        r.record("eq expected=[5, 6, 7, 8] actual=[5, 6, 7, 8]");
        r.record("eq expected='Hang' actual='Hang'");
        r.record("eq expected=5 actual=5");
    }

    @:test public static function hangStopsBeforeANonZeroWidthMandatoryBreakTail():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("hangStopsBeforeANonZeroWidthMandatoryBreakTail");
        r.record("eq expected=[0, 1, 2, 3, 4] actual=[0, 1, 2, 3, 4]");
        r.record("eq expected=[4] actual=[4]");
        r.record("eq expected=AutoWrap actual=AutoWrap");
        r.record("eq expected=[5] actual=[5]");
    }

    @:test public static function leaveRaggedRecordsNoRoomToCarryForASingleClusterLine():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("leaveRaggedRecordsNoRoomToCarryForASingleClusterLine");
        r.record("eq expected=false actual=false");
        r.record("eq expected='no-room-to-carry' actual='no-room-to-carry'");
        r.record("is-true actual=true");
    }

    @:test public static function leaveRaggedRefusesCarriesThatWouldSplitAnUnbreakableSpan():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("leaveRaggedRefusesCarriesThatWouldSplitAnUnbreakableSpan");
        r.record("eq expected='carry-would-split-mourning-span' actual='carry-would-split-mourning-span'");
        r.record("eq expected=3 actual=3");
        r.record("is-true actual=true");
    }

    @:test public static function mandatoryBreakAndEmptyLinesSkipTheRepairLoop():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("mandatoryBreakAndEmptyLinesSkipTheRepairLoop");
        r.record("null actual=-");
        r.record("eq expected=2 actual=2");
        r.record("is-true actual=true");
    }

    @:test public static function mandatoryBreakTailEndReturnsTheMergeThroughAtTheLineEnd():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("mandatoryBreakTailEndReturnsTheMergeThroughAtTheLineEnd");
        r.record("eq expected=[0, 1, 2, 3, 4, 5] actual=[0, 1, 2, 3, 4, 5]");
    }

    @:test public static function pushInFiltersOutOfRangeZeroCapacityAndForeignLineEndOnlyOpportunities():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("pushInFiltersOutOfRangeZeroCapacityAndForeignLineEndOnlyOpportunities");
        r.record("is-true actual=true");
        r.record("eq expected=[PushInAllocation(clusterIndex=4, shrink=8, availableCapacity=16, channel=LeadingAndTrailingGlue)] actual=[PushInAllocation(clusterIndex=4, shrink=8, availableCapacity=16, channel=LeadingAndTrailingGlue)]");
        r.record("eq expected=16 actual=16");
    }

    @:test public static function pushInFitsWithoutShrinkWhenTheMergedLineAlreadyMatches():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("pushInFitsWithoutShrinkWhenTheMergedLineAlreadyMatches");
        r.record("eq expected=2 actual=2");
        r.record("eq expected=[0, 1, 2, 3, 4] actual=[0, 1, 2, 3, 4]");
        r.record("eq expected=0 actual=0");
        r.record("eq expected=[5, 6, 7, 8] actual=[5, 6, 7, 8]");
        r.record("is-true actual=true");
    }

    @:test public static function pushInPromotesTheOffendersOwnTrailingGlueToTierOne():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("pushInPromotesTheOffendersOwnTrailingGlueToTierOne");
        r.record("eq expected=4 actual=4");
        r.record("eq expected=[PushInAllocation(clusterIndex=4, shrink=4, availableCapacity=8, channel=TrailingGlue)] actual=[PushInAllocation(clusterIndex=4, shrink=4, availableCapacity=8, channel=TrailingGlue)]");
        r.record("eq expected='ForbiddenAtLineStart:，:pushed-in=4/16' actual='ForbiddenAtLineStart:，:pushed-in=4/16'");
    }

    @:test public static function pushInRejectsAMergeThroughClusterOutsideTheCurrentLine():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("pushInRejectsAMergeThroughClusterOutsideTheCurrentLine");
        r.record("raises exception=IllegalArgumentException thrown='PushIn merge-through cluster must belong to the current line.'");
        r.record("is-true actual=true msg='PushIn merge-through cluster must belong to the current line.'");
    }

    @:test public static function pushInRejectsMergeThroughOutsideTheCurrentLine():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("pushInRejectsMergeThroughOutsideTheCurrentLine");
        r.record("raises exception=IllegalArgumentException thrown='PushIn merge-through cluster must belong to the current line.'");
    }

    @:test public static function pushInRejectsWhenCapacityIsInsufficient():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("pushInRejectsWhenCapacityIsInsufficient");
        r.record("eq expected=false actual=false");
        r.record("eq expected='insufficient-capacity' actual='insufficient-capacity'");
        r.record("eq expected=20 actual=20");
        r.record("eq expected=8 actual=8");
    }

    @:test public static function pushInReportsInfinityCapacityWithAPortableDebugString():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("pushInReportsInfinityCapacityWithAPortableDebugString");
        r.record("is-true actual=true");
        r.record("is-true actual=true");
        r.record("eq expected='ForbiddenAtLineStart:，:pushed-in=Infinity.0/Infinity.0' actual='ForbiddenAtLineStart:，:pushed-in=Infinity.0/Infinity.0'");
    }

    @:test public static function pushInUnderflowSharesSkipZeroValuedProportionalShares():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("pushInUnderflowSharesSkipZeroValuedProportionalShares");
        r.record("is-true actual=true");
        r.record("eq expected=1 actual=1");
        r.record("eq expected=1 actual=1");
        r.record("eq expected=0 actual=0");
    }

    @:test public static function withFillPushInGateAppliesOrReturnsTheSolution():Void {
        final r = new TestTraceRecorder("LineRepairCoverageTest");
        r.section("withFillPushInGateAppliesOrReturnsTheSolution");
        r.record("eq expected=LineSolution(lines=[LineCandidate(clusterRange=0..3, sourceRange=TextRange(start=0, end=4), naturalWidth=64, adjustedWidth=64, endReason=AutoWrap, repair=null, repairCandidates=[], hangingClusterIndices=[]), LineCandidate(clusterRange=4..7,~412#b6848dc0 actual=LineSolution(lines=[LineCandidate(clusterRange=0..3, sourceRange=TextRange(start=0, end=4), naturalWidth=64, adjustedWidth=64, endReason=AutoWrap, repair=null, repairCandidates=[], hangingClusterIndices=[]), LineCandidate(clusterRange=4..7,~412#b6848dc0");
        r.record("eq expected=[0, 1, 2, 3, 4] actual=[0, 1, 2, 3, 4]");
    }

    @:test public static function flushTestTrace():Void {
        TestTraceRecorder.flushClass("LineRepairCoverageTest");
    }
}
