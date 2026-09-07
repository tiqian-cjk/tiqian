package org.tiqian.clreq;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class BopomofoParserTest {
    @:test
    public static function yinpingHasNoMark():Void {
        new TestTraceRecorder("BopomofoParserTest").section("yinpingHasNoMark");
        final reading = BopomofoParser.parse("ㄓㄨㄥ");
        TracedAssertions.assertEqualsStringArray(["ㄓ", "ㄨ", "ㄥ"], reading.symbols);
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Yinping, reading.tone);
    }

    @:test
    public static function suffixMarksAreToneAndStripped():Void {
        new TestTraceRecorder("BopomofoParserTest").section("suffixMarksAreToneAndStripped");
        TracedAssertions.assertEqualsBopomofoReading(new BopomofoReading(["ㄔ", "ㄤ"], BopomofoTone.Yangping), BopomofoParser.parse("ㄔㄤˊ"));
        TracedAssertions.assertEqualsBopomofoReading(new BopomofoReading(["ㄋ", "ㄧ"], BopomofoTone.Shang), BopomofoParser.parse("ㄋㄧˇ"));
        TracedAssertions.assertEqualsBopomofoReading(new BopomofoReading(["ㄑ", "ㄩ"], BopomofoTone.Qu), BopomofoParser.parse("ㄑㄩˋ"));
        TracedAssertions.assertEqualsBopomofoReading(new BopomofoReading(["ㄇ", "ㄚ"], BopomofoTone.Yinping), BopomofoParser.parse("ㄇㄚˉ"));
    }

    @:test
    public static function neutralToneIsPrefixed():Void {
        new TestTraceRecorder("BopomofoParserTest").section("neutralToneIsPrefixed");
        final reading = BopomofoParser.parse("˙ㄉㄜ");
        TracedAssertions.assertEqualsStringArray(["ㄉ", "ㄜ"], reading.symbols);
        TracedAssertions.assertEqualsBopomofoTone(BopomofoTone.Neutral, reading.tone);
    }

    @:test
    public static function singleSymbol():Void {
        new TestTraceRecorder("BopomofoParserTest").section("singleSymbol");
        TracedAssertions.assertEqualsBopomofoReading(new BopomofoReading(["ㄦ"], BopomofoTone.Yangping), BopomofoParser.parse("ㄦˊ"));
    }
}
