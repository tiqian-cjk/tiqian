package org.tiqian.layout;

import org.tiqian.core.Ic;
import org.tiqian.core.LayoutConstraints;
import org.tiqian.core.LayoutInput;
import org.tiqian.core.ParagraphStyle;
import org.tiqian.core.TiqianTextContent;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class InterpunctShrinkOpportunityTest {
    @:test public static function interpunctInkEvidenceFreesPairedGlueForTierThreeShrink():Void {
        final t = new TestTraceRecorder("InterpunctShrinkOpportunityTest");
        t.section("interpunctInkEvidenceFreesPairedGlueForTierThreeShrink");
        final text = "正文·间隔号·后文…结尾";
        final result = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null,
            InterpunctShrinkOpportunityTestSupport.haltInkShaper()).layout(new LayoutInput(new TiqianTextContent(text), null,
                new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(320.0)));
        final dots = [];
        for (i in 0...result.debug.punctuationDecisions.length)
            if (result.debug.punctuationDecisions[i].char == "·")
                dots.push(result.debug.punctuationDecisions[i]);
        TracedAssertions.assertEqualsInt(2, dots.length);
        for (dot in dots) {
            TracedAssertions.assertTrue(dot.leadingGlueNatural > 0.0, "leading glue: " + dot.leadingGlueNatural);
            TracedAssertions.assertTrue(dot.trailingGlueNatural > 0.0, "trailing glue: " + dot.trailingGlueNatural);
            TracedAssertions.assertEqualsString("Center", dot.anchor);
            TracedAssertions.assertEqualsString("FontHaltFittedBodyCompression", dot.geometrySource);
        }
        final ellipsis = result.debug.punctuationDecisions[result.debug.punctuationDecisions.length - 1];
        TracedAssertions.assertEqualsFloat(0.0, ellipsis.leadingGlueNatural);
        TracedAssertions.assertTrue(ellipsis.trailingGlueNatural > 0.0, "trailing glue: " + ellipsis.trailingGlueNatural);
        TracedAssertions.assertTrue(result.lines.length > 0);
    }

    @:test public static function preservedInterpunctCodepointKeepsInterpunctClassForTierThreeShrink():Void {
        final t = new TestTraceRecorder("InterpunctShrinkOpportunityTest");
        t.section("preservedInterpunctCodepointKeepsInterpunctClassForTierThreeShrink");
        final text = "正文・间隔・后文";
        final result = new ExplainableStubParagraphLayoutEngine(null, null, InterpunctShrinkOpportunityTestSupport.preserveResolver(), null, null, null, null,
            null, null, null,
            InterpunctShrinkOpportunityTestSupport.haltInkShaper()).layout(new LayoutInput(new TiqianTextContent(text), null,
                new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(320.0)));
        final interpuncts = [];
        for (i in 0...result.debug.punctuationDecisions.length)
            if (result.debug.punctuationDecisions[i].punctuationClass == "Interpunct")
                interpuncts.push(result.debug.punctuationDecisions[i]);
        final chars = [];
        for (dot in interpuncts)
            chars.push(dot.char);
        TracedAssertions.assertEqualsStringArray(["・", "・"], chars);
        for (dot in interpuncts) {
            TracedAssertions.assertTrue(dot.leadingGlueNatural > 0.0, "leading glue: " + dot.leadingGlueNatural);
            TracedAssertions.assertTrue(dot.trailingGlueNatural > 0.0, "trailing glue: " + dot.trailingGlueNatural);
            TracedAssertions.assertEqualsString("Center", dot.anchor);
        }
        TracedAssertions.assertTrue(result.lines.length > 0);
    }
}
