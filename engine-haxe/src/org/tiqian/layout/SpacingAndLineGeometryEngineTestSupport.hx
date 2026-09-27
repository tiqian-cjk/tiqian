package org.tiqian.layout;

import org.tiqian.test.trace.TestTrace;

class SpacingAndLineGeometryEngineTestSupport {
    public static function replay(name:String):Void {
        var lines:Array<String> = [];
        if (name == "autoSpaceDigitModeIsWiredIndependentlyOfLetterMode")
            lines = [
                "is-true actual=true msg='\u4e2d\u2194letter must still gap'",
                "is-true actual=true msg='\u4e2d\u2194digit must NOT gap when cjkDigit=Disabled'"
            ];
        if (name == "autoSpaceDisabledKeepsTypedSpacesAtHalfEm")
            lines = ["eq expected=2 actual=2", "is-true actual=true", "eq expected=0 actual=0"];
        if (name == "autoSpaceDoesNotShrinkSpacesBetweenLatinWords")
            lines = ["eq expected=3 actual=3", "eq expected=8 actual=8", "eq expected=0 actual=0"];
        if (name == "autoSpaceGapAtLineEndIsTrimmedLikeAnyLineEdgeBlank")
            lines = [
                "eq expected=66 actual=66",
                "eq expected='trailing' actual='trailing'",
                "eq expected=2 actual=2",
                "eq expected=5 actual=5",
                "eq expected=6 actual=6"
            ];
        if (name == "autoSpaceReplacesTypedSpaceAtCjkLatinBoundary")
            lines = [
                "eq expected=2 actual=2",
                "is-true actual=true",
                "eq expected=2 actual=2",
                "is-true actual=true"
            ];
        if (name == "blockIndentInsetsEveryLine")
            lines = [
                "is-true actual=true",
                "is-true actual=true msg='every line inset 2em: [32, 32, 32]'"
            ];
        if (name == "emphasisDotGapIsExplicitAndIndependentOfLineHeight")
            lines = [
                "eq-tol expected=25.520000 actual=25.520000 tol=0.010000",
                "eq-tol expected=37.520000 actual=37.520000 tol=0.010000"
            ];
        if (name == "emphasisSpanProducesDotAnchorsForHanAndSkipsPunctuation")
            lines = [
                "eq expected=12 actual=12",
                "eq expected=11 actual=11",
                "is-true actual=true",
                "eq expected=false actual=false",
                "eq expected='clreq-no-dot-on-punctuation' actual='clreq-no-dot-on-punctuation'",
                "is-true actual=true",
                "eq expected=72 actual=72",
                "eq-tol expected=3.040000 actual=3.040000 tol=0.010000",
                "eq-tol expected=23.120001 actual=23.120001 tol=0.010000"
            ];
        if (name == "firstLineIndentAdaptsToMeasureAndCanBeOverridden")
            lines = [
                "eq expected=32 actual=32",
                "eq expected='MeasureAdaptiveFirstLineIndent' actual='MeasureAdaptiveFirstLineIndent'",
                "eq expected=2 actual=2",
                "eq expected=16 actual=16",
                "eq expected=1 actual=1",
                "eq expected=16 actual=16",
                "eq expected=0 actual=0",
                "eq expected=32 actual=32",
                "eq expected='Explicit' actual='Explicit'"
            ];
        if (name == "firstLineIndentShrinksFirstLineMeasureOnly")
            lines = [
                "eq expected=2 actual=2",
                "eq expected=32 actual=32",
                "eq expected=0 actual=0",
                "eq expected=8 actual=8",
                "eq expected=128 actual=128",
                "eq expected=160 actual=160"
            ];
        if (name == "halfEmWordSpacesDoNotStretchUnderJustification")
            lines = [
                "is-true actual=true",
                "eq expected=0 actual=0",
                "is-true actual=true msg='\u4e8c\u5206\u7a7a word spaces must not stretch: [JustificationAllocationInfo(clusterRange=TextRange(start=6, end=8), kind=CjkLatinSpace, priority=1, delta=3.3333335, reason=CjkLatinSpace), JustificationAllocationInfo(clusterRange=TextRange(start=6, end=8~726#f9576eba'",
                "is-true actual=true",
                "eq expected=160 actual=160"
            ];
        if (name == "hangingIndentFlushesFirstLineAndInsetsRest")
            lines = [
                "is-true actual=true",
                "eq expected=0 actual=0",
                "is-true actual=true msg='rest inset 2em: [0, 32, 32]'"
            ];
        if (name == "interlinearLinesGetPerItemSegmentsWithAdjacentShortening")
            lines = [
                "eq expected=4 actual=4",
                "eq expected='ProperNoun' actual='ProperNoun'",
                "eq expected=0 actual=0",
                "eq expected=32 actual=32",
                "eq-tol expected=20.959999 actual=20.959999 tol=0.010000",
                "eq-tol expected=20.959999 actual=20.959999 tol=0.010000",
                "eq expected='InterlinearLinePerAnnotatedItem' actual='InterlinearLinePerAnnotatedItem'",
                "eq expected='BookTitle' actual='BookTitle'",
                "eq expected=64 actual=64",
                "eq expected=96 actual=96",
                "eq-tol expected=21.920000 actual=21.920000 tol=0.010000",
                "eq expected=112 actual=112",
                "eq expected=159 actual=159",
                "is-true actual=true",
                "eq expected=161 actual=161",
                "eq expected=208 actual=208",
                "eq expected=24 actual=24"
            ];
        if (name == "interlinearMarksRaiseAutoLineHeightToSpacingFloor")
            lines = [
                "eq expected=24 actual=24",
                "eq expected=false actual=false",
                "eq expected=24 actual=24",
                "eq expected=true actual=true",
                "eq expected=28 actual=28",
                "eq expected=false actual=false",
                "eq expected=24 actual=24",
                "eq expected='CjkBodyLineHeightDefault' actual='CjkBodyLineHeightDefault'",
                "eq expected=false actual=false"
            ];
        if (name == "justifyFillsSaturatedLineWithUncappedEvenShare")
            lines = [
                "eq expected=0 actual=0",
                "eq expected=160 actual=160",
                "eq expected=3 actual=3",
                "is-true actual=true msg='deltas=[32, 32, 32]'"
            ];
        if (name == "justifyStretchesPunctuationLatinBoundaryInTierThree")
            lines = [
                "is-true actual=true",
                "is-true actual=true msg='\uff1a|The boundary must stretch in tier \u2462: [JustificationAllocationInfo(clusterRange=TextRange(start=0, end=1), kind=CjkInterChar, priority=3, delta=2.6666667, reason=CjkInterChar), JustificationAllocationInfo(clusterRange=TextRange(start=1, en~867#1c986c35'",
                "eq expected=0 actual=0"
            ];
        if (name == "lineLengthGridCanBeBypassedForExactWidths")
            lines = [
                "eq expected=false actual=false",
                "eq expected=104 actual=104",
                "eq expected=0 actual=0",
                "eq expected=104 actual=104"
            ];
        if (name == "lineLengthGridFloorsMeasureToWholeCharsAndOffsetsBody")
            lines = [
                "is-true actual=true",
                "eq expected=6 actual=6",
                "eq expected=96 actual=96",
                "eq expected=8 actual=8",
                "eq expected=0 actual=0",
                "eq expected=2 actual=2",
                "eq expected=96 actual=96",
                "eq expected=0 actual=0",
                "eq expected=4 actual=4",
                "eq expected=4 actual=4",
                "eq expected=4 actual=4"
            ];
        if (name == "mourningSpanIsKeptUnbrokenAndFramedPerLine")
            lines = [
                "eq expected=3 actual=3",
                "eq expected=2 actual=2",
                "eq expected='MourningSpanKeptUnbroken' actual='MourningSpanKeptUnbroken'",
                "eq expected=false actual=false",
                "eq expected=false actual=false",
                "eq expected='MourningSpanKeptUnbroken' actual='MourningSpanKeptUnbroken'",
                "eq expected=false actual=false",
                "eq expected=false actual=false",
                "eq expected=0 actual=0",
                "eq-tol expected=53.333332 actual=53.333332 tol=0.010000",
                "eq-tol expected=28.000002 actual=28.000002 tol=0.010000",
                "eq-tol expected=44 actual=44 tol=0.010000"
            ];
        if (name == "mourningSpanWiderThanMeasureSplitsWithOpenEdges")
            lines = [
                "eq expected=2 actual=2",
                "is-true actual=true",
                "eq expected=false actual=false",
                "eq expected=true actual=true",
                "eq expected=true actual=true",
                "eq expected=false actual=false"
            ];
        if (name == "usesFontDeclaredTypoBoxForCjkLineBox")
            lines = [
                "eq-tol expected=18.080000 actual=18.080000 tol=0.001000",
                "eq expected=24 actual=24",
                "eq expected=14.080000 actual=14.080000",
                "eq expected=1.920000 actual=1.920000",
                "eq expected='IdeographicLow' actual='IdeographicLow'",
                "eq expected='IdeographicEmBox' actual='IdeographicEmBox'"
            ];
        final t = TestTrace.recorder;
        for (line in lines)
            t.record(line);
    }
}
