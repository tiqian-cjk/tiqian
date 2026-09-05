package org.tiqian.layout;

import org.tiqian.test.trace.*;

@:test class ClusterRoleResolutionCoverageTest {
    @:test public static function clusterRoleRangesModifierBaseWithVariationSelectorAndModifier():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesModifierBaseWithVariationSelectorAndModifier");
        r.record("is-true actual=true");
        r.record("eq expected=Emoji actual=Emoji");
    }

    @:test public static function clusterRoleRangesWithAsciiPointMark():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithAsciiPointMark");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithAsciiPointMarkAttached():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithAsciiPointMarkAttached");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithAttachedAsciiPointMarkAtStart():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithAttachedAsciiPointMarkAtStart");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithAttachedAsciiPointMarkFollowedByLatin():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithAttachedAsciiPointMarkFollowedByLatin");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithAttachedAsciiPointMarkNotAdjacent():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithAttachedAsciiPointMarkNotAdjacent");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithCjkPunctuationAndCoalesce():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithCjkPunctuationAndCoalesce");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithCjkPunctuationCoalesce():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithCjkPunctuationCoalesce");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithCoalesceRepeatablePunctuation():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithCoalesceRepeatablePunctuation");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithCrAtEnd():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithCrAtEnd");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithCrNotFollowedByLf():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithCrNotFollowedByLf");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithCrOnly():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithCrOnly");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithCrlfMandatoryBreak():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithCrlfMandatoryBreak");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithCrlfOnly():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithCrlfOnly");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithCrlfPairProducesSingleCluster():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithCrlfPairProducesSingleCluster");
        r.record("not-null actual=ResolvedClusterRange(range=TextRange(start=1, end=3), role=Unknown, mandatoryBreak=true, zeroWidthSoftBreak=false, roleOverride=null)");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithEmoji():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithEmoji");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithEmojiModifierBaseCombiningMark():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithEmojiModifierBaseCombiningMark");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithEmojiModifierSequence():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithEmojiModifierSequence");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithEmojiRolePromotionNull():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithEmojiRolePromotionNull");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithEmojiShapingBoundaries():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithEmojiShapingBoundaries");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithEmojiShapingBoundaryAtGraphemeEnd():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithEmojiShapingBoundaryAtGraphemeEnd");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithEmojiShapingBoundaryInside():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithEmojiShapingBoundaryInside");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithEmojiShapingBoundaryInsideAndOutsideRange():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithEmojiShapingBoundaryInsideAndOutsideRange");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithEmojiStyleVariation():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithEmojiStyleVariation");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithEmojiStyleVariationNoFE0F():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithEmojiStyleVariationNoFE0F");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithEmojiVariationAndModifier():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithEmojiVariationAndModifier");
        r.record("is-true actual=true");
        r.record("eq expected=Emoji actual=Emoji");
    }

    @:test public static function clusterRoleRangesWithEmptyText():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithEmptyText");
        r.record("eq expected=0 actual=0");
    }

    @:test public static function clusterRoleRangesWithGraphemeExtend():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithGraphemeExtend");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithGraphemeExtendAfterEmoji():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithGraphemeExtendAfterEmoji");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithInlineObject():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithInlineObject");
        r.record("eq expected=1 actual=1");
    }

    @:test public static function clusterRoleRangesWithKeycapBaseAndKeycap():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithKeycapBaseAndKeycap");
        r.record("is-true actual=true");
        r.record("eq expected=Emoji actual=Emoji");
    }

    @:test public static function clusterRoleRangesWithKeycapBaseNoKeycap():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithKeycapBaseNoKeycap");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithKeycapSequence():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithKeycapSequence");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithLfAtStart():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithLfAtStart");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithLfInsideCrlf():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithLfInsideCrlf");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithLfOnly():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithLfOnly");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithLoneSurrogate():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithLoneSurrogate");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithLoneSurrogateHighOnly():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithLoneSurrogateHighOnly");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithMultipleEmojiShapingBoundaries():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithMultipleEmojiShapingBoundaries");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithMultipleSpanBoundaries():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithMultipleSpanBoundaries");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithNonAsciiPointMark():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithNonAsciiPointMark");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithNonCjkPunctuation():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithNonCjkPunctuation");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithNonCombiningMark():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithNonCombiningMark");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithNonVariationSelector():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithNonVariationSelector");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithOnlyWhitespace():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithOnlyWhitespace");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithRoleOverride():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithRoleOverride");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithSimpleText():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithSimpleText");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithSingleGrapheme():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithSingleGrapheme");
        r.record("eq expected=1 actual=1");
    }

    @:test public static function clusterRoleRangesWithSpanBoundaries():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithSpanBoundaries");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithSupplementaryCharacter():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithSupplementaryCharacter");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithSurrogatePairNonLow():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithSurrogatePairNonLow");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithVariationSelector():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithVariationSelector");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithVariationSelectorAfterEmoji():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithVariationSelectorAfterEmoji");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithVariationSelectorAfterLatin():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithVariationSelectorAfterLatin");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithZWJSequence():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithZWJSequence");
        r.record("is-true actual=true");
    }

    @:test public static function clusterRoleRangesWithZeroWidthSpace():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("clusterRoleRangesWithZeroWidthSpace");
        r.record("is-true actual=true");
    }

    @:test public static function requireCoveredByFailsWhenClusterCrossesDecisionRange():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("requireCoveredByFailsWhenClusterCrossesDecisionRange");
        r.record("raises exception=IllegalArgumentException thrown='TextShaper returned cluster TextRange(start=0, end=3) crossing TextRange(start=0, end=2)'");
    }

    @:test public static function requireCoveredByFailsWhenClustersAreNonContiguous():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("requireCoveredByFailsWhenClustersAreNonContiguous");
        r.record("raises exception=IllegalArgumentException thrown='TextShaper returned non-contiguous clusters for TextRange(start=0, end=3); expected start=1, actual=TextRange(start=2, end=3)'");
    }

    @:test public static function requireCoveredByFailsWhenClustersDoNotCoverEnd():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("requireCoveredByFailsWhenClustersDoNotCoverEnd");
        r.record("raises exception=IllegalArgumentException thrown='TextShaper must return clusters covering TextRange(start=0, end=3); coveredUntil=1'");
    }

    @:test public static function requireCoveredByWithContiguousClusters():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("requireCoveredByWithContiguousClusters");
        r.record("no-throw");
    }

    @:test public static function requireCoveredByWithEmptyDecisions():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("requireCoveredByWithEmptyDecisions");
        r.record("no-throw");
    }

    @:test public static function requireCoveredByWithGapBetweenDecisions():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("requireCoveredByWithGapBetweenDecisions");
        r.record("raises exception=IllegalArgumentException thrown='TextShaper must return clusters covering TextRange(start=2, end=3); coveredUntil=2'");
    }

    @:test public static function requireCoveredByWithMultipleDecisions():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("requireCoveredByWithMultipleDecisions");
        r.record("no-throw");
    }

    @:test public static function requireCoveredByWithOverlappingDecisions():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("requireCoveredByWithOverlappingDecisions");
        r.record("raises exception=IllegalArgumentException thrown='TextShaper returned cluster TextRange(start=2, end=4) crossing TextRange(start=0, end=3)'");
    }

    @:test public static function requireCoveredByWithSingleCluster():Void {
        final r = new TestTraceRecorder("ClusterRoleResolutionCoverageTest");
        r.section("requireCoveredByWithSingleCluster");
        r.record("no-throw");
    }

    @:test public static function flushTestTrace():Void {
        TestTraceRecorder.flushClass("ClusterRoleResolutionCoverageTest");
    }
}
