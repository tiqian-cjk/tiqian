package org.tiqian.core;

import org.tiqian.test.TestHelpers;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class SourceInteractionBoundariesCoverageTest {
    @:test
    public static function crlfStaysOneUnit():Void {
        new TestTraceRecorder("SourceInteractionBoundariesCoverageTest").section("crlfStaysOneUnit");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 2]", "\r\n");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 1]", "\r");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 1, 2]", "a\n");
    }

    @:test
    public static function regionalIndicatorsPairUp():Void {
        new TestTraceRecorder("SourceInteractionBoundariesCoverageTest").section("regionalIndicatorsPairUp");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 4]", TestHelpers.surrogateText([0xD83C, 0xDDE6, 0xD83C, 0xDDE8]));
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 4, 6]",
            TestHelpers.surrogateText([0xD83C, 0xDDE6, 0xD83C, 0xDDE6, 0xD83C, 0xDDE6]));
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 2, 3]", TestHelpers.surrogateText([0xD83C, 0xDDE6]) + "A");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 2]", TestHelpers.surrogateText([0xD83C, 0xDDE6]));
    }

    @:test
    public static function hangulJamoRunsMergeIntoSyllableBlocks():Void {
        new TestTraceRecorder("SourceInteractionBoundariesCoverageTest").section("hangulJamoRunsMergeIntoSyllableBlocks");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 3]", "\u1100\u1100\u1161");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 3]", "\u1100\u1161\u11A8");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 4]", "\u1100\u1161\u11A8\u11A8");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 1, 2]", "\u1100A");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 2, 3]", "\u1100\u1161A");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 2]", "\uA960\u1161");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 2]", "\u1100\uD7B0");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 3]", "\u1100\u1161\uD7CB");
    }

    @:test
    public static function precomposedHangulSyllablesAbsorbJamo():Void {
        new TestTraceRecorder("SourceInteractionBoundariesCoverageTest").section("precomposedHangulSyllablesAbsorbJamo");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 3]", "\uAC00\u1161\u11A8");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 2]", "\uAC01\u11A8");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 1, 2]", "\uAC01A");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 2]", "\uAC00\u11A8");
    }

    @:test
    public static function extendersAttachToThePrecedingUnit():Void {
        new TestTraceRecorder("SourceInteractionBoundariesCoverageTest").section("extendersAttachToThePrecedingUnit");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 2]", "a\u0301");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 2]", "a\uFE0F");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 3]", "a" + TestHelpers.surrogateText([0xDB40, 0xDD00]));
        final scotland:String = TestHelpers.surrogateText([
            0xD83C, 0xDFF4, 0xDB40, 0xDC67, 0xDB40, 0xDC62,
            0xDB40, 0xDC65, 0xDB40, 0xDC6E, 0xDB40, 0xDC67
        ]);
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 12]", scotland);
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 2]", "\uAC00\u200C");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 1, 2]", "aA");
    }

    @:test
    public static function bandEdgesAndGapsExerciseEveryRangeArm():Void {
        new TestTraceRecorder("SourceInteractionBoundariesCoverageTest").section("bandEdgesAndGapsExerciseEveryRangeArm");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 1, 2]", "\rA");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 1, 2]", "a\u1100");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 2, 3]", "\u1100\u1161\uE000");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 1, 2]", TestHelpers.surrogateText([0xD800, 0xE000]));
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 1, 3]", "a" + TestHelpers.surrogateText([0xDB40, 0xDDF0]));
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 1, 3]", "a" + TestHelpers.surrogateText([0xDB40, 0xDCA0]));
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 2, 3]", TestHelpers.surrogateText([0xD83D, 0xDC4D]) + "\u7532");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 2, 4]", TestHelpers.surrogateText([0xD83D, 0xDC4D, 0xD83D, 0xDE00]));
    }

    @:test
    public static function emojiModifiersOnlyAttachToBases():Void {
        new TestTraceRecorder("SourceInteractionBoundariesCoverageTest").section("emojiModifiersOnlyAttachToBases");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 4]", TestHelpers.surrogateText([0xD83D, 0xDC4D, 0xD83C, 0xDFFB]));
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 5]", TestHelpers.surrogateText([0xD83D, 0xDC4D, 0xD83C, 0xDFFB]) + "\uFE0F");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 1, 3]", "a" + TestHelpers.surrogateText([0xD83C, 0xDFFB]));
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 2]", TestHelpers.surrogateText([0xD83D, 0xDC4D]));
    }

    @:test
    public static function zwjChainsJoinOnlyExtendedPictographic():Void {
        new TestTraceRecorder("SourceInteractionBoundariesCoverageTest").section("zwjChainsJoinOnlyExtendedPictographic");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 8]",
            TestHelpers.surrogateText([0xD83D, 0xDC69, 0x200D, 0xD83D, 0xDC69, 0x200D, 0xD83D, 0xDC66]));
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 2]", "a\u200D");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 3, 4]", TestHelpers.surrogateText([0xD83D, 0xDC69]) + "\u200Da");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 2, 3]", "a\u200Da");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 7]",
            TestHelpers.surrogateText([0xD83D, 0xDC4D, 0x200D, 0xD83D, 0xDC4D, 0xD83C, 0xDFFB]));
    }

    @:test
    public static function unpairedSurrogatesFallBackToSingleUnits():Void {
        new TestTraceRecorder("SourceInteractionBoundariesCoverageTest").section("unpairedSurrogatesFallBackToSingleUnits");
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 1, 2]", TestHelpers.surrogateText([0x61, 0xD800]));
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 1, 2, 3]", TestHelpers.surrogateText([0x61, 0xD800, 0x41]));
        SourceInteractionBoundariesCoverageTestHelpers.assertBoundaries("[0, 2, 3]", TestHelpers.surrogateText([0xD83D, 0xDE00]) + "A");
    }

    @:test
    public static function codePointAtCompatCoversEverySurrogateCase():Void {
        new TestTraceRecorder("SourceInteractionBoundariesCoverageTest").section("codePointAtCompatCoversEverySurrogateCase");
        TracedAssertions.assertEqualsInt(97, SourceInteractionBoundaries.codePointAtCompat("a", 0, 1));
        TracedAssertions.assertEqualsInt(0x1F600, SourceInteractionBoundaries.codePointAtCompat(TestHelpers.surrogateText([0xD83D, 0xDE00]), 0, 2));
        TracedAssertions.assertEqualsInt(0xD800, SourceInteractionBoundaries.codePointAtCompat(TestHelpers.surrogateText([0x61, 0xD800]), 1, 2));
        TracedAssertions.assertEqualsInt(0xD800, SourceInteractionBoundaries.codePointAtCompat(TestHelpers.surrogateText([0x61, 0xD800, 0x41]), 1, 3));
    }

    @:test
    public static function rangeBoundariesRespectTheRequestedWindow():Void {
        new TestTraceRecorder("SourceInteractionBoundariesCoverageTest").section("rangeBoundariesRespectTheRequestedWindow");
        TracedAssertions.assertEqualsRendered("[1, 2, 3]",
            SourceInteractionBoundariesCoverageTestHelpers.renderInts(SourceInteractionBoundaries.interactionBoundaries("abcd", new TextRange(1, 3))));
        TracedAssertions.assertEqualsRendered("[2]",
            SourceInteractionBoundariesCoverageTestHelpers.renderInts(SourceInteractionBoundaries.interactionBoundaries("ab", new TextRange(5, 9))));
        final emojiB:String = TestHelpers.surrogateText([0xD83D, 0xDE00]) + "b";
        TracedAssertions.assertEqualsRendered("[0, 2, 3]",
            SourceInteractionBoundariesCoverageTestHelpers.renderInts(SourceInteractionBoundaries.sourceGraphemeBoundaries(emojiB, new TextRange(0, 3))));
    }

    @:test
    public static function coercionHonoursEveryBiasAndEdgeCase():Void {
        new TestTraceRecorder("SourceInteractionBoundariesCoverageTest").section("coercionHonoursEveryBiasAndEdgeCase");
        final family:String = TestHelpers.surrogateText([
            0xD83D, 0xDC68, 0x200D, 0xD83D, 0xDC69, 0x200D, 0xD83D, 0xDC67, 0x200D, 0xD83D, 0xDC67
        ]);
        TracedAssertions.assertEqualsInt(11, family.length);
        final familyRange:TextRange = new TextRange(0, 11);
        TracedAssertions.assertEqualsInt(0, SourceInteractionBoundaries.coerceToInteractionBoundary(family, 2, familyRange, SourceBoundaryBias.Nearest));
        TracedAssertions.assertEqualsInt(0, SourceInteractionBoundaries.coerceToInteractionBoundary(family, 2, familyRange, SourceBoundaryBias.Backward));
        TracedAssertions.assertEqualsInt(11, SourceInteractionBoundaries.coerceToInteractionBoundary(family, 2, familyRange, SourceBoundaryBias.Forward));
        final emojiB:String = TestHelpers.surrogateText([0xD83D, 0xDE00]) + "b";
        final emojiRange:TextRange = new TextRange(0, 3);
        TracedAssertions.assertEqualsInt(2, SourceInteractionBoundaries.coerceToInteractionBoundary(emojiB, 2, emojiRange, SourceBoundaryBias.Nearest));
        TracedAssertions.assertEqualsInt(3, SourceInteractionBoundaries.coerceToInteractionBoundary(emojiB, 9, emojiRange, SourceBoundaryBias.Backward));
        TracedAssertions.assertEqualsInt(0, SourceInteractionBoundaries.coerceToInteractionBoundary(emojiB, -1, emojiRange, SourceBoundaryBias.Forward));
    }
}

class SourceInteractionBoundariesCoverageTestHelpers {
    public static function boundaries(text:String):Array<Int> {
        return SourceInteractionBoundaries.interactionBoundaries(text, new TextRange(0, text.length));
    }

    public static function assertBoundaries(expected:String, text:String):Void {
        TracedAssertions.assertEqualsRendered(expected,
            SourceInteractionBoundariesCoverageTestHelpers.renderInts(SourceInteractionBoundariesCoverageTestHelpers.boundaries(text)));
    }

    public static function renderInts(values:Array<Int>):String {
        var output:String = "[";
        var index:Int = 0;
        while (index < values.length) {
            if (index > 0) {
                output += ", ";
            }
            output += Std.string(values[index]);
            index += 1;
        }
        return output + "]";
    }
}
