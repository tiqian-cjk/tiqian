package org.tiqian.core;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class TextRangeTest {
    @:test
    public static function exposesLength():Void {
        new TestTraceRecorder("TextRangeTest").section("exposesLength");
        TracedAssertions.assertEquals(3, new TextRange(2, 5).length);
    }

    @:test
    public static function rejectsNegativeStart():Void {
        new TestTraceRecorder("TextRangeTest").section("rejectsNegativeStart");
        TracedAssertions.assertFailsWith(null, () -> {
            new TextRange(-1, 1);
        });
    }
}
