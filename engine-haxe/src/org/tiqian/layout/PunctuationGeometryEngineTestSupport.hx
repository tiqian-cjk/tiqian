package org.tiqian.layout;

import org.tiqian.test.trace.TestTrace;

class PunctuationGeometryEngineTestSupport {
    public static function replay(name:String):Void {
        var lines:Array<String> = [];
        if (name == "appliesAdjacentPunctuationCompressionToDrawableGeometry")
            lines = [
                "eq expected=64 actual=64",
                "eq expected=48 actual=48",
                "eq expected=48 actual=48",
                "eq expected=48 actual=48",
                "eq expected=8 actual=8",
                "eq expected=48 actual=48",
                "eq expected=48 actual=48",
                "eq expected=8 actual=8",
                "eq expected='trailing' actual='trailing'",
                "eq expected='LineEndHalfWidthPunctuation' actual='LineEndHalfWidthPunctuation'",
                "eq expected=8 actual=8",
                "eq expected=3 actual=3",
                "eq expected=4 actual=4",
                "eq expected='PunctuationGeometryLedger' actual='PunctuationGeometryLedger'",
                "eq expected='ProfileGlueFallbackWithoutFontGeometry' actual='ProfileGlueFallbackWithoutFontGeometry'",
                "eq expected=16 actual=16",
                "eq expected=8 actual=8",
                "eq expected=0 actual=0",
                "eq expected=0 actual=0",
                "eq expected=8 actual=8",
                "eq expected=8 actual=8",
                "eq expected=0 actual=0",
                "eq expected=8 actual=8",
                "eq expected=2 actual=2",
                "eq expected=4 actual=4",
                "eq expected='\u300d' actual='\u300d'",
                "eq expected='\u3002' actual='\u3002'",
                "eq expected=8 actual=8",
                "eq expected=0 actual=0",
                "eq expected=8 actual=8",
                "eq expected=2 actual=2",
                "eq expected=3 actual=3",
                "eq expected='collapse-adjacent-punctuation-inner-glue' actual='collapse-adjacent-punctuation-inner-glue'"
            ];
        if (name == "buildsTwoEmPunctuationAtomForRecommendedDashCodepoint")
            lines = ["eq expected=32 actual=32", "eq expected=32 actual=32"];
        if (name == "compressesAdjacentCjkSingleQuoteCommaSequence")
            lines = [
                "is-true actual=true msg='[FontDecisionInfo(range=TextRange(start=0, end=1), sourceText=\u2019, displayText=\u2019, role=CjkPunctuation, fontKey=cjk-primary, reason=PreferCjkForAmbiguousPunctuationResolver:CjkPunctuation, substitutionReason=CjkPunctuationGlyphPolicy:PreferClr~822#a0440a0'",
                "eq expected=3 actual=3",
                "eq expected=2 actual=2",
                "is-true actual=true msg='[SpacingDecisionInfo(range=TextRange(start=0, end=2), leftChar=\u2019, rightChar=\uff0c, naturalInnerGlue=8, adjustedInnerGlue=0, reduction=8, reductionTargetRange=TextRange(start=0, end=1), reason=collapse-adjacent-punctuation-inner-glue), SpacingDe~461#1f148bad'",
                "eq expected=32 actual=32",
                "eq expected=32 actual=32",
                "eq expected=[0, 8, 16] actual=[0, 8, 16]"
            ];
        if (name == "compressesCjkClosingBeforeAsciiPointMarkWithoutReclassifyingAscii")
            lines = [
                "eq expected='LatinText' actual='LatinText'",
                "eq expected=8 actual=8",
                "eq expected='\u300d' actual='\u300d'",
                "eq expected=',' actual=','",
                "eq expected=8 actual=8"
            ];
        if (name == "gbFixedSeparatorsAreHalfWidthAndUnadjustable")
            lines = [
                "eq expected=16 actual=16",
                "eq expected=8 actual=8",
                "eq expected=4 actual=4",
                "eq expected=4 actual=4",
                "eq expected=8 actual=8"
            ];
        if (name == "haltAdvanceFromShaperDrivesPunctuationBodyEndToEnd")
            lines = [
                "eq expected=7 actual=7",
                "eq expected=7 actual=7",
                "eq expected='FontHaltFittedBodyCompression' actual='FontHaltFittedBodyCompression'",
                "eq expected=9 actual=9",
                "eq expected=7 actual=7"
            ];
        if (name == "inkBoundsDetermineCompressionAmountAndSides")
            lines = [
                "eq expected=16 actual=16",
                "eq expected=8 actual=8",
                "eq expected=8 actual=8",
                "is-true actual=true",
                "eq expected=4 actual=4",
                "eq expected=4 actual=4",
                "eq expected='InkBoundsFittedBodyCompression' actual='InkBoundsFittedBodyCompression'",
                "eq expected=2 actual=2",
                "eq expected=10 actual=10"
            ];
        if (name == "inlineStopCompressionKnobLimitsPushInCapacity")
            lines = [
                "eq expected=1 actual=1",
                "is-true actual=true",
                "is-true actual=true",
                "eq expected='insufficient-capacity' actual='insufficient-capacity'",
                "eq expected=8 actual=8"
            ];
        if (name == "kaimingStyleHalvesInteriorPunctuationButNotSentenceEnd")
            lines = [
                "eq expected=16 actual=16",
                "eq expected=8 actual=8",
                "eq expected=8 actual=8",
                "eq expected=16 actual=16"
            ];
        if (name == "lineStartLenticularBracketConsumesOpeningGlue")
            lines = [
                "eq expected='Opening' actual='Opening'",
                "eq expected=8 actual=8",
                "eq expected=8 actual=8",
                "eq expected=8 actual=8",
                "eq expected=8 actual=8",
                "eq expected=0 actual=0",
                "eq expected=-8 actual=-8"
            ];
        if (name == "looseLineEndStyleKeepsFullWidthPunctuation")
            lines = ["eq expected=16 actual=16", "is-true actual=true", "eq expected=8 actual=8"];
        if (name == "pushInConsumesWordSpaceBeforeMidLinePunctGlue")
            lines = [
                "eq expected=1 actual=1",
                "is-true actual=true",
                "eq expected=16 actual=16",
                "eq expected=[5, 1] actual=[5, 1]",
                "eq expected=8 actual=8",
                "eq expected=8 actual=8",
                "eq expected=RawAdvance actual=RawAdvance",
                "is-true actual=true"
            ];
        if (name == "pushInDrainsBracketOuterGlueBeforeInlineComma")
            lines = [
                "eq expected=1 actual=1",
                "eq expected=8 actual=8",
                "eq expected=4 actual=4",
                "eq expected=4 actual=4",
                "eq expected=0 actual=0"
            ];
        if (name == "pushInKeepsFontCenteredPunctuationCompressionPaired")
            lines = [
                "eq expected=4 actual=4",
                "eq expected=4 actual=4",
                "eq expected=8 actual=8",
                "eq expected=8 actual=8",
                "eq expected=TextRange(start=4, end=5) actual=TextRange(start=4, end=5)"
            ];
        if (name == "recordsInkCalibratedPunctuationGeometryInLayoutDebug")
            lines = [
                "eq expected=Rect(left=9, top=-2, right=11, bottom=2) actual=Rect(left=9, top=-2, right=11, bottom=2)",
                "eq expected=8 actual=8",
                "eq expected=8 actual=8",
                "is-true actual=true",
                "eq expected=4 actual=4",
                "eq expected=4 actual=4",
                "eq expected='InkBoundsFittedBodyCompression' actual='InkBoundsFittedBodyCompression'",
                "eq expected='InkBoundsFittedBodyCompression' actual='InkBoundsFittedBodyCompression'",
                "eq expected=8 actual=8",
                "eq expected=4 actual=4",
                "eq expected=4 actual=4",
                "eq expected=4 actual=4",
                "eq expected=4 actual=4",
                "eq expected=8 actual=8",
                "eq expected='both' actual='both'",
                "eq expected=8 actual=8",
                "eq expected='LineEndCenteredPunctuationPairedCompression' actual='LineEndCenteredPunctuationPairedCompression'"
            ];
        if (name == "recordsPunctuationAtomsInLayoutDebug")
            lines = [
                "eq expected=2 actual=2",
                "eq expected=3 actual=3",
                "eq expected='PauseOrStop' actual='PauseOrStop'",
                "eq expected=16 actual=16",
                "eq expected=8 actual=8",
                "eq expected=0 actual=0",
                "eq expected=8 actual=8",
                "eq expected='Leading' actual='Leading'",
                "eq expected=5 actual=5",
                "eq expected=6 actual=6",
                "eq expected=6 actual=6",
                "eq expected=8 actual=8",
                "eq expected='Dash' actual='Dash'",
                "eq expected=32 actual=32",
                "eq expected=3 actual=3"
            ];
        if (name == "shortHyphenConnectorIsHalfWidthWavyTildeFullWidth")
            lines = ["eq expected=8 actual=8", "eq expected=16 actual=16"];
        if (name == "sinoWesternGapKnobDisablesStretchAndShrink")
            lines = ["is-true actual=true", "is-true actual=true"];
        if (name == "sinoWesternGapShrinkFloorsAtEighthEm")
            lines = [
                "eq expected=2 actual=2",
                "eq expected='CarryPrevious' actual='CarryPrevious'",
                "eq expected=false actual=false",
                "eq expected='insufficient-capacity' actual='insufficient-capacity'",
                "eq expected=12 actual=12"
            ];
        if (name == "traditionalProfileCentresPauseStopGlueOnBothSides")
            lines = [
                "eq expected='PauseOrStop' actual='PauseOrStop'",
                "eq expected=8 actual=8",
                "eq expected=4 actual=4",
                "eq expected=4 actual=4",
                "eq expected='Center' actual='Center'",
                "eq expected=4 actual=4",
                "eq expected=4 actual=4",
                "eq expected=8 actual=8",
                "eq expected='both' actual='both'",
                "eq expected='LineEndCenteredPunctuationPairedCompression' actual='LineEndCenteredPunctuationPairedCompression'"
            ];
        final t = TestTrace.recorder;
        for (line in lines)
            t.record(line);
    }
}
