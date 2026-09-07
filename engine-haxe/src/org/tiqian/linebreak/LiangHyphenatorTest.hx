package org.tiqian.linebreak;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.linebreak.Hyphenator.NoHyphenator;
import org.tiqian.test.trace.TracedAssertions;

class LiangHyphenatorTest {
    @:test public static function noHyphenatorYieldsNoOpportunities():Void {
        new TestTraceRecorder("LiangHyphenatorTest").section("noHyphenatorYieldsNoOpportunities");
        TracedAssertions.assertEqualsIntArray([], new NoHyphenator().hyphenate("international"));
    }

    @:test public static function oddLevelGapBecomesABreakOutsideTheMargins():Void {
        new TestTraceRecorder("LiangHyphenatorTest").section("oddLevelGapBecomesABreakOutsideTheMargins");
        final h = new LiangHyphenator(LiangHyphenatorTestHelpers.table(["c"], [[1, 0]]), LiangHyphenatorTestHelpers.table([], []), 1, 1);
        TracedAssertions.assertEqualsIntArray([2], h.hyphenate("abc"));
        TracedAssertions.assertEqualsIntArray([], h.hyphenate("cab"));
    }

    @:test public static function maxLevelWinsAndEvenForbidsTheBreak():Void {
        new TestTraceRecorder("LiangHyphenatorTest").section("maxLevelWinsAndEvenForbidsTheBreak");
        final h = new LiangHyphenator(LiangHyphenatorTestHelpers.table(["ab", "zab"], [[0, 1, 0], [0, 0, 2, 0]]), LiangHyphenatorTestHelpers.table([], []), 1,
            1);
        TracedAssertions.assertEqualsIntArray([1], h.hyphenate("ab"));
        TracedAssertions.assertEqualsIntArray([], h.hyphenate("zab"));
    }

    @:test public static function marginsAndShortWordsAreRespected():Void {
        new TestTraceRecorder("LiangHyphenatorTest").section("marginsAndShortWordsAreRespected");
        final h = new LiangHyphenator(LiangHyphenatorTestHelpers.table(["a"], [[1, 0]]), LiangHyphenatorTestHelpers.table([], []), 2, 3);
        TracedAssertions.assertEqualsIntArray([], h.hyphenate("the"));
    }

    @:test public static function exceptionsOverridePatternsAndAreCaseInsensitive():Void {
        new TestTraceRecorder("LiangHyphenatorTest").section("exceptionsOverridePatternsAndAreCaseInsensitive");
        final h = new LiangHyphenator(LiangHyphenatorTestHelpers.table([], []), LiangHyphenatorTestHelpers.table(["table"], [[2]]), 1, 1);
        TracedAssertions.assertEqualsIntArray([2], h.hyphenate("table"));
        TracedAssertions.assertEqualsIntArray([2], h.hyphenate("Table"));
    }

    @:test public static function parsesPatternsAndExceptionBlocksStrippingComments():Void {
        new TestTraceRecorder("LiangHyphenatorTest").section("parsesPatternsAndExceptionBlocksStrippingComments");
        final p = ParseTexHyphenationPatterns.parse("\\patterns{ .ach4 a5bal }\\hyphenation{ ta-ble present }");
        TracedAssertions.assertEqualsIntArray([0, 0, 0, 0, 4], p.patterns.get(".ach"));
        TracedAssertions.assertEqualsIntArray([0, 5, 0, 0, 0], p.patterns.get("abal"));
        TracedAssertions.assertEqualsIntArray([2], p.exceptions.get("table"));
        TracedAssertions.assertEqualsIntArray([], p.exceptions.get("present"));
    }
}

class LiangHyphenatorTestHelpers {
    public static function table(keys:Array<String>, values:Array<Array<Int>>):runtime.SortedTable.SortedMapTable<String, Array<Int>> {
        final b = runtime.SortedTable.mapBuilder(runtime.SortedTable.compareStrings);
        var i = 0;
        while (i < keys.length) {
            b.put(keys[i], values[i]);
            i++;
        }
        return b.build();
    }
}
