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
import std.StringBuf;

class LayoutQueriesTest {
    @:test
    public static function clipboardProjectionRestoresSourceAndAddsFullySelectedAnnotations():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("clipboardProjectionRestoresSourceAndAddsFullySelectedAnnotations");
        final text:String = "提椠与您";
        final ruby:RubyDecisionInfo = new RubyDecisionInfo(new TextRange(0, 2), "tíqiàn", 0, 0.0, 0.0, 8.0, 0.0, 0.0, 0.0, 0.0, [], 400, "zh-Hans", []);
        final bopomofo:BopomofoDecisionInfo = new BopomofoDecisionInfo(new TextRange(3, 4), "ㄋㄧㄣˊ", 0, [], [], 400, "zh-Hans");
        final debug:LayoutDebugInfo = new LayoutDebugInfo(null, [], [], [], [ruby], [bopomofo]);
        final result:LayoutResult = LayoutQueriesTestHelpers.result(text, 200.0, null, new Size(0.0, 0.0), [], [], [], debug, null);

        TracedAssertions.assertEqualsString("提椠（tíqiàn）与您（ㄋㄧㄣˊ）", LayoutQueries.getTextForCopy(result, new TextRange(0, 4)));
        TracedAssertions.assertEqualsString("提", LayoutQueries.getTextForCopy(result, new TextRange(0, 1)));
        TracedAssertions.assertEqualsString("提椠（tíqiàn）", LayoutQueries.getTextForCopy(result, new TextRange(0, 2)));
        TracedAssertions.assertEqualsString("您（ㄋㄧㄣˊ）", LayoutQueries.getTextForCopy(result, new TextRange(3, 4)));
    }

    @:test
    public static function positionedClustersFollowLineIndentAndAdvance():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("positionedClustersFollowLineIndentAndAdvance");
        final positions:Array<PositionedCluster> = LayoutQueries.positionedClusters(LayoutQueriesTestHelpers.sampleResult());
        TracedAssertions.assertEqualsRendered(new Rect(4.0, 0.0, 14.0, 20.0).toString(), positions[0].rect.toString());
        TracedAssertions.assertEqualsRendered(new Rect(14.0, 0.0, 34.0, 20.0).toString(), positions[1].rect.toString());
        TracedAssertions.assertEqualsRendered(new Rect(0.0, 20.0, 10.0, 40.0).toString(), positions[2].rect.toString());
    }

    @:test
    public static function positionedClustersSeparateOccupiedBoxFromAutoSpaceDrawOrigin():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("positionedClustersSeparateOccupiedBoxFromAutoSpaceDrawOrigin");
        final decision:AutoSpaceDecisionInfo = new AutoSpaceDecisionInfo(new TextRange(1, 3), "leading", "CjkLatin", "Insert", 1, -2.5, -2.5,
            "TextAutoSpaceInsert:ideograph-alpha:quarter-em");
        final result:LayoutResult = LayoutQueriesTestHelpers.result("中Hi", 40.0, LayoutQueriesTestHelpers.style(10.0), new Size(32.5, 20.0), [
            LayoutQueriesTestHelpers.cluster(new TextRange(0, 1), "中", "cjk", 10.0),
            LayoutQueriesTestHelpers.cluster(new TextRange(1, 3), "Hi", "latin", 22.5)
        ], [], [
            LayoutQueriesTestHelpers.line(new TextRange(0, 3), 0, 1, 15.0, 0.0, 20.0, 32.5, 32.5, 32.5, null)
        ], new LayoutDebugInfo(null, [], [], [decision], [], []), null);
        final positions:Array<PositionedCluster> = LayoutQueries.positionedClusters(result);
        TracedAssertions.assertEqualsRendered(new Rect(10.0, 0.0, 32.5, 20.0).toString(), positions[1].rect.toString());
        TracedAssertions.assertEqualsFloat(12.5, positions[1].drawX);
        TracedAssertions.assertEqualsRendered(new Rect(10.0, 0.0, 32.5, 20.0).toString(), LayoutQueries.getBoundingBox(result, 1).toString());
        TracedAssertions.assertEqualsInt(1, LayoutQueries.getOffsetForPosition(result, 11.0, 5.0));
    }

    @:test
    public static function positionedClustersSeparateOccupiedBoxFromConsumedLeadingGlueDrawOrigin():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("positionedClustersSeparateOccupiedBoxFromConsumedLeadingGlueDrawOrigin");
        final geometry:ClusterGeometryDecisionInfo = LayoutQueriesTestHelpers.punctuationGeometry(new TextRange(0, 1), "（", 4.0, 0.0, 4.0, 4.0);
        final result:LayoutResult = LayoutQueriesTestHelpers.result("（", 10.0, LayoutQueriesTestHelpers.style(10.0), new Size(6.0, 20.0),
            [LayoutQueriesTestHelpers.cluster(new TextRange(0, 1), "（", "cjk", 6.0)], [], [
                LayoutQueriesTestHelpers.line(new TextRange(0, 1), 0, 0, 15.0, 0.0, 20.0, 6.0, 6.0, 6.0, null)
            ], new LayoutDebugInfo(null, [], [geometry], [], [], []), null);
        final positioned:Array<PositionedCluster> = LayoutQueries.positionedClusters(result);
        TracedAssertions.assertEqualsRendered(new Rect(0.0, 0.0, 6.0, 20.0).toString(), positioned[0].rect.toString());
        TracedAssertions.assertEqualsFloat(-4.0, positioned[0].drawX);
        TracedAssertions.assertEqualsRendered(new Rect(0.0, 0.0, 1.0, 20.0).toString(), LayoutQueries.getCursorRect(result, 0).toString());
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getOffsetForPosition(result, -3.0, 5.0));
    }

    @:test
    public static function glyphInkBoundsKeepItalicOverhangSeparateFromOccupiedGeometry():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("glyphInkBoundsKeepItalicOverhangSeparateFromOccupiedGeometry");
        final glyphRange:TextRange = new TextRange(0, 1);
        final glyph:Glyph = new Glyph(1, glyphRange, 10.0, 0.0, 0.0, null, new Rect(-3.0, -9.0, 12.0, 2.0), null, null);
        final result:LayoutResult = LayoutQueriesTestHelpers.result("f", 10.0, LayoutQueriesTestHelpers.style(10.0), new Size(10.0, 20.0),
            [LayoutQueriesTestHelpers.cluster(glyphRange, "f", "latin", 10.0)], [new GlyphRun(glyphRange, "latin", [glyph], 10.0, [])], [
                LayoutQueriesTestHelpers.line(glyphRange, 0, 0, 14.0, 0.0, 20.0, 10.0, 10.0, 10.0, null)
            ], null, null);
        TracedAssertions.assertEqualsRendered(new Rect(0.0, 0.0, 10.0, 20.0).toString(), LayoutQueries.positionedClusters(result)[0].rect.toString());
        TracedAssertions.assertEqualsRendered(new Rect(-3.0, 5.0, 12.0, 16.0).toString(), LayoutQueries.glyphInkBounds(result).toString());
    }

    @:test
    public static function lineAndBoxQueriesUseTiqianLineGeometry():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("lineAndBoxQueriesUseTiqianLineGeometry");
        final result:LayoutResult = LayoutQueriesTestHelpers.sampleResult();
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getLineForOffset(result, 1));
        TracedAssertions.assertEqualsInt(1, LayoutQueries.getLineForOffset(result, 3));
        TracedAssertions.assertEqualsRendered(new Rect(14.0, 0.0, 34.0, 20.0).toString(), LayoutQueries.getBoundingBox(result, 1).toString());
        TracedAssertions.assertEqualsRendered(new Rect(10.0, 20.0, 11.0, 40.0).toString(), LayoutQueries.getCursorRect(result, 4).toString());
    }

    @:test
    public static function rangeBoxesSplitMultiUnitClustersBySourceRange():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("rangeBoxesSplitMultiUnitClustersBySourceRange");
        final boxes:Array<Rect> = LayoutQueries.getBoundingBoxes(LayoutQueriesTestHelpers.sampleResult(), new TextRange(2, 4));
        final expected:Array<Rect> = [new Rect(24.0, 0.0, 34.0, 20.0), new Rect(0.0, 20.0, 10.0, 40.0)];
        TracedAssertions.assertEqualsRendered(LayoutQueriesTestHelpers.renderRects(expected), LayoutQueriesTestHelpers.renderRects(boxes));
    }

    @:test
    public static function richTextSegmentsReusePositionedClusterGeometryAndSplitLines():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("richTextSegmentsReusePositionedClusterGeometryAndSplitLines");
        final result:LayoutResult = LayoutQueriesTestHelpers.sampleResult();
        final paint:RichTextPaint = RichTextPaint.withArgb(0x33FF0000);
        final span:RichTextSpan = new RichTextSpan(new TextRange(1, 4), Background.instance, paint);
        final segments:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(result, [span]);
        TracedAssertions.assertEqualsInt(2, segments.length);
        TracedAssertions.assertEqualsRendered(new TextRange(1, 3).toString(), segments[0].range.toString());
        TracedAssertions.assertEqualsRendered(new Rect(14.0, 0.0, 34.0, 20.0).toString(), segments[0].rect.toString());
        TracedAssertions.assertEqualsRendered(new TextRange(3, 4).toString(), segments[1].range.toString());
        TracedAssertions.assertEqualsRendered(new Rect(0.0, 20.0, 10.0, 40.0).toString(), segments[1].rect.toString());
        TracedAssertions.assertEqualsRendered(span.toString(), segments[0].span.toString());
    }

    @:test
    public static function richTextDecorationTrimsOnlyOuterPunctuationGlue():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("richTextDecorationTrimsOnlyOuterPunctuationGlue");
        final result:LayoutResult = LayoutQueriesTestHelpers.punctuationGlueResult();
        final underline:RichTextSpan = new RichTextSpan(new TextRange(0, 4), Underline.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0));
        final occupied:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(result, [underline]);
        final decorations:Array<RichTextLineSegment> = LayoutQueries.trimmedRichTextDecorationSegments(result, occupied);
        TracedAssertions.assertEqualsRendered(new Rect(0.0, 0.0, 40.0, 20.0).toString(), occupied[0].rect.toString());
        TracedAssertions.assertEqualsRendered(new Rect(5.0, 0.0, 35.0, 20.0).toString(), decorations[0].rect.toString());
        TracedAssertions.assertEqualsRendered(new TextRange(0, 4).toString(), decorations[0].range.toString());
    }

    @:test
    public static function richTextDecorationKeepsPunctuationGlueInsideItsRange():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("richTextDecorationKeepsPunctuationGlueInsideItsRange");
        final result:LayoutResult = LayoutQueriesTestHelpers.punctuationGlueResult();
        final underline:RichTextSpan = new RichTextSpan(new TextRange(1, 4), Underline.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0));
        final occupied:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(result, [underline]);
        final decorations:Array<RichTextLineSegment> = LayoutQueries.trimmedRichTextDecorationSegments(result, occupied);
        TracedAssertions.assertEqualsRendered(new Rect(10.0, 0.0, 35.0, 20.0).toString(), decorations[0].rect.toString());
    }

    @:test
    public static function richTextDecorationDoesNotTrimAlreadyConsumedOpeningGlueTwice():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("richTextDecorationDoesNotTrimAlreadyConsumedOpeningGlueTwice");
        final original:LayoutResult = LayoutQueriesTestHelpers.punctuationGlueResult();
        final geometry:Array<ClusterGeometryDecisionInfo> = [];
        var index:Int = 0;
        while (index < original.debug.geometryDecisions.length) {
            final decision:ClusterGeometryDecisionInfo = original.debug.geometryDecisions[index];
            if (LayoutQueriesTestHelpers.sameRange(decision.range, new TextRange(0, 1))) {
                geometry.push(new ClusterGeometryDecisionInfo(decision.range, decision.sourceText, decision.displayText, decision.baseAdvance,
                    decision.bodyWidth, decision.leadingGlueNatural, decision.leadingGlueNatural, decision.trailingGlueNatural, decision.trailingGlueConsumed,
                    decision.justificationDelta, decision.resolvedAdvance, decision.source, decision.reason, decision.rubySpread, decision.glyphInlineShift,
                    decision.glyphPlacementReason));
            } else {
                geometry.push(decision);
            }
            index += 1;
        }
        final result:LayoutResult = LayoutQueriesTestHelpers.copyResultWithDebug(original, new LayoutDebugInfo(null, [], geometry, [], [], []));
        final underline:RichTextSpan = new RichTextSpan(new TextRange(0, 1), Underline.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0));
        final occupied:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(result, [underline]);
        final decorations:Array<RichTextLineSegment> = LayoutQueries.trimmedRichTextDecorationSegments(result, occupied);
        TracedAssertions.assertEqualsFloat(0.0, decorations[0].left);
    }

    @:test
    public static function customLineStylesReuseTheRendererUnderlineHeight():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("customLineStylesReuseTheRendererUnderlineHeight");
        final result:LayoutResult = LayoutQueriesTestHelpers.punctuationGlueResult();
        final underline:RichTextSpan = new RichTextSpan(new TextRange(0, 4), Underline.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0));
        final occupied:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(result, [underline]);
        final segment:Array<RichTextLineSegment> = LayoutQueries.trimmedRichTextDecorationSegments(result, occupied);
        final expected:Float = segment[0].baseline + result.input.textStyle.fontSize * 0.18;
        TracedAssertions.assertEqualsFloatTolerance(expected, LayoutQueries.richTextDecorationLineY(result, segment[0], 1.0), 0.001);
    }

    @:test
    public static function lineThroughBisectsTheIdeographicMetricBox():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("lineThroughBisectsTheIdeographicMetricBox");
        final original:LayoutResult = LayoutQueriesTestHelpers.backgroundGeometryResult();
        final metric:MetricDecisionInfo = LayoutQueriesTestHelpers.backgroundMetric(new TextRange(0, 3), "IdeographicEmBox", 8.0, 2.0);
        final result:LayoutResult = LayoutQueriesTestHelpers.copyResultWithDebug(original, new LayoutDebugInfo(null, [metric], [], [], [], []));
        final lineThrough:RichTextSpan = new RichTextSpan(new TextRange(0, 3), LineThrough.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0));
        final occupied:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(result, [lineThrough]);
        final segment:Array<RichTextLineSegment> = LayoutQueries.trimmedRichTextDecorationSegments(result, occupied);
        TracedAssertions.assertEqualsFloatTolerance(17.0, LayoutQueries.richTextDecorationLineY(result, segment[0], 1.0), 0.001);
    }

    @:test
    public static function richTextBackgroundKeepsInternalGapsButTrimsItsOuterLayoutSpace():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("richTextBackgroundKeepsInternalGapsButTrimsItsOuterLayoutSpace");
        final result:LayoutResult = LayoutQueriesTestHelpers.backgroundGeometryResult();
        final full:RichTextSpan = new RichTextSpan(new TextRange(0, 3), Background.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0));
        final finalCharacter:RichTextSpan = new RichTextSpan(new TextRange(2, 3), Background.instance,
            new RichTextPaint(null, Solid.instance,
                new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0));
        final fullOccupied:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(result, [full]);
        final finalOccupied:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(result, [finalCharacter]);
        final fullSegment:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(result, fullOccupied);
        final finalSegment:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(result, finalOccupied);
        TracedAssertions.assertEqualsRendered(new Rect(0.0, 11.2, 29.0, 21.2).toString(), fullSegment[0].rect.toString());
        TracedAssertions.assertEqualsRendered(new Rect(19.0, 11.2, 29.0, 21.2).toString(), finalSegment[0].rect.toString());
    }

    @:test
    public static function uniformTextStyleBackgroundIgnoresFallbackFaceHeightAndAddsPadding():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("uniformTextStyleBackgroundIgnoresFallbackFaceHeightAndAddsPadding");
        final original:LayoutResult = LayoutQueriesTestHelpers.backgroundGeometryResult();
        final metrics:Array<MetricDecisionInfo> = [
            LayoutQueriesTestHelpers.backgroundMetric(new TextRange(0, 1), "IdeographicEmBox", 8.0, 2.0),
            LayoutQueriesTestHelpers.backgroundMetric(new TextRange(1, 3), "RawFontBox", 12.0, 4.0)
        ];
        final result:LayoutResult = LayoutQueriesTestHelpers.copyResultWithDebug(original, new LayoutDebugInfo(null, metrics, [], [], [], []));
        final background:RichTextBackgroundPaint = new RichTextBackgroundPaint(0.0, 1.0, 2.0, 2.0, RichTextBackgroundMetricPolicy.UniformTextStyle,
            Fill.instance);
        final paint:RichTextPaint = RichTextPaint.withBackground(background);
        final first:RichTextSpan = new RichTextSpan(new TextRange(0, 1), Background.instance, paint);
        final mixed:RichTextSpan = new RichTextSpan(new TextRange(0, 3), Background.instance, paint);
        final occupied:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(result, [first, mixed]);
        final segments:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(result, occupied);
        TracedAssertions.assertEqualsInt(2, segments.length);
        TracedAssertions.assertEqualsFloat(11.0, segments[0].top);
        TracedAssertions.assertEqualsFloat(23.0, segments[0].bottom);
        TracedAssertions.assertEqualsFloat(segments[0].top, segments[1].top);
        TracedAssertions.assertEqualsFloat(segments[0].bottom, segments[1].bottom);
        TracedAssertions.assertEqualsFloat(2.0, segments[0].span.paint.background.cornerRadius);
    }

    @:test
    public static function backgroundContinuationCornersKeepOnlyTrueSourceEndsFullyRounded():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("backgroundContinuationCornersKeepOnlyTrueSourceEndsFullyRounded");
        final background:RichTextBackgroundPaint = new RichTextBackgroundPaint(0.0, 0.0, 3.0, 1.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance);
        final span:RichTextSpan = new RichTextSpan(new TextRange(0, 12), InlineCode.instance, RichTextPaint.withBackground(background));
        final first:RichTextLineSegment = LayoutQueriesTestHelpers.segmentFor(span, 0, 4);
        final middle:RichTextLineSegment = LayoutQueriesTestHelpers.segmentFor(span, 4, 8);
        final last:RichTextLineSegment = LayoutQueriesTestHelpers.segmentFor(span, 8, 12);
        final whole:RichTextLineSegment = LayoutQueriesTestHelpers.segmentFor(span, 0, 12);
        TracedAssertions.assertEqualsRendered(new RichTextCornerRadii(3.0, 1.0, 1.0, 3.0).toString(),
            LayoutQueries.resolvedBackgroundCornerRadii(first, 0.0).toString());
        TracedAssertions.assertEqualsRendered(new RichTextCornerRadii(1.0, 1.0, 1.0, 1.0).toString(),
            LayoutQueries.resolvedBackgroundCornerRadii(middle, 0.0).toString());
        TracedAssertions.assertEqualsRendered(new RichTextCornerRadii(1.0, 3.0, 3.0, 1.0).toString(),
            LayoutQueries.resolvedBackgroundCornerRadii(last, 0.0).toString());
        TracedAssertions.assertEqualsRendered(new RichTextCornerRadii(3.0, 3.0, 3.0, 3.0).toString(),
            LayoutQueries.resolvedBackgroundCornerRadii(whole, 0.0).toString());
    }

    @:test
    public static function backgroundContinuationRadiusDefaultsToTheAuthoredCornerRadius():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("backgroundContinuationRadiusDefaultsToTheAuthoredCornerRadius");
        final background:RichTextBackgroundPaint = new RichTextBackgroundPaint(0.0, 0.0, 5.0, 5.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance);
        TracedAssertions.assertEqualsFloat(5.0, background.continuationCornerRadius);
    }

    @:test
    public static function adjacentBackgroundsWithTheSameStyleShareOneClearance():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("adjacentBackgroundsWithTheSameStyleShareOneClearance");
        final result:LayoutResult = LayoutQueriesTestHelpers.sampleResult();
        final paint:RichTextPaint = new RichTextPaint(null, Solid.instance,
            new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 2.0);
        final spans:Array<RichTextSpan> = [
            new RichTextSpan(new TextRange(0, 1), Background.instance, paint),
            new RichTextSpan(new TextRange(1, 3), Background.instance, paint)
        ];
        final occupied:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(result, spans);
        final segments:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(result, occupied);
        TracedAssertions.assertEqualsInt(2, segments.length);
        TracedAssertions.assertEqualsFloatTolerance(2.0, segments[1].left - segments[0].right, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(13.0, segments[0].right, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(15.0, segments[1].left, 0.001);
    }

    @:test
    public static function adjacentLineDecorationsWithTheSameStyleShareOneClearance():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("adjacentLineDecorationsWithTheSameStyleShareOneClearance");
        final result:LayoutResult = LayoutQueriesTestHelpers.sampleResult();
        final paint:RichTextPaint = new RichTextPaint(null, Solid.instance,
            new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 2.0);
        final spans:Array<RichTextSpan> = [
            new RichTextSpan(new TextRange(0, 1), Underline.instance, paint),
            new RichTextSpan(new TextRange(1, 3), Underline.instance, paint)
        ];
        final occupied:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(result, spans);
        final segments:Array<RichTextLineSegment> = LayoutQueries.trimmedRichTextDecorationSegments(result, occupied);
        TracedAssertions.assertEqualsInt(2, segments.length);
        TracedAssertions.assertEqualsFloatTolerance(2.0, segments[1].left - segments[0].right, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(13.0, segments[0].right, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(15.0, segments[1].left, 0.001);
    }

    @:test
    public static function adjacentBackgroundAndUnderlineDoNotAvoidAcrossStyles():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("adjacentBackgroundAndUnderlineDoNotAvoidAcrossStyles");
        final result:LayoutResult = LayoutQueriesTestHelpers.sampleResult();
        final paint:RichTextPaint = new RichTextPaint(null, Solid.instance,
            new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 2.0);
        final background:RichTextSpan = new RichTextSpan(new TextRange(0, 1), Background.instance, paint);
        final underline:RichTextSpan = new RichTextSpan(new TextRange(1, 3), Underline.instance, paint);
        final occupied:Array<RichTextLineSegment> = LayoutQueries.positionedRichTextSegments(result, [background, underline]);
        final fill:Array<RichTextLineSegment> = LayoutQueries.richTextBackgroundSegments(result, occupied);
        final lineSegments:Array<RichTextLineSegment> = LayoutQueries.trimmedRichTextDecorationSegments(result, occupied);
        TracedAssertions.assertEqualsFloatTolerance(14.0, fill[0].right, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(14.0, lineSegments[0].left, 0.001);
    }

    @:test
    public static function hitTestingChoosesOffsetFromTiqianClusterAdvances():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("hitTestingChoosesOffsetFromTiqianClusterAdvances");
        final result:LayoutResult = LayoutQueriesTestHelpers.sampleResult();
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getOffsetForPosition(result, 3.0, 5.0));
        TracedAssertions.assertEqualsInt(1, LayoutQueries.getOffsetForPosition(result, 18.0, 5.0));
        TracedAssertions.assertEqualsInt(2, LayoutQueries.getOffsetForPosition(result, 24.0, 5.0));
        TracedAssertions.assertEqualsInt(3, LayoutQueries.getOffsetForPosition(result, 4.0, 25.0));
        TracedAssertions.assertEqualsInt(4, LayoutQueries.getOffsetForPosition(result, 30.0, 25.0));
    }

    @:test
    public static function selectionHitTestingKeepsSupportedSourceSequencesAtomic():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("selectionHitTestingKeepsSupportedSourceSequencesAtomic");
        final result:LayoutResult = LayoutQueriesTestHelpers.interactionBoundaryResult();
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getSelectionOffsetForPosition(result, 5.0, 10.0));
        TracedAssertions.assertEqualsInt(2, LayoutQueries.getSelectionOffsetForPosition(result, 15.0, 10.0));
        TracedAssertions.assertEqualsInt(2, LayoutQueries.getSelectionOffsetForPosition(result, 25.0, 10.0));
        TracedAssertions.assertEqualsInt(4, LayoutQueries.getSelectionOffsetForPosition(result, 35.0, 10.0));
        TracedAssertions.assertEqualsInt(4, LayoutQueries.getSelectionOffsetForPosition(result, 45.0, 10.0));
        TracedAssertions.assertEqualsInt(9, LayoutQueries.getSelectionOffsetForPosition(result, 75.0, 10.0));
    }

    @:test
    public static function externalSelectionOffsetsRespectDirectionalBoundaryBias():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("externalSelectionOffsetsRespectDirectionalBoundaryBias");
        final result:LayoutResult = LayoutQueriesTestHelpers.interactionBoundaryResult();
        TracedAssertions.assertEqualsInt(2, LayoutQueries.coerceSelectionOffset(result, 3, SourceBoundaryBias.Backward));
        TracedAssertions.assertEqualsInt(4, LayoutQueries.coerceSelectionOffset(result, 3, SourceBoundaryBias.Forward));
        TracedAssertions.assertEqualsInt(4, LayoutQueries.coerceSelectionOffset(result, 3, SourceBoundaryBias.Nearest));
        TracedAssertions.assertEqualsInt(4, LayoutQueries.coerceSelectionOffset(result, 6, SourceBoundaryBias.Backward));
        TracedAssertions.assertEqualsInt(9, LayoutQueries.coerceSelectionOffset(result, 6, SourceBoundaryBias.Forward));
    }

    @:test
    public static function supportedSourceSequenceRemainsAtomicAcrossEngineClusterBoundaries():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("supportedSourceSequenceRemainsAtomicAcrossEngineClusterBoundaries");
        final result:LayoutResult = LayoutQueriesTestHelpers.crossClusterInteractionBoundaryResult();
        TracedAssertions.assertEqualsInt(0, LayoutQueries.coerceSelectionOffset(result, 1, SourceBoundaryBias.Backward));
        TracedAssertions.assertEqualsInt(2, LayoutQueries.coerceSelectionOffset(result, 1, SourceBoundaryBias.Forward));
        TracedAssertions.assertEqualsInt(0, LayoutQueries.getSelectionOffsetForPosition(result, 8.0, 10.0));
        TracedAssertions.assertEqualsInt(2, LayoutQueries.getSelectionOffsetForPosition(result, 12.0, 10.0));
    }

    @:test
    public static function inlineObjectSourceRangeIsOneSelectionUnit():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("inlineObjectSourceRangeIsOneSelectionUnit");
        final source:String = "a\\operatorname{lim}b";
        final objectRange:TextRange = new TextRange(1, source.length - 1);
        final object:InlineObjectSpan = new InlineObjectSpan(objectRange, 40.0, 12.0, 4.0, InlineObjectBoundaryAdjustment.fixed(),
            InlineObjectBoundaryAdjustment.fixed());
        final result:LayoutResult = LayoutQueriesTestHelpers.result(source, 200.0, null, new Size(60.0, 20.0), [], [], [],
            LayoutQueriesTestHelpers.emptyDebug(), [object]);
        TracedAssertions.assertEqualsInt(1, LayoutQueries.coerceSelectionOffset(result, 5, SourceBoundaryBias.Backward));
        TracedAssertions.assertEqualsInt(objectRange.end, LayoutQueries.coerceSelectionOffset(result, 5, SourceBoundaryBias.Forward));
        TracedAssertions.assertEqualsInt(1, LayoutQueries.coerceSelectionOffset(result, 5, SourceBoundaryBias.Nearest));
        TracedAssertions.assertEqualsInt(objectRange.end, LayoutQueries.coerceSelectionOffset(result, objectRange.end - 1, SourceBoundaryBias.Nearest));
        TracedAssertions.assertEqualsRendered(objectRange.toString(), LayoutQueries.getSelectionWordBoundary(result, 5).toString());
    }

    @:test
    public static function selectionWordBoundaryExpandsLatinButKeepsHanAtomic():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("selectionWordBoundaryExpandsLatinButKeepsHanAtomic");
        final result:LayoutResult = LayoutQueriesTestHelpers.wordBoundaryResult();
        TracedAssertions.assertEqualsRendered(new TextRange(2, 10).toString(), LayoutQueries.getSelectionWordBoundary(result, 6).toString());
        TracedAssertions.assertEqualsRendered(new TextRange(0, 1).toString(), LayoutQueries.getSelectionWordBoundary(result, 0).toString());
        TracedAssertions.assertEqualsRendered(new TextRange(1, 2).toString(), LayoutQueries.getSelectionWordBoundary(result, 1).toString());
        TracedAssertions.assertEqualsRendered(new TextRange(11, 12).toString(), LayoutQueries.getSelectionWordBoundary(result, 12).toString());
        final first:Null<TextRange> = LayoutQueries.getSelectionWordBoundaryForPosition(result, 5.0, 10.0);
        final second:Null<TextRange> = LayoutQueries.getSelectionWordBoundaryForPosition(result, 60.0, 10.0);
        TracedAssertions.assertEqualsRendered(new TextRange(0, 1).toString(), first == null ? "null" : first.toString());
        TracedAssertions.assertEqualsRendered(new TextRange(2, 10).toString(), second == null ? "null" : second.toString());
    }

    @:test
    public static function rubySelectionGeometryRedistributesAvoidanceSpreadWithoutOverlap():Void {
        new TestTraceRecorder("LayoutQueriesTest").section("rubySelectionGeometryRedistributesAvoidanceSpreadWithoutOverlap");
        final result:LayoutResult = LayoutQueriesTestHelpers.rubySelectionResult();
        final positioned:Array<PositionedCluster> = LayoutQueries.positionedClusters(result);
        TracedAssertions.assertEqualsRendered(new Rect(-6.0, 0.0, 26.0, 20.0).toString(), positioned[0].rect.toString());
        TracedAssertions.assertEqualsRendered(new Rect(29.0, 0.0, 61.0, 20.0).toString(), positioned[1].rect.toString());
        TracedAssertions.assertEqualsRendered(new Rect(64.0, 0.0, 96.0, 20.0).toString(), positioned[2].rect.toString());
        var noOverlap:Bool = true;
        var index:Int = 0;
        while (index + 1 < positioned.length) {
            if (!(positioned[index].right <= positioned[index + 1].left)) {
                noOverlap = false;
            }
            index += 1;
        }
        TracedAssertions.assertTrue(noOverlap, "ruby selection rects must not overlap: " + LayoutQueriesTestHelpers.renderPositioned(positioned));
        final first:Array<Rect> = LayoutQueries.getBoundingBoxes(result, new TextRange(0, 1));
        final second:Array<Rect> = LayoutQueries.getBoundingBoxes(result, new TextRange(1, 2));
        TracedAssertions.assertEqualsRendered(new Rect(-6.0, 0.0, 26.0, 20.0).toString(), first[0].toString());
        TracedAssertions.assertEqualsRendered(new Rect(29.0, 0.0, 61.0, 20.0).toString(), second[0].toString());
    }
}

class LayoutQueriesTestHelpers {
    public static function content(text:String):TiqianTextContent {
        return new TiqianTextContent(text, [], [], [], []);
    }

    public static function style(fontSize:Float):TextStyle {
        return new TextStyle([], fontSize, "zh-Hans", 400, false, 0.0, InlineAttachment.None);
    }

    public static function constraints(maxWidth:Float):LayoutConstraints {
        return new LayoutConstraints(maxWidth, Math.POSITIVE_INFINITY, 2147483647);
    }

    public static function input(text:String, maxWidth:Float, textStyle:Null<TextStyle>, inlineObjects:Null<Array<InlineObjectSpan>>):LayoutInput {
        return new LayoutInput(LayoutQueriesTestHelpers.content(text), textStyle,
            new ParagraphStyle(LastLineAlignment.Start, WritingMode.HorizontalTb, null, null, Ic.Zero, new MeasureAdaptiveFirstLineIndent(14.0, 1.0, 2.0),
                new LineLengthGrid(true, null), RubyLineHeightMode.PerLine, ParagraphStyle.DEFAULT_INLINE_OBJECT_MINIMUM_CLEARANCE_EM,
                ParagraphStyle.DEFAULT_EMPHASIS_DOT_GAP_EM),
            LayoutQueriesTestHelpers.constraints(maxWidth), BuiltInLayoutProfiles.ClreqHorizontal, [], [], [], inlineObjects);
    }

    public static function cluster(range:TextRange, text:String, fontKey:String, advance:Float):Cluster {
        return new Cluster(range, text, fontKey, advance, (text), 0.0, 0.0, 0.0);
    }

    public static function line(range:TextRange, clusterStart:Int, clusterEnd:Int, baseline:Float, top:Float, bottom:Float, naturalWidth:Float,
            adjustedWidth:Float, visualWidth:Float, indent:Null<Float>):LineBox {
        return new LineBox(range, new IntRange(clusterStart, clusterEnd), baseline, top, bottom, naturalWidth, adjustedWidth, visualWidth, 0.0, indent,
            LineEndReason.ParagraphEnd, 0.0, [], new LineDebugInfo(null, []));
    }

    public static function result(text:String, maxWidth:Float, textStyle:Null<TextStyle>, size:Size, clusters:Array<Cluster>, glyphRuns:Array<GlyphRun>,
            lines:Array<LineBox>, debug:Null<LayoutDebugInfo>, inlineObjects:Null<Array<InlineObjectSpan>>):LayoutResult {
        return new LayoutResult(LayoutQueriesTestHelpers.input(text, maxWidth, textStyle, inlineObjects), size, clusters, glyphRuns, lines,
            debug == null ? LayoutQueriesTestHelpers.emptyDebug() : debug);
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

    public static function renderPositioned(values:Array<PositionedCluster>):String {
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

    public static function sampleResult():LayoutResult {
        final text:String = "甲——乙";
        final dashRange:TextRange = new TextRange(1, 3);
        return LayoutQueriesTestHelpers.result(text, 40.0, LayoutQueriesTestHelpers.style(10.0), new Size(34.0, 40.0), [
            LayoutQueriesTestHelpers.cluster(new TextRange(0, 1), "甲", "cjk", 10.0),
            new Cluster(dashRange, "——", "cjk", 20.0, "⸺", 0.0, 0.0, 0.0),
            LayoutQueriesTestHelpers.cluster(new TextRange(3, 4), "乙", "cjk", 10.0)
        ], [], [
            LayoutQueriesTestHelpers.line(new TextRange(0, 3), 0, 1, 15.0, 0.0, 20.0, 30.0, 30.0, 30.0, 4.0),
            LayoutQueriesTestHelpers.line(new TextRange(3, 4), 2, 2, 35.0, 20.0, 40.0, 10.0, 10.0, 10.0, null)
        ], null, null);
    }

    public static function backgroundGeometryResult():LayoutResult {
        final text:String = "A B";
        final glyphA:Glyph = new Glyph(1, new TextRange(0, 1), 10.0, 0.0, 0.0, null, null, null, null);
        final glyphB:Glyph = new Glyph(2, new TextRange(2, 3), 10.0, 0.0, 0.0, null, null, null, null);
        final glyphRuns:Array<GlyphRun> = [
            new GlyphRun(new TextRange(0, 1), "latin", [glyphA], 10.0, []),
            new GlyphRun(new TextRange(2, 3), "latin", [glyphB], 10.0, [])
        ];
        final autoSpace:AutoSpaceDecisionInfo = new AutoSpaceDecisionInfo(new TextRange(2, 3), "leading", "CjkLatin", "Insert", 1, -2.0, -2.0,
            "test-leading-gap");
        return LayoutQueriesTestHelpers.result(text, 31.0, LayoutQueriesTestHelpers.style(10.0), new Size(31.0, 30.0), [
            LayoutQueriesTestHelpers.cluster(new TextRange(0, 1), "A", "latin", 12.0),
            LayoutQueriesTestHelpers.cluster(new TextRange(1, 2), " ", "latin", 5.0),
            LayoutQueriesTestHelpers.cluster(new TextRange(2, 3), "B", "latin", 14.0)
        ], glyphRuns, [
            LayoutQueriesTestHelpers.line(new TextRange(0, 3), 0, 2, 20.0, 0.0, 30.0, 31.0, 31.0, 31.0, null)
        ], new LayoutDebugInfo(null, [], [], [autoSpace], [], []), null);
    }

    public static function backgroundMetric(range:TextRange, metricBox:String, ascent:Float, descent:Float):MetricDecisionInfo {
        return new MetricDecisionInfo(range, "test", "test", "test", ascent, descent, 0.0, "test", ascent, descent, "test", metricBox, "test", "test");
    }

    public static function punctuationGlueResult():LayoutResult {
        final text:String = "（，中）";
        final geometries:Array<ClusterGeometryDecisionInfo> = [
            LayoutQueriesTestHelpers.punctuationGeometry(new TextRange(0, 1), "（", 5.0, 0.0, 0.0, 0.0),
            LayoutQueriesTestHelpers.punctuationGeometry(new TextRange(1, 2), "，", 0.0, 5.0, 0.0, 0.0),
            LayoutQueriesTestHelpers.punctuationGeometry(new TextRange(2, 3), "中", 0.0, 0.0, 0.0, 0.0),
            LayoutQueriesTestHelpers.punctuationGeometry(new TextRange(3, 4), "）", 0.0, 5.0, 0.0, 0.0)
        ];
        return LayoutQueriesTestHelpers.result(text, 40.0, LayoutQueriesTestHelpers.style(10.0), new Size(40.0, 20.0), [
            LayoutQueriesTestHelpers.cluster(new TextRange(0, 1), "（", "cjk", 10.0),
            LayoutQueriesTestHelpers.cluster(new TextRange(1, 2), "，", "cjk", 10.0),
            LayoutQueriesTestHelpers.cluster(new TextRange(2, 3), "中", "cjk", 10.0),
            LayoutQueriesTestHelpers.cluster(new TextRange(3, 4), "）", "cjk", 10.0)
        ], [], [
            LayoutQueriesTestHelpers.line(new TextRange(0, 4), 0, 3, 15.0, 0.0, 20.0, 40.0, 40.0, 40.0, null)
        ], new LayoutDebugInfo(null, [], geometries, [], [], []), null);
    }

    public static function interactionBoundaryResult():LayoutResult {
        final text:String = TestHelpers.surrogateText([0xD83D, 0xDE00]) + "e\u0301" + TestHelpers.surrogateText([0xD83D, 0xDC69, 0x200D, 0xD83D, 0xDC69]);
        return LayoutQueriesTestHelpers.result(text, 90.0, LayoutQueriesTestHelpers.style(10.0), new Size(90.0, 20.0), [
            LayoutQueriesTestHelpers.cluster(new TextRange(0, 2), TestHelpers.surrogateText([0xD83D, 0xDE00]), "emoji", 20.0),
            LayoutQueriesTestHelpers.cluster(new TextRange(2, 4), "e\u0301", "latin", 20.0),
            LayoutQueriesTestHelpers.cluster(new TextRange(4, 9), TestHelpers.surrogateText([0xD83D, 0xDC69, 0x200D, 0xD83D, 0xDC69]), "emoji", 50.0)
        ], [], [
            LayoutQueriesTestHelpers.line(new TextRange(0, 9), 0, 2, 15.0, 0.0, 20.0, 90.0, 90.0, 90.0, null)
        ], null, null);
    }

    public static function wordBoundaryResult():LayoutResult {
        final text:String = "前 template 后";
        return LayoutQueriesTestHelpers.result(text, 120.0, LayoutQueriesTestHelpers.style(10.0), new Size(120.0, 20.0), [
            LayoutQueriesTestHelpers.cluster(new TextRange(0, 1), "前", "cjk", 10.0),
            LayoutQueriesTestHelpers.cluster(new TextRange(1, 2), " ", "latin", 10.0),
            LayoutQueriesTestHelpers.cluster(new TextRange(2, 10), "template", "latin", 80.0),
            LayoutQueriesTestHelpers.cluster(new TextRange(10, 11), " ", "latin", 10.0),
            LayoutQueriesTestHelpers.cluster(new TextRange(11, 12), "后", "cjk", 10.0)
        ], [], [
            LayoutQueriesTestHelpers.line(new TextRange(0, 12), 0, 4, 15.0, 0.0, 20.0, 120.0, 120.0, 120.0, null)
        ], null, null);
    }

    public static function crossClusterInteractionBoundaryResult():LayoutResult {
        final text:String = "e\u0301";
        return LayoutQueriesTestHelpers.result(text, 20.0, LayoutQueriesTestHelpers.style(10.0), new Size(20.0, 20.0), [
            LayoutQueriesTestHelpers.cluster(new TextRange(0, 1), "e", "latin", 10.0),
            LayoutQueriesTestHelpers.cluster(new TextRange(1, 2), "\u0301", "latin", 10.0)
        ], [], [
            LayoutQueriesTestHelpers.line(new TextRange(0, 2), 0, 1, 15.0, 0.0, 20.0, 20.0, 20.0, 20.0, null)
        ], null, null);
    }

    public static function punctuationGeometry(range:TextRange, text:String, leadingGlue:Float, trailingGlue:Float, leadingConsumed:Float,
            trailingConsumed:Float):ClusterGeometryDecisionInfo {
        return new ClusterGeometryDecisionInfo(range, text, text, 10.0, 10.0 - leadingGlue - trailingGlue, leadingGlue, leadingConsumed, trailingGlue,
            trailingConsumed, 0.0, 10.0, "test", "PunctuationGlueTest", 0.0, 0.0, null);
    }

    public static function rubySelectionResult():LayoutResult {
        final text:String = "张王李";
        final glyphs:Array<Glyph> = [
            new Glyph(1, new TextRange(0, 1), 20.0, 0.0, 0.0, null, null, null, null),
            new Glyph(2, new TextRange(1, 2), 20.0, 0.0, 0.0, null, null, null, null),
            new Glyph(3, new TextRange(2, 3), 20.0, 0.0, 0.0, null, null, null, null)
        ];
        final rubies:Array<RubyDecisionInfo> = [
            new RubyDecisionInfo(new TextRange(0, 1), "zhuāng", 0, 10.0, 0.0, 10.0, 6.0, 0.0, 0.0, 32.0, [], 400, "zh-Hans", []),
            new RubyDecisionInfo(new TextRange(1, 2), "chuáng", 0, 45.0, 0.0, 10.0, 6.0, 0.0, 0.0, 32.0, [], 400, "zh-Hans", []),
            new RubyDecisionInfo(new TextRange(2, 3), "shuāng", 0, 80.0, 0.0, 10.0, 6.0, 0.0, 0.0, 32.0, [], 400, "zh-Hans", [])
        ];
        final geometries:Array<ClusterGeometryDecisionInfo> = [
            LayoutQueriesTestHelpers.rubyGeometry(new TextRange(0, 1), "张", 15.0, 35.0),
            LayoutQueriesTestHelpers.rubyGeometry(new TextRange(1, 2), "王", 15.0, 35.0),
            LayoutQueriesTestHelpers.rubyGeometry(new TextRange(2, 3), "李", 0.0, 20.0)
        ];
        return LayoutQueriesTestHelpers.result(text, 200.0, LayoutQueriesTestHelpers.style(20.0), new Size(90.0, 20.0), [
            LayoutQueriesTestHelpers.cluster(new TextRange(0, 1), "张", "cjk", 35.0),
            LayoutQueriesTestHelpers.cluster(new TextRange(1, 2), "王", "cjk", 35.0),
            LayoutQueriesTestHelpers.cluster(new TextRange(2, 3), "李", "cjk", 20.0)
        ], [new GlyphRun(new TextRange(0, 3), "cjk", glyphs, 60.0, [])], [
            LayoutQueriesTestHelpers.line(new TextRange(0, 3), 0, 2, 15.0, 0.0, 20.0, 60.0, 90.0, 90.0, null)
        ], new LayoutDebugInfo(null, [], geometries, [], rubies, []), null);
    }

    public static function rubyGeometry(range:TextRange, text:String, rubySpread:Float, resolvedAdvance:Float):ClusterGeometryDecisionInfo {
        return new ClusterGeometryDecisionInfo(range, text, text, 20.0, 20.0, 0.0, 0.0, 0.0, 0.0, 0.0, resolvedAdvance, "test", "RubyAvoidanceSpread",
            rubySpread, 0.0, null);
    }

    public static function segmentFor(span:RichTextSpan, start:Int, end:Int):RichTextLineSegment {
        return new RichTextLineSegment(span, 0, new TextRange(start, end), 0.0, 0.0, 40.0, 20.0, 16.0);
    }

    public static function sameRange(first:TextRange, second:TextRange):Bool {
        return first.start == second.start && first.end == second.end;
    }

    public static function copyResultWithDebug(original:LayoutResult, debug:LayoutDebugInfo):LayoutResult {
        return new LayoutResult(original.input, original.size, original.clusters, original.glyphRuns, original.lines, debug);
    }
}
