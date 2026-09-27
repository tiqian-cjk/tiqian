package org.tiqian.layout;

import org.tiqian.layout.PreparedParagraph.PreparedParagraphFns;
import org.tiqian.test.TestHelpers;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class PreparedParagraphJsonNumberTest {
    @:test public static function zeroValuesSerializeWithoutSign():Void {
        PreparedParagraphJsonNumberTestSupport.rec("zeroValuesSerializeWithoutSign");
        PreparedParagraphJsonNumberTestSupport.eq("0", TestHelpers.f32Literal(0.0));
        PreparedParagraphJsonNumberTestSupport.eq("0", TestHelpers.f32Literal(-0.0));
        PreparedParagraphJsonNumberTestSupport.eq("NaN", Math.NaN);
        PreparedParagraphJsonNumberTestSupport.eq("Infinity", Math.POSITIVE_INFINITY);
        PreparedParagraphJsonNumberTestSupport.eq("-Infinity", Math.NEGATIVE_INFINITY);
    }

    @:test public static function integerFormsPadToDecimalExponent():Void {
        PreparedParagraphJsonNumberTestSupport.rec("integerFormsPadToDecimalExponent");
        PreparedParagraphJsonNumberTestSupport.eq("1", TestHelpers.f32Literal(1));
        PreparedParagraphJsonNumberTestSupport.eq("200", TestHelpers.f32Literal(200));
        PreparedParagraphJsonNumberTestSupport.eq("999999986991104", TestHelpers.f32Literal(1.0e15));
        PreparedParagraphJsonNumberTestSupport.eq("10000000272564224", TestHelpers.f32Literal(1.0e16));
        PreparedParagraphJsonNumberTestSupport.eq("100000002004087730000", TestHelpers.f32Literal(1.0e20));
        PreparedParagraphJsonNumberTestSupport.eq("9007199254740992", TestHelpers.f32Literal(9007199254740992));
    }

    @:test public static function fractionFormsInsertDecimalPoint():Void {
        PreparedParagraphJsonNumberTestSupport.rec("fractionFormsInsertDecimalPoint");
        PreparedParagraphJsonNumberTestSupport.eq("1.5", TestHelpers.f32Literal(1.5));
        PreparedParagraphJsonNumberTestSupport.eq("12.5", TestHelpers.f32Literal(12.5));
        PreparedParagraphJsonNumberTestSupport.eq("1000000.5", TestHelpers.f32Literal(1000000.5));
    }

    @:test public static function smallFractionsUseLeadingZeros():Void {
        PreparedParagraphJsonNumberTestSupport.rec("smallFractionsUseLeadingZeros");
        PreparedParagraphJsonNumberTestSupport.eq("0.10000000149011612", TestHelpers.f32Literal(.1));
        PreparedParagraphJsonNumberTestSupport.eq("0.44999998807907104", TestHelpers.f32Literal(.45));
        PreparedParagraphJsonNumberTestSupport.eq("0.05000000074505806", TestHelpers.f32Literal(.05));
        PreparedParagraphJsonNumberTestSupport.eq("0.009999999776482582", TestHelpers.f32Literal(.01));
        PreparedParagraphJsonNumberTestSupport.eq("0.00009999999747378752", TestHelpers.f32Literal(.0001));
        PreparedParagraphJsonNumberTestSupport.eq("0.0003499999875202775", TestHelpers.f32Literal(.00035));
    }

    @:test public static function exponentFormsCarryExplicitSign():Void {
        PreparedParagraphJsonNumberTestSupport.rec("exponentFormsCarryExplicitSign");
        PreparedParagraphJsonNumberTestSupport.eq("1.0000000200408773e+21", TestHelpers.f32Literal(1e21));
        PreparedParagraphJsonNumberTestSupport.eq("9.999999778196308e+21", TestHelpers.f32Literal(1e22));
        PreparedParagraphJsonNumberTestSupport.eq("1.4999999667294463e+22", TestHelpers.f32Literal(1.5e22));
        PreparedParagraphJsonNumberTestSupport.eq("2.499999944549077e+22", TestHelpers.f32Literal(2.5e22));
        PreparedParagraphJsonNumberTestSupport.eq("1.5000000207726418e+24", TestHelpers.f32Literal(1.5e24));
        PreparedParagraphJsonNumberTestSupport.eq("1.0000000116860974e-7", TestHelpers.f32Literal(1e-7));
        PreparedParagraphJsonNumberTestSupport.eq("1.500000053056283e-7", TestHelpers.f32Literal(1.5e-7));
    }

    @:test public static function negativeValuesKeepOnlyMagnitudeSign():Void {
        PreparedParagraphJsonNumberTestSupport.rec("negativeValuesKeepOnlyMagnitudeSign");
        PreparedParagraphJsonNumberTestSupport.eq("-1.5", TestHelpers.f32Literal(-1.5));
        PreparedParagraphJsonNumberTestSupport.eq("-2.499999993688107e-7", TestHelpers.f32Literal(-2.5e-7));
    }

    @:test public static function exactTiesRoundToEvenDigit():Void {
        PreparedParagraphJsonNumberTestSupport.rec("exactTiesRoundToEvenDigit");
        PreparedParagraphJsonNumberTestSupport.eq("5.960464477539062e-8", TestHelpers.f32Literal(5.960464477539063e-8));
        PreparedParagraphJsonNumberTestSupport.eq("2.9802322387695312e-8", TestHelpers.f32Literal(2.9802322387695312e-8));
        PreparedParagraphJsonNumberTestSupport.eq("1.7432641983032227", TestHelpers.f32Literal(1.7432641983032227));
    }

    @:test public static function exactExpansionRoundsPlatformDigits():Void {
        PreparedParagraphJsonNumberTestSupport.rec("exactExpansionRoundsPlatformDigits");
        PreparedParagraphJsonNumberTestSupport.eq("1152921504606847000", TestHelpers.f32Literal(1152921504606846976));
        PreparedParagraphJsonNumberTestSupport.eq("5.684341886080801e-14", TestHelpers.f32Literal(5.684341886080802e-14));
        PreparedParagraphJsonNumberTestSupport.eq("5.316911983139663e+36", TestHelpers.f32Literal(5.316911983139664e+36));
    }

    @:test public static function boundaryMidpointsAcceptOnlyAtEvenMantissa():Void {
        PreparedParagraphJsonNumberTestSupport.rec("boundaryMidpointsAcceptOnlyAtEvenMantissa");
        PreparedParagraphJsonNumberTestSupport.eq("33474762504142850", TestHelpers.f32Bits(0x5AEDDA3D));
        PreparedParagraphJsonNumberTestSupport.eq("103571925162262530", TestHelpers.f32Bits(0x5BB7FB0F));
    }

    @:test public static function decimalAlignedMantissaSkipsZeroChunk():Void {
        PreparedParagraphJsonNumberTestSupport.rec("decimalAlignedMantissaSkipsZeroChunk");
        PreparedParagraphJsonNumberTestSupport.eq("12500000", TestHelpers.f32Literal(12500000));
    }

    @:test public static function subnormalExpansionsSerialize():Void {
        PreparedParagraphJsonNumberTestSupport.rec("subnormalExpansionsSerialize");
        PreparedParagraphJsonNumberTestSupport.eq("1.401298464324817e-45", TestHelpers.f32Bits(1));
        PreparedParagraphJsonNumberTestSupport.eq("4.203895392974451e-45", TestHelpers.f32Bits(3));
    }

    public static function flushTestTrace():Void {
        TestTraceRecorder.flushClass("PreparedParagraphJsonNumberTest");
    }

}
