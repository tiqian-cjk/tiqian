package org.tiqian.core;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class UnicodeWordCharacterTest {
    @:test
    public static function lettersAndNumbersAreWordCharactersAcrossScripts():Void {
        new TestTraceRecorder("UnicodeWordCharacterTest").section("lettersAndNumbersAreWordCharactersAcrossScripts");
        final positives:Array<Int> = [0x41, 0x32, 0x400D, 0x0301, 0x03C0, 0x0416, 0x0662, 0x20000];
        var index:Int = 0;
        while (index < positives.length) {
            final codePoint:Int = positives[index];
            TracedAssertions.assertTrue(UnicodeWordCharacter.contains(codePoint), "U+" + StringTools.hex(codePoint, 0).toLowerCase());
            index += 1;
        }
        final negatives:Array<Int> = [0x20, 0x2019, 0xFF1F, 0x1F600];
        index = 0;
        while (index < negatives.length) {
            final codePoint:Int = negatives[index];
            TracedAssertions.assertFalse(UnicodeWordCharacter.contains(codePoint), "U+" + StringTools.hex(codePoint, 0).toLowerCase());
            index += 1;
        }
    }
}
