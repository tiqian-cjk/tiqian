package org.tiqian.core;

import org.tiqian.test.TestHelpers;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class CoreBoundaryTest {
    @:test
    public static function coerceToInteractionBoundaryBackwardReturnsBoundaryWhenAtEnd():Void {
        new TestTraceRecorder("CoreBoundaryTest").section("coerceToInteractionBoundaryBackwardReturnsBoundaryWhenAtEnd");
        TracedAssertions.assertEqualsInt(3,
            SourceInteractionBoundaries.coerceToInteractionBoundary("abc", 3, new TextRange(0, 3), SourceBoundaryBias.Backward));
    }

    @:test
    public static function coerceToInteractionBoundaryForwardReturnsNextBoundary():Void {
        new TestTraceRecorder("CoreBoundaryTest").section("coerceToInteractionBoundaryForwardReturnsNextBoundary");
        TracedAssertions.assertEqualsInt(3, SourceInteractionBoundaries.coerceToInteractionBoundary("abc", 3, new TextRange(0, 3), SourceBoundaryBias.Forward));
    }

    @:test
    public static function coerceToInteractionBoundaryNearestChoosesCloser():Void {
        new TestTraceRecorder("CoreBoundaryTest").section("coerceToInteractionBoundaryNearestChoosesCloser");
        TracedAssertions.assertEqualsInt(3,
            SourceInteractionBoundaries.coerceToInteractionBoundary("abcdef", 3, new TextRange(0, 6), SourceBoundaryBias.Nearest));
    }

    @:test
    public static function coerceToInteractionBoundaryWithSurrogatePair():Void {
        new TestTraceRecorder("CoreBoundaryTest").section("coerceToInteractionBoundaryWithSurrogatePair");
        final emoji:String = TestHelpers.surrogateText([0xD83D, 0xDE00]);
        final text:String = "a" + emoji + "b";
        TracedAssertions.assertEqualsInt(3,
            SourceInteractionBoundaries.coerceToInteractionBoundary(text, 3, new TextRange(0, text.length), SourceBoundaryBias.Nearest));
    }

    @:test
    public static function coerceToInteractionBoundaryWithInvalidSurrogatePair():Void {
        new TestTraceRecorder("CoreBoundaryTest").section("coerceToInteractionBoundaryWithInvalidSurrogatePair");
        final text:String = TestHelpers.surrogateText([0xD800]) + "A";
        TracedAssertions.assertEqualsInt(1,
            SourceInteractionBoundaries.coerceToInteractionBoundary(text, 1, new TextRange(0, text.length), SourceBoundaryBias.Nearest));
    }

    @:test
    public static function sourceGraphemeBoundariesWithHangulLeadingJamo():Void {
        new TestTraceRecorder("CoreBoundaryTest").section("sourceGraphemeBoundariesWithHangulLeadingJamo");
        final text:String = "\u1100\u1161\u11A8";
        final boundaries:Array<Int> = SourceInteractionBoundaries.sourceGraphemeBoundaries(text, new TextRange(0, 3));
        TracedAssertions.assertTrue(boundaries.indexOf(3) >= 0);
    }

    @:test
    public static function sourceGraphemeBoundariesWithHangulSyllable():Void {
        new TestTraceRecorder("CoreBoundaryTest").section("sourceGraphemeBoundariesWithHangulSyllable");
        final text:String = "\uAC00";
        final boundaries:Array<Int> = SourceInteractionBoundaries.sourceGraphemeBoundaries(text, new TextRange(0, 1));
        TracedAssertions.assertEqualsInt(2, boundaries.length);
        TracedAssertions.assertEqualsInt(0, boundaries[0]);
        TracedAssertions.assertEqualsInt(1, boundaries[boundaries.length - 1]);
    }

    @:test
    public static function sourceGraphemeBoundariesWithRegionalIndicator():Void {
        new TestTraceRecorder("CoreBoundaryTest").section("sourceGraphemeBoundariesWithRegionalIndicator");
        final text:String = TestHelpers.surrogateText([0xD83C, 0xDDE8, 0xD83C, 0xDDE6]);
        final boundaries:Array<Int> = SourceInteractionBoundaries.sourceGraphemeBoundaries(text, new TextRange(0, text.length));
        TracedAssertions.assertTrue(boundaries.indexOf(text.length) >= 0);
    }

    @:test
    public static function sourceGraphemeBoundariesWithEmojiZwjSequence():Void {
        new TestTraceRecorder("CoreBoundaryTest").section("sourceGraphemeBoundariesWithEmojiZwjSequence");
        final text:String = TestHelpers.surrogateText([0xD83D, 0xDC69, 0x200D, 0xD83D, 0xDC69]);
        final boundaries:Array<Int> = SourceInteractionBoundaries.sourceGraphemeBoundaries(text, new TextRange(0, text.length));
        TracedAssertions.assertEqualsInt(2, boundaries.length);
        TracedAssertions.assertEqualsInt(0, boundaries[0]);
    }

    @:test
    public static function sourceGraphemeBoundariesWithEmojiModifier():Void {
        new TestTraceRecorder("CoreBoundaryTest").section("sourceGraphemeBoundariesWithEmojiModifier");
        final text:String = TestHelpers.surrogateText([0xD83D, 0xDC69, 0xD83C, 0xDFFB]);
        final boundaries:Array<Int> = SourceInteractionBoundaries.sourceGraphemeBoundaries(text, new TextRange(0, text.length));
        TracedAssertions.assertTrue(boundaries.indexOf(text.length) >= 0);
    }

    @:test
    public static function sourceGraphemeBoundariesReturnsSingleBoundaryForEmptyText():Void {
        new TestTraceRecorder("CoreBoundaryTest").section("sourceGraphemeBoundariesReturnsSingleBoundaryForEmptyText");
        final boundaries:Array<Int> = SourceInteractionBoundaries.sourceGraphemeBoundaries("", new TextRange(0, 0));
        TracedAssertions.assertEqualsInt(1, boundaries.length);
        TracedAssertions.assertEqualsInt(0, boundaries[0]);
    }

    @:test
    public static function interactionBoundariesWithTextRange():Void {
        new TestTraceRecorder("CoreBoundaryTest").section("interactionBoundariesWithTextRange");
        final boundaries:Array<Int> = SourceInteractionBoundaries.interactionBoundaries("abc", new TextRange(1, 2));
        TracedAssertions.assertEqualsRendered("[1, 2]", CoreBoundaryTestHelpers.renderInts(boundaries));
    }

    @:test
    public static function getSelectionOffsetForPositionReturnsStartOfFirstCluster():Void {
        new TestTraceRecorder("CoreBoundaryTest").section("getSelectionOffsetForPositionReturnsStartOfFirstCluster");
        final value:LayoutResult = CoreBoundaryTestHelpers.interactionResult("abc");
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getSelectionOffsetForPosition(value, 0.0, 10.0));
        TracedAssertions.assertEqualsInt(1, LayoutQueries.getSelectionOffsetForPosition(value, 10.0, 10.0));
        TracedAssertions.assertEqualsInt(2, LayoutQueries.getSelectionOffsetForPosition(value, 20.0, 10.0));
    }

    @:test
    public static function getSelectionOffsetForPositionReturnsStartOfLineWhenEmptyClusters():Void {
        new TestTraceRecorder("CoreBoundaryTest").section("getSelectionOffsetForPositionReturnsStartOfLineWhenEmptyClusters");
        final input:LayoutInput = new LayoutInput(new TiqianTextContent("", [], [], [], []),
            new TextStyle([], 16.0, "zh-Hans", 400, false, 0.0, InlineAttachment.None),
            new ParagraphStyle(LastLineAlignment.Start, WritingMode.HorizontalTb, null, null, Ic.Zero, new MeasureAdaptiveFirstLineIndent(14.0, 1.0, 2.0),
                new LineLengthGrid(true, null), RubyLineHeightMode.PerLine, ParagraphStyle.DEFAULT_INLINE_OBJECT_MINIMUM_CLEARANCE_EM,
                ParagraphStyle.DEFAULT_EMPHASIS_DOT_GAP_EM),
            new LayoutConstraints(100.0, Math.POSITIVE_INFINITY, 2147483647), BuiltInLayoutProfiles.ClreqHorizontal, [], [], [], []);
        final line:LineBox = new LineBox(new TextRange(0, 0), new IntRange(0, -1), 15.0, 0.0, 20.0, 0.0, 0.0, 0.0, 0.0, 0.0, LineEndReason.ParagraphEnd, 0.0,
            [], new LineDebugInfo(null, []));
        final value:LayoutResult = new LayoutResult(input, new Size(0.0, 20.0), [], [], [line], new LayoutDebugInfo(null, [], [], [], [], []));
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getSelectionOffsetForPosition(value, 5.0, 10.0));
    }
}

class CoreBoundaryTestHelpers {
    public static function interactionResult(text:String):LayoutResult {
        final clusters:Array<Cluster> = [
            new Cluster(new TextRange(0, 1), "a", "latin", 10.0, ("a"), 0.0, 0.0, 0.0),
            new Cluster(new TextRange(1, 2), "b", "latin", 10.0, ("b"), 0.0, 0.0, 0.0),
            new Cluster(new TextRange(2, 3), "c", "latin", 10.0, ("c"), 0.0, 0.0, 0.0)
        ];
        final line:LineBox = new LineBox(new TextRange(0, 3), new IntRange(0, 2), 15.0, 0.0, 20.0, 30.0, 30.0, 30.0, 0.0, 0.0, LineEndReason.ParagraphEnd,
            0.0, [], new LineDebugInfo(null, []));
        final input:LayoutInput = new LayoutInput(new TiqianTextContent(text, [], [], [], []),
            new TextStyle([], 16.0, "zh-Hans", 400, false, 0.0, InlineAttachment.None),
            new ParagraphStyle(LastLineAlignment.Start, WritingMode.HorizontalTb, null, null, Ic.Zero, new MeasureAdaptiveFirstLineIndent(14.0, 1.0, 2.0),
                new LineLengthGrid(true, null), RubyLineHeightMode.PerLine, ParagraphStyle.DEFAULT_INLINE_OBJECT_MINIMUM_CLEARANCE_EM,
                ParagraphStyle.DEFAULT_EMPHASIS_DOT_GAP_EM),
            new LayoutConstraints(100.0, Math.POSITIVE_INFINITY, 2147483647), BuiltInLayoutProfiles.ClreqHorizontal, [], [], [], []);
        return new LayoutResult(input, new Size(30.0, 20.0), clusters, [], [line], new LayoutDebugInfo(null, [], [], [], [], []));
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
