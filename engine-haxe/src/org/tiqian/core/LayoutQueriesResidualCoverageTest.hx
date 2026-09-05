package org.tiqian.core;

import org.tiqian.core.RichTextRole.Background;
import org.tiqian.core.RichTextRole.Underline;
import org.tiqian.core.RichTextRole.LineThrough;
import org.tiqian.core.RichTextRole.Link;
import org.tiqian.core.RichTextRole.TechnicalInline;
import org.tiqian.core.RichTextRole.InlineCode;
import org.tiqian.core.RichTextLinePattern.Solid;
import org.tiqian.core.RichTextBackgroundDrawStyle.Fill;
import org.tiqian.test.TestHelpers;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import org.tiqian.test.trace.TestTraceRender;
import std.StringBuf;

class LayoutQueriesResidualCoverageTest {
    @:test
    public static function cornerRadiiPredicatesCoverEveryComparison():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("cornerRadiiPredicatesCoverEveryComparison");
        TracedAssertions.assertTrue(new RichTextCornerRadii(0.0, 0.0, 0.0, 0.0).isSquare);
        TracedAssertions.assertTrue(!new RichTextCornerRadii(1.0, 0.0, 0.0, 0.0).isSquare);
        TracedAssertions.assertTrue(!new RichTextCornerRadii(0.0, 1.0, 0.0, 0.0).isSquare);
        TracedAssertions.assertTrue(!new RichTextCornerRadii(0.0, 0.0, 1.0, 0.0).isSquare);
        TracedAssertions.assertTrue(!new RichTextCornerRadii(0.0, 0.0, 0.0, 1.0).isSquare);
        TracedAssertions.assertTrue(new RichTextCornerRadii(2.0, 2.0, 2.0, 2.0).isUniform);
        TracedAssertions.assertTrue(!new RichTextCornerRadii(1.0, 2.0, 2.0, 2.0).isUniform);
        TracedAssertions.assertTrue(!new RichTextCornerRadii(2.0, 1.0, 2.0, 2.0).isUniform);
        TracedAssertions.assertTrue(!new RichTextCornerRadii(2.0, 2.0, 1.0, 2.0).isUniform);
        TracedAssertions.assertTrue(!new RichTextCornerRadii(2.0, 2.0, 2.0, 1.0).isUniform);
    }

    @:test
    public static function resolvedCornerRadiiRejectsInvalidInsetsAndResolvesContinuations():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("resolvedCornerRadiiRejectsInvalidInsetsAndResolvesContinuations");
        final continuing:RichTextLineSegment = LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(1, 2), Background.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 6.0, 2.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
            0, new TextRange(0, 3), 0.0, 0.0, 30.0, 10.0, 15.0);
        TracedAssertions.assertFailsWith(null, function():Void {
            LayoutQueries.resolvedBackgroundCornerRadii(continuing, -1.0);
        });
        TracedAssertions.assertFailsWith(null, function():Void {
            LayoutQueries.resolvedBackgroundCornerRadii(continuing, LayoutQueriesResidualCoverageTestHelpers.nan());
        });
        final resolved:RichTextCornerRadii = LayoutQueries.resolvedBackgroundCornerRadii(continuing, 0.0);
        TracedAssertions.assertEqualsFloat(2.0, resolved.topLeft);
        TracedAssertions.assertEqualsFloat(2.0, resolved.topRight);
        TracedAssertions.assertEqualsFloat(2.0, resolved.bottomRight);
        TracedAssertions.assertEqualsFloat(2.0, resolved.bottomLeft);
    }

    @:test
    public static function copyProjectionAppendsFullySelectedAnnotationsOnly():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("copyProjectionAppendsFullySelectedAnnotationsOnly");
        final debug:LayoutDebugInfo = new LayoutDebugInfo(null, [], [], [], [
            new RubyDecisionInfo(new TextRange(0, 2), "zhù", 0, 10.0, 12.0, 6.0, 0.0, 0.0, 0.0, 12.0, [], 400, "zh-Hans", [])
        ],
            [new BopomofoDecisionInfo(new TextRange(2, 4), "ㄋㄧˇ", 0, [], [], 400, "zh-Hans")]);
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abcd", [], [], [], [], [], debug,
            LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsString("", LayoutQueries.getTextForCopy(content, new TextRange(1, 1)));
        TracedAssertions.assertEqualsString("ab（zhù）c", LayoutQueries.getTextForCopy(content, new TextRange(0, 3)));
        TracedAssertions.assertEqualsString("ab（zhù）cd（ㄋㄧˇ）", LayoutQueries.getTextForCopy(content, new TextRange(0, 4)));
        TracedAssertions.assertEqualsString("d", LayoutQueries.getTextForCopy(content, new TextRange(3, 4)));
    }

    @:test
    public static function positionedClustersByLineRejectsForeignLines():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("positionedClustersByLineRejectsForeignLines");
        final owned:LineBox = LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 0.0, 20.0, 15.0, 0.0, 10.0);
        final foreign:LineBox = LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 99.0, 119.0, 114.0, 0.0, 10.0);
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 2), "ab", 20.0)
        ], [owned], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsInt(1, LayoutQueries.positionedClustersForLine(content, owned).length);
        final error:TiqianIllegalArgumentException = TracedAssertions.assertFailsWith(null, function():Void {
            LayoutQueries.positionedClustersForLine(content, foreign);
        });
        TracedAssertions.assertTrue(error.message.indexOf("must belong") >= 0, error.message);
    }

    @:test
    public static function glyphInkBoundsSkipsUnmatchedGlyphsAndReturnsNullWithoutInk():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("glyphInkBoundsSkipsUnmatchedGlyphsAndReturnsNullWithoutInk");
        final clusters:Array<Cluster> = [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0)
        ];
        final runs:Array<GlyphRun> = [
            new GlyphRun(new TextRange(0, 2), "test", [
                new Glyph(1, new TextRange(0, 1), 10.0, 0.0, 0.0, null, new Rect(0.0, 2.0, 8.0, 12.0), null, null),
                new Glyph(2, new TextRange(0, 1), 10.0, 0.0, 0.0, null, null, null, null),
                new Glyph(3, new TextRange(5, 6), 10.0, 0.0, 0.0, null, new Rect(0.0, 0.0, 1.0, 1.0), null, null)
            ], 20.0, [])
        ];
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", clusters, [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], runs, [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsRendered(new Rect(0.0, 17.0, 8.0, 27.0).toString(), LayoutQueries.glyphInkBounds(content).toString());
        final noInk:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", clusters, [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final noInkBounds = LayoutQueries.glyphInkBounds(noInk);
        TracedAssertions.assertNullRendered(noInkBounds == null, noInkBounds == null ? "-" : noInkBounds.toString());
    }

    @:test
    public static function emptyLineResultsShortCircuitEveryQuery():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("emptyLineResultsShortCircuitEveryQuery");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [], [], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsInt(-1, LayoutQueries.getLineForOffset(content, 0));
        TracedAssertions.assertEqualsRendered(new Rect(0.0, 0.0, 0.0, 0.0).toString(), LayoutQueries.getBoundingBox(content, 0).toString());
        TracedAssertions.assertEqualsRendered(new Rect(0.0, 0.0, 0.0, 0.0).toString(), LayoutQueries.getCursorRect(content, 0).toString());
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getOffsetForPosition(content, 5.0, 5.0));
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getSelectionOffsetForPosition(content, 5.0, 5.0));
        TracedAssertions.assertEqualsRendered("[]",
            LayoutQueriesResidualCoverageTestHelpers.renderRects(LayoutQueries.getBoundingBoxes(content, new TextRange(0, 2))));
        final noWordBoundary = LayoutQueries.getSelectionWordBoundaryForPosition(content, 5.0, 5.0);
        TracedAssertions.assertNullRendered(noWordBoundary == null, noWordBoundary == null ? "-" : noWordBoundary.toString());
        TracedAssertions.assertEqualsRendered("[]", LayoutQueriesResidualCoverageTestHelpers.renderSegments(LayoutQueries.positionedRichTextSegments(content, [
            new RichTextSpan(new TextRange(0, 1), Background.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0))
        ])));
        TracedAssertions.assertEqualsRendered("[]",
            LayoutQueriesResidualCoverageTestHelpers.renderSegments(LayoutQueries.trimmedRichTextDecorationSegments(content, [])));
        TracedAssertions.assertEqualsRendered("[]",
            LayoutQueriesResidualCoverageTestHelpers.renderSegments(LayoutQueries.richTextBackgroundSegments(content, [])));
    }

    @:test
    public static function boundingBoxFallsBackToTheCursorRectAtClusterGaps():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("boundingBoxFallsBackToTheCursorRectAtClusterGaps");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abc", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 3), "c", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 1, 0.0, 20.0, 15.0, 0.0, 10.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsRendered(new Rect(10.0, 0.0, 11.0, 20.0).toString(), LayoutQueries.getBoundingBox(content, 1).toString());
        TracedAssertions.assertEqualsRendered(new Rect(20.0, 0.0, 21.0, 20.0).toString(), LayoutQueries.getBoundingBox(content, 3).toString());
        TracedAssertions.assertEqualsRendered("[]",
            LayoutQueriesResidualCoverageTestHelpers.renderRects(LayoutQueries.getBoundingBoxes(content, new TextRange(3, 5))));
    }

    @:test
    public static function richTextSegmentsSplitOnLineBreaksAndClusterGaps():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("richTextSegmentsSplitOnLineBreaksAndClusterGaps");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abcd", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 3), "c", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(3, 4), "d", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0),
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(3, 4), 2, 2, 20.0, 40.0, 35.0, 0.0, 10.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final span:RichTextSpan = new RichTextSpan(new TextRange(0, 4), Underline.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0));
        final split:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(content, [span]);
        TracedAssertions.assertEqualsInt(3, split.length);
        TracedAssertions.assertEqualsRendered(new TextRange(0, 1).toString(), split[0].range.toString());
        TracedAssertions.assertEqualsRendered(new TextRange(2, 3).toString(), split[1].range.toString());
        TracedAssertions.assertEqualsRendered(new TextRange(3, 4).toString(), split[2].range.toString());
        TracedAssertions.assertEqualsInt(0, split[0].lineIndex);
        TracedAssertions.assertEqualsInt(0, split[1].lineIndex);
        TracedAssertions.assertEqualsInt(1, split[2].lineIndex);
        TracedAssertions.assertTrue(LayoutQueries.positionedRichTextSegments(content, [
            new RichTextSpan(new TextRange(5, 8), Underline.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0))
        ]).length == 0);
    }

    @:test
    public static function richTextSegmentsSkipZeroLengthClustersBetweenSlices():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("richTextSegmentsSkipZeroLengthClustersBetweenSlices");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 1), "", 0.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 2, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final segments:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(content, [
            new RichTextSpan(new TextRange(0, 2), Underline.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0))
        ]);
        TracedAssertions.assertEqualsInt(1, segments.length);
        TracedAssertions.assertEqualsRendered(new TextRange(0, 2).toString(), segments[0].range.toString());
        TracedAssertions.assertEqualsFloat(0.0, segments[0].left);
        TracedAssertions.assertEqualsFloat(20.0, segments[0].right);
    }

    @:test
    public static function trimmedDecorationSegmentsKeepOnlyDecorationRoles():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("trimmedDecorationSegmentsKeepOnlyDecorationRoles");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [], [], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final decoration:RichTextLineSegment = LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 2), Underline.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
            0, new TextRange(0, 2), 0.0, 0.0, 20.0, 20.0, 15.0);
        TracedAssertions.assertEqualsRendered(LayoutQueriesResidualCoverageTestHelpers.renderSegments([decoration]),
            LayoutQueriesResidualCoverageTestHelpers.renderSegments(LayoutQueries.trimmedRichTextDecorationSegments(content, [decoration])));
        TracedAssertions.assertTrue(LayoutQueries.trimmedRichTextDecorationSegments(content,
            [LayoutQueriesResidualCoverageTestHelpers.plainSegment(new TextRange(0, 2))])
            .length == 0);
    }

    @:test
    public static function backgroundSegmentsPassThroughUnmatchableSegments():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("backgroundSegmentsPassThroughUnmatchableSegments");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab",
            [LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0)], [
                LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 0.0, 20.0, 15.0, 0.0, 10.0)
            ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final far:RichTextLineSegment = LayoutQueriesResidualCoverageTestHelpers.plainSegment(new TextRange(10, 12));
        TracedAssertions.assertEqualsRendered(LayoutQueriesResidualCoverageTestHelpers.renderSegments([far]),
            LayoutQueriesResidualCoverageTestHelpers.renderSegments(LayoutQueries.richTextBackgroundSegments(content, [far])));
        final orphan:RichTextLineSegment = LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 1), Background.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
            5, new TextRange(0, 1), 0.0, 0.0, 20.0, 20.0, 15.0);
        TracedAssertions.assertEqualsRendered(LayoutQueriesResidualCoverageTestHelpers.renderSegments([orphan]),
            LayoutQueriesResidualCoverageTestHelpers.renderSegments(LayoutQueries.richTextBackgroundSegments(content, [orphan])));
        final underline:RichTextLineSegment = LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 1), Underline.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
            0, new TextRange(0, 1), 0.0, 0.0, 20.0, 20.0, 15.0);
        TracedAssertions.assertTrue(LayoutQueries.richTextBackgroundSegments(content, [underline]).length == 0);
    }

    @:test
    public static function backgroundSegmentsTrimGlueApplyPaddingAndUseGlyphAdvances():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("backgroundSegmentsTrimGlueApplyPaddingAndUseGlyphAdvances");
        final clusters:Array<Cluster> = [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "，", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "字", 10.0)
        ];
        final glue:ClusterGeometryDecisionInfo = new ClusterGeometryDecisionInfo(new TextRange(0, 1), "，", "，", 10.0, 5.0, 4.0, 1.0, 4.0, 1.0, 0.0, 10.0,
            "test", "test", 0.0, 0.0, null);
        final runs:Array<GlyphRun> = [
            new GlyphRun(new TextRange(1, 2), "test", [new Glyph(9, new TextRange(1, 2), 9.0, 1.0, 0.0, null, null, null, null)], 10.0, [])
        ];
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("，字", clusters, [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], runs, [], [],
            new LayoutDebugInfo(null, [], [glue], [], [], []), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final full:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 2), Background.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
                0, new TextRange(0, 2), 0.0, 0.0, 20.0, 20.0, 15.0)
        ]);
        TracedAssertions.assertEqualsFloat(3.0, full[0].left);
        TracedAssertions.assertEqualsFloat(20.0, full[0].right);
        TracedAssertions.assertEqualsFloat(15.0 - 10.0 * 0.88, full[0].top);
        TracedAssertions.assertEqualsFloat(15.0 + 10.0 * 0.12, full[0].bottom);
        final headPaint:RichTextPaint = new RichTextPaint(null, Solid.instance,
            new RichTextBackgroundPaint(5.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0);
        final head:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 2), Background.instance, headPaint, 0, new TextRange(0, 3), 0.0, 0.0, 20.0,
                20.0, 15.0)
        ]);
        TracedAssertions.assertEqualsFloat(3.0, head[0].left);
        TracedAssertions.assertEqualsFloat(20.0, head[0].right);
        final continuation:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(1, 2), Background.instance, headPaint, 0, new TextRange(0, 3), 10.0, 0.0, 20.0,
                20.0, 15.0)
        ]);
        TracedAssertions.assertEqualsFloat(10.0, continuation[0].left);
        TracedAssertions.assertEqualsFloat(20.0, continuation[0].right);
    }

    @:test
    public static function markedFacesUseMetricDecisionsWhenTheyCoverTheCluster():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("markedFacesUseMetricDecisionsWhenTheyCoverTheCluster");
        final decision:MetricDecisionInfo = LayoutQueriesResidualCoverageTestHelpers.metric(new TextRange(0, 2), "IdeographicEmBox", 7.0, 3.0, "ideographic");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [],
            new LayoutDebugInfo(null, [decision], [], [], [], []), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final box:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 2), Background.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
                0, new TextRange(0, 2), 0.0, 0.0, 20.0, 20.0, 15.0)
        ]);
        TracedAssertions.assertEqualsFloat(8.0, box[0].top);
        TracedAssertions.assertEqualsFloat(18.0, box[0].bottom);
    }

    @:test
    public static function uniformTextStyleFallsBackWhenEveryMetricFieldDiffers():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("uniformTextStyleFallsBackWhenEveryMetricFieldDiffers");
        final base:TextStyle = LayoutQueriesResidualCoverageTestHelpers.style(10.0);
        final variants:Array<TextStyle> = [
            new TextStyle(["other"], 10.0, "zh-Hans", 400, false, 0.0, InlineAttachment.None),
            new TextStyle([], 11.0, "zh-Hans", 400, false, 0.0, InlineAttachment.None),
            new TextStyle([], 10.0, "ja-JP", 400, false, 0.0, InlineAttachment.None),
            new TextStyle([], 10.0, "zh-Hans", 700, false, 0.0, InlineAttachment.None),
            new TextStyle([], 10.0, "zh-Hans", 400, true, 0.0, InlineAttachment.None),
            new TextStyle([], 10.0, "zh-Hans", 400, false, 2.0, InlineAttachment.None)
        ];
        final clusters:Array<Cluster> = [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0)
        ];
        final decision:MetricDecisionInfo = LayoutQueriesResidualCoverageTestHelpers.metric(new TextRange(1, 2), "LatinBox", 9.0, 1.0, "latin");
        final paint:RichTextPaint = new RichTextPaint(null, Solid.instance,
            new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.UniformTextStyle, Fill.instance), 0.0);
        var index:Int = 0;
        while (index < variants.length) {
            final variant:TextStyle = variants[index];
            final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", clusters, [
                LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
            ], [],
                [new TextSpan(new TextRange(0, 1), variant)], [], new LayoutDebugInfo(null, [decision], [], [], [], []), base);
            final box:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [
                LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 2), Background.instance, paint, 0, new TextRange(0, 2), 0.0, 0.0, 20.0,
                    20.0, 15.0)
            ]);
            final message:String = "variant=" + variant.toString();
            TracedAssertions.assertEqualsFloat(15.0 - variant.fontSize * 0.88, box[0].top, message);
            TracedAssertions.assertEqualsFloat(15.0 + variant.fontSize * 0.12, box[0].bottom, message);
            index += 1;
        }
    }

    @:test
    public static function uniformTextStylePrefersIdeographicMetricsThenAnyMatchingFace():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("uniformTextStylePrefersIdeographicMetricsThenAnyMatchingFace");
        final paint:RichTextPaint = new RichTextPaint(null, Solid.instance,
            new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.UniformTextStyle, Fill.instance), 0.0);
        final clusters:Array<Cluster> = [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0)
        ];
        final lineValue:LineBox = LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0);
        final latin:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", clusters, [lineValue], [], [], [], new LayoutDebugInfo(null, [
            LayoutQueriesResidualCoverageTestHelpers.metric(new TextRange(0, 2), "LatinBox", 9.0, 1.0, "latin")
        ], [], [], [], []), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final latinBox:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(latin, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 2), Background.instance, paint, 0, new TextRange(0, 2), 0.0, 0.0, 20.0, 20.0,
                15.0)
        ]);
        TracedAssertions.assertEqualsFloat(6.0, latinBox[0].top);
        TracedAssertions.assertEqualsFloat(16.0, latinBox[0].bottom);
        final bothMetrics:Array<MetricDecisionInfo> = [
            LayoutQueriesResidualCoverageTestHelpers.metric(new TextRange(0, 1), "LatinBox", 9.0, 1.0, "latin"),
            LayoutQueriesResidualCoverageTestHelpers.metric(new TextRange(0, 2), "IdeographicEmBox", 8.0, 2.0, "ideographic")
        ];
        final both:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", clusters, [lineValue], [], [], [],
            new LayoutDebugInfo(null, bothMetrics, [], [], [], []), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final ideographicBox:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(both, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 2), Background.instance, paint, 0, new TextRange(0, 2), 0.0, 0.0, 20.0, 20.0,
                15.0)
        ]);
        TracedAssertions.assertEqualsFloat(7.0, ideographicBox[0].top);
        TracedAssertions.assertEqualsFloat(17.0, ideographicBox[0].bottom);
    }

    @:test
    public static function adjacentSameStyleSegmentsShareClearance():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("adjacentSameStyleSegmentsShareClearance");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final paint:RichTextPaint = new RichTextPaint(null, Solid.instance,
            new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 4.0);
        final first:RichTextLineSegment = LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 1), Background.instance, paint, 0,
            new TextRange(0, 1), 0.0, 0.0, 10.0, 20.0, 15.0);
        final second:RichTextLineSegment = LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(1, 2), Background.instance, paint, 0,
            new TextRange(1, 2), 10.0, 0.0, 20.0, 20.0, 15.0);
        final cleared:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [first, second]);
        TracedAssertions.assertEqualsInt(2, cleared.length);
        TracedAssertions.assertEqualsFloat(8.0, cleared[0].right);
        TracedAssertions.assertEqualsFloat(12.0, cleared[1].left);
        final other:RichTextLineSegment = LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(1, 2), Background.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 3.0, 3.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
            0, new TextRange(1, 2), 10.0, 0.0, 20.0, 20.0, 15.0);
        final untouched:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [first, other]);
        TracedAssertions.assertEqualsInt(2, untouched.length);
        TracedAssertions.assertEqualsFloat(10.0, untouched[0].right);
        TracedAssertions.assertEqualsFloat(10.0, untouched[1].left);
    }

    @:test
    public static function decorationLineYRequiresValidStrokeAndDecorationRoles():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("decorationLineYRequiresValidStrokeAndDecorationRoles");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 0.0, 20.0, 15.0, 0.0, 10.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final underline:RichTextLineSegment = LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 1), Underline.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
            0, new TextRange(0, 1), 0.0, 0.0, 20.0, 20.0, 15.0);
        TracedAssertions.assertFailsWith(null, function():Void {
            LayoutQueries.richTextDecorationLineY(content, underline, -1.0);
        });
        TracedAssertions.assertFailsWith(null, function():Void {
            LayoutQueries.richTextDecorationLineY(content, underline, LayoutQueriesResidualCoverageTestHelpers.nan());
        });
        final error:TiqianIllegalArgumentException = TracedAssertions.assertFailsWith(null, function():Void {
            LayoutQueries.richTextDecorationLineY(content, LayoutQueriesResidualCoverageTestHelpers.plainSegment(new TextRange(0, 1)), 1.0);
        });
        TracedAssertions.assertTrue(error.message.indexOf("underline and line-through") >= 0, error.message);
        final withSpanStyle:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab",
            [LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0)], [
                LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 0.0, 20.0, 15.0, 0.0, 10.0)
            ], [], [
                new TextSpan(new TextRange(0, 1), LayoutQueriesResidualCoverageTestHelpers.style(10.0))
            ], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final y:Float = LayoutQueries.richTextDecorationLineY(withSpanStyle, underline, 1.0);
        TracedAssertions.assertTrue(y >= underline.top && y <= underline.bottom, Std.string(y));
        final lineThrough:RichTextLineSegment = LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 1), LineThrough.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
            0, new TextRange(0, 1), 0.0, 0.0, 20.0, 20.0, 15.0);
        final strike:Float = LayoutQueries.richTextDecorationLineY(withSpanStyle, lineThrough, 1.0);
        TracedAssertions.assertEqualsFloatTolerance(11.2, strike, 0.001);
    }

    @:test
    public static function cursorRectCoversEmptyLinesEmptyClustersAndMultiUnitClusters():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("cursorRectCoversEmptyLinesEmptyClustersAndMultiUnitClusters");
        final emptyClusterLine:LineBox = LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 0), 0, -1, 0.0, 20.0, 15.0, 6.0, 10.0);
        final withEmptyLine:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("a", [], [emptyClusterLine], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsRendered(new Rect(6.0, 0.0, 7.0, 20.0).toString(), LayoutQueries.getCursorRect(withEmptyLine, 0).toString());
        final linear:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 2), "ab", 20.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsFloat(10.0, LayoutQueries.getCursorRect(linear, 1).left);
        final stops:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 2), "ab", 20.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [
            new GlyphRun(new TextRange(0, 2), "test", [
                new Glyph(1, new TextRange(0, 2), 10.0, 0.0, 0.0, null, null, null, null),
                new Glyph(2, new TextRange(0, 2), 10.0, 12.0, 0.0, null, null, null, null)
            ], 20.0, [])
        ], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsFloat(12.0, LayoutQueries.getCursorRect(stops, 1).left);
    }

    @:test
    public static function offsetForPositionCoversVerticalDistancesAndNaNPoints():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("offsetForPositionCoversVerticalDistancesAndNaNPoints");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0),
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(2, 2), 2, -1, 20.0, 40.0, 35.0, 0.0, 0.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getOffsetForPosition(content, 2.0, -50.0));
        TracedAssertions.assertEqualsInt(2, LayoutQueries.getOffsetForPosition(content, 5.0, 90.0));
        TracedAssertions.assertEqualsInt(2, LayoutQueries.getOffsetForPosition(content, 5.0, 30.0));
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getSelectionOffsetForPosition(content, 2.0, -50.0));
        TracedAssertions.assertEqualsInt(2, LayoutQueries.getSelectionOffsetForPosition(content, 5.0, 90.0));
        final withStops:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 2), "ab", 20.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [
            new GlyphRun(new TextRange(0, 2), "test", [
                new Glyph(1, new TextRange(0, 2), 10.0, 0.0, 0.0, null, null, null, null),
                new Glyph(2, new TextRange(0, 2), 10.0, 10.0, 0.0, null, null, null, null)
            ], 20.0, [])
        ], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getOffsetForPosition(withStops, LayoutQueriesResidualCoverageTestHelpers.nan(), 5.0));
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getSelectionOffsetForPosition(withStops, LayoutQueriesResidualCoverageTestHelpers.nan(), 5.0));
    }

    @:test
    public static function selectionSnapPrefersTheCloserInlineObjectBoundary():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("selectionSnapPrefersTheCloserInlineObjectBoundary");
        final object:InlineObjectSpan = new InlineObjectSpan(new TextRange(1, 3), 8.0, 4.0, 4.0, InlineObjectBoundaryAdjustment.fixed(),
            InlineObjectBoundaryAdjustment.fixed());
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abb", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 3), "abb", 30.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 0, 0.0, 20.0, 15.0, 0.0, 30.0)
        ], [], [], [object],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsInt(1, LayoutQueries.getSelectionOffsetForPosition(content, 15.0, 5.0));
        TracedAssertions.assertEqualsInt(3, LayoutQueries.getSelectionOffsetForPosition(content, 21.0, 5.0));
    }

    @:test
    public static function selectionWordBoundaryForPositionRejectsDegenerateContent():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("selectionWordBoundaryForPositionRejectsDegenerateContent");
        final emptyText:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("", [], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 0), 0, -1, 0.0, 20.0, 15.0, 0.0, 0.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final emptyTextBoundary = LayoutQueries.getSelectionWordBoundaryForPosition(emptyText, 0.0, 0.0);
        TracedAssertions.assertNullRendered(emptyTextBoundary == null, emptyTextBoundary == null ? "-" : emptyTextBoundary.toString());
        final emptyLine:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("a",
            [LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0)], [
                LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 1), 0, 0, 0.0, 20.0, 15.0, 0.0, 10.0),
                LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(1, 1), 1, -1, 20.0, 40.0, 35.0, 0.0, 0.0)
            ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final emptyLineBoundary = LayoutQueries.getSelectionWordBoundaryForPosition(emptyLine, 5.0, 30.0);
        TracedAssertions.assertNullRendered(emptyLineBoundary == null, emptyLineBoundary == null ? "-" : emptyLineBoundary.toString());
        final leadingEmpty:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("a", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 0), "", 0.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 1), 0, 1, 0.0, 20.0, 15.0, 0.0, 10.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final leadingEmptyBoundary = LayoutQueries.getSelectionWordBoundaryForPosition(leadingEmpty, 0.0, 5.0);
        TracedAssertions.assertNullRendered(leadingEmptyBoundary == null, leadingEmptyBoundary == null ? "-" : leadingEmptyBoundary.toString());
        TracedAssertions.assertEqualsRendered(new TextRange(0, 1).toString(),
            LayoutQueries.getSelectionWordBoundaryForPosition(leadingEmpty, 5.0, 5.0).toString());
    }

    @:test
    public static function zeroWidthClustersReturnTheirStartInHitTests():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("zeroWidthClustersReturnTheirStartInHitTests");
        final emptyRange:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("",
            [LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 0), "", 5.0)], [
                LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 0), 0, 0, 0.0, 20.0, 15.0, 0.0, 5.0)
            ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getOffsetForPosition(emptyRange, 2.0, 5.0));
        final zeroAdvance:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 0.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 1), 0, 0, 0.0, 20.0, 15.0, 0.0, 10.0),
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(1, 2), 1, 1, 20.0, 40.0, 35.0, 0.0, 0.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsRendered(new TextRange(0, 2).toString(),
            LayoutQueries.getSelectionWordBoundaryForPosition(zeroAdvance, 0.0, 30.0).toString());
    }

    @:test
    public static function coerceSelectionOffsetHonoursInlineObjectBoundaries():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("coerceSelectionOffsetHonoursInlineObjectBoundaries");
        final object:InlineObjectSpan = new InlineObjectSpan(new TextRange(1, 3), 8.0, 4.0, 4.0, InlineObjectBoundaryAdjustment.fixed(),
            InlineObjectBoundaryAdjustment.fixed());
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abb", [], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 0, 0.0, 20.0, 15.0, 0.0, 0.0)
        ], [], [], [object],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsInt(1, LayoutQueries.coerceSelectionOffset(content, 2, SourceBoundaryBias.Backward));
        TracedAssertions.assertEqualsInt(3, LayoutQueries.coerceSelectionOffset(content, 2, SourceBoundaryBias.Forward));
        TracedAssertions.assertEqualsInt(3, LayoutQueries.coerceSelectionOffset(content, 2, SourceBoundaryBias.Nearest));
        TracedAssertions.assertEqualsInt(1, LayoutQueries.coerceSelectionOffset(content, 1, SourceBoundaryBias.Nearest));
        TracedAssertions.assertEqualsInt(3, LayoutQueries.coerceSelectionOffset(content, 3, SourceBoundaryBias.Nearest));
    }

    @:test
    public static function selectionWordBoundaryExpandsWordsAndHonoursInlineObjects():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("selectionWordBoundaryExpandsWordsAndHonoursInlineObjects");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("hello", [], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 5), 0, 0, 0.0, 20.0, 15.0, 0.0, 0.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsRendered(new TextRange(0, 5).toString(), LayoutQueries.getSelectionWordBoundary(content, 2).toString());
        TracedAssertions.assertEqualsRendered(new TextRange(0, 5).toString(), LayoutQueries.getSelectionWordBoundary(content, 5).toString());
        final emojiText:String = TestHelpers.surrogateText([0xD83D, 0xDE00]);
        final emoji:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result(emojiText, [], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 0.0, 20.0, 15.0, 0.0, 0.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsRendered(new TextRange(0, 2).toString(), LayoutQueries.getSelectionWordBoundary(emoji, 1).toString());
        final object:InlineObjectSpan = new InlineObjectSpan(new TextRange(1, 3), 8.0, 4.0, 4.0, InlineObjectBoundaryAdjustment.fixed(),
            InlineObjectBoundaryAdjustment.fixed());
        final withObject:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abb", [], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 0, 0.0, 20.0, 15.0, 0.0, 0.0)
        ], [], [], [object],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsRendered(new TextRange(1, 3).toString(), LayoutQueries.getSelectionWordBoundary(withObject, 2).toString());
        final mandatory:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("a\nb", [], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 0, 0.0, 20.0, 15.0, 0.0, 0.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsRendered(new TextRange(1, 2).toString(), LayoutQueries.getSelectionWordBoundary(mandatory, 1).toString());
        final connectors:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("a_b", [], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 0, 0.0, 20.0, 15.0, 0.0, 0.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsRendered(new TextRange(0, 3).toString(), LayoutQueries.getSelectionWordBoundary(connectors, 1).toString());
        final empty:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("", [], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 0), 0, -1, 0.0, 20.0, 15.0, 0.0, 0.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsRendered(new TextRange(0, 0).toString(), LayoutQueries.getSelectionWordBoundary(empty, 0).toString());
    }

    @:test
    public static function selectionWordKindCoversEveryHanBlock():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("selectionWordKindCoversEveryHanBlock");
        final supplementary:String = TestHelpers.surrogateText([0xD840, 0xDC00]);
        final values:Array<String> = ["㐀", "一", "豈", supplementary];
        var index:Int = 0;
        while (index < values.length) {
            final text:String = values[index];
            final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result(text, [], [
                LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, text.length), 0, 0, 0.0, 20.0, 15.0, 0.0, 0.0)
            ], [], [], [],
                LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
            TracedAssertions.assertEqualsRendered(new TextRange(0, text.length).toString(), LayoutQueries.getSelectionWordBoundary(content, 0).toString(),
                "text=" + text);
            index += 1;
        }
    }

    @:test
    public static function nearestLineFallsBackToTheOnlyLineAtItsEndOffset():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("nearestLineFallsBackToTheOnlyLineAtItsEndOffset");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abc", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 2), "ab", 20.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getLineForOffset(content, 2));
    }

    @:test
    public static function rubyGeometryRedistributesSelectionBoxesAndDropsSourceStops():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("rubyGeometryRedistributesSelectionBoxesAndDropsSourceStops");
        final clusters:Array<Cluster> = [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 2), "ab", 20.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 3), "c", 10.0)
        ];
        final runs:Array<GlyphRun> = [
            new GlyphRun(new TextRange(0, 2), "test", [
                new Glyph(1, new TextRange(0, 2), 10.0, 0.0, 0.0, null, null, null, null),
                new Glyph(2, new TextRange(0, 2), 10.0, 10.0, 0.0, null, null, null, null)
            ], 20.0, [])
        ];
        final matching:RubyDecisionInfo = new RubyDecisionInfo(new TextRange(0, 3), "zhù", 0, 15.0, 4.0, 6.0, 0.0, 0.0, 0.0, 30.0, [], 400, "zh-Hans", []);
        final stray:RubyDecisionInfo = new RubyDecisionInfo(new TextRange(5, 6), "x", 0, 0.0, 4.0, 6.0, 0.0, 0.0, 0.0, 6.0, [], 400, "zh-Hans", []);
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abc", clusters, [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 1, 0.0, 20.0, 15.0, 0.0, 30.0)
        ], runs, [], [],
            new LayoutDebugInfo(null, [], [], [], [matching, stray], []), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final positioned:Array<PositionedCluster> = LayoutQueries.positionedClusters(content);
        TracedAssertions.assertEqualsInt(2, positioned.length);
        final firstStops = positioned[0].sourceStops;
        TracedAssertions.assertNullRendered(firstStops == null, firstStops == null ? "-" : Std.string(firstStops));
        final secondStops = positioned[1].sourceStops;
        TracedAssertions.assertNullRendered(secondStops == null, secondStops == null ? "-" : Std.string(secondStops));
        TracedAssertions.assertEqualsFloat(0.0, positioned[0].left);
        TracedAssertions.assertEqualsFloat(17.5, positioned[0].right);
        TracedAssertions.assertEqualsFloat(17.5, positioned[1].left);
        TracedAssertions.assertEqualsFloat(30.0, positioned[1].right);
    }

    @:test
    public static function boundingBoxesSliceZeroWidthAndEmptyClusters():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("boundingBoxesSliceZeroWidthAndEmptyClusters");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 0.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 10.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final boxes:Array<Rect> = LayoutQueries.getBoundingBoxes(content, new TextRange(0, 2));
        TracedAssertions.assertEqualsInt(2, boxes.length);
        TracedAssertions.assertEqualsFloat(10.0, boxes[1].left);
        TracedAssertions.assertEqualsFloat(10.0, boxes[1].right);
        final tail:Array<Rect> = LayoutQueries.getBoundingBoxes(content, new TextRange(1, 2));
        TracedAssertions.assertEqualsInt(1, tail.length);
        TracedAssertions.assertEqualsFloat(10.0, tail[0].left);
    }

    @:test
    public static function positionedClustersAndSegmentsReturnEmptyWithoutLines():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("positionedClustersAndSegmentsReturnEmptyWithoutLines");
        final noLines:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab",
            [LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0)], [], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertTrue(LayoutQueries.positionedClusters(noLines).length == 0);
        TracedAssertions.assertTrue(LayoutQueries.positionedRichTextSegments(noLines, [
            new RichTextSpan(new TextRange(0, 2), Background.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0))
        ]).length == 0);
        final noSpans:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab",
            [LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0)], [
                LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 1), 0, 0, 0.0, 20.0, 15.0, 0.0, 10.0)
            ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertTrue(LayoutQueries.positionedRichTextSegments(noSpans, []).length == 0);
    }

    @:test
    public static function sameSpanSlicesAcrossASourceBoundaryMergeIntoOneSegment():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("sameSpanSlicesAcrossASourceBoundaryMergeIntoOneSegment");
        final inputContent:TiqianTextContent = new TiqianTextContent("ab", [], [1], [], []);
        final input:LayoutInput = new LayoutInput(inputContent, LayoutQueriesResidualCoverageTestHelpers.style(10.0),
            new ParagraphStyle(LastLineAlignment.Start, WritingMode.HorizontalTb, null, null, Ic.Zero, new MeasureAdaptiveFirstLineIndent(14.0, 1.0, 2.0),
                new LineLengthGrid(true, null), RubyLineHeightMode.PerLine, ParagraphStyle.DEFAULT_INLINE_OBJECT_MINIMUM_CLEARANCE_EM,
                ParagraphStyle.DEFAULT_EMPHASIS_DOT_GAP_EM),
            new LayoutConstraints(100.0, Math.POSITIVE_INFINITY, 2147483647), BuiltInLayoutProfiles.ClreqHorizontal, [], [], [], []);
        final content:LayoutResult = new LayoutResult(input, new Size(20.0, 20.0), [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0)
        ], [], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], LayoutQueriesResidualCoverageTestHelpers.emptyDebug());
        final segments:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(content, [
            new RichTextSpan(new TextRange(0, 2), Background.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0))
        ]);
        TracedAssertions.assertEqualsInt(1, segments.length);
        TracedAssertions.assertEqualsRendered(new TextRange(0, 2).toString(), segments[0].range.toString());
        TracedAssertions.assertEqualsFloat(0.0, segments[0].left);
        TracedAssertions.assertEqualsFloat(20.0, segments[0].right);
    }

    @:test
    public static function glyphInkBoundsSkipsUnusableGlyphsAndReportsNull():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("glyphInkBoundsSkipsUnusableGlyphsAndReportsNull");
        final clusters:Array<Cluster> = [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0)
        ];
        final lines:Array<LineBox> = [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
        ];
        final noBounds:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", clusters, lines, [
            new GlyphRun(new TextRange(0, 2), "test", [new Glyph(1, new TextRange(0, 1), 10.0, 0.0, 0.0, null, null, null, null)], 20.0, [])
        ], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final absentBounds = LayoutQueries.glyphInkBounds(noBounds);
        TracedAssertions.assertNullRendered(absentBounds == null, absentBounds == null ? "-" : absentBounds.toString());
        final nanPlaced:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", clusters, lines, [
            new GlyphRun(new TextRange(1, 2), "test", [
                new Glyph(9, new TextRange(1, 2), 9.0, LayoutQueriesResidualCoverageTestHelpers.nan(), 0.0, null, new Rect(1.0, 2.0, 8.0, 4.0), null, null)
            ], 10.0, [])
        ], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final nanPlacedBounds = LayoutQueries.glyphInkBounds(nanPlaced);
        TracedAssertions.assertNullRendered(nanPlacedBounds == null, nanPlacedBounds == null ? "-" : nanPlacedBounds.toString());
        final usable:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", clusters, lines, [
            new GlyphRun(new TextRange(0, 2), "test", [
                new Glyph(1, new TextRange(0, 1), 10.0, 2.0, 1.0, null, new Rect(1.0, 2.0, 8.0, 4.0), null, null),
                new Glyph(2, new TextRange(1, 2), 10.0, 1.0, 0.0, null, new Rect(0.0, 1.0, 9.0, 3.0), null, null)
            ], 20.0, [])
        ], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final ink:Rect = LayoutQueries.glyphInkBounds(usable);
        TracedAssertions.assertEqualsFloat(3.0, ink.left);
        TracedAssertions.assertEqualsFloat(20.0, ink.right);
        TracedAssertions.assertEqualsFloat(16.0, ink.top);
        TracedAssertions.assertEqualsFloat(20.0, ink.bottom);
    }

    @:test
    public static function backgroundTrailingEdgeUsesGlyphAdvancesWhenAvailable():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("backgroundTrailingEdgeUsesGlyphAdvancesWhenAvailable");
        final clusters:Array<Cluster> = [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0)
        ];
        final lines:Array<LineBox> = [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
        ];
        final shortGlyph:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", clusters, lines, [
            new GlyphRun(new TextRange(1, 2), "test", [new Glyph(2, new TextRange(1, 2), 5.0, 0.0, 0.0, null, null, null, null)], 10.0, [])
        ], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final shortSegments:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(shortGlyph, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 2), Background.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
                0, new TextRange(0, 2), 0.0, 0.0, 20.0, 20.0, 15.0)
        ]);
        TracedAssertions.assertEqualsFloat(15.0, shortSegments[0].right);
        final emptyGlyphRun:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", clusters, lines,
            [new GlyphRun(new TextRange(1, 2), "test", [], 10.0, [])], [], [], LayoutQueriesResidualCoverageTestHelpers.emptyDebug(),
            LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final emptySegments:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(emptyGlyphRun, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 2), Background.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
                0, new TextRange(0, 2), 0.0, 0.0, 20.0, 20.0, 15.0)
        ]);
        TracedAssertions.assertEqualsFloat(20.0, emptySegments[0].right);
    }

    @:test
    public static function clearanceNeedsSameRoleAndUsesTheSmallerSide():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("clearanceNeedsSameRoleAndUsesTheSmallerSide");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final background:RichTextLineSegment = LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 1), Background.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 4.0),
            0, new TextRange(0, 1), 0.0, 0.0, 10.0, 20.0, 15.0);
        final inlineCode:RichTextLineSegment = LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(1, 2), InlineCode.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 4.0),
            0, new TextRange(1, 2), 10.0, 0.0, 20.0, 20.0, 15.0);
        final byRole:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [background, inlineCode]);
        TracedAssertions.assertEqualsFloat(10.0, byRole[0].right);
        TracedAssertions.assertEqualsFloat(10.0, byRole[1].left);
        final weak:RichTextLineSegment = LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 1), Background.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 2.0),
            0, new TextRange(0, 1), 0.0, 0.0, 10.0, 20.0, 15.0);
        final strong:RichTextLineSegment = LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(1, 2), Background.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 6.0),
            0, new TextRange(1, 2), 10.0, 0.0, 20.0, 20.0, 15.0);
        final cleared:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [weak, strong]);
        TracedAssertions.assertEqualsFloat(9.0, cleared[0].right);
        TracedAssertions.assertEqualsFloat(11.0, cleared[1].left);
    }

    @:test
    public static function metricDecisionsMustFullyContainTheCluster():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("metricDecisionsMustFullyContainTheCluster");
        final first:Array<Float> = LayoutQueriesResidualCoverageTestHelpers.metricBounds(new TextRange(1, 2));
        TracedAssertions.assertEqualsFloat(15.0 - 10.0 * 0.88, first[0]);
        TracedAssertions.assertEqualsFloat(15.0 + 10.0 * 0.12, first[1]);
        final second:Array<Float> = LayoutQueriesResidualCoverageTestHelpers.metricBounds(new TextRange(0, 1));
        TracedAssertions.assertEqualsFloat(15.0 - 10.0 * 0.88, second[0]);
    }

    @:test
    public static function decorationStyleResolvesInsideSpansAndAtTheirEdges():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("decorationStyleResolvesInsideSpansAndAtTheirEdges");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abc", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 3), "c", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 2, 0.0, 20.0, 15.0, 0.0, 30.0)
        ], [], [
            new TextSpan(new TextRange(0, 1), LayoutQueriesResidualCoverageTestHelpers.style(10.0)),
            new TextSpan(new TextRange(2, 3), LayoutQueriesResidualCoverageTestHelpers.style(20.0))
        ], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final between:Float = LayoutQueries.richTextDecorationLineY(content,
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(1, 2), Underline.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
                0, new TextRange(1, 2), 10.0, 0.0, 20.0, 20.0, 15.0),
            1.0);
        final inside:Float = LayoutQueries.richTextDecorationLineY(content,
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(2, 3), Underline.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
                0, new TextRange(2, 3), 20.0, 0.0, 30.0, 20.0, 15.0),
            1.0);
        TracedAssertions.assertEqualsFloat(15.0 + 10.0 * 0.18, between);
        TracedAssertions.assertEqualsFloat(15.0 + 20.0 * 0.18, inside);
    }

    @:test
    public static function glueTrimSkipsInteriorSegmentEdges():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("glueTrimSkipsInteriorSegmentEdges");
        final glue:ClusterGeometryDecisionInfo = new ClusterGeometryDecisionInfo(new TextRange(0, 2), "ab", "ab", 20.0, 10.0, 4.0, 1.0, 4.0, 1.0, 0.0, 20.0,
            "test", "test", 0.0, 0.0, null);
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 2), "ab", 20.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [],
            new LayoutDebugInfo(null, [], [glue], [], [], []), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final interiorStart:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(1, 2), Background.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
                0, new TextRange(1, 2), 10.0, 0.0, 20.0, 20.0, 15.0)
        ]);
        TracedAssertions.assertEqualsFloat(10.0, interiorStart[0].left);
        final interiorEnd:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 1), Background.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
                0, new TextRange(0, 1), 0.0, 0.0, 10.0, 20.0, 15.0)
        ]);
        TracedAssertions.assertEqualsFloat(10.0, interiorEnd[0].right);
    }

    @:test
    public static function backgroundSegmentOutsideEverySpanUsesTheParagraphStyle():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("backgroundSegmentOutsideEverySpanUsesTheParagraphStyle");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abc", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 3), "c", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 2, 0.0, 20.0, 15.0, 0.0, 30.0)
        ], [], [
            new TextSpan(new TextRange(1, 2), LayoutQueriesResidualCoverageTestHelpers.style(40.0))
        ], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final before:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 1), Background.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
                0, new TextRange(0, 1), 0.0, 0.0, 10.0, 20.0, 15.0)
        ]);
        TracedAssertions.assertEqualsFloat(15.0 - 10.0 * 0.88, before[0].top);
        final atEnd:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(2, 3), Background.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
                0, new TextRange(2, 3), 20.0, 0.0, 30.0, 20.0, 15.0)
        ]);
        TracedAssertions.assertEqualsFloat(15.0 - 10.0 * 0.88, atEnd[0].top);
    }

    @:test
    public static function cursorRectFindsLaterClustersAndRejectsGappedRanges():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("cursorRectFindsLaterClustersAndRejectsGappedRanges");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abc", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 3), "c", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 2, 0.0, 20.0, 15.0, 0.0, 30.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsFloat(20.0, LayoutQueries.getCursorRect(content, 2).left);
        final gapped:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abcde", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(4, 5), "e", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 5), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertFailsWithNoSuchElement(null, function():Void {
            LayoutQueries.getCursorRect(gapped, 2);
        });
    }

    @:test
    public static function emptyMidClusterHoldsTheCaretAndSlicesKeepDegenerateRects():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("emptyMidClusterHoldsTheCaretAndSlicesKeepDegenerateRects");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abc", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 2), "", 0.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 3), "c", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 2, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsFloat(10.0, LayoutQueries.getCursorRect(content, 2).left);
        final withEmpty:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 1), "", 0.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 2, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final boxes:Array<Rect> = LayoutQueries.getBoundingBoxes(withEmpty, new TextRange(0, 2));
        TracedAssertions.assertEqualsInt(2, boxes.length);
        TracedAssertions.assertEqualsFloat(0.0, boxes[0].left);
        TracedAssertions.assertEqualsFloat(10.0, boxes[0].right);
        TracedAssertions.assertEqualsFloat(10.0, boxes[1].left);
        TracedAssertions.assertEqualsFloat(20.0, boxes[1].right);
        final zeroAdvance:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abc", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 0.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 3), "c", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 2, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final degenerate:Array<Rect> = LayoutQueries.getBoundingBoxes(zeroAdvance, new TextRange(0, 3));
        TracedAssertions.assertEqualsInt(3, degenerate.length);
        TracedAssertions.assertEqualsFloat(10.0, degenerate[1].left);
        TracedAssertions.assertEqualsFloat(10.0, degenerate[1].right);
    }

    @:test
    public static function selectionWordBoundarySkipsInlineObjectsItDoesNotContain():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("selectionWordBoundarySkipsInlineObjectsItDoesNotContain");
        final objects:Array<InlineObjectSpan> = [
            new InlineObjectSpan(new TextRange(1, 3), 8.0, 4.0, 4.0, InlineObjectBoundaryAdjustment.fixed(), InlineObjectBoundaryAdjustment.fixed()),
            new InlineObjectSpan(new TextRange(5, 7), 8.0, 4.0, 4.0, InlineObjectBoundaryAdjustment.fixed(), InlineObjectBoundaryAdjustment.fixed())
        ];
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abcdefg", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 7), "abcdefg", 70.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 7), 0, 0, 0.0, 20.0, 15.0, 0.0, 70.0)
        ], [], [], objects,
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsRendered(new TextRange(0, 7).toString(), LayoutQueries.getSelectionWordBoundary(content, 4).toString());
        TracedAssertions.assertEqualsRendered(new TextRange(1, 3).toString(), LayoutQueries.getSelectionWordBoundary(content, 2).toString());
    }

    @:test
    public static function selectionWordBoundaryForPositionCoversDistancesAndFallbacks():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("selectionWordBoundaryForPositionCoversDistancesAndFallbacks");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("甲乙", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "甲", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "乙", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsRendered(new TextRange(0, 1).toString(), LayoutQueries.getSelectionWordBoundaryForPosition(content, 5.0, 10.0)
            .toString());
        TracedAssertions.assertEqualsRendered(new TextRange(0, 1).toString(),
            LayoutQueries.getSelectionWordBoundaryForPosition(content, 5.0, -10.0).toString());
        TracedAssertions.assertEqualsRendered(new TextRange(0, 1).toString(), LayoutQueries.getSelectionWordBoundaryForPosition(content, 5.0, 60.0)
            .toString());
        TracedAssertions.assertEqualsRendered(new TextRange(0, 1).toString(),
            LayoutQueries.getSelectionWordBoundaryForPosition(content, -50.0, 10.0).toString());
        TracedAssertions.assertEqualsRendered(new TextRange(1, 2).toString(),
            LayoutQueries.getSelectionWordBoundaryForPosition(content, 500.0, 10.0).toString());
    }

    @:test
    public static function lineForOffsetInsideARangeTakesTheZeroDistanceArm():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("lineForOffsetInsideARangeTakesTheZeroDistanceArm");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abcde", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(4, 5), "e", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 0.0, 20.0, 15.0, 0.0, 10.0),
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(4, 5), 1, 1, 20.0, 40.0, 35.0, 0.0, 10.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getLineForOffset(content, 1));
    }

    @:test
    public static function compatibilityIdeographsFormIndividualWordUnits():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("compatibilityIdeographsFormIndividualWordUnits");
        final text:String = TestHelpers.surrogateText([0xD840, 0xDC00]) + "\uF900";
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result(text, [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 2), TestHelpers.surrogateText([0xD840, 0xDC00]), 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 3), "\uF900", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsRendered(new TextRange(0, 2).toString(), LayoutQueries.getSelectionWordBoundary(content, 0).toString());
        TracedAssertions.assertEqualsRendered(new TextRange(2, 3).toString(), LayoutQueries.getSelectionWordBoundary(content, 2).toString());
    }

    @:test
    public static function rubySpreadShiftsSelectionBoxesAndZeroWidthRubiesAreIgnored():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("rubySpreadShiftsSelectionBoxesAndZeroWidthRubiesAreIgnored");
        final clusters:Array<Cluster> = [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 2), "ab", 20.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 3), "c", 10.0)
        ];
        final geometries:Array<ClusterGeometryDecisionInfo> = [
            LayoutQueriesResidualCoverageTestHelpers.geometry(new TextRange(0, 2), "ab", 0.0, 0.0, 0.0, 0.0),
            LayoutQueriesResidualCoverageTestHelpers.geometry(new TextRange(2, 3), "c", 0.0, 0.0, 0.0, 0.0)
        ];
        final firstGeometry:ClusterGeometryDecisionInfo = new ClusterGeometryDecisionInfo(new TextRange(0, 2), "ab", "ab", 20.0, 10.0, 0.0, 0.0, 0.0, 0.0,
            0.0, 20.0, "test", "test", 5.0, 0.0, null);
        final secondGeometry:ClusterGeometryDecisionInfo = new ClusterGeometryDecisionInfo(new TextRange(2, 3), "c", "c", 10.0, 10.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            10.0, "test", "test", 2.0, 0.0, null);
        geometries[0] = firstGeometry;
        geometries[1] = secondGeometry;
        final rubies:Array<RubyDecisionInfo> = [
            new RubyDecisionInfo(new TextRange(0, 3), "zhù", 0, 15.0, 4.0, 6.0, 0.0, 0.0, 0.0, 30.0, [], 400, "zh-Hans", []),
            new RubyDecisionInfo(new TextRange(2, 3), "x", 0, 25.0, 4.0, 6.0, 0.0, 0.0, 0.0, 0.0, [], 400, "zh-Hans", []),
            new RubyDecisionInfo(new TextRange(5, 6), "y", 0, 25.0, 4.0, 6.0, 0.0, 0.0, 0.0, 6.0, [], 400, "zh-Hans", [])
        ];
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abc", clusters, [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 1, 0.0, 20.0, 15.0, 0.0, 30.0)
        ], [], [], [],
            new LayoutDebugInfo(null, [], geometries, [], rubies, []), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final positioned:Array<PositionedCluster> = LayoutQueries.positionedClusters(content);
        TracedAssertions.assertEqualsFloat(0.0, positioned[0].left);
        TracedAssertions.assertEqualsFloat(15.75, positioned[0].right);
        TracedAssertions.assertEqualsFloat(15.75, positioned[1].left);
        TracedAssertions.assertEqualsFloat(30.0, positioned[1].right);
        final glyphResult:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abc", clusters, [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 1, 0.0, 20.0, 15.0, 0.0, 30.0)
        ], [
            new GlyphRun(new TextRange(0, 3), "test", [
                new Glyph(1, new TextRange(0, 2), 16.0, 0.0, 0.0, null, null, null, null),
                new Glyph(2, new TextRange(2, 3), 8.0, 0.0, 0.0, null, null, null, null)
            ], 30.0, [])
        ], [], [],
            new LayoutDebugInfo(null, [], geometries, [], rubies, []), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final glyphPositioned:Array<PositionedCluster> = LayoutQueries.positionedClusters(glyphResult);
        TracedAssertions.assertEqualsFloat(0.0, glyphPositioned[0].left);
        TracedAssertions.assertEqualsFloat(16.0, glyphPositioned[0].right);
        TracedAssertions.assertEqualsFloat(16.0, glyphPositioned[1].left);
        TracedAssertions.assertEqualsFloat(30.0, glyphPositioned[1].right);
    }

    @:test
    public static function noArgPositionedClustersWalksEveryLine():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("noArgPositionedClustersWalksEveryLine");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abcd", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 3), "c", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(3, 4), "d", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0),
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(2, 4), 2, 3, 20.0, 40.0, 35.0, 0.0, 20.0),
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(4, 4), 2, 1, 40.0, 60.0, 55.0, 0.0, 0.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final positioned:Array<PositionedCluster> = LayoutQueries.positionedClusters(content);
        TracedAssertions.assertEqualsInt(4, positioned.length);
        TracedAssertions.assertEqualsInt(0, positioned[0].lineIndex);
        TracedAssertions.assertEqualsInt(1, positioned[2].lineIndex);
        TracedAssertions.assertEqualsFloat(20.0, positioned[3].right);
    }

    @:test
    public static function glyphInkBoundsRejectsEachNonFiniteEdgeIndependently():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("glyphInkBoundsRejectsEachNonFiniteEdgeIndependently");
        final nonFiniteLeft = LayoutQueriesResidualCoverageTestHelpers.inkWithBounds(new Rect(LayoutQueriesResidualCoverageTestHelpers.nan(), 2.0, 8.0, 4.0));
        TracedAssertions.assertNullRendered(nonFiniteLeft == null, nonFiniteLeft == null ? "-" : nonFiniteLeft.toString());
        final nonFiniteTop = LayoutQueriesResidualCoverageTestHelpers.inkWithBounds(new Rect(1.0, LayoutQueriesResidualCoverageTestHelpers.nan(), 8.0, 4.0));
        TracedAssertions.assertNullRendered(nonFiniteTop == null, nonFiniteTop == null ? "-" : nonFiniteTop.toString());
        final nonFiniteRight = LayoutQueriesResidualCoverageTestHelpers.inkWithBounds(new Rect(1.0, 2.0, LayoutQueriesResidualCoverageTestHelpers.nan(), 4.0));
        TracedAssertions.assertNullRendered(nonFiniteRight == null, nonFiniteRight == null ? "-" : nonFiniteRight.toString());
        final nonFiniteBottom = LayoutQueriesResidualCoverageTestHelpers.inkWithBounds(new Rect(1.0, 2.0, 8.0, LayoutQueriesResidualCoverageTestHelpers.nan()));
        TracedAssertions.assertNullRendered(nonFiniteBottom == null, nonFiniteBottom == null ? "-" : nonFiniteBottom.toString());
    }

    @:test
    public static function clearanceTakesTheSmallerSideWhicheverSegmentOwnsIt():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("clearanceTakesTheSmallerSideWhicheverSegmentOwnsIt");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final weakFirst:RichTextLineSegment = LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 1), Background.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 6.0),
            0, new TextRange(0, 1), 0.0, 0.0, 10.0, 20.0, 15.0);
        final strongSecond:RichTextLineSegment = LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(1, 2), Background.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 2.0),
            0, new TextRange(1, 2), 10.0, 0.0, 20.0, 20.0, 15.0);
        final cleared:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [weakFirst, strongSecond]);
        TracedAssertions.assertEqualsFloat(9.0, cleared[0].right);
        TracedAssertions.assertEqualsFloat(11.0, cleared[1].left);
        final styledA:RichTextLineSegment = LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(1, 2), Background.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 4.0),
            0, new TextRange(1, 2), 10.0, 0.0, 20.0, 20.0, 15.0);
        final scanPast:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(1, 2), InlineCode.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 4.0),
                0, new TextRange(1, 2), 10.0, 0.0, 20.0, 20.0, 15.0),
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 1), Background.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 4.0),
                0, new TextRange(0, 1), 0.0, 0.0, 10.0, 20.0, 15.0),
            styledA
        ]);
        TracedAssertions.assertEqualsInt(3, scanPast.length);
        TracedAssertions.assertEqualsFloat(8.0, scanPast[1].right);
        TracedAssertions.assertEqualsFloat(12.0, scanPast[2].left);
    }

    @:test
    public static function uniformTextStylePolicyResolvesSpanStyleOrParagraphStyle():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("uniformTextStylePolicyResolvesSpanStyleOrParagraphStyle");
        final uniform:RichTextPaint = new RichTextPaint(null, Solid.instance,
            new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.UniformTextStyle, Fill.instance), 0.0);
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abc", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 3), "c", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 2, 0.0, 20.0, 15.0, 0.0, 30.0)
        ], [], [
            new TextSpan(new TextRange(1, 2), LayoutQueriesResidualCoverageTestHelpers.style(40.0))
        ], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final outside:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 1), Background.instance, uniform, 0, new TextRange(0, 1), 0.0, 0.0, 10.0, 20.0,
                15.0)
        ]);
        TracedAssertions.assertEqualsFloat(15.0 - 10.0 * 0.88, outside[0].top);
        final inside:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(1, 2), Background.instance, uniform, 0, new TextRange(1, 2), 10.0, 0.0, 20.0, 20.0,
                15.0)
        ]);
        TracedAssertions.assertEqualsFloat(0.0, inside[0].top);
    }

    @:test
    public static function trailingGlueIsSkippedWhenNoClusterEndsBeforeTheSegmentEnd():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("trailingGlueIsSkippedWhenNoClusterEndsBeforeTheSegmentEnd");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab",
            [LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0)], [
                LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 0.0, 20.0, 15.0, 0.0, 10.0)
            ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final out:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 1), Background.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
                0, new TextRange(0, 1), 0.0, 0.0, 10.0, 20.0, 15.0)
        ]);
        TracedAssertions.assertEqualsFloat(10.0, out[0].right);
    }

    @:test
    public static function decorationLineYWithoutSpansUsesTheParagraphStyle():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("decorationLineYWithoutSpansUsesTheParagraphStyle");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 2), "ab", 20.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final value:Float = LayoutQueries.richTextDecorationLineY(content,
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 2), Underline.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
                0, new TextRange(0, 2), 0.0, 0.0, 20.0, 20.0, 15.0),
            1.0);
        TracedAssertions.assertEqualsFloat(15.0 + 10.0 * 0.18, value);
    }

    @:test
    public static function wordBoundaryForPositionHandlesANonFiniteY():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("wordBoundaryForPositionHandlesANonFiniteY");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("甲乙", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "甲", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "乙", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsRendered(new TextRange(0, 1).toString(),
            LayoutQueries.getSelectionWordBoundaryForPosition(content, 5.0, LayoutQueriesResidualCoverageTestHelpers.nan()).toString());
    }

    @:test
    public static function supplementaryIdeographBeyondTheHanRangesIsItsOwnUnit():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("supplementaryIdeographBeyondTheHanRangesIsItsOwnUnit");
        final text:String = TestHelpers.surrogateText([0xD880, 0xDC00]);
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result(text, [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 2), text, 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 0.0, 20.0, 15.0, 0.0, 10.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsRendered(new TextRange(0, 2).toString(), LayoutQueries.getSelectionWordBoundary(content, 0).toString());
    }

    @:test
    public static function planeFourCodepointAboveTheHanBandsIsItsOwnUnit():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("planeFourCodepointAboveTheHanBandsIsItsOwnUnit");
        final text:String = TestHelpers.surrogateText([0xD900, 0xDC00]);
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result(text, [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 2), text, 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 0.0, 20.0, 15.0, 0.0, 10.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsRendered(new TextRange(0, 2).toString(), LayoutQueries.getSelectionWordBoundary(content, 0).toString());
    }

    @:test
    public static function nearestLineSearchCoversAllThreeDistanceArms():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("nearestLineSearchCoversAllThreeDistanceArms");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abcde", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(4, 5), "e", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 0.0, 20.0, 15.0, 0.0, 10.0),
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(4, 5), 1, 1, 20.0, 40.0, 35.0, 0.0, 10.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsFloat(10.0, LayoutQueries.getCursorRect(content, 2).left);
        TracedAssertions.assertEqualsFloat(10.0, LayoutQueries.getCursorRect(content, 3).left);
    }

    @:test
    public static function rubiesOnOtherLinesDoNotAffectThisLineGeometry():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("rubiesOnOtherLinesDoNotAffectThisLineGeometry");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [], new LayoutDebugInfo(null, [], [], [], [
            new RubyDecisionInfo(new TextRange(0, 2), "zhù", 1, 10.0, 4.0, 6.0, 0.0, 0.0, 0.0, 30.0, [], 400, "zh-Hans", [])
            ], []), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final positioned:Array<PositionedCluster> = LayoutQueries.positionedClusters(content);
        TracedAssertions.assertEqualsFloat(0.0, positioned[0].left);
        TracedAssertions.assertEqualsFloat(10.0, positioned[0].right);
        TracedAssertions.assertEqualsFloat(10.0, positioned[1].left);
        TracedAssertions.assertEqualsFloat(20.0, positioned[1].right);
    }

    @:test
    public static function backgroundTrailingEdgePicksTheLargestGlyphAdvance():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("backgroundTrailingEdgePicksTheLargestGlyphAdvance");
        final clusters:Array<Cluster> = [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0)
        ];
        final runs:Array<GlyphRun> = [
            new GlyphRun(new TextRange(1, 2), "test", [
                new Glyph(1, new TextRange(1, 2), 5.0, 0.0, 0.0, null, null, null, null),
                new Glyph(2, new TextRange(1, 2), 6.0, 0.0, 0.0, null, null, null, null)
            ], 10.0, [])
        ];
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", clusters, [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], runs, [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final output:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 2), Background.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
                0, new TextRange(0, 2), 0.0, 0.0, 20.0, 20.0, 15.0)
        ]);
        TracedAssertions.assertEqualsFloat(16.0, output[0].right);
    }

    @:test
    public static function backgroundTrailingEdgeKeepsTheFirstGlyphWhenItIsLargest():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("backgroundTrailingEdgeKeepsTheFirstGlyphWhenItIsLargest");
        final clusters:Array<Cluster> = [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0)
        ];
        final runs:Array<GlyphRun> = [
            new GlyphRun(new TextRange(1, 2), "test", [
                new Glyph(1, new TextRange(1, 2), 6.0, 0.0, 0.0, null, null, null, null),
                new Glyph(2, new TextRange(1, 2), 5.0, 0.0, 0.0, null, null, null, null)
            ], 10.0, [])
        ];
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", clusters, [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], runs, [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final output:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 2), Background.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
                0, new TextRange(0, 2), 0.0, 0.0, 20.0, 20.0, 15.0)
        ]);
        TracedAssertions.assertEqualsFloat(16.0, output[0].right);
    }

    @:test
    public static function selectionWordBoundaryForPositionPrefersTheCloserLaterLine():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("selectionWordBoundaryForPositionPrefersTheCloserLaterLine");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("甲乙丙丁", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "甲", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "乙", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 3), "丙", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(3, 4), "丁", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0),
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(2, 4), 2, 3, 40.0, 60.0, 55.0, 0.0, 20.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsRendered(new TextRange(2, 3).toString(), LayoutQueries.getSelectionWordBoundaryForPosition(content, 5.0, 50.0)
            .toString());
        TracedAssertions.assertEqualsRendered(new TextRange(0, 1).toString(), LayoutQueries.getSelectionWordBoundaryForPosition(content, 5.0, 30.0)
            .toString());
        TracedAssertions.assertEqualsRendered(new TextRange(0, 1).toString(),
            LayoutQueries.getSelectionWordBoundaryForPosition(content, 5.0, -10.0).toString());
        TracedAssertions.assertEqualsRendered(new TextRange(0, 1).toString(), LayoutQueries.getSelectionWordBoundaryForPosition(content, 5.0, 10.0)
            .toString());
        TracedAssertions.assertEqualsRendered(new TextRange(2, 3).toString(),
            LayoutQueries.getSelectionWordBoundaryForPosition(content, 5.0, 100.0).toString());
    }

    @:test
    public static function nearestLineSearchUpdatesToAStrictlyCloserLaterLine():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("nearestLineSearchUpdatesToAStrictlyCloserLaterLine");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abcde", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(5, 6), "e", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 0.0, 20.0, 15.0, 0.0, 10.0),
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(5, 7), 1, 1, 20.0, 40.0, 35.0, 10.0, 10.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsFloat(10.0, LayoutQueries.getCursorRect(content, 4).left);
    }

    @:test
    public static function nearestLineSearchCoversBothLambdaCopiesOfEachArm():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("nearestLineSearchCoversBothLambdaCopiesOfEachArm");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abcdefghij", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 3), "c", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(3, 4), "d", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(6, 7), "g", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(7, 8), "h", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(2, 4), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0),
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(6, 8), 2, 3, 20.0, 40.0, 35.0, 0.0, 20.0)
        ], [], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        TracedAssertions.assertEqualsFloat(0.0, LayoutQueries.getCursorRect(content, 1).left);
        TracedAssertions.assertEqualsFloat(20.0, LayoutQueries.getCursorRect(content, 8).left);
        TracedAssertions.assertEqualsFloat(20.0, LayoutQueries.getCursorRect(content, 9).left);
    }

    @:test
    public static function uniformTextStylePolicyPicksTheLastMatchingSpan():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("uniformTextStylePolicyPicksTheLastMatchingSpan");
        final uniform:RichTextPaint = new RichTextPaint(null, Solid.instance,
            new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.UniformTextStyle, Fill.instance), 0.0);
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abc", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 3), "c", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 2, 0.0, 20.0, 15.0, 0.0, 30.0)
        ], [], [
            new TextSpan(new TextRange(0, 2), LayoutQueriesResidualCoverageTestHelpers.style(10.0)),
            new TextSpan(new TextRange(1, 3), LayoutQueriesResidualCoverageTestHelpers.style(40.0))
        ], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final inside:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(2, 3), Background.instance, uniform, 0, new TextRange(2, 3), 20.0, 0.0, 30.0, 20.0,
                15.0)
        ]);
        TracedAssertions.assertEqualsFloat(0.0, inside[0].top);
    }

    @:test
    public static function decorationLineYPicksTheLastMatchingSpan():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("decorationLineYPicksTheLastMatchingSpan");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abc", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 3), "c", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 2, 0.0, 20.0, 15.0, 0.0, 30.0)
        ], [], [
            new TextSpan(new TextRange(0, 2), LayoutQueriesResidualCoverageTestHelpers.style(10.0)),
            new TextSpan(new TextRange(1, 3), LayoutQueriesResidualCoverageTestHelpers.style(20.0))
        ], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final value:Float = LayoutQueries.richTextDecorationLineY(content,
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(2, 3), Underline.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
                0, new TextRange(2, 3), 20.0, 0.0, 30.0, 20.0, 15.0),
            1.0);
        TracedAssertions.assertEqualsFloat(15.0 + 20.0 * 0.18, value);
    }

    @:test
    public static function uniformTextStylePolicyKeepsTheEarlierSpanWhenALaterOneMisses():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("uniformTextStylePolicyKeepsTheEarlierSpanWhenALaterOneMisses");
        final uniform:RichTextPaint = new RichTextPaint(null, Solid.instance,
            new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.UniformTextStyle, Fill.instance), 0.0);
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abc", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 3), "c", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 2, 0.0, 20.0, 15.0, 0.0, 30.0)
        ], [], [
            new TextSpan(new TextRange(0, 3), LayoutQueriesResidualCoverageTestHelpers.style(40.0)),
            new TextSpan(new TextRange(1, 2), LayoutQueriesResidualCoverageTestHelpers.style(10.0))
        ], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final output:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 1), Background.instance, uniform, 0, new TextRange(0, 1), 0.0, 0.0, 10.0, 20.0,
                15.0)
        ]);
        TracedAssertions.assertEqualsFloat(0.0, output[0].top);
    }

    @:test
    public static function decorationLineYKeepsTheEarlierSpanWhenALaterOneMisses():Void {
        new TestTraceRecorder("LayoutQueriesResidualCoverageTest").section("decorationLineYKeepsTheEarlierSpanWhenALaterOneMisses");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("abc", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(2, 3), "c", 10.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 3), 0, 2, 0.0, 20.0, 15.0, 0.0, 30.0)
        ], [], [
            new TextSpan(new TextRange(0, 3), LayoutQueriesResidualCoverageTestHelpers.style(20.0)),
            new TextSpan(new TextRange(1, 2), LayoutQueriesResidualCoverageTestHelpers.style(10.0))
        ], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final value:Float = LayoutQueries.richTextDecorationLineY(content,
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 1), Underline.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
                0, new TextRange(0, 1), 0.0, 0.0, 10.0, 20.0, 15.0),
            1.0);
        TracedAssertions.assertEqualsFloat(15.0 + 20.0 * 0.18, value);
    }
}

class LayoutQueriesResidualCoverageTestHelpers {
    public static function cluster(range:TextRange, text:String, advance:Float):Cluster {
        return new Cluster(range, text, "test", advance, (text), 0.0, 0.0, 0.0);
    }

    public static function line(range:TextRange, clusterStart:Int, clusterEnd:Int, top:Float, bottom:Float, baseline:Float, indent:Float, width:Float):LineBox {
        return new LineBox(range, new IntRange(clusterStart, clusterEnd), baseline, top, bottom, width, width, width, 0.0, indent, LineEndReason.ParagraphEnd,
            0.0, [], new LineDebugInfo(null, []));
    }

    public static function style(fontSize:Float):TextStyle {
        return new TextStyle([], fontSize, "zh-Hans", 400, false, 0.0, InlineAttachment.None);
    }

    public static function emptyDebug():LayoutDebugInfo {
        return new LayoutDebugInfo(null, [], [], [], [], []);
    }

    public static function result(text:String, clusters:Array<Cluster>, lines:Array<LineBox>, glyphRuns:Array<GlyphRun>, spans:Array<TextSpan>,
            inlineObjects:Array<InlineObjectSpan>, debug:LayoutDebugInfo, textStyle:TextStyle):LayoutResult {
        final content:TiqianTextContent = new TiqianTextContent(text, spans, [], [], []);
        final input:LayoutInput = new LayoutInput(content, textStyle,
            new ParagraphStyle(LastLineAlignment.Start, WritingMode.HorizontalTb, null, null, Ic.Zero, new MeasureAdaptiveFirstLineIndent(14.0, 1.0, 2.0),
                new LineLengthGrid(true, null), RubyLineHeightMode.PerLine, ParagraphStyle.DEFAULT_INLINE_OBJECT_MINIMUM_CLEARANCE_EM,
                ParagraphStyle.DEFAULT_EMPHASIS_DOT_GAP_EM),
            new LayoutConstraints(100.0, Math.POSITIVE_INFINITY, 2147483647), BuiltInLayoutProfiles.ClreqHorizontal, [], [], [], inlineObjects);
        return new LayoutResult(input, new Size(30.0, 40.0), clusters, glyphRuns, lines, debug);
    }

    public static function segment(range:TextRange, role:RichTextRole, paint:RichTextPaint, lineIndex:Int, spanRange:TextRange, left:Float, top:Float,
            right:Float, bottom:Float, baseline:Float):RichTextLineSegment {
        return new RichTextLineSegment(new RichTextSpan(spanRange, role, paint), lineIndex, range, left, top, right, bottom, baseline);
    }

    public static function plainSegment(range:TextRange):RichTextLineSegment {
        return LayoutQueriesResidualCoverageTestHelpers.segment(range, Background.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
            0, range, 0.0, 0.0, 20.0, 20.0, 15.0);
    }

    public static function renderSegments(values:Array<RichTextLineSegment>):String {
        final output = new StringBuf();
        output.add("[");
        var index:Int = 0;
        while (index < values.length) {
            if (index > 0) {
                output.add(", ");
            }
            output.add(TestTraceRender.cap(values[index].toString()));
            index += 1;
        }
        output.add("]");
        return output.toString();
    }

    public static function renderRects(values:Array<Rect>):String {
        final output = new StringBuf();
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

    public static function nan():Float {
        return 0.0 / 0.0;
    }

    public static function metric(range:TextRange, metricBox:String, ascent:Float, descent:Float, baselineClass:String):MetricDecisionInfo {
        return new MetricDecisionInfo(range, "ab", "body", "test", 8.0, 2.0, 0.0, "stub", ascent, descent, baselineClass, metricBox, "normalized", "test");
    }

    public static function geometry(range:TextRange, sourceText:String, leading:Float, leadingConsumed:Float, trailing:Float,
            trailingConsumed:Float):ClusterGeometryDecisionInfo {
        return new ClusterGeometryDecisionInfo(range, sourceText, sourceText, 10.0, 10.0 - leading - trailing, leading, leadingConsumed, trailing,
            trailingConsumed, 0.0, 10.0, "test", "test", 0.0, 0.0, null);
    }

    public static function metricBounds(decisionRange:TextRange):Array<Float> {
        final decision:MetricDecisionInfo = LayoutQueriesResidualCoverageTestHelpers.metric(decisionRange, "IdeographicEmBox", 7.0, 3.0, "ideographic");
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 2), "ab", 20.0)
        ], [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 0, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [], [], [],
            new LayoutDebugInfo(null, [decision], [], [], [], []), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        final box:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(content, [
            LayoutQueriesResidualCoverageTestHelpers.segment(new TextRange(0, 2), Background.instance,
                new RichTextPaint(null, Solid.instance,
                    new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0),
                0, new TextRange(0, 2), 0.0, 0.0, 20.0, 20.0, 15.0)
        ]);
        return [box[0].top, box[0].bottom];
    }

    public static function inkWithBounds(bounds:Rect):Null<Rect> {
        final clusters:Array<Cluster> = [
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(0, 1), "a", 10.0),
            LayoutQueriesResidualCoverageTestHelpers.cluster(new TextRange(1, 2), "b", 10.0)
        ];
        final content:LayoutResult = LayoutQueriesResidualCoverageTestHelpers.result("ab", clusters, [
            LayoutQueriesResidualCoverageTestHelpers.line(new TextRange(0, 2), 0, 1, 0.0, 20.0, 15.0, 0.0, 20.0)
        ], [
            new GlyphRun(new TextRange(0, 2), "test", [new Glyph(1, new TextRange(0, 1), 10.0, 0.0, 0.0, null, bounds, null, null)], 20.0, [])
        ], [], [],
            LayoutQueriesResidualCoverageTestHelpers.emptyDebug(), LayoutQueriesResidualCoverageTestHelpers.style(10.0));
        return LayoutQueries.glyphInkBounds(content);
    }
}
