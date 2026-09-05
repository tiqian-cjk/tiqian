package org.tiqian.core;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class EastAsianSpacingLookupCoverageTest {
    @:test
    public static function lookupCoversEveryGeneratedValueAndBothMissDirections():Void {
        new TestTraceRecorder("EastAsianSpacingLookupCoverageTest").section("lookupCoversEveryGeneratedValueAndBothMissDirections");
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Conditional), Std.string(EastAsianSpacingData.lookup(0x21)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Narrow), Std.string(EastAsianSpacingData.lookup(0x41)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Narrow), Std.string(EastAsianSpacingData.lookup(0x30)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Wide), Std.string(EastAsianSpacingData.lookup(0x4E00)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Wide), Std.string(EastAsianSpacingData.lookup(0x9FFF)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Other), Std.string(EastAsianSpacingData.lookup(0x02)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Other), Std.string(EastAsianSpacingData.lookup(0x10FFFF)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Other), Std.string(EastAsianSpacingData.lookup(0x22)));
    }
}
