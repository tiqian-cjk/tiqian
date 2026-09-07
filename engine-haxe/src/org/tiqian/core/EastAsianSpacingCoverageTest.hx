package org.tiqian.core;

import org.tiqian.test.TestHelpers;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class EastAsianSpacingCoverageTest {
    @:test
    public static function testUnicodeWordCharacter():Void {
        new TestTraceRecorder("EastAsianSpacingCoverageTest").section("testUnicodeWordCharacter");
        TracedAssertions.assertEqualsString("17.0.0", UnicodeWordCharacter.DATA_REVISION);
        TracedAssertions.assertTrue(UnicodeWordCharacter.DATA_SOURCE.length > 0);
        TracedAssertions.assertTrue(UnicodeWordCharacter.DATA_SHA256.length > 0);

        EastAsianSpacingCoverageTestHelpers.expectArgumentFailure(() -> UnicodeWordCharacter.contains(-1));
        EastAsianSpacingCoverageTestHelpers.expectArgumentFailure(() -> UnicodeWordCharacter.contains(0x110000));
        EastAsianSpacingCoverageTestHelpers.expectArgumentFailure(() -> UnicodeWordCharacter.contains(0xD800));
        EastAsianSpacingCoverageTestHelpers.expectArgumentFailure(() -> UnicodeWordCharacter.contains(0xDFFF));

        TracedAssertions.assertTrue(UnicodeWordCharacter.contains(0x41));
        TracedAssertions.assertTrue(UnicodeWordCharacter.contains(0x4E2D));
        TracedAssertions.assertFalse(UnicodeWordCharacter.contains(0x20));
        TracedAssertions.assertFalse(UnicodeWordCharacter.contains(0x21));
    }

    @:test
    public static function testUnicodeScriptEvidence():Void {
        new TestTraceRecorder("EastAsianSpacingCoverageTest").section("testUnicodeScriptEvidence");
        final values:Array<UnicodeScriptEvidence> = [
            UnicodeScriptEvidence.Neutral,
            UnicodeScriptEvidence.EastAsian,
            UnicodeScriptEvidence.Other
        ];
        var index:Int = 0;
        while (index < values.length) {
            final value = values[index];
            TracedAssertions.assertNotNullRendered(value != null, value == null ? "-" : Std.string(value));
            index += 1;
        }

        TracedAssertions.assertEqualsString("17.0.0", UnicodeScriptEvidenceClassifier.DATA_REVISION);
        TracedAssertions.assertTrue(UnicodeScriptEvidenceClassifier.DATA_SOURCE.length > 0);
        TracedAssertions.assertTrue(UnicodeScriptEvidenceClassifier.DATA_SHA256.length > 0);

        EastAsianSpacingCoverageTestHelpers.expectArgumentFailure(() -> UnicodeScriptEvidenceClassifier.classify(-1));
        EastAsianSpacingCoverageTestHelpers.expectArgumentFailure(() -> UnicodeScriptEvidenceClassifier.classify(0x110000));
        EastAsianSpacingCoverageTestHelpers.expectArgumentFailure(() -> UnicodeScriptEvidenceClassifier.classify(0xD800));
        EastAsianSpacingCoverageTestHelpers.expectArgumentFailure(() -> UnicodeScriptEvidenceClassifier.classify(0xDFFF));

        TracedAssertions.assertEqualsRendered(Std.string(UnicodeScriptEvidence.EastAsian), Std.string(UnicodeScriptEvidenceClassifier.classify(0x4E00)));
        TracedAssertions.assertEqualsRendered(Std.string(UnicodeScriptEvidence.Other), Std.string(UnicodeScriptEvidenceClassifier.classify(0x0041)));
        TracedAssertions.assertEqualsRendered(Std.string(UnicodeScriptEvidence.Neutral), Std.string(UnicodeScriptEvidenceClassifier.classify(0x0020)));
    }

    @:test
    public static function testEastAsianSpacingDataAndValues():Void {
        new TestTraceRecorder("EastAsianSpacingCoverageTest").section("testEastAsianSpacingDataAndValues");
        final values:Array<EastAsianSpacingValue> = [
            EastAsianSpacingValue.Wide,
            EastAsianSpacingValue.Narrow,
            EastAsianSpacingValue.Other,
            EastAsianSpacingValue.Conditional
        ];
        var index:Int = 0;
        while (index < values.length) {
            final value = values[index];
            TracedAssertions.assertNotNullRendered(value != null, value == null ? "-" : Std.string(value));
            index += 1;
        }

        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Wide), Std.string(EastAsianSpacingData.lookup(0x02C7)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Narrow), Std.string(EastAsianSpacingData.lookup(0x0030)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Conditional), Std.string(EastAsianSpacingData.lookup(0x0021)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Other), Std.string(EastAsianSpacingData.lookup(0x0000)));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Other), Std.string(EastAsianSpacingData.lookup(0x10FFFF)));
    }

    @:test
    public static function testEastAsianSpacingEdgesModel():Void {
        new TestTraceRecorder("EastAsianSpacingCoverageTest").section("testEastAsianSpacingEdgesModel");
        final edges:EastAsianSpacingEdges = new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Narrow, true);
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Wide), Std.string(edges.leading));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Narrow), Std.string(edges.trailing));
        TracedAssertions.assertTrue(edges.containsWide);
        TracedAssertions.assertEqualsEastAsianSpacingEdges(new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Narrow, true), edges);
        TracedAssertions.assertTrue(edges.leading == new EastAsianSpacingEdges(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Narrow, true).leading);
        TracedAssertions.assertTrue(edges.toString().indexOf("EastAsianSpacingEdges") >= 0);
    }

    @:test
    public static function testUnicodeEastAsianSpacing():Void {
        new TestTraceRecorder("EastAsianSpacingCoverageTest").section("testUnicodeEastAsianSpacing");
        TracedAssertions.assertEqualsString("draft-2024-12-16", UnicodeEastAsianSpacing.DATA_REVISION);
        TracedAssertions.assertTrue(UnicodeEastAsianSpacing.DATA_SOURCE.length > 0);
        TracedAssertions.assertTrue(UnicodeEastAsianSpacing.DATA_SHA256.length > 0);
        TracedAssertions.assertEqualsString("2026-06-14", UnicodeEastAsianSpacing.LANGUAGE_REGISTRY_REVISION);
        TracedAssertions.assertTrue(UnicodeEastAsianSpacing.LANGUAGE_REGISTRY_SOURCE.length > 0);

        final chineseLocales:Array<String> = [
            "zh",
            "zh-Hans",
            "zh-Hant",
            "zh-CN",
            "zh_TW",
            "cdo",
            "cjy",
            "cmn",
            "cnp",
            "cpx",
            "csp",
            "czh",
            "czo",
            "gan",
            "hak",
            "hnm",
            "hsn",
            "luh",
            "lzh",
            "mnp",
            "nan",
            "sjc",
            "wuu",
            "yue",
            "yue-HK",
            "cmn-Hans-CN"
        ];
        var index:Int = 0;
        while (index < chineseLocales.length) {
            final locale:String = chineseLocales[index];
            TracedAssertions.assertTrue(UnicodeEastAsianSpacing.isChineseLanguageContext(locale), "Locale " + locale + " should be Chinese");
            index += 1;
        }

        final nonChineseLocales:Array<String> = ["en", "en-US", "ja", "ko", "fr", "de", "es"];
        index = 0;
        while (index < nonChineseLocales.length) {
            final locale:String = nonChineseLocales[index];
            TracedAssertions.assertFalse(UnicodeEastAsianSpacing.isChineseLanguageContext(locale), "Locale " + locale + " should not be Chinese");
            index += 1;
        }

        EastAsianSpacingCoverageTestHelpers.expectArgumentFailure(() -> UnicodeEastAsianSpacing.propertyOf(-1));
        EastAsianSpacingCoverageTestHelpers.expectArgumentFailure(() -> UnicodeEastAsianSpacing.propertyOf(0x110000));
        EastAsianSpacingCoverageTestHelpers.expectArgumentFailure(() -> UnicodeEastAsianSpacing.propertyOf(0xD800));
        EastAsianSpacingCoverageTestHelpers.expectArgumentFailure(() -> UnicodeEastAsianSpacing.propertyOf(0xDFFF));

        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Other),
            Std.string(UnicodeEastAsianSpacing.resolvedForGraphemeCluster("", "zh")));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Other),
            Std.string(UnicodeEastAsianSpacing.resolvedForGraphemeCluster("A\u20DD", "zh")));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Narrow),
            Std.string(UnicodeEastAsianSpacing.resolvedForGraphemeCluster("!", "zh-CN")));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Other),
            Std.string(UnicodeEastAsianSpacing.resolvedForGraphemeCluster("!", "en-US")));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Wide),
            Std.string(UnicodeEastAsianSpacing.resolvedForGraphemeCluster("\u4E2D", "zh")));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Narrow),
            Std.string(UnicodeEastAsianSpacing.resolvedForGraphemeCluster("A", "zh")));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Other),
            Std.string(UnicodeEastAsianSpacing.resolvedForGraphemeCluster("\u0000", "zh")));

        final emptyEdges:EastAsianSpacingEdges = UnicodeEastAsianSpacing.resolvedEdges("", "zh");
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Other), Std.string(emptyEdges.leading));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Other), Std.string(emptyEdges.trailing));
        TracedAssertions.assertFalse(emptyEdges.containsWide);

        final mixedEdges:EastAsianSpacingEdges = UnicodeEastAsianSpacing.resolvedEdges("\u4E2Da\u6587", "zh");
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Wide), Std.string(mixedEdges.leading));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Wide), Std.string(mixedEdges.trailing));
        TracedAssertions.assertTrue(mixedEdges.containsWide);

        final westernEdges:EastAsianSpacingEdges = UnicodeEastAsianSpacing.resolvedEdges("hello", "en");
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Narrow), Std.string(westernEdges.leading));
        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Narrow), Std.string(westernEdges.trailing));
        TracedAssertions.assertFalse(westernEdges.containsWide);

        TracedAssertions.assertEqualsRendered(Std.string(EastAsianSpacingValue.Other),
            Std.string(UnicodeEastAsianSpacing.resolvedForGraphemeCluster(TestHelpers.surrogateText([0xD83D, 0xDE00]), "zh")));
        EastAsianSpacingCoverageTestHelpers.expectArgumentFailure(() -> UnicodeEastAsianSpacing.resolvedForGraphemeCluster(TestHelpers.surrogateText([0xD800]),
            "zh"));
        EastAsianSpacingCoverageTestHelpers.expectArgumentFailure(() ->
            UnicodeEastAsianSpacing.resolvedForGraphemeCluster(TestHelpers.surrogateText([0xD800, 0x41]), "zh"));
        EastAsianSpacingCoverageTestHelpers.expectArgumentFailure(() ->
            UnicodeEastAsianSpacing.resolvedForGraphemeCluster(TestHelpers.surrogateText([0xD800, 0xE000]), "zh"));
    }
}

class EastAsianSpacingCoverageTestHelpers {
    public static function expectArgumentFailure(block:() -> Void):Void {
        TracedAssertions.assertFailsWith(null, block);
    }
}
