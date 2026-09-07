package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.ProgressiveBreakDecisions;

class ParagraphLayoutEngineValidationCoverageTest {
    @:test public static function emphasisDotGapEmMustBeFiniteAndNonNegative():Void {
        final t = new TestTraceRecorder("ParagraphLayoutEngineValidationCoverageTest");
        t.section("emphasisDotGapEmMustBeFiniteAndNonNegative");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(new ParagraphStyle(null, null, null, null,
            null, null, null, null, null, Math.NaN)),
            "emphasisDotGapEm");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(new ParagraphStyle(null, null, null, null,
            null, null, null, null, null, -.1)),
            "emphasisDotGapEm");
    }

    @:test public static function inlineObjectMinimumClearanceEmMustBeFiniteAndNonNegative():Void {
        final t = new TestTraceRecorder("ParagraphLayoutEngineValidationCoverageTest");
        t.section("inlineObjectMinimumClearanceEmMustBeFiniteAndNonNegative");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(new ParagraphStyle(null, null, null, null,
            null, null, null, null, Math.NaN)),
            "inlineObjectMinimumClearanceEm");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(new ParagraphStyle(null, null, null, null,
            null, null, null, null, -1)),
            "inlineObjectMinimumClearanceEm");
    }

    @:test public static function sourceTextMustNotContainUnpairedSurrogates():Void {
        final t = new TestTraceRecorder("ParagraphLayoutEngineValidationCoverageTest");
        t.section("sourceTextMustNotContainUnpairedSurrogates");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null, null,
            new TiqianTextContent(ParagraphLayoutEngineValidationCoverageSupport.code(0x4e2d) + ParagraphLayoutEngineValidationCoverageSupport.code(0xd800))),
            "unpaired high surrogate");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null, null,
            new TiqianTextContent(ParagraphLayoutEngineValidationCoverageSupport.code(0x4e2d) + ParagraphLayoutEngineValidationCoverageSupport.code(0xdc00))),
            "unpaired low surrogate");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null, null,
            new TiqianTextContent(ParagraphLayoutEngineValidationCoverageSupport.code(0xd800)
                + ParagraphLayoutEngineValidationCoverageSupport.code(0xd800)
                + ParagraphLayoutEngineValidationCoverageSupport.code(0xdc00))),
            "unpaired high surrogate");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null, null,
            new TiqianTextContent(ParagraphLayoutEngineValidationCoverageSupport.code(0xd800) + ParagraphLayoutEngineValidationCoverageSupport.code(0xf900))),
            "unpaired high surrogate");
    }

    @:test public static function inlineBoxSpanMustBeANonEmptyInBoundsRange():Void {
        final t = new TestTraceRecorder("ParagraphLayoutEngineValidationCoverageTest");
        t.section("inlineBoxSpanMustBeANonEmptyInBoundsRange");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null,
            [new InlineBoxSpan(new TextRange(0, 0))], null), "non-empty source range");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null,
            [new InlineBoxSpan(new TextRange(1, 9))], null), "non-empty source range");
    }

    @:test public static function inlineBoxSpanMustHaveFiniteInlineEdges():Void {
        final t = new TestTraceRecorder("ParagraphLayoutEngineValidationCoverageTest");
        t.section("inlineBoxSpanMustHaveFiniteInlineEdges");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null,
            [new InlineBoxSpan(new TextRange(0, 1), Math.NaN)], null), "finite inline edges");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null,
            [new InlineBoxSpan(new TextRange(0, 1), Math.POSITIVE_INFINITY)], null),
            "finite inline edges");
    }

    @:test public static function lineBreakSpansMustBeNonEmptyInBoundsRanges():Void {
        final t = new TestTraceRecorder("ParagraphLayoutEngineValidationCoverageTest");
        t.section("lineBreakSpansMustBeNonEmptyInBoundsRanges");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null, null,
            new TiqianTextContent("甲乙", null, [new LineBreakSpan(new TextRange(0, 0), LineBreakPolicy.ProgressiveTechnical)])),
            "LineBreakSpan");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null, null,
            new TiqianTextContent("甲乙", null, [new LineBreakSpan(new TextRange(2, 3), LineBreakPolicy.ProgressiveTechnical)])),
            "LineBreakSpan");
    }

    @:test public static function autoSpaceSuppressedRangesMustBeNonEmptyInBounds():Void {
        final t = new TestTraceRecorder("ParagraphLayoutEngineValidationCoverageTest");
        t.section("autoSpaceSuppressedRangesMustBeNonEmptyInBounds");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null, null,
            new TiqianTextContent("甲乙", null, null, [new TextRange(1, 1)])),
            "Auto-space suppressed range");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null, null,
            new TiqianTextContent("甲乙", null, null, [new TextRange(0, 8)])),
            "Auto-space suppressed range");
    }

    @:test public static function inlineObjectRangesMustBeUnique():Void {
        final t = new TestTraceRecorder("ParagraphLayoutEngineValidationCoverageTest");
        t.section("inlineObjectRangesMustBeUnique");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null, [
            ParagraphLayoutEngineValidationCoverageSupport.obj(new TextRange(0, 1)),
            ParagraphLayoutEngineValidationCoverageSupport.obj(new TextRange(0, 1))
        ]), "unique");
    }

    @:test public static function inlineObjectRangesMustNotOverlap():Void {
        final t = new TestTraceRecorder("ParagraphLayoutEngineValidationCoverageTest");
        t.section("inlineObjectRangesMustNotOverlap");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null, [
            ParagraphLayoutEngineValidationCoverageSupport.obj(new TextRange(0, 2)),
            ParagraphLayoutEngineValidationCoverageSupport.obj(new TextRange(1, 2))
        ]), "overlap");
    }

    @:test public static function inlineObjectMustCoverANonEmptyInBoundsRange():Void {
        final t = new TestTraceRecorder("ParagraphLayoutEngineValidationCoverageTest");
        t.section("inlineObjectMustCoverANonEmptyInBoundsRange");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null,
            [ParagraphLayoutEngineValidationCoverageSupport.obj(new TextRange(1, 1))]),
            "non-empty source range");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null,
            [ParagraphLayoutEngineValidationCoverageSupport.obj(new TextRange(0, 9))]),
            "non-empty source range");
    }

    @:test public static function inlineObjectMustHaveFinitePositiveGeometry():Void {
        final t = new TestTraceRecorder("ParagraphLayoutEngineValidationCoverageTest");
        t.section("inlineObjectMustHaveFinitePositiveGeometry");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null,
            [ParagraphLayoutEngineValidationCoverageSupport.obj(null, 0)]),
            "finite positive geometry");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null,
            [ParagraphLayoutEngineValidationCoverageSupport.obj(null, Math.NaN)]),
            "finite positive geometry");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null,
            [ParagraphLayoutEngineValidationCoverageSupport.obj(null, null, -1)]),
            "finite positive geometry");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null,
            [ParagraphLayoutEngineValidationCoverageSupport.obj(null, null, Math.NaN)]),
            "finite positive geometry");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null,
            [ParagraphLayoutEngineValidationCoverageSupport.obj(null, null, null, Math.NaN)]),
            "finite positive geometry");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null,
            [ParagraphLayoutEngineValidationCoverageSupport.obj(null, null, null, -1)]),
            "finite positive geometry");
    }

    @:test public static function inlineObjectLeadingBoundaryMustBeFixed():Void {
        final t = new TestTraceRecorder("ParagraphLayoutEngineValidationCoverageTest");
        t.section("inlineObjectLeadingBoundaryMustBeFixed");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null, [
            ParagraphLayoutEngineValidationCoverageSupport.obj(null, null, null, null, new InlineObjectBoundaryAdjustment(null, null, .5))
        ]), "cannot shrink its leading boundary");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null, [
            ParagraphLayoutEngineValidationCoverageSupport.obj(null, null, null, null, new InlineObjectBoundaryAdjustment(null, null, null, .5))
        ]), "cannot discard advance at its leading boundary");
    }

    @:test public static function inlineObjectTrailingBoundaryMustNotExceedAdvance():Void {
        final t = new TestTraceRecorder("ParagraphLayoutEngineValidationCoverageTest");
        t.section("inlineObjectTrailingBoundaryMustNotExceedAdvance");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null, [
            ParagraphLayoutEngineValidationCoverageSupport.obj(null, null, null, null, null, new InlineObjectBoundaryAdjustment(null, null, 10.5))
        ]), "trailing shrink capacity");
        ParagraphLayoutEngineValidationCoverageSupport.reject(ParagraphLayoutEngineValidationCoverageSupport.input(null, null, [
            ParagraphLayoutEngineValidationCoverageSupport.obj(null, null, null, null, null, new InlineObjectBoundaryAdjustment(null, null, null, 10.5))
        ]), "trailing line-end discard");
    }
}
