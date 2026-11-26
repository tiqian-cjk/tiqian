package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;

/**
 * `ExplainableStubParagraphLayoutEngine.recordsDebugInfo`: an engine that does not record debug
 * information returns `LayoutDebugInfo.Default` and otherwise the same result, including the
 * presentation records; an engine that records it shares the presentation lists with the debug
 * record.
 */
class LayoutDebugRecordingTest {
    @:test public static function disabledDebugRecordingKeepsEveryOtherField():Void {
        new TestTraceRecorder("LayoutDebugRecordingTest").section("disabledDebugRecordingKeepsEveryOtherField");
        final recorded = LayoutDebugRecordingTestSupport.layout(true);
        final skipped = LayoutDebugRecordingTestSupport.layout(false);
        TracedAssertions.assertEqualsString(LayoutDebugInfo.Default.toString(), skipped.debug.toString());
        TracedAssertions.assertEqualsString(LayoutDebugRecordingTestSupport.withoutDebug(recorded).toString(),
            LayoutDebugRecordingTestSupport.withoutDebug(skipped).toString());
        TracedAssertions.assertTrue(recorded.presentation.fontDecisions.length > 0);
        TracedAssertions.assertTrue(recorded.debug.lineDecisions.length > 0);
    }

    @:test public static function recordedDebugRepeatsThePresentationLists():Void {
        new TestTraceRecorder("LayoutDebugRecordingTest").section("recordedDebugRepeatsThePresentationLists");
        final result = LayoutDebugRecordingTestSupport.layout(true);
        final p = result.presentation;
        final d = result.debug;
        TracedAssertions.assertEqualsString(LayoutDebugRecordingTestSupport.joinFontDecisions(p.fontDecisions),
            LayoutDebugRecordingTestSupport.joinFontDecisions(d.fontDecisions));
        TracedAssertions.assertEqualsString(LayoutDebugRecordingTestSupport.joinMetricDecisions(p.metricDecisions),
            LayoutDebugRecordingTestSupport.joinMetricDecisions(d.metricDecisions));
        TracedAssertions.assertEqualsString(LayoutDebugRecordingTestSupport.joinPunctuationDecisions(p.punctuationDecisions),
            LayoutDebugRecordingTestSupport.joinPunctuationDecisions(d.punctuationDecisions));
        TracedAssertions.assertEqualsString(LayoutDebugRecordingTestSupport.joinGeometryDecisions(p.geometryDecisions),
            LayoutDebugRecordingTestSupport.joinGeometryDecisions(d.geometryDecisions));
        TracedAssertions.assertEqualsString(LayoutDebugRecordingTestSupport.joinShapingDecisions(p.shapingDecisions),
            LayoutDebugRecordingTestSupport.joinShapingDecisions(d.shapingDecisions));
        TracedAssertions.assertEqualsString(LayoutDebugRecordingTestSupport.lineSpacingText(p.lineSpacingDecision),
            LayoutDebugRecordingTestSupport.lineSpacingText(d.lineSpacingDecision));
    }
}
