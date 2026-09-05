package org.tiqian.layout;

import org.tiqian.test.trace.*;

@:test class ClusterRoleResolutionSurrogateAndExtenderEdgeTest {
    @:test public static function astralVariationSelectorAfterAnAttachedPointMarkEndsTheRun():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionSurrogateAndExtenderEdgeTest");
        r.section("astralVariationSelectorAfterAnAttachedPointMarkEndsTheRun");
        r.record("eq expected=3 actual=3 msg='[ResolvedClusterRange(range=TextRange(start=0, end=1), role=CjkText, mandatoryBreak=false, zeroWidthSoftBreak=false, roleOverride=null), ResolvedClusterRange(range=TextRange(start=1, end=4), role=LatinText, mandatoryBreak=false, zeroWidthSo~410#679463cd'");
        r.record("eq expected=TextRange(start=1, end=4) actual=TextRange(start=1, end=4)");
        r.record("eq expected=LatinText actual=LatinText");
    }

    @:test public static function astralVariationSelectorBetweenBaseAndModifierKeepsTheSequence():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionSurrogateAndExtenderEdgeTest");
        r.section("astralVariationSelectorBetweenBaseAndModifierKeepsTheSequence");
        r.record("eq expected=1 actual=1 msg='[ResolvedClusterRange(range=TextRange(start=0, end=5), role=Emoji, mandatoryBreak=false, zeroWidthSoftBreak=false, roleOverride=null)]'");
        r.record("eq expected=TextRange(start=0, end=5) actual=TextRange(start=0, end=5)");
        r.record("eq expected=Emoji actual=Emoji");
    }

    @:test public static function astralVariationSelectorExtendsTheRunBeforeIt():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionSurrogateAndExtenderEdgeTest");
        r.section("astralVariationSelectorExtendsTheRunBeforeIt");
        r.record("eq expected=2 actual=2 msg='[ResolvedClusterRange(range=TextRange(start=0, end=3), role=CjkText, mandatoryBreak=false, zeroWidthSoftBreak=false, roleOverride=null), ResolvedClusterRange(range=TextRange(start=3, end=4), role=CjkText, mandatoryBreak=false, zeroWidthSoft~272#2a105d37'");
        r.record("eq expected=TextRange(start=0, end=3) actual=TextRange(start=0, end=3)");
        r.record("eq expected=CjkText actual=CjkText");
        r.record("eq expected=TextRange(start=3, end=4) actual=TextRange(start=3, end=4)");
    }

    @:test public static function codePointAboveTheSupplementarySelectorRangeStandsAlone():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionSurrogateAndExtenderEdgeTest");
        r.section("codePointAboveTheSupplementarySelectorRangeStandsAlone");
        r.record("eq expected=3 actual=3 msg='[ResolvedClusterRange(range=TextRange(start=0, end=1), role=CjkText, mandatoryBreak=false, zeroWidthSoftBreak=false, roleOverride=null), ResolvedClusterRange(range=TextRange(start=1, end=3), role=Unknown, mandatoryBreak=false, zeroWidthSoft~408#b9ee8ab9'");
        r.record("eq expected=TextRange(start=0, end=1) actual=TextRange(start=0, end=1)");
        r.record("eq expected=TextRange(start=1, end=3) actual=TextRange(start=1, end=3)");
        r.record("eq expected=TextRange(start=3, end=4) actual=TextRange(start=3, end=4)");
    }

    @:test public static function highSurrogateBeforePlainBmpKeepsTheLoneHalf():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionSurrogateAndExtenderEdgeTest");
        r.section("highSurrogateBeforePlainBmpKeepsTheLoneHalf");
        r.record("eq expected=2 actual=2 msg='[ResolvedClusterRange(range=TextRange(start=0, end=1), role=Unknown, mandatoryBreak=false, zeroWidthSoftBreak=false, roleOverride=null), ResolvedClusterRange(range=TextRange(start=1, end=2), role=CjkText, mandatoryBreak=false, zeroWidthSoft~272#c7546518'");
        r.record("eq expected=TextRange(start=0, end=1) actual=TextRange(start=0, end=1)");
        r.record("eq expected=TextRange(start=1, end=2) actual=TextRange(start=1, end=2)");
    }

    @:test public static function highSurrogateBeforePrivateUseKeepsTheLoneHalf():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionSurrogateAndExtenderEdgeTest");
        r.section("highSurrogateBeforePrivateUseKeepsTheLoneHalf");
        r.record("eq expected=3 actual=3 msg='[ResolvedClusterRange(range=TextRange(start=0, end=1), role=Unknown, mandatoryBreak=false, zeroWidthSoftBreak=false, roleOverride=null), ResolvedClusterRange(range=TextRange(start=1, end=2), role=Unknown, mandatoryBreak=false, zeroWidthSoft~408#655aab7f'");
        r.record("eq expected=TextRange(start=0, end=1) actual=TextRange(start=0, end=1)");
        r.record("eq expected=TextRange(start=1, end=2) actual=TextRange(start=1, end=2)");
    }

    @:test public static function inlineObjectOverTheCrWalksTheLfWithACrBehindIt():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionSurrogateAndExtenderEdgeTest");
        r.section("inlineObjectOverTheCrWalksTheLfWithACrBehindIt");
        r.record("eq expected=2 actual=2 msg='[ResolvedClusterRange(range=TextRange(start=0, end=1), role=Unknown, mandatoryBreak=false, zeroWidthSoftBreak=false, roleOverride=null), ResolvedClusterRange(range=TextRange(start=1, end=2), role=Unknown, mandatoryBreak=false, zeroWidthSoft~272#36a39ab5'");
        r.record("eq expected=TextRange(start=0, end=1) actual=TextRange(start=0, end=1)");
        r.record("eq expected=TextRange(start=1, end=2) actual=TextRange(start=1, end=2)");
        r.record("is-false actual=false msg='[ResolvedClusterRange(range=TextRange(start=0, end=1), role=Unknown, mandatoryBreak=false, zeroWidthSoftBreak=false, roleOverride=null), ResolvedClusterRange(range=TextRange(start=1, end=2), role=Unknown, mandatoryBreak=false, zeroWidthSoft~272#36a39ab5'");
        r.record("is-true actual=true msg='[ResolvedClusterRange(range=TextRange(start=0, end=1), role=Unknown, mandatoryBreak=false, zeroWidthSoftBreak=false, roleOverride=null), ResolvedClusterRange(range=TextRange(start=1, end=2), role=Unknown, mandatoryBreak=false, zeroWidthSoft~272#36a39ab5'");
    }

    @:test public static function modifierBaseWithABmpSelectorWalksTheSelectorTrueArm():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionSurrogateAndExtenderEdgeTest");
        r.section("modifierBaseWithABmpSelectorWalksTheSelectorTrueArm");
        r.record("eq expected=1 actual=1 msg='[ResolvedClusterRange(range=TextRange(start=0, end=4), role=Emoji, mandatoryBreak=false, zeroWidthSoftBreak=false, roleOverride=null)]'");
        r.record("eq expected=TextRange(start=0, end=4) actual=TextRange(start=0, end=4)");
        r.record("eq expected=Emoji actual=Emoji");
    }

    @:test public static function modifierBaseWithOnlyASelectorEndsTheWalkAtTheClusterEnd():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionSurrogateAndExtenderEdgeTest");
        r.section("modifierBaseWithOnlyASelectorEndsTheWalkAtTheClusterEnd");
        r.record("eq expected=1 actual=1 msg='[ResolvedClusterRange(range=TextRange(start=0, end=3), role=Emoji, mandatoryBreak=false, zeroWidthSoftBreak=false, roleOverride=null)]'");
        r.record("eq expected=TextRange(start=0, end=3) actual=TextRange(start=0, end=3)");
    }

    @:test public static function spanBoundaryAfterASpaceLetThePointMarkSeeItsWhitespaceNeighbour():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionSurrogateAndExtenderEdgeTest");
        r.section("spanBoundaryAfterASpaceLetThePointMarkSeeItsWhitespaceNeighbour");
        r.record("eq expected=2 actual=2 msg='[ResolvedClusterRange(range=TextRange(start=0, end=2), role=LatinText, mandatoryBreak=false, zeroWidthSoftBreak=false, roleOverride=null), ResolvedClusterRange(range=TextRange(start=2, end=3), role=LatinText, mandatoryBreak=false, zeroWidth~276#317cf548'");
        r.record("eq expected=TextRange(start=0, end=2) actual=TextRange(start=0, end=2)");
        r.record("eq expected=TextRange(start=2, end=3) actual=TextRange(start=2, end=3)");
    }

    @:test public static function zwjMemberInsideAModifierBaseClusterBreaksTheWalkBelowTheRange():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionSurrogateAndExtenderEdgeTest");
        r.section("zwjMemberInsideAModifierBaseClusterBreaksTheWalkBelowTheRange");
        r.record("eq expected=1 actual=1 msg='[ResolvedClusterRange(range=TextRange(start=0, end=4), role=Emoji, mandatoryBreak=false, zeroWidthSoftBreak=false, roleOverride=null)]'");
        r.record("eq expected=TextRange(start=0, end=4) actual=TextRange(start=0, end=4)");
    }

    @:test public static function flushTestTrace():Void {
        TestTraceRecorder.flushClass("ClusterRoleResolutionSurrogateAndExtenderEdgeTest");
    }
}
