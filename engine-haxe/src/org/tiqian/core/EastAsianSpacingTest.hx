package org.tiqian.core;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class EastAsianSpacingTest {
    @:test
    public static function chineseLanguageContextUsesPinnedMacrolanguageRegistry():Void {
        new TestTraceRecorder("EastAsianSpacingTest").section("chineseLanguageContextUsesPinnedMacrolanguageRegistry");
        TracedAssertions.assertTrue(UnicodeEastAsianSpacing.isChineseLanguageContext("zh-Hans"));
        TracedAssertions.assertTrue(UnicodeEastAsianSpacing.isChineseLanguageContext("yue-Hant-HK"));
        TracedAssertions.assertFalse(UnicodeEastAsianSpacing.isChineseLanguageContext("en"));
    }

    @:test
    public static function usesPinnedUnicodeDraftDataAcrossScripts():Void {
        new TestTraceRecorder("EastAsianSpacingTest").section("usesPinnedUnicodeDraftDataAcrossScripts");
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Wide), Std.string(UnicodeEastAsianSpacing.propertyOf(0x63D0)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Wide), Std.string(UnicodeEastAsianSpacing.propertyOf(0x17000)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Narrow), Std.string(UnicodeEastAsianSpacing.propertyOf(0x41)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Narrow), Std.string(UnicodeEastAsianSpacing.propertyOf(0x03B1)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Narrow), Std.string(UnicodeEastAsianSpacing.propertyOf(0x044F)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Narrow), Std.string(UnicodeEastAsianSpacing.propertyOf(0x39)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Conditional), Std.string(UnicodeEastAsianSpacing.propertyOf(0x25)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Other), Std.string(UnicodeEastAsianSpacing.propertyOf(0xFF0F)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Other), Std.string(UnicodeEastAsianSpacing.propertyOf(0x1F600)));
    }

    @:test
    public static function resolvesConditionalValuesFromChineseLanguageContext():Void {
        new TestTraceRecorder("EastAsianSpacingTest").section("resolvesConditionalValuesFromChineseLanguageContext");
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Narrow),
            Std.string(UnicodeEastAsianSpacing.resolvedForGraphemeCluster("%", "zh-Hans")));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Narrow),
            Std.string(UnicodeEastAsianSpacing.resolvedForGraphemeCluster("%", "yue-Hant-HK")));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Other),
            Std.string(UnicodeEastAsianSpacing.resolvedForGraphemeCluster("%", "en")));
    }

    @:test
    public static function enclosingMarkMakesTheWholeGraphemeClusterOther():Void {
        new TestTraceRecorder("EastAsianSpacingTest").section("enclosingMarkMakesTheWholeGraphemeClusterOther");
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Other),
            Std.string(UnicodeEastAsianSpacing.resolvedForGraphemeCluster("A\u20DD", "zh-Hans")));
    }

    @:test
    public static function resolvesTheActualSourceUnitAtEachShapingClusterEdge():Void {
        new TestTraceRecorder("EastAsianSpacingTest").section("resolvesTheActualSourceUnitAtEachShapingClusterEdge");
        TracedAssertions.assertEqualsEastAsianSpacingEdges(new EastAsianSpacingEdges(EastAsianSpacingValue.Other, EastAsianSpacingValue.Narrow, false),
            UnicodeEastAsianSpacing.resolvedEdges("/Hi", "zh-Hans"));
        TracedAssertions.assertEqualsEastAsianSpacingEdges(new EastAsianSpacingEdges(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other, false),
            UnicodeEastAsianSpacing.resolvedEdges("A\u20DD", "zh-Hans"));
    }
}
