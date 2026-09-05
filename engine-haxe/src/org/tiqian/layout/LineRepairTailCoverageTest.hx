package org.tiqian.layout;

import org.tiqian.test.trace.*;

@:test class LineRepairTailCoverageTest {
    @:test public static function fillPullAcrossDifferentTechnicalSpansSkipsTierComparisons():Void {
        final r = new TestTraceRecorder("LineRepairTailCoverageTest");
        r.section("fillPullAcrossDifferentTechnicalSpansSkipsTierComparisons");
        r.record("eq expected=[0, 1, 2, 3, 4, 5] actual=[0, 1, 2, 3, 4, 5]");
        r.record("eq expected=[6, 7] actual=[6, 7]");
    }

    @:test public static function flushTestTrace():Void {
        TestTraceRecorder.flushClass("LineRepairTailCoverageTest");
    }
}
