package org.tiqian.core;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class UnicodeNumberTest {
    @:test
    public static function numbersAreMembersAcrossScriptsAndNonScalarsAreRejected():Void {
        new TestTraceRecorder("UnicodeNumberTest").section("numbersAreMembersAcrossScriptsAndNonScalarsAreRejected");
        final positives:Array<Int> = [0x30, 0x0662, 0x00BD];
        var index:Int = 0;
        while (index < positives.length) {
            final codePoint:Int = positives[index];
            TracedAssertions.assertTrue(UnicodeNumber.contains(codePoint), "U+" + StringTools.hex(codePoint, 0).toLowerCase());
            index += 1;
        }
        final negatives:Array<Int> = [0x61, 0x400D, 0x2019];
        index = 0;
        while (index < negatives.length) {
            final codePoint:Int = negatives[index];
            TracedAssertions.assertFalse(UnicodeNumber.contains(codePoint), "U+" + StringTools.hex(codePoint, 0).toLowerCase());
            index += 1;
        }
        TracedAssertions.assertFailsWith(null, function():Void {
            UnicodeNumber.contains(0xDC00);
        });
        TracedAssertions.assertFailsWith(null, function():Void {
            UnicodeNumber.contains(-1);
        });
        TracedAssertions.assertFailsWith(null, function():Void {
            UnicodeNumber.contains(0x110000);
        });
    }
}
