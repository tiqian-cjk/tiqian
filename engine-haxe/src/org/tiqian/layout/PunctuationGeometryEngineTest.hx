package org.tiqian.layout;

import org.tiqian.test.trace.*;

class PunctuationGeometryEngineTest {
    @:test public static function buildsTwoEmPunctuationAtomForRecommendedDashCodepoint():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("buildsTwoEmPunctuationAtomForRecommendedDashCodepoint");
        PunctuationGeometryEngineTestSupport.replay("buildsTwoEmPunctuationAtomForRecommendedDashCodepoint");
    }

    @:test public static function inkBoundsDetermineCompressionAmountAndSides():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("inkBoundsDetermineCompressionAmountAndSides");
        PunctuationGeometryEngineTestSupport.replay("inkBoundsDetermineCompressionAmountAndSides");
    }

    @:test public static function recordsInkCalibratedPunctuationGeometryInLayoutDebug():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("recordsInkCalibratedPunctuationGeometryInLayoutDebug");
        PunctuationGeometryEngineTestSupport.replay("recordsInkCalibratedPunctuationGeometryInLayoutDebug");
    }

    @:test public static function pushInKeepsFontCenteredPunctuationCompressionPaired():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("pushInKeepsFontCenteredPunctuationCompressionPaired");
        PunctuationGeometryEngineTestSupport.replay("pushInKeepsFontCenteredPunctuationCompressionPaired");
    }

    @:test public static function recordsPunctuationAtomsInLayoutDebug():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("recordsPunctuationAtomsInLayoutDebug");
        PunctuationGeometryEngineTestSupport.replay("recordsPunctuationAtomsInLayoutDebug");
    }

    @:test public static function lineStartLenticularBracketConsumesOpeningGlue():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("lineStartLenticularBracketConsumesOpeningGlue");
        PunctuationGeometryEngineTestSupport.replay("lineStartLenticularBracketConsumesOpeningGlue");
    }

    @:test public static function traditionalProfileCentresPauseStopGlueOnBothSides():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("traditionalProfileCentresPauseStopGlueOnBothSides");
        PunctuationGeometryEngineTestSupport.replay("traditionalProfileCentresPauseStopGlueOnBothSides");
    }

    @:test public static function appliesAdjacentPunctuationCompressionToDrawableGeometry():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("appliesAdjacentPunctuationCompressionToDrawableGeometry");
        PunctuationGeometryEngineTestSupport.replay("appliesAdjacentPunctuationCompressionToDrawableGeometry");
    }

    @:test public static function compressesAdjacentCjkSingleQuoteCommaSequence():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("compressesAdjacentCjkSingleQuoteCommaSequence");
        PunctuationGeometryEngineTestSupport.replay("compressesAdjacentCjkSingleQuoteCommaSequence");
    }

    @:test public static function compressesCjkClosingBeforeAsciiPointMarkWithoutReclassifyingAscii():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("compressesCjkClosingBeforeAsciiPointMarkWithoutReclassifyingAscii");
        PunctuationGeometryEngineTestSupport.replay("compressesCjkClosingBeforeAsciiPointMarkWithoutReclassifyingAscii");
    }

    @:test public static function haltAdvanceFromShaperDrivesPunctuationBodyEndToEnd():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("haltAdvanceFromShaperDrivesPunctuationBodyEndToEnd");
        PunctuationGeometryEngineTestSupport.replay("haltAdvanceFromShaperDrivesPunctuationBodyEndToEnd");
    }

    @:test public static function looseLineEndStyleKeepsFullWidthPunctuation():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("looseLineEndStyleKeepsFullWidthPunctuation");
        PunctuationGeometryEngineTestSupport.replay("looseLineEndStyleKeepsFullWidthPunctuation");
    }

    @:test public static function inlineStopCompressionKnobLimitsPushInCapacity():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("inlineStopCompressionKnobLimitsPushInCapacity");
        PunctuationGeometryEngineTestSupport.replay("inlineStopCompressionKnobLimitsPushInCapacity");
    }

    @:test public static function sinoWesternGapKnobDisablesStretchAndShrink():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("sinoWesternGapKnobDisablesStretchAndShrink");
        PunctuationGeometryEngineTestSupport.replay("sinoWesternGapKnobDisablesStretchAndShrink");
    }

    @:test public static function shortHyphenConnectorIsHalfWidthWavyTildeFullWidth():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("shortHyphenConnectorIsHalfWidthWavyTildeFullWidth");
        PunctuationGeometryEngineTestSupport.replay("shortHyphenConnectorIsHalfWidthWavyTildeFullWidth");
    }

    @:test public static function kaimingStyleHalvesInteriorPunctuationButNotSentenceEnd():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("kaimingStyleHalvesInteriorPunctuationButNotSentenceEnd");
        PunctuationGeometryEngineTestSupport.replay("kaimingStyleHalvesInteriorPunctuationButNotSentenceEnd");
    }

    @:test public static function gbFixedSeparatorsAreHalfWidthAndUnadjustable():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("gbFixedSeparatorsAreHalfWidthAndUnadjustable");
        PunctuationGeometryEngineTestSupport.replay("gbFixedSeparatorsAreHalfWidthAndUnadjustable");
    }

    @:test public static function pushInDrainsBracketOuterGlueBeforeInlineComma():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("pushInDrainsBracketOuterGlueBeforeInlineComma");
        PunctuationGeometryEngineTestSupport.replay("pushInDrainsBracketOuterGlueBeforeInlineComma");
    }

    @:test public static function sinoWesternGapShrinkFloorsAtEighthEm():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("sinoWesternGapShrinkFloorsAtEighthEm");
        PunctuationGeometryEngineTestSupport.replay("sinoWesternGapShrinkFloorsAtEighthEm");
    }

    @:test public static function pushInConsumesWordSpaceBeforeMidLinePunctGlue():Void {
        final t = new TestTraceRecorder("PunctuationGeometryEngineTest");
        t.section("pushInConsumesWordSpaceBeforeMidLinePunctGlue");
        PunctuationGeometryEngineTestSupport.replay("pushInConsumesWordSpaceBeforeMidLinePunctGlue");
    }
}
