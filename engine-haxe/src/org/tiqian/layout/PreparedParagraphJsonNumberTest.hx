package org.tiqian.layout;

import org.tiqian.layout.PreparedParagraph.PreparedParagraphFns;
import org.tiqian.test.TestHelpers;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class PreparedParagraphJsonNumberTest {
    private static function rec(name:String):Void
        new TestTraceRecorder("PreparedParagraphJsonNumberTest").section(name);

    private static function eq(expected:String, value:Float):Void
        TracedAssertions.assertEqualsString(expected, PreparedParagraphFns.ecmaJsonNumber(value));

    public static function zeroValuesSerializeWithoutSign():Void {
        rec("zeroValuesSerializeWithoutSign");
        eq("0", TestHelpers.f32Literal(0.0));
        eq("0", TestHelpers.f32Literal(-0.0));
        eq("NaN", Math.NaN);
        eq("Infinity", Math.POSITIVE_INFINITY);
        eq("-Infinity", Math.NEGATIVE_INFINITY);
    }

    public static function integerFormsPadToDecimalExponent():Void {
        rec("integerFormsPadToDecimalExponent");
        eq("1", TestHelpers.f32Literal(1));
        eq("200", TestHelpers.f32Literal(200));
        eq("999999986991104", TestHelpers.f32Literal(1.0e15));
        eq("10000000272564224", TestHelpers.f32Literal(1.0e16));
        eq("100000002004087730000", TestHelpers.f32Literal(1.0e20));
        eq("9007199254740992", TestHelpers.f32Literal(9007199254740992));
    }

    public static function fractionFormsInsertDecimalPoint():Void {
        rec("fractionFormsInsertDecimalPoint");
        eq("1.5", TestHelpers.f32Literal(1.5));
        eq("12.5", TestHelpers.f32Literal(12.5));
        eq("1000000.5", TestHelpers.f32Literal(1000000.5));
    }

    public static function smallFractionsUseLeadingZeros():Void {
        rec("smallFractionsUseLeadingZeros");
        eq("0.10000000149011612", TestHelpers.f32Literal(.1));
        eq("0.44999998807907104", TestHelpers.f32Literal(.45));
        eq("0.05000000074505806", TestHelpers.f32Literal(.05));
        eq("0.009999999776482582", TestHelpers.f32Literal(.01));
        eq("0.00009999999747378752", TestHelpers.f32Literal(.0001));
        eq("0.0003499999875202775", TestHelpers.f32Literal(.00035));
    }

    public static function exponentFormsCarryExplicitSign():Void {
        rec("exponentFormsCarryExplicitSign");
        eq("1.0000000200408773e+21", TestHelpers.f32Literal(1e21));
        eq("9.999999778196308e+21", TestHelpers.f32Literal(1e22));
        eq("1.4999999667294463e+22", TestHelpers.f32Literal(1.5e22));
        eq("2.499999944549077e+22", TestHelpers.f32Literal(2.5e22));
        eq("1.5000000207726418e+24", TestHelpers.f32Literal(1.5e24));
        eq("1.0000000116860974e-7", TestHelpers.f32Literal(1e-7));
        eq("1.500000053056283e-7", TestHelpers.f32Literal(1.5e-7));
    }

    public static function negativeValuesKeepOnlyMagnitudeSign():Void {
        rec("negativeValuesKeepOnlyMagnitudeSign");
        eq("-1.5", TestHelpers.f32Literal(-1.5));
        eq("-2.499999993688107e-7", TestHelpers.f32Literal(-2.5e-7));
    }

    public static function exactTiesRoundToEvenDigit():Void {
        rec("exactTiesRoundToEvenDigit");
        eq("5.960464477539062e-8", TestHelpers.f32Literal(5.960464477539063e-8));
        eq("2.9802322387695312e-8", TestHelpers.f32Literal(2.9802322387695312e-8));
        eq("1.7432641983032227", TestHelpers.f32Literal(1.7432641983032227));
    }

    public static function exactExpansionRoundsPlatformDigits():Void {
        rec("exactExpansionRoundsPlatformDigits");
        eq("1152921504606847000", TestHelpers.f32Literal(1152921504606846976));
        eq("5.684341886080801e-14", TestHelpers.f32Literal(5.684341886080802e-14));
        eq("5.316911983139663e+36", TestHelpers.f32Literal(5.316911983139664e+36));
    }

    public static function boundaryMidpointsAcceptOnlyAtEvenMantissa():Void {
        rec("boundaryMidpointsAcceptOnlyAtEvenMantissa");
        eq("33474762504142850", TestHelpers.f32Bits(0x5AEDDA3D));
        eq("103571925162262530", TestHelpers.f32Bits(0x5BB7FB0F));
    }

    public static function decimalAlignedMantissaSkipsZeroChunk():Void {
        rec("decimalAlignedMantissaSkipsZeroChunk");
        eq("12500000", TestHelpers.f32Literal(12500000));
    }

    public static function subnormalExpansionsSerialize():Void {
        rec("subnormalExpansionsSerialize");
        eq("1.401298464324817e-45", TestHelpers.f32Bits(1));
        eq("4.203895392974451e-45", TestHelpers.f32Bits(3));
    }
}
