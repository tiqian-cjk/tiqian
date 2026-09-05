package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class VerbatimRangeAutoSpaceTest {
    @:test public static function internalBoundariesAreSuppressedAndOuterEdgesKeepTheGap():Void {
        final t = new TestTraceRecorder("VerbatimRangeAutoSpaceTest");
        t.section("internalBoundariesAreSuppressedAndOuterEdgesKeepTheGap");
        final text = "跑print你好print跑";
        final control = VerbatimRangeAutoSpaceTestSupport.layout(text, []);
        TracedAssertions.assertEqualsInt(4, VerbatimRangeAutoSpaceTestSupport.count(control, "TextAutoSpaceInsert:east-asian-spacing-W-N"),
            Std.string(control) + ".debug.autoSpaceDecisions");
        final result = VerbatimRangeAutoSpaceTestSupport.layout(text, [new TextRange(1, 13)]);
        final decisions = result.debug.autoSpaceDecisions;
        TracedAssertions.assertEqualsInt(2, VerbatimRangeAutoSpaceTestSupport.count(result, "TextAutoSpaceInsert:east-asian-spacing-W-N"),
            Std.string(decisions));
        TracedAssertions.assertEqualsInt(2, VerbatimRangeAutoSpaceTestSupport.count(result, "VerbatimRangeAutoSpace:east-asian-spacing-W-N-suppressed"),
            Std.string(decisions));
    }

    @:test public static function typedSpaceInsideAVerbatimRangeIsNotNormalised():Void {
        final t = new TestTraceRecorder("VerbatimRangeAutoSpaceTest");
        t.section("typedSpaceInsideAVerbatimRangeIsNotNormalised");
        final text = "跑a 你b跑";
        final control = VerbatimRangeAutoSpaceTestSupport.layout(text, []);
        TracedAssertions.assertEqualsInt(1, VerbatimRangeAutoSpaceTestSupport.count(control, "TextAutoSpaceReplace:east-asian-spacing-W-space-N"),
            Std.string(control) + ".debug.autoSpaceDecisions");
        final result = VerbatimRangeAutoSpaceTestSupport.layout(text, [new TextRange(1, 5)]);
        TracedAssertions.assertEqualsInt(0, VerbatimRangeAutoSpaceTestSupport.count(result, "TextAutoSpaceReplace:east-asian-spacing-W-space-N"),
            Std.string(result) + ".debug.autoSpaceDecisions");
    }
}
