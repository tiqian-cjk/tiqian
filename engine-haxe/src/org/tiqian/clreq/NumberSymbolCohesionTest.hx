package org.tiqian.clreq;

import org.tiqian.core.IntRange;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class NumberSymbolCohesionTest {
    @:test
    public static function bareNumberIsItsOwnGroup():Void {
        new TestTraceRecorder("NumberSymbolCohesionTest").section("bareNumberIsItsOwnGroup");
        TracedAssertions.assertEqualsStringArray(["2024"], NumberSymbolCohesionTestHelpers.groups("在2024年"));
        TracedAssertions.assertEqualsStringArray([], NumberSymbolCohesionTestHelpers.groups("纯中文没有数字"));
    }

    @:test
    public static function bindsDigitsWithSuffixUnitPrefixSignAndCurrency():Void {
        new TestTraceRecorder("NumberSymbolCohesionTest").section("bindsDigitsWithSuffixUnitPrefixSignAndCurrency");
        TracedAssertions.assertEqualsStringArray(["50%"], NumberSymbolCohesionTestHelpers.groups("增长50%了"));
        TracedAssertions.assertEqualsStringArray(["37℃"], NumberSymbolCohesionTestHelpers.groups("温37℃高"));
        TracedAssertions.assertEqualsStringArray(["90°"], NumberSymbolCohesionTestHelpers.groups("转90°角"));
        TracedAssertions.assertEqualsStringArray(["+5"], NumberSymbolCohesionTestHelpers.groups("是+5度"));
        TracedAssertions.assertEqualsStringArray(["±2"], NumberSymbolCohesionTestHelpers.groups("误差±2毫米"));
        TracedAssertions.assertEqualsStringArray(["¥100"], NumberSymbolCohesionTestHelpers.groups("价¥100元"));
        TracedAssertions.assertEqualsStringArray(["100₫"], NumberSymbolCohesionTestHelpers.groups("约100₫的"));
    }

    @:test
    public static function keepsInteriorDecimalAndThousandsSeparators():Void {
        new TestTraceRecorder("NumberSymbolCohesionTest").section("keepsInteriorDecimalAndThousandsSeparators");
        TracedAssertions.assertEqualsStringArray(["3.14"], NumberSymbolCohesionTestHelpers.groups("π≈3.14啦"));
        TracedAssertions.assertEqualsStringArray(["1,000"], NumberSymbolCohesionTestHelpers.groups("共1,000人"));
        TracedAssertions.assertEqualsStringArray(["100"], NumberSymbolCohesionTestHelpers.groups("有100。"));
    }
}

class NumberSymbolCohesionTestHelpers {
    public static function groups(text:String):Array<String> {
        final ranges:Array<IntRange> = NumberSymbolCohesion.unbreakableRanges(text);
        final result:Array<String> = [];
        var index:Int = 0;
        while (index < ranges.length) {
            result.push(text.substring(ranges[index].start, ranges[index].end + 1));
            index += 1;
        }
        return result;
    }
}
