package org.tiqian.linebreak;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class EnglishHyphenationTest {
    @:test public static function hyphenatesCommonWordsAtSyllablePoints():Void {
        new TestTraceRecorder("EnglishHyphenationTest").section("hyphenatesCommonWordsAtSyllablePoints");
        TracedAssertions.assertEqualsString("hy-phen-ation", EnglishHyphenationTestHelpers.hyphenated("hyphenation"));
        TracedAssertions.assertEqualsString("com-puter", EnglishHyphenationTestHelpers.hyphenated("computer"));
        TracedAssertions.assertTrue(EnglishHyphenationTestHelpers.hyphenated("international").indexOf("in-ter") == 0,
            EnglishHyphenationTestHelpers.hyphenated("international"));
    }

    @:test public static function respectsMarginsAndShortWords():Void {
        new TestTraceRecorder("EnglishHyphenationTest").section("respectsMarginsAndShortWords");
        TracedAssertions.assertEqualsIntArray([], EnglishHyphenation.enUs().hyphenate("the"));
        TracedAssertions.assertEqualsIntArray([], EnglishHyphenation.enUs().hyphenate("a"));
        TracedAssertions.assertTrue(EnglishHyphenationTestHelpers.withinMargins(EnglishHyphenation.enUs().hyphenate("supercalifragilistic"), 2, 3, 20),
            "offsets=[2, 5, 8, 13, 17]");
    }

    @:test public static function honoursTheExceptionList():Void {
        new TestTraceRecorder("EnglishHyphenationTest").section("honoursTheExceptionList");
        TracedAssertions.assertEqualsIntArray([], EnglishHyphenation.enUs().hyphenate("project"));
        TracedAssertions.assertEqualsIntArray([], EnglishHyphenation.enUs().hyphenate("present"));
    }
}

class EnglishHyphenationTestHelpers {
    public static function hyphenated(word:String):String {
        final offsets = EnglishHyphenation.enUs().hyphenate(word);
        final b = new StringBuf();
        var i = 0;
        while (i < word.length) {
            var j = 0;
            var found = false;
            while (j < offsets.length) {
                if (offsets[j] == i)
                    found = true;
                j++;
            }
            if (found)
                b.add("-");
            b.add(word.charAt(i));
            i++;
        }
        return b.toString();
    }

    public static function withinMargins(values:std.ReadOnlyArray<Int>, left:Int, right:Int, length:Int):Bool {
        var i = 0;
        while (i < values.length) {
            if (values[i] < left || values[i] > length - right)
                return false;
            i++;
        }
        return true;
    }
}
