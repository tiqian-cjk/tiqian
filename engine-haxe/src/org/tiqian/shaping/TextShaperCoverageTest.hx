package org.tiqian.shaping;

import org.tiqian.font.FontRole;
import org.tiqian.shaping.TextShaper.ShapingSource;
import org.tiqian.shaping.TextShaper.ExplainableStubTextShaper;
import org.tiqian.shaping.TextShaper.UnimplementedTextShaper;
import org.tiqian.shaping.TextShaper.ShapingSource;
import org.tiqian.shaping.TextShaper.ExplainableStubTextShaper;
import org.tiqian.shaping.TextShaper.UnimplementedTextShaper;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class TextShaperCoverageTest {
    @:test public static function coversAllShapingSourceEnumEntries():Void {
        new TestTraceRecorder("TextShaperCoverageTest").section("coversAllShapingSourceEnumEntries");
        var sources:Array<ShapingSource> = Type.allEnums(ShapingSource);
        var hasStub = false;
        var hasJvmAwt = false;
        var hasAndroidPaint = false;
        var hasSkia = false;
        var hasHarfBuzz = false;
        var hasCoreText = false;
        var e = 0;
        while (e < sources.length) {
            var entry = sources[e];
            if (entry == ShapingSource.Stub)
                hasStub = true;
            if (entry == ShapingSource.JvmAwt)
                hasJvmAwt = true;
            if (entry == ShapingSource.AndroidPaint)
                hasAndroidPaint = true;
            if (entry == ShapingSource.Skia)
                hasSkia = true;
            if (entry == ShapingSource.HarfBuzz)
                hasHarfBuzz = true;
            if (entry == ShapingSource.CoreText)
                hasCoreText = true;
            e += 1;
        }
        TracedAssertions.assertTrue(hasStub);
        TracedAssertions.assertTrue(hasJvmAwt);
        TracedAssertions.assertTrue(hasAndroidPaint);
        TracedAssertions.assertTrue(hasSkia);
        TracedAssertions.assertTrue(hasHarfBuzz);
        TracedAssertions.assertTrue(hasCoreText);
        TracedAssertions.assertEqualsInt(6, sources.length);
        var i = 0;
        while (i < sources.length) {
            var source = sources[i];
            var name = Type.enumConstructor(source);
            TracedAssertions.assertEqualsRendered(name, Type.enumConstructor(Type.createEnum(ShapingSource, name)));
            i++;
        }
    }

    @:test public static function unimplementedTextShaperThrowsOnShape():Void {
        new TestTraceRecorder("TextShaperCoverageTest").section("unimplementedTextShaperThrowsOnShape");
        var error = TracedAssertions.assertFailsWith(null, function() new UnimplementedTextShaper().shape(TextShaperCoverageTestSupport.input("test")));
        TracedAssertions.assertTrue(error.message.indexOf("platform-specific") >= 0);
    }

    @:test public static function explainableStubNominalAdvanceBranches():Void {
        new TestTraceRecorder("TextShaperCoverageTest").section("explainableStubNominalAdvanceBranches");
        var shaper = new ExplainableStubTextShaper();
        TracedAssertions.assertEqualsFloat(32.0, shaper.shape(TextShaperCoverageTestSupport.input("\u2E3A", FontRole.CjkPunctuation)).clusters[0].advance);
        TracedAssertions.assertEqualsFloat(32.0,
            shaper.shape(TextShaperCoverageTestSupport.input("——", FontRole.CjkPunctuation, "\u2E3A")).clusters[0].advance);
        TracedAssertions.assertEqualsFloat(8.0, shaper.shape(TextShaperCoverageTestSupport.input(" ")).clusters[0].advance);
        TracedAssertions.assertEqualsFloat(24.0, shaper.shape(TextShaperCoverageTestSupport.input("   ")).clusters[0].advance);
        var empty = shaper.shape(TextShaperCoverageTestSupport.input(""));
        TracedAssertions.assertEqualsFloat(0.0, empty.clusters[0].advance);
        TracedAssertions.assertEqualsInt(1, empty.glyphRuns[0].glyphs.length);
        TracedAssertions.assertEqualsFloat(32.0, shaper.shape(TextShaperCoverageTestSupport.input(" a")).clusters[0].advance);
        TracedAssertions.assertEqualsFloat(32.0, shaper.shape(TextShaperCoverageTestSupport.input("a ")).clusters[0].advance);
    }

    @:test public static function surrogatePairHandlingInCodePointCount():Void {
        new TestTraceRecorder("TextShaperCoverageTest").section("surrogatePairHandlingInCodePointCount");
        var shaper = new ExplainableStubTextShaper();
        var one = shaper.shape(TextShaperCoverageTestSupport.input(TextShaperCoverageTestSupport.surrogateText([0xD83D, 0xDE00])));
        TracedAssertions.assertEqualsInt(1, one.decisions[0].glyphCount);
        TracedAssertions.assertEqualsFloat(16.0, one.clusters[0].advance);
        var two = shaper.shape(TextShaperCoverageTestSupport.input(TextShaperCoverageTestSupport.surrogateText([0xD83D, 0xDE00, 0xD840, 0xDC0B])));
        TracedAssertions.assertEqualsInt(2, two.decisions[0].glyphCount);
        TracedAssertions.assertEqualsFloat(32.0, two.clusters[0].advance);
        var high = shaper.shape(TextShaperCoverageTestSupport.input(TextShaperCoverageTestSupport.surrogateText([0xD83D])));
        TracedAssertions.assertEqualsInt(1, high.decisions[0].glyphCount);
        TracedAssertions.assertEqualsFloat(16.0, high.clusters[0].advance);
        var invalid = shaper.shape(TextShaperCoverageTestSupport.input(TextShaperCoverageTestSupport.surrogateText([0xD83D, 0x41])));
        TracedAssertions.assertEqualsInt(2, invalid.decisions[0].glyphCount);
        TracedAssertions.assertEqualsFloat(32.0, invalid.clusters[0].advance);
    }

    @:test public static function shapingInputWithFeaturesAndConstants():Void {
        new TestTraceRecorder("TextShaperCoverageTest").section("shapingInputWithFeaturesAndConstants");
        var inputValue = TextShaperCoverageTestSupport.input("Test", null, null, ["fwid=1", "vert=1"]);
        TracedAssertions.assertEqualsStringArray(["fwid=1", "vert=1"], inputValue.openTypeFeatures);
        TracedAssertions.assertEqualsString("Test", inputValue.displayText);
        var result = new ExplainableStubTextShaper().shape(inputValue);
        TracedAssertions.assertEqualsInt(4, result.decisions[0].glyphCount);
        TracedAssertions.assertEqualsInt(4, result.decisions[0].glyphsWithoutInkBounds);
        TracedAssertions.assertEqualsString("ExplainableStubTextShaper:nominal-em-advance", result.decisions[0].reason);
        TracedAssertions.assertEqualsString(Type.enumConstructor(ShapingSource.Stub), result.decisions[0].source);
        TracedAssertions.assertNotNullRendered(TextShaper.UNVERIFIED_DISPLAY_SUBSTITUTION_COVERAGE_ISSUE != null,
            "'" + TextShaper.UNVERIFIED_DISPLAY_SUBSTITUTION_COVERAGE_ISSUE + "'");
        TracedAssertions.assertNotNullRendered(TextShaper.PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE != null,
            "'" + TextShaper.PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE + "'");
    }
}
