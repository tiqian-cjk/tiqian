package org.tiqian.layout;

import org.tiqian.core.IntRange;
import org.tiqian.core.TextRange;
import org.tiqian.layout.LineOptimization.LineCandidate;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedSet;

class LineCandidateValidationTest {
    @:test public static function hangingBelowLineRangeIsRejected():Void {
        final testTrace = new TestTraceRecorder("LineCandidateValidationTest");
        testTrace.section("hangingBelowLineRangeIsRejected");
        final error = TracedAssertions.assertFailsWith(null, function() LineCandidateValidationTestSupport.candidate([-1, 3]));
        TracedAssertions.assertEqualsString("Hanging clusters must be a trailing line suffix: line=0..3 hanging=[-1, 3]", error.message);
    }

    @:test public static function hangingEntirelyAboveLineIsRejected():Void {
        final testTrace = new TestTraceRecorder("LineCandidateValidationTest");
        testTrace.section("hangingEntirelyAboveLineIsRejected");
        TracedAssertions.assertFailsWith(null, function() LineCandidateValidationTestSupport.candidate([5, 6]));
    }

    @:test public static function hangingAboveLineLastIsRejected():Void {
        final testTrace = new TestTraceRecorder("LineCandidateValidationTest");
        testTrace.section("hangingAboveLineLastIsRejected");
        TracedAssertions.assertFailsWith(null, function() LineCandidateValidationTestSupport.candidate([1, 4]));
    }

    @:test public static function nonContiguousHangingIsRejected():Void {
        final testTrace = new TestTraceRecorder("LineCandidateValidationTest");
        testTrace.section("nonContiguousHangingIsRejected");
        TracedAssertions.assertFailsWith(null, function() LineCandidateValidationTestSupport.candidate([0, 2, 3]));
    }

    @:test public static function inMeasureRangeExcludesHangingSuffix():Void {
        final testTrace = new TestTraceRecorder("LineCandidateValidationTest");
        testTrace.section("inMeasureRangeExcludesHangingSuffix");
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 1), LineCandidateValidationTestSupport.candidate([2, 3]).inMeasureClusterRange);
    }

    @:test public static function inMeasureRangeIsFullLineWithoutHanging():Void {
        final testTrace = new TestTraceRecorder("LineCandidateValidationTest");
        testTrace.section("inMeasureRangeIsFullLineWithoutHanging");
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 3), LineCandidateValidationTestSupport.candidate([]).inMeasureClusterRange);
    }
}
