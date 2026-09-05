package org.tiqian.layout;

import org.tiqian.core.Ic;
import org.tiqian.core.LayoutConstraints;
import org.tiqian.core.LayoutInput;
import org.tiqian.core.ParagraphStyle;
import org.tiqian.core.TextRange;
import org.tiqian.core.TextSpan;
import org.tiqian.core.TextStyle;
import org.tiqian.core.TiqianTextContent;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class BaselineAlignmentTest {
    @:test public static function cjkMixedSizesAlignByIdeographicBoxBottom():Void {
        final t = new TestTraceRecorder("BaselineAlignmentTest");
        t.section("cjkMixedSizesAlignByIdeographicBoxBottom");
        final result = new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent("中小大", [
            new TextSpan(new TextRange(1, 2), new TextStyle(null, 12.0)),
            new TextSpan(new TextRange(2, 3), new TextStyle(null, 20.0))
        ]), null, new ParagraphStyle(null, null, null, Ic.Zero),
            new LayoutConstraints(400.0)));
        final base = result.clusters[0];
        final small = result.clusters[1];
        final large = result.clusters[2];
        TracedAssertions.assertEqualsFloat(0.0, base.baselineShift);
        TracedAssertions.assertEqualsFloatTolerance(TracedAssertions.f32Literal(0.48), small.baselineShift, TracedAssertions.f32Literal(0.01));
        TracedAssertions.assertEqualsFloatTolerance(TracedAssertions.f32Literal(-0.48), large.baselineShift, TracedAssertions.f32Literal(0.01));
    }

    @:test public static function cjkPunctuationProvidesIdeographicReferenceWithoutHanBody():Void {
        final t = new TestTraceRecorder("BaselineAlignmentTest");
        t.section("cjkPunctuationProvidesIdeographicReferenceWithoutHanBody");
        final result = new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent("MacBook。"), null,
            new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(400.0)));
        final punctuation = result.clusters[result.clusters.length - 1];
        TracedAssertions.assertEqualsFloat(0.0, punctuation.baselineShift,
            "CJK punctuation carries an IdeographicEmBox and must not be aligned to Latin raw descent");
    }

    @:test public static function explicitBaselineShiftAppliesToRomanClusters():Void {
        final t = new TestTraceRecorder("BaselineAlignmentTest");
        t.section("explicitBaselineShiftAppliesToRomanClusters");
        final result = new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent("中A文", [
            new TextSpan(new TextRange(1, 2), new TextStyle(null, null, null, null, null, -6.0))
        ]), null, new ParagraphStyle(null, null, null, Ic.Zero),
            new LayoutConstraints(400.0)));
        final latin = result.clusters[1];
        TracedAssertions.assertEqualsFloatTolerance(-6.0, latin.baselineShift, TracedAssertions.f32Literal(0.001));
    }

    @:test public static function latinInsideCjkUsesSharedRomanBaseline():Void {
        final t = new TestTraceRecorder("BaselineAlignmentTest");
        t.section("latinInsideCjkUsesSharedRomanBaseline");
        final result = new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent("中A文"), null,
            new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(400.0)));
        final latin = result.clusters[1];
        TracedAssertions.assertEqualsFloat(0.0, latin.baselineShift, "Latin mixed into CJK should use the shared Roman baseline");
    }
}
