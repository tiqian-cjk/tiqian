package org.tiqian.core;

import org.tiqian.core.RichTextRole.Background;
import org.tiqian.core.RichTextRole.Underline;
import org.tiqian.core.RichTextRole.LineThrough;
import org.tiqian.core.RichTextRole.Link;
import org.tiqian.core.RichTextRole.TechnicalInline;
import org.tiqian.core.RichTextRole.InlineCode;
import org.tiqian.core.RichTextLinePattern.Solid;
import org.tiqian.core.RichTextBackgroundDrawStyle.Fill;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import org.tiqian.test.TestHelpers;
import std.StringBuf;

class CoreLayoutQueriesGapsTest {
    @:test
    public static function positionedClusterHeightReturnsDifference():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("positionedClusterHeightReturnsDifference");
        final result:LayoutResult = CoreLayoutQueriesGapsTestHelpers.sampleResult();
        final positions:Array<PositionedCluster> = LayoutQueries.positionedClusters(result);
        TracedAssertions.assertEqualsFloat(20.0, positions[0].height);
    }

    @:test
    public static function getLineForOffsetUsesNearestLineWhenGapBetweenLines():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("getLineForOffsetUsesNearestLineWhenGapBetweenLines");
        final result:LayoutResult = CoreLayoutQueriesGapsTestHelpers.resultWith("abcde", 100.0, null, new Size(10.0, 40.0), [
            CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(0, 1), "a", "cjk", 10.0),
            CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(1, 2), "b", "cjk", 10.0),
            CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(2, 3), "c", "cjk", 10.0),
            CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(4, 5), "e", "cjk", 10.0)
        ], [], [
            CoreLayoutQueriesGapsTestHelpers.line(new TextRange(0, 2), 0, 1, 15.0, 0.0, 20.0, 20.0, null),
            CoreLayoutQueriesGapsTestHelpers.line(new TextRange(4, 5), 2, 3, 35.0, 25.0, 45.0, 10.0, null)
        ], null);
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getLineForOffset(result, 3));
    }

    @:test
    public static function getBoundingBoxesIntDelegatesToTextRange():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("getBoundingBoxesIntDelegatesToTextRange");
        final result:LayoutResult = CoreLayoutQueriesGapsTestHelpers.sampleResult();
        final fromInt:Array<Rect> = LayoutQueries.getBoundingBoxesInt(result, 2, 4);
        final fromRange:Array<Rect> = LayoutQueries.getBoundingBoxes(result, new TextRange(2, 4));
        TracedAssertions.assertEqualsRendered(CoreLayoutQueriesGapsTestHelpers.renderRects(fromRange), CoreLayoutQueriesGapsTestHelpers.renderRects(fromInt));
    }

    @:test
    public static function richTextBackgroundUsesHorizontalPadding():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("richTextBackgroundUsesHorizontalPadding");
        final result:LayoutResult = CoreLayoutQueriesGapsTestHelpers.resultWith("AB", 100.0, CoreLayoutQueriesGapsTestHelpers.style(10.0),
            new Size(20.0, 20.0), [
                CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(0, 1), "A", "latin", 10.0),
                CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(1, 2), "B", "latin", 10.0)
            ], [], [
                CoreLayoutQueriesGapsTestHelpers.line(new TextRange(0, 2), 0, 1, 15.0, 0.0, 20.0, 20.0, null)
            ], CoreLayoutQueriesGapsTestHelpers.emptyDebug());
        final span:RichTextSpan = new RichTextSpan(new TextRange(0, 2), Background.instance,
            RichTextPaint.withBackground(RichTextBackgroundPaint.withHorizontalPadding(5.0)));
        final occupied:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(result, [span]);
        final segments:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(result, occupied);
        TracedAssertions.assertEqualsInt(1, segments.length);
    }

    @:test
    public static function richTextBackgroundTrailingPaddingWhenSpanEndsAtSegmentEnd():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("richTextBackgroundTrailingPaddingWhenSpanEndsAtSegmentEnd");
        final result:LayoutResult = CoreLayoutQueriesGapsTestHelpers.resultWith("AB", 100.0, CoreLayoutQueriesGapsTestHelpers.style(10.0),
            new Size(20.0, 20.0), [
                CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(0, 1), "A", "latin", 10.0),
                CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(1, 2), "B", "latin", 10.0)
            ], [], [
                CoreLayoutQueriesGapsTestHelpers.line(new TextRange(0, 2), 0, 1, 15.0, 0.0, 20.0, 20.0, null)
            ], CoreLayoutQueriesGapsTestHelpers.emptyDebug());
        final span:RichTextSpan = new RichTextSpan(new TextRange(0, 2), Background.instance,
            RichTextPaint.withBackground(RichTextBackgroundPaint.withHorizontalPadding(5.0)));
        final occupied:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(result, [span]);
        final segments:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(result, occupied);
        TracedAssertions.assertEqualsInt(1, segments.length);
        TracedAssertions.assertTrue(segments[0].right > 15.0);
    }

    @:test
    public static function richTextBackgroundUniformParagraphStyleUsesParagraphStyle():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("richTextBackgroundUniformParagraphStyleUsesParagraphStyle");
        final result:LayoutResult = CoreLayoutQueriesGapsTestHelpers.resultWith("AB", 100.0, CoreLayoutQueriesGapsTestHelpers.style(12.0),
            new Size(20.0, 20.0), [
                CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(0, 1), "A", "latin", 10.0),
                CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(1, 2), "B", "latin", 10.0)
            ], [], [
                CoreLayoutQueriesGapsTestHelpers.line(new TextRange(0, 2), 0, 1, 15.0, 0.0, 20.0, 20.0, null)
            ], new LayoutDebugInfo(null, [], [], []));
        final paint:RichTextPaint = RichTextPaint.withBackground(new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0,
            RichTextBackgroundMetricPolicy.UniformParagraphStyle, Fill.instance));
        final span:RichTextSpan = new RichTextSpan(new TextRange(0, 2), Background.instance, paint);
        final occupied:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(result, [span]);
        final segments:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(result, occupied);
        TracedAssertions.assertEqualsInt(1, segments.length);
    }

    @:test
    public static function markedFaceVerticalBoundsUsesFallbackWhenNoMetricMatches():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("markedFaceVerticalBoundsUsesFallbackWhenNoMetricMatches");
        final metric:MetricDecisionInfo = new MetricDecisionInfo(new TextRange(0, 1), "test", "test", "test", 8.0, 2.0, 0.0, "test", 8.0, 2.0, "test", "test",
            "test", "test");
        final result:LayoutResult = CoreLayoutQueriesGapsTestHelpers.resultWith("AB", 100.0, CoreLayoutQueriesGapsTestHelpers.style(10.0),
            new Size(20.0, 20.0), [
                CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(0, 2), "AB", "latin", 20.0)
            ], [], [
                CoreLayoutQueriesGapsTestHelpers.line(new TextRange(0, 2), 0, 0, 15.0, 0.0, 20.0, 20.0, null)
            ], new LayoutDebugInfo(null, [metric], [], []));
        final span:RichTextSpan = new RichTextSpan(new TextRange(0, 2), Background.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0));
        final occupied:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(result, [span]);
        final segments:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(result, occupied);
        TracedAssertions.assertEqualsInt(1, segments.length);
    }

    @:test
    public static function getSelectionOffsetForPositionReturnsNearestWhenBeforeFirstCluster():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("getSelectionOffsetForPositionReturnsNearestWhenBeforeFirstCluster");
        final result:LayoutResult = CoreLayoutQueriesGapsTestHelpers.sampleResult();
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getSelectionOffsetForPosition(result, 3.0, 5.0));
    }

    @:test
    public static function getSelectionOffsetForPositionReturnsNearestWhenAfterLastCluster():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("getSelectionOffsetForPositionReturnsNearestWhenAfterLastCluster");
        final result:LayoutResult = CoreLayoutQueriesGapsTestHelpers.sampleResult();
        TracedAssertions.assertEqualsInt(4, LayoutQueries.getSelectionOffsetForPosition(result, 35.0, 25.0));
    }

    @:test
    public static function getSelectionOffsetForPositionReturnsStartOfLineWhenClustersEmpty():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("getSelectionOffsetForPositionReturnsStartOfLineWhenClustersEmpty");
        final result:LayoutResult = CoreLayoutQueriesGapsTestHelpers.resultWith("", 100.0, null, new Size(0.0, 20.0), [], [], [
            CoreLayoutQueriesGapsTestHelpers.line(new TextRange(0, 0), 0, -1, 15.0, 0.0, 20.0, 0.0, null)
        ], null);
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getSelectionOffsetForPosition(result, 5.0, 10.0));
    }

    @:test
    public static function getSelectionWordBoundaryForEmojiZwjSequence():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("getSelectionWordBoundaryForEmojiZwjSequence");
        final text:String = TestHelpers.surrogateText([0xD83D, 0xDC69, 0x200D, 0xD83D, 0xDC69]);
        final result:LayoutResult = CoreLayoutQueriesGapsTestHelpers.resultWith(text, 100.0, null, new Size(50.0, 20.0), [
            CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(0, 5), text, "emoji", 50.0)
        ], [], [
            CoreLayoutQueriesGapsTestHelpers.line(new TextRange(0, 5), 0, 0, 15.0, 0.0, 20.0, 50.0, null)
        ], null);
        final boundary:TextRange = LayoutQueries.getSelectionWordBoundary(result, 5);
        TracedAssertions.assertEqualsRendered(new TextRange(0, 5).toString(), boundary.toString());
    }

    @:test
    public static function getSelectionWordBoundaryForPunctuationReturnsSingle():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("getSelectionWordBoundaryForPunctuationReturnsSingle");
        final result:LayoutResult = CoreLayoutQueriesGapsTestHelpers.resultWith("A,B", 100.0, null, new Size(30.0, 20.0), [
            CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(0, 1), "A", "latin", 10.0),
            CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(1, 2), ",", "latin", 10.0),
            CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(2, 3), "B", "latin", 10.0)
        ], [], [
            CoreLayoutQueriesGapsTestHelpers.line(new TextRange(0, 3), 0, 2, 15.0, 0.0, 20.0, 30.0, null)
        ], null);
        final boundary:TextRange = LayoutQueries.getSelectionWordBoundary(result, 1);
        TracedAssertions.assertEqualsRendered(new TextRange(1, 2).toString(), boundary.toString());
    }

    @:test
    public static function positionedClustersProducesSourceStopsForLatinRun():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("positionedClustersProducesSourceStopsForLatinRun");
        final text:String = "Hi";
        final glyphRange:TextRange = new TextRange(0, 2);
        final glyphs:Array<Glyph> = [
            new Glyph(1, glyphRange, 10.0, 0.0, 0.0, null, null, null, null),
            new Glyph(2, glyphRange, 10.0, 0.0, 0.0, null, null, null, null)
        ];
        final result:LayoutResult = CoreLayoutQueriesGapsTestHelpers.resultWith(text, 100.0, CoreLayoutQueriesGapsTestHelpers.style(10.0),
            new Size(20.0, 20.0), [CoreLayoutQueriesGapsTestHelpers.cluster(glyphRange, text, "latin", 20.0)],
            [new GlyphRun(glyphRange, "latin", glyphs, 20.0, [])], [
                CoreLayoutQueriesGapsTestHelpers.line(glyphRange, 0, 0, 15.0, 0.0, 20.0, 20.0, null)
            ], null);
        final positioned:Array<PositionedCluster> = LayoutQueries.positionedClusters(result);
        TracedAssertions.assertEqualsInt(3, positioned[0].sourceStops == null ? 0 : positioned[0].sourceStops.length);
        TracedAssertions.assertTrue(positioned[0].sourceStops != null);
    }

    @:test
    public static function offsetForXUsesSourceStopsWhenAvailable():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("offsetForXUsesSourceStopsWhenAvailable");
        final text:String = "Hi";
        final glyphRange:TextRange = new TextRange(0, 2);
        final glyphs:Array<Glyph> = [
            new Glyph(1, glyphRange, 10.0, 5.0, 0.0, null, null, null, null),
            new Glyph(2, glyphRange, 10.0, 15.0, 0.0, null, null, null, null)
        ];
        final result:LayoutResult = CoreLayoutQueriesGapsTestHelpers.resultWith(text, 100.0, CoreLayoutQueriesGapsTestHelpers.style(10.0),
            new Size(20.0, 20.0), [CoreLayoutQueriesGapsTestHelpers.cluster(glyphRange, text, "latin", 20.0)],
            [new GlyphRun(glyphRange, "latin", glyphs, 20.0, [])], [
                CoreLayoutQueriesGapsTestHelpers.line(glyphRange, 0, 0, 15.0, 0.0, 20.0, 20.0, null)
            ], CoreLayoutQueriesGapsTestHelpers.emptyDebug());
        final positioned:Array<PositionedCluster> = LayoutQueries.positionedClusters(result);
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getOffsetForPosition(result, positioned[0].left, 10.0));
        TracedAssertions.assertEqualsInt(1, LayoutQueries.getOffsetForPosition(result, 15.0, 10.0));
    }

    @:test
    public static function getBoundingBoxesEmptyRangeReturnsEmptyList():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("getBoundingBoxesEmptyRangeReturnsEmptyList");
        final result:LayoutResult = CoreLayoutQueriesGapsTestHelpers.sampleResult();
        final boxes:Array<Rect> = LayoutQueries.getBoundingBoxes(result, new TextRange(2, 2));
        var renderedBoxes:String = "[";
        var boxIndex:Int = 0;
        while (boxIndex < boxes.length) {
            if (boxIndex > 0)
                renderedBoxes += ", ";
            renderedBoxes += boxes[boxIndex].toString();
            boxIndex += 1;
        }
        renderedBoxes += "]";
        TracedAssertions.assertEqualsRendered("[]", renderedBoxes);
    }

    @:test
    public static function getLineForOffsetReturnsNearestLine():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("getLineForOffsetReturnsNearestLine");
        final result:LayoutResult = CoreLayoutQueriesGapsTestHelpers.resultWith("abc", 100.0, null, new Size(30.0, 40.0), [
            CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(0, 1), "a", "cjk", 10.0),
            CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(1, 2), "b", "cjk", 10.0),
            CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(2, 3), "c", "cjk", 10.0)
        ], [], [
            CoreLayoutQueriesGapsTestHelpers.line(new TextRange(0, 1), 0, 0, 15.0, 0.0, 20.0, 10.0, null),
            CoreLayoutQueriesGapsTestHelpers.line(new TextRange(1, 2), 1, 1, 35.0, 25.0, 45.0, 10.0, null)
        ], null);
        TracedAssertions.assertEqualsInt(1, LayoutQueries.getLineForOffset(result, 10));
    }

    @:test
    public static function getCursorRectReturnsCaretInCluster():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("getCursorRectReturnsCaretInCluster");
        final rect:Rect = LayoutQueries.getCursorRect(CoreLayoutQueriesGapsTestHelpers.sampleResult(), 2);
        TracedAssertions.assertEqualsRendered(new Rect(24.0, 0.0, 25.0, 20.0).toString(), rect.toString());
    }

    @:test
    public static function getOffsetForPositionUsesMinByWhenOutsideClusters():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("getOffsetForPositionUsesMinByWhenOutsideClusters");
        TracedAssertions.assertEqualsInt(1, LayoutQueries.getOffsetForPosition(CoreLayoutQueriesGapsTestHelpers.sampleResult(), 12.0, 5.0));
    }

    @:test
    public static function getSelectionWordBoundaryReturnsEmptyForEmptyText():Void {
        new TestTraceRecorder("CoreLayoutQueriesGapsTest").section("getSelectionWordBoundaryReturnsEmptyForEmptyText");
        final result:LayoutResult = CoreLayoutQueriesGapsTestHelpers.resultWith("", 100.0, null, new Size(0.0, 20.0), [], [], [], null);
        final boundary:TextRange = LayoutQueries.getSelectionWordBoundary(result, 0);
        TracedAssertions.assertEqualsRendered(new TextRange(0, 0).toString(), boundary.toString());
    }
}

class CoreLayoutQueriesGapsTestHelpers {
    public static function content(text:String):TiqianTextContent {
        return new TiqianTextContent(text, [], [], [], []);
    }

    public static function constraints(maxWidth:Float):LayoutConstraints {
        return new LayoutConstraints(maxWidth, Math.POSITIVE_INFINITY, 2147483647);
    }

    public static function style(fontSize:Float):TextStyle {
        return new TextStyle([], fontSize, "zh-Hans", 400, false, 0.0, InlineAttachment.None);
    }

    public static function input(text:String, maxWidth:Float, textStyle:Null<TextStyle>):LayoutInput {
        final style:TextStyle = textStyle == null ? new TextStyle([], 16.0, "zh-Hans", 400, false, 0.0, InlineAttachment.None) : textStyle;
        return new LayoutInput(CoreLayoutQueriesGapsTestHelpers.content(text), style,
            new ParagraphStyle(LastLineAlignment.Start, WritingMode.HorizontalTb, null, null, Ic.Zero, new MeasureAdaptiveFirstLineIndent(14.0, 1.0, 2.0),
                new LineLengthGrid(true, null), RubyLineHeightMode.PerLine, ParagraphStyle.DEFAULT_INLINE_OBJECT_MINIMUM_CLEARANCE_EM,
                ParagraphStyle.DEFAULT_EMPHASIS_DOT_GAP_EM),
            CoreLayoutQueriesGapsTestHelpers.constraints(maxWidth), BuiltInLayoutProfiles.ClreqHorizontal, [], [], [], []);
    }

    public static function cluster(range:TextRange, text:String, fontKey:String, advance:Float):Cluster {
        return new Cluster(range, text, fontKey, advance, (text), 0.0, 0.0, 0.0);
    }

    public static function substitutedCluster(range:TextRange, text:String, displayText:String, fontKey:String, advance:Float):Cluster {
        return new Cluster(range, text, fontKey, advance, displayText, 0.0, 0.0, 0.0);
    }

    public static function line(range:TextRange, clusterStart:Int, clusterEnd:Int, baseline:Float, top:Float, bottom:Float, width:Float,
            indent:Null<Float>):LineBox {
        return new LineBox(range, new IntRange(clusterStart, clusterEnd), baseline, top, bottom, width, width, width, 0.0, indent, LineEndReason.ParagraphEnd,
            0.0, [], new LineDebugInfo(null, []));
    }

    public static function emptyDebug():LayoutDebugInfo {
        return new LayoutDebugInfo(null, [], [], [], [], []);
    }

    public static function renderRects(values:Array<Rect>):String {
        final output:StringBuf = new StringBuf();
        output.add("[");
        var index:Int = 0;
        while (index < values.length) {
            if (index > 0) {
                output.add(", ");
            }
            output.add(values[index].toString());
            index += 1;
        }
        output.add("]");
        return output.toString();
    }

    public static function resultWith(text:String, maxWidth:Float, textStyle:Null<TextStyle>, size:Size, clusters:Array<Cluster>, glyphRuns:Array<GlyphRun>,
            lines:Array<LineBox>, debug:Null<LayoutDebugInfo>):LayoutResult {
        return new LayoutResult(CoreLayoutQueriesGapsTestHelpers.input(text, maxWidth, textStyle), size, clusters, glyphRuns, lines,
            debug == null ? CoreLayoutQueriesGapsTestHelpers.emptyDebug() : debug);
    }

    public static function sampleResult():LayoutResult {
        final text:String = "甲——乙";
        final dashRange:TextRange = new TextRange(1, 3);
        return CoreLayoutQueriesGapsTestHelpers.resultWith(text, 40.0, CoreLayoutQueriesGapsTestHelpers.style(10.0), new Size(34.0, 40.0), [
            CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(0, 1), "甲", "cjk", 10.0),
            CoreLayoutQueriesGapsTestHelpers.substitutedCluster(dashRange, "——", "⸺", "cjk", 20.0),
            CoreLayoutQueriesGapsTestHelpers.cluster(new TextRange(3, 4), "乙", "cjk", 10.0)
        ], [], [
            CoreLayoutQueriesGapsTestHelpers.line(new TextRange(0, 3), 0, 1, 15.0, 0.0, 20.0, 30.0, 4.0),
            CoreLayoutQueriesGapsTestHelpers.line(new TextRange(3, 4), 2, 2, 35.0, 20.0, 40.0, 10.0, null)
        ], null);
    }
}
