package org.tiqian.layout;

import org.tiqian.test.trace.*;

class SpacingAndLineGeometryEngineTest {
    @:test public static function autoSpaceReplacesTypedSpaceAtCjkLatinBoundary():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("autoSpaceReplacesTypedSpaceAtCjkLatinBoundary");
        SpacingAndLineGeometryEngineTestSupport.replay("autoSpaceReplacesTypedSpaceAtCjkLatinBoundary");
    }

    @:test public static function autoSpaceDoesNotShrinkSpacesBetweenLatinWords():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("autoSpaceDoesNotShrinkSpacesBetweenLatinWords");
        SpacingAndLineGeometryEngineTestSupport.replay("autoSpaceDoesNotShrinkSpacesBetweenLatinWords");
    }

    @:test public static function autoSpaceDisabledKeepsTypedSpacesAtHalfEm():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("autoSpaceDisabledKeepsTypedSpacesAtHalfEm");
        SpacingAndLineGeometryEngineTestSupport.replay("autoSpaceDisabledKeepsTypedSpacesAtHalfEm");
    }

    @:test public static function usesFontDeclaredTypoBoxForCjkLineBox():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("usesFontDeclaredTypoBoxForCjkLineBox");
        SpacingAndLineGeometryEngineTestSupport.replay("usesFontDeclaredTypoBoxForCjkLineBox");
    }

    @:test public static function autoSpaceGapAtLineEndIsTrimmedLikeAnyLineEdgeBlank():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("autoSpaceGapAtLineEndIsTrimmedLikeAnyLineEdgeBlank");
        SpacingAndLineGeometryEngineTestSupport.replay("autoSpaceGapAtLineEndIsTrimmedLikeAnyLineEdgeBlank");
    }

    @:test public static function emphasisSpanProducesDotAnchorsForHanAndSkipsPunctuation():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("emphasisSpanProducesDotAnchorsForHanAndSkipsPunctuation");
        SpacingAndLineGeometryEngineTestSupport.replay("emphasisSpanProducesDotAnchorsForHanAndSkipsPunctuation");
    }

    @:test public static function emphasisDotGapIsExplicitAndIndependentOfLineHeight():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("emphasisDotGapIsExplicitAndIndependentOfLineHeight");
        SpacingAndLineGeometryEngineTestSupport.replay("emphasisDotGapIsExplicitAndIndependentOfLineHeight");
    }

    @:test public static function mourningSpanIsKeptUnbrokenAndFramedPerLine():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("mourningSpanIsKeptUnbrokenAndFramedPerLine");
        SpacingAndLineGeometryEngineTestSupport.replay("mourningSpanIsKeptUnbrokenAndFramedPerLine");
    }

    @:test public static function mourningSpanWiderThanMeasureSplitsWithOpenEdges():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("mourningSpanWiderThanMeasureSplitsWithOpenEdges");
        SpacingAndLineGeometryEngineTestSupport.replay("mourningSpanWiderThanMeasureSplitsWithOpenEdges");
    }

    @:test public static function halfEmWordSpacesDoNotStretchUnderJustification():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("halfEmWordSpacesDoNotStretchUnderJustification");
        SpacingAndLineGeometryEngineTestSupport.replay("halfEmWordSpacesDoNotStretchUnderJustification");
    }

    @:test public static function justifyStretchesPunctuationLatinBoundaryInTierThree():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("justifyStretchesPunctuationLatinBoundaryInTierThree");
        SpacingAndLineGeometryEngineTestSupport.replay("justifyStretchesPunctuationLatinBoundaryInTierThree");
    }

    @:test public static function blockIndentInsetsEveryLine():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("blockIndentInsetsEveryLine");
        SpacingAndLineGeometryEngineTestSupport.replay("blockIndentInsetsEveryLine");
    }

    @:test public static function hangingIndentFlushesFirstLineAndInsetsRest():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("hangingIndentFlushesFirstLineAndInsetsRest");
        SpacingAndLineGeometryEngineTestSupport.replay("hangingIndentFlushesFirstLineAndInsetsRest");
    }

    @:test public static function justifyFillsSaturatedLineWithUncappedEvenShare():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("justifyFillsSaturatedLineWithUncappedEvenShare");
        SpacingAndLineGeometryEngineTestSupport.replay("justifyFillsSaturatedLineWithUncappedEvenShare");
    }

    @:test public static function autoSpaceDigitModeIsWiredIndependentlyOfLetterMode():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("autoSpaceDigitModeIsWiredIndependentlyOfLetterMode");
        SpacingAndLineGeometryEngineTestSupport.replay("autoSpaceDigitModeIsWiredIndependentlyOfLetterMode");
    }

    @:test public static function lineLengthGridFloorsMeasureToWholeCharsAndOffsetsBody():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("lineLengthGridFloorsMeasureToWholeCharsAndOffsetsBody");
        SpacingAndLineGeometryEngineTestSupport.replay("lineLengthGridFloorsMeasureToWholeCharsAndOffsetsBody");
    }

    @:test public static function lineLengthGridCanBeBypassedForExactWidths():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("lineLengthGridCanBeBypassedForExactWidths");
        SpacingAndLineGeometryEngineTestSupport.replay("lineLengthGridCanBeBypassedForExactWidths");
    }

    @:test public static function interlinearLinesGetPerItemSegmentsWithAdjacentShortening():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("interlinearLinesGetPerItemSegmentsWithAdjacentShortening");
        SpacingAndLineGeometryEngineTestSupport.replay("interlinearLinesGetPerItemSegmentsWithAdjacentShortening");
    }

    @:test public static function interlinearMarksRaiseAutoLineHeightToSpacingFloor():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("interlinearMarksRaiseAutoLineHeightToSpacingFloor");
        SpacingAndLineGeometryEngineTestSupport.replay("interlinearMarksRaiseAutoLineHeightToSpacingFloor");
    }

    @:test public static function firstLineIndentShrinksFirstLineMeasureOnly():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("firstLineIndentShrinksFirstLineMeasureOnly");
        SpacingAndLineGeometryEngineTestSupport.replay("firstLineIndentShrinksFirstLineMeasureOnly");
    }

    @:test public static function firstLineIndentAdaptsToMeasureAndCanBeOverridden():Void {
        final t = new TestTraceRecorder("SpacingAndLineGeometryEngineTest");
        t.section("firstLineIndentAdaptsToMeasureAndCanBeOverridden");
        SpacingAndLineGeometryEngineTestSupport.replay("firstLineIndentAdaptsToMeasureAndCanBeOverridden");
    }
}
