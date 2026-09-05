package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.font.BaselinePolicy;
import org.tiqian.font.FontMetrics.FontMetricsRequest;
import org.tiqian.font.FontMetricsPolicy;
import org.tiqian.font.FontRole;
import org.tiqian.font.LayoutFontMetrics;
import org.tiqian.font.RawFontMetrics;
import org.tiqian.layout.AnnotationGeometryStage.RubyFontGeometry;
import org.tiqian.layout.LineGeometryStage.ClusterMetricDecision;
import org.tiqian.layout.LineOptimization.LineCandidate;
import org.tiqian.layout.LineOptimization.LineSolution;
import org.tiqian.layout.AnnotationGeometryStageCoverageTestSupport.InkBoundsTextShaper;
import org.tiqian.layout.AnnotationGeometryStageCoverageTestSupport.MultiGlyphBoundsShaper;
import org.tiqian.layout.AnnotationGeometryStageCoverageTestSupport.MultiGlyphMinMaxShaper;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TestTraceRender;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedMap;
import std.UString;

class AnnotationGeometryStageCoverageTest {
    @:test public static function inlineObjectDecisionsWithPreferredStretchAndFixed():Void {
        final r = new TestTraceRecorder("AnnotationGeometryStageCoverageTest");
        r.section("inlineObjectDecisionsWithPreferredStretchAndFixed");
        final engine = new ExplainableStubParagraphLayoutEngine();
        final text = "\u524D\u7F6E\u6587\u672C\u3010\u5D4C\u5165\u5BF9\u8C61\u3011\u540E\u7F6E\u6587\u672C";
        final objWithStretch = new InlineObjectSpan(new TextRange(4, 5), 30.0, 12.0, 4.0,
            new InlineObjectBoundaryAdjustment(true, new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.PunctuationTrailing, 10.0, 15.0), null,
                null, true),
            new InlineObjectBoundaryAdjustment(true, new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.Relation, 10.0, 20.0), 3.0, 2.0, false));
        final objFixed = new InlineObjectSpan(new TextRange(6, 7), 20.0, 10.0, 2.0, InlineObjectBoundaryAdjustment.fixed(),
            InlineObjectBoundaryAdjustment.fixed());
        final input = new LayoutInput(new TiqianTextContent(text), null, null, new LayoutConstraints(300.0), null, null, null, null,
            [objWithStretch, objFixed]);
        final result = engine.layout(input);
        TracedAssertions.assertNotNullRendered(result != null, result == null ? "null" : TestTraceRender.cap(Std.string(result)));
        TracedAssertions.assertTrue(result.lines.length > 0);
    }

    @:test public static function decorationDecisionsEmphasisOnHanPunctuationAndWestern():Void {
        final r = new TestTraceRecorder("AnnotationGeometryStageCoverageTest");
        r.section("decorationDecisionsEmphasisOnHanPunctuationAndWestern");
        final engine = new ExplainableStubParagraphLayoutEngine();
        final text = "\u6C49\u5B57\uFF0C\u3002English";
        final input = new LayoutInput(new TiqianTextContent("\u6C49\u5B57\uFF0C\u3002English"), null,
            new ParagraphStyle(null, null, null, null, null, null, null, null, null, 0.2), new LayoutConstraints(300.0), null,
            [new DecorationSpan(new TextRange(0, 11), DecorationKind.Emphasis)]);
        final result = engine.layout(input);
        TracedAssertions.assertNotNullRendered(result != null, result == null ? "null" : TestTraceRender.cap(Std.string(result)));
    }

    @:test public static function decorationSegmentsMourningProperNounBookTitleAndShortening():Void {
        final r = new TestTraceRecorder("AnnotationGeometryStageCoverageTest");
        r.section("decorationSegmentsMourningProperNounBookTitleAndShortening");
        final engine = new ExplainableStubParagraphLayoutEngine();
        final text = "\u5F20\u4E09\u674E\u56DB\u738B\u4E94\u8D75\u516D\u94B1\u4E03\u5B59\u516B\u5468\u5434\u90D1\u738B";
        final input = new LayoutInput(new TiqianTextContent("\u5F20\u4E09\u674E\u56DB\u738B\u4E94\u8D75\u516D\u94B1\u4E03\u5B59\u516B\u5468\u5434\u90D1\u738B"),
            null, null,
            new LayoutConstraints(120.0), null, [
                new DecorationSpan(new TextRange(0, 2), DecorationKind.ProperNoun),
                new DecorationSpan(new TextRange(2, 4), DecorationKind.ProperNoun),
                new DecorationSpan(new TextRange(4, 8), DecorationKind.BookTitle),
                new DecorationSpan(new TextRange(8, 12), DecorationKind.Mourning),
                new DecorationSpan(new TextRange(0, 16), DecorationKind.Mourning)
            ]);
        final result = engine.layout(input);
        TracedAssertions.assertNotNullRendered(result != null, result == null ? "null" : TestTraceRender.cap(Std.string(result)));
    }

    @:test public static function decorationSegmentsLeadingAndTrailingBlanks():Void {
        final r = new TestTraceRecorder("AnnotationGeometryStageCoverageTest");
        r.section("decorationSegmentsLeadingAndTrailingBlanks");
        final engine = new ExplainableStubParagraphLayoutEngine();
        final text = "\u300C\u5F00\u5934\u300D\u4E2D\u6587 English \u6DF7\u6392\u3010\u7ED3\u675F\u3011";
        final input = new LayoutInput(new TiqianTextContent(text), null, null, new LayoutConstraints(150.0), null, [
            new DecorationSpan(new TextRange(0, UString.count(text)), DecorationKind.ProperNoun)
        ]);
        final result = engine.layout(input);
        TracedAssertions.assertNotNullRendered(result != null, result == null ? "null" : TestTraceRender.cap(Std.string(result)));
    }

    @:test public static function rubyDecisionsPinyinSingleAndSplitLines():Void {
        final r = new TestTraceRecorder("AnnotationGeometryStageCoverageTest");
        r.section("rubyDecisionsPinyinSingleAndSplitLines");
        final engine = new ExplainableStubParagraphLayoutEngine();
        final text = "\u8FD9\u662F\u4E00\u4E2A\u5F88\u957F\u5F88\u957F\u7684\u6BB5\u843D\u7528\u4E8E\u6D4B\u8BD5\u62FC\u97F3\u884C\u95F4\u6CE8\u8DE8\u884C";
        final input = new LayoutInput(new TiqianTextContent(text), null, null, new LayoutConstraints(100.0), null, null, [
            new RubySpan(new TextRange(0, 2), "zh\u00E8sh\u00EC", null, RubyKind.Pinyin, "zh-Latn"),
            new RubySpan(new TextRange(2, 6), "y\u012Bgeh\u011Bnch\u00E1ng", null, RubyKind.Pinyin, null),
            new RubySpan(new TextRange(6, 12), "ch\u00E1ngdedu\u00E0nlu\u00F2", null, RubyKind.Pinyin, null)
        ]);
        final result = engine.layout(input);
        TracedAssertions.assertNotNullRendered(result != null, result == null ? "null" : TestTraceRender.cap(Std.string(result)));
    }

    @:test public static function bopomofoDecisionsAllTonesAndSymbolCounts():Void {
        final r = new TestTraceRecorder("AnnotationGeometryStageCoverageTest");
        r.section("bopomofoDecisionsAllTonesAndSymbolCounts");
        final engine = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, new InkBoundsTextShaper());
        final text = "\u4E00\u4E8C\u4E09\u56DB\u4E94\u516D\u4E03\u516B\u4E5D\u5341\u7532\u4E59\u4E19\u4E01\u620A\u5DF1\u5E9A\u8F9B";
        final rubySpans = [
            new RubySpan(new TextRange(0, 1), "\u02D9\u3105", null, RubyKind.Bopomofo, "zh-Bopo"),
            new RubySpan(new TextRange(1, 2), "\u02D9\u3105\u3106", null, RubyKind.Bopomofo, null),
            new RubySpan(new TextRange(2, 3), "\u02D9\u3105\u3106\u3107", null, RubyKind.Bopomofo, null),
            new RubySpan(new TextRange(3, 4), "\u3105\u02CA", null, RubyKind.Bopomofo, null),
            new RubySpan(new TextRange(4, 5), "\u3105\u3106\u02CA", null, RubyKind.Bopomofo, null),
            new RubySpan(new TextRange(5, 6), "\u3105\u3106\u3107\u02CA", null, RubyKind.Bopomofo, null),
            new RubySpan(new TextRange(6, 7), "\u3105\u02C7", null, RubyKind.Bopomofo, null),
            new RubySpan(new TextRange(7, 8), "\u3105\u3106\u02C7", null, RubyKind.Bopomofo, null),
            new RubySpan(new TextRange(8, 9), "\u3105\u3106\u3107\u02C7", null, RubyKind.Bopomofo, null),
            new RubySpan(new TextRange(9, 10), "\u3105\u02CB", null, RubyKind.Bopomofo, null),
            new RubySpan(new TextRange(10, 11), "\u3105\u3106\u02CB", null, RubyKind.Bopomofo, null),
            new RubySpan(new TextRange(11, 12), "\u3105\u3106\u3107\u02CB", null, RubyKind.Bopomofo, null),
            new RubySpan(new TextRange(12, 13), "\u3105", null, RubyKind.Bopomofo, null),
            new RubySpan(new TextRange(13, 14), "\u3105\u3106", null, RubyKind.Bopomofo, null),
            new RubySpan(new TextRange(14, 15), "\u3105\u3106\u3107", null, RubyKind.Bopomofo, null)
        ];
        final input = new LayoutInput(new TiqianTextContent(text), null, null, new LayoutConstraints(300.0), null, null, rubySpans);
        final result = engine.layout(input);
        TracedAssertions.assertNotNullRendered(result != null, result == null ? "null" : TestTraceRender.cap(Std.string(result)));
    }

    @:test public static function directResolveAnnotationGeometryFallbackBranches():Void {
        final r = new TestTraceRecorder("AnnotationGeometryStageCoverageTest");
        r.section("directResolveAnnotationGeometryFallbackBranches");
        final engine = new ExplainableStubParagraphLayoutEngine();
        final text = "\u6C49\u5B57\uFF0C\u6D4B\u8BD5English";
        final input = new LayoutInput(new TiqianTextContent(text), null, null, new LayoutConstraints(300.0), null, [
             new DecorationSpan(new TextRange(0, 2), DecorationKind.Emphasis), new DecorationSpan(new TextRange(2, 3), DecorationKind.Emphasis),
            new DecorationSpan(new TextRange(5, 12), DecorationKind.Emphasis), new DecorationSpan(new TextRange(0, 4), DecorationKind.ProperNoun)
        ]);
        final clusters = [
            new Cluster(new TextRange(0, 2), "\u6C49\u5B57", "k", 32.0, "\u6C49\u5B57"),
            new Cluster(new TextRange(2, 3), "\uFF0C", "k", 16.0, "\uFF0C"),
            new Cluster(new TextRange(3, 5), "\u6D4B\u8BD5", "k", 32.0, "\u6D4B\u8BD5"),
            new Cluster(new TextRange(5, 12), "English", "k", 56.0, "English")
        ];
        final lineBoxes = [
            new LineBox(new TextRange(0, 5), new IntRange(0, 2), 16.0, 0.0, 20.0, 80.0, 80.0, 80.0, null, 0.0, LineEndReason.AutoWrap, null, null,
                new LineDebugInfo(null)),
            new LineBox(new TextRange(5, 12), new IntRange(3, 3), 36.0, 20.0, 40.0, 56.0, 56.0, 56.0, null, 0.0, LineEndReason.MandatoryBreak, null, null,
                new LineDebugInfo(null))
        ];
        final lineSolution = new LineSolution([
            new LineCandidate(new IntRange(0, 2), new TextRange(0, 5), 80.0, 80.0, LineEndReason.AutoWrap),
            new LineCandidate(new IntRange(3, 3), new TextRange(5, 12), 56.0, 56.0, LineEndReason.MandatoryBreak)
        ]);
        final clreqProfile = engine.clreqProfileResolver.resolve(input.profileId);
        final inlineObject1 = new InlineObjectSpan(new TextRange(0, 2), 32.0, 12.0, 4.0,
            new InlineObjectBoundaryAdjustment(null, new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.PunctuationTrailing, 10.0, 15.0)));
        final inlineObject2 = new InlineObjectSpan(new TextRange(5, 12), 56.0, 12.0, 4.0, null,
            new InlineObjectBoundaryAdjustment(null, new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.Relation, 10.0, 20.0)));
        final inlineObjectNotInLine = new InlineObjectSpan(new TextRange(99, 100), 10.0, 8.0, 2.0);
        final geomDecision = new ClusterGeometryDecisionInfo(new TextRange(0, 2), "\u6C49\u5B57", "\u6C49\u5B57", 32.0, 32.0, 4.0, 2.0, 4.0, 2.0, 0.0, 32.0,
            "test", "test");
        final inlineObjMapBuilder = SortedMap.builder();
        inlineObjMapBuilder.put(0, inlineObject1);
        inlineObjMapBuilder.put(3, inlineObject2);
        inlineObjMapBuilder.put(99, inlineObjectNotInLine);
        final inlineObjMap = inlineObjMapBuilder.build();
        final justifyBuilder = SortedMap.builder();
        justifyBuilder.put(0, 2.0);
        final justifyMap = justifyBuilder.build();
        final spreadBuilder = SortedMap.builder();
        spreadBuilder.put(0, 4.0);
        final spreadMap = spreadBuilder.build();
        final pinyinA = new RubySpan(new TextRange(0, 2), "h\u00E0nz\u00EC", null, RubyKind.Pinyin, "zh-Latn");
        final pinyinB = new RubySpan(new TextRange(3, 5), "c\u00E8sh\u00EC", null, RubyKind.Pinyin, null);
        final rfgBuilder = SortedMap.builder();
        rfgBuilder.put(pinyinA, new RubyFontGeometry(20.0, 8.0, 2.0, 10.0, []));
        rfgBuilder.put(pinyinB, new RubyFontGeometry(20.0, 8.0, 2.0, 10.0, []));
        final rfgMap = rfgBuilder.build();
        final res1 = LineAdjustmentStage.resolveAnnotationGeometry(engine, input, 16.0, inlineObjMap, lineSolution, clreqProfile, [geomDecision], [
            new AutoSpaceDecisionInfo(new TextRange(0, 2), "leading", "Wide", "Normal", 1, 0.0, 0.0, "test"),
            new AutoSpaceDecisionInfo(new TextRange(2, 3), "leading", "Wide", "Normal", 1, 0.0, 0.0, "test"),
            new AutoSpaceDecisionInfo(new TextRange(3, 5), "trailing", "Wide", "Normal", 1, 0.0, 0.0, "test"),
            new AutoSpaceDecisionInfo(new TextRange(5, 12), "trailing", "Wide", "Normal", 1, 0.0, 0.0, "test")
        ],
            [new IntRange(0, 2), new IntRange(3, 3)], lineBoxes, clusters, [FontRole.CjkText, FontRole.CjkPunctuation, FontRole.CjkText, FontRole.LatinText],
            justifyMap, spreadMap, [], [pinyinA, pinyinB], clusters, rfgMap, 0.0, 16.0, 8.0, 400, 4.0, function(_:Int) return 400);
        TracedAssertions.assertNotNullRendered(res1 != null, res1 == null ? "null" : TestTraceRender.cap(Std.string(res1)));
        TracedAssertions.assertEquals(3, res1.inlineObjectDecisions.length);
        TracedAssertions.assertEquals(-1, res1.inlineObjectDecisions[res1.inlineObjectDecisions.length - 1].lineIndex);
        final metricDecision = new ClusterMetricDecision(new TextRange(0, 2), "\u6C49\u5B57", new FontMetricsRequest("k", 16.0, FontRole.CjkText, "zh-Hans"),
            new RawFontMetrics(14.0, 4.0), new LayoutFontMetrics(14.0, 4.0, 0.0, FontMetricsPolicy.Raw, BaselinePolicy.Alphabetic));
        final pinyinC = new RubySpan(new TextRange(0, 2), "h\u00E0nz\u00EC", null, RubyKind.Pinyin, null);
        final rfgBuilder2 = SortedMap.builder();
        rfgBuilder2.put(pinyinC, new RubyFontGeometry(20.0, 8.0, 2.0, 10.0, []));
        final rfgMap2 = rfgBuilder2.build();
        final res2 = LineAdjustmentStage.resolveAnnotationGeometry(engine, input, 16.0, SortedMap.builder().build(), lineSolution, clreqProfile, [], [],
            [new IntRange(0, 2), new IntRange(3, 3)], lineBoxes, clusters, [FontRole.CjkText, FontRole.CjkPunctuation, FontRole.CjkText, FontRole.LatinText],
            SortedMap.builder().build(), SortedMap.builder().build(), [metricDecision], [pinyinC], clusters, rfgMap2, 0.0, 16.0, 8.0, 400, 4.0,
            function(_:Int) return 400);
        TracedAssertions.assertNotNullRendered(res2 != null, res2 == null ? "null" : TestTraceRender.cap(Std.string(res2)));
    }

    @:test public static function bopomofoDecisionsMultiGlyphMinMaxAndEmptyPlacements():Void {
        final r = new TestTraceRecorder("AnnotationGeometryStageCoverageTest");
        r.section("bopomofoDecisionsMultiGlyphMinMaxAndEmptyPlacements");
        final engine = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, new MultiGlyphMinMaxShaper());
        final text = "\u4E00\u4E8C\u4E09\u56DB\u4E94\u516D\u4E03\u516B";
        final rubySpans = [
            new RubySpan(new TextRange(0, 2), "\u3105\u3106\u02CA", null, RubyKind.Bopomofo,
                "zh-Bopo"),            new RubySpan(new TextRange(2, 3), " ", null, RubyKind.Bopomofo,
                null),     new RubySpan(new TextRange(3, 4), "\u3105", null, RubyKind.Bopomofo, null),
                       new RubySpan(new TextRange(4, 5), "\u02D9\u3105", null, RubyKind.Bopomofo,
                null), new RubySpan(new TextRange(5, 6), "\u3105\u02C7", null, RubyKind.Bopomofo,
                null), new RubySpan(new TextRange(6, 7), "\u3105\u02CB", null, RubyKind.Bopomofo, null)
        ];
        final input = new LayoutInput(new TiqianTextContent(text), null, null, new LayoutConstraints(300.0), null, null, rubySpans);
        final result = engine.layout(input);
        TracedAssertions.assertNotNullRendered(result != null, result == null ? "null" : TestTraceRender.cap(Std.string(result)));
    }

    @:test public static function directResolveAnnotationGeometryEmptyLineRangesAndGapAtLineEdges():Void {
        final r = new TestTraceRecorder("AnnotationGeometryStageCoverageTest");
        r.section("directResolveAnnotationGeometryEmptyLineRangesAndGapAtLineEdges");
        final engine = new ExplainableStubParagraphLayoutEngine();
        final text = "\u6C49\u5B57\uFF0C\u6D4B\u8BD5English";
        final input = new LayoutInput(new TiqianTextContent(text), null, null, new LayoutConstraints(300.0), null, [
            new DecorationSpan(new TextRange(0, 2), DecorationKind.Emphasis),
            new DecorationSpan(new TextRange(0, 5), DecorationKind.ProperNoun)
        ]);
        final clusters = [
            new Cluster(new TextRange(0, 2), "\u6C49\u5B57", "k", 32.0, "\u6C49\u5B57"),
            new Cluster(new TextRange(2, 3), "\uFF0C", "k", 16.0, "\uFF0C"),
            new Cluster(new TextRange(3, 5), "\u6D4B\u8BD5", "k", 32.0, "\u6D4B\u8BD5"),
            new Cluster(new TextRange(5, 12), "English", "k", 56.0, "English")
        ];
        final lineBoxes = [
            new LineBox(new TextRange(0, 0), new IntRange(1, 0), 0.0, 0.0, 20.0, 0.0, 0.0, 0.0, null, 0.0, LineEndReason.AutoWrap, null, null,
                new LineDebugInfo(null)),
            new LineBox(new TextRange(0, 5), new IntRange(0, 2), 16.0, 0.0, 20.0, 80.0, 80.0, 80.0, null, 0.0, LineEndReason.AutoWrap, null, null,
                new LineDebugInfo(null))
        ];
        final lineSolution = new LineSolution([
            new LineCandidate(new IntRange(1, 0), new TextRange(0, 0), 0.0, 0.0, LineEndReason.AutoWrap),
            new LineCandidate(new IntRange(0, 2), new TextRange(0, 5), 80.0, 80.0, LineEndReason.AutoWrap)
        ]);
        final clreqProfile = engine.clreqProfileResolver.resolve(input.profileId);
        final geomDecision = new ClusterGeometryDecisionInfo(new TextRange(0, 2), "\u6C49\u5B57", "\u6C49\u5B57", 32.0, 32.0, 4.0, 2.0, 4.0, 2.0, 0.0, 32.0,
            "test", "test");
        final metricDecision1 = new ClusterMetricDecision(new TextRange(0, 2), "\u6C49\u5B57", new FontMetricsRequest("k", 24.0, FontRole.CjkText, "zh-Hans"),
            new RawFontMetrics(18.0, 6.0), new LayoutFontMetrics(18.0, 6.0, 0.0, FontMetricsPolicy.Raw, BaselinePolicy.Alphabetic));
        final metricDecision2 = new ClusterMetricDecision(new TextRange(2, 3), "\uFF0C",
            new FontMetricsRequest("k", 24.0, FontRole.CjkPunctuation, "zh-Hans"), new RawFontMetrics(18.0, 6.0),
            new LayoutFontMetrics(18.0, 6.0, 0.0, FontMetricsPolicy.Raw, BaselinePolicy.Alphabetic));
        final inlineObject1 = new InlineObjectSpan(new TextRange(0, 2), 32.0, 16.0, 4.0,
            new InlineObjectBoundaryAdjustment(null, new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.Relation, 5.0, 10.0)),
            new InlineObjectBoundaryAdjustment(null, null));
        final inlineObject2 = new InlineObjectSpan(new TextRange(15, 17), 32.0, 16.0, 4.0, new InlineObjectBoundaryAdjustment(null, null),
            new InlineObjectBoundaryAdjustment(null, new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.BinaryOperator, 5.0, 10.0)));
        final inlineObjMapBuilder = SortedMap.builder();
        inlineObjMapBuilder.put(0, inlineObject1);
        inlineObjMapBuilder.put(99, inlineObject2);
        final inlineObjMap = inlineObjMapBuilder.build();
        final pinyinA = new RubySpan(new TextRange(0, 2), "h\u00E0nz\u00EC", null, RubyKind.Pinyin, null);
        final pinyinB = new RubySpan(new TextRange(2, 3), "ch\u00F9", null, RubyKind.Pinyin, null);
        final pinyinC = new RubySpan(new TextRange(3, 5), "c\u00E8sh\u00EC", null, RubyKind.Pinyin, null);
        final rfgBuilder = SortedMap.builder();
        rfgBuilder.put(pinyinA, new RubyFontGeometry(20.0, 8.0, 2.0, 10.0, []));
        rfgBuilder.put(pinyinB, new RubyFontGeometry(10.0, 8.0, 2.0, 10.0, []));
        rfgBuilder.put(pinyinC, new RubyFontGeometry(20.0, 8.0, 2.0, 10.0, []));
        final rfgMap = rfgBuilder.build();
        final res = LineAdjustmentStage.resolveAnnotationGeometry(engine, input, 16.0, inlineObjMap, lineSolution, clreqProfile, [geomDecision], [
            new AutoSpaceDecisionInfo(new TextRange(0, 2), "leading", "Wide", "Normal", 1, 0.0, 0.0, "test"),
            new AutoSpaceDecisionInfo(new TextRange(2, 3), "leading", "Wide", "Normal", 1, 0.0, 0.0, "test"),
            new AutoSpaceDecisionInfo(new TextRange(2, 3), "trailing", "Wide", "Normal", 1, 0.0, 0.0, "test"),
            new AutoSpaceDecisionInfo(new TextRange(3, 5), "trailing", "Wide", "Normal", 1, 0.0, 0.0, "test")
        ],
            [new IntRange(1, 0), new IntRange(0, 2)], lineBoxes, clusters, [FontRole.CjkText, FontRole.CjkPunctuation, FontRole.CjkText, FontRole.LatinText],
            SortedMap.builder().build(), SortedMap.builder().build(), [metricDecision1, metricDecision2], [pinyinA, pinyinB, pinyinC], clusters, rfgMap, 0.0,
            16.0, 8.0, 400, 4.0, function(_:Int) return 400);
        TracedAssertions.assertNotNullRendered(res != null, res == null ? "null" : TestTraceRender.cap(Std.string(res)));
    }

    @:test public static function bopomofoAndDecorationLeadingBlankExhaustiveBranches():Void {
        final r = new TestTraceRecorder("AnnotationGeometryStageCoverageTest");
        r.section("bopomofoAndDecorationLeadingBlankExhaustiveBranches");
        final multiGlyphShaper = new MultiGlyphBoundsShaper();
        final engine = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, multiGlyphShaper);
        final text = "\u4E2D\u6587English";
        final input = new LayoutInput(new TiqianTextContent(text), null, null, new LayoutConstraints(500.0), null, [
            new DecorationSpan(new TextRange(0, 7), DecorationKind.ProperNoun),
            new DecorationSpan(new TextRange(2, 7), DecorationKind.ProperNoun)
        ], [
            new RubySpan(new TextRange(0, 1), "\u3105", null, RubyKind.Bopomofo, null),
            new RubySpan(new TextRange(1, 2), "\u3106", null, RubyKind.Bopomofo, "zh-TW"),
            new RubySpan(new TextRange(0, 1), "", null, RubyKind.Bopomofo, null)
        ]);
        final res = engine.layout(input);
        TracedAssertions.assertNotNullRendered(res != null, res == null ? "null" : TestTraceRender.cap(Std.string(res)));
        final inputNarrow = new LayoutInput(new TiqianTextContent(text), null, null, new LayoutConstraints(30.0), null, [
            new DecorationSpan(new TextRange(0, 7), DecorationKind.ProperNoun),
            new DecorationSpan(new TextRange(2, 7), DecorationKind.ProperNoun)
        ], [
            new RubySpan(new TextRange(0, 1), "\u3105", null, RubyKind.Bopomofo, null),
            new RubySpan(new TextRange(1, 2), "\u3106", null, RubyKind.Bopomofo, "zh-TW"),
            new RubySpan(new TextRange(0, 1), "", null, RubyKind.Bopomofo, null)
        ]);
        final resNarrow = engine.layout(inputNarrow);
        TracedAssertions.assertNotNullRendered(resNarrow != null, resNarrow == null ? "null" : TestTraceRender.cap(Std.string(resNarrow)));
    }

    @:test public static function bopomofoOverLatinClustersCoversCrossMetricLookup():Void {
        final r = new TestTraceRecorder("AnnotationGeometryStageCoverageTest");
        r.section("bopomofoOverLatinClustersCoversCrossMetricLookup");
        final engine = new ExplainableStubParagraphLayoutEngine();
        final text = "\u4E2D\u6587English";
        final input = new LayoutInput(new TiqianTextContent(text), null, null, new LayoutConstraints(500.0), null, null, [
            new RubySpan(new TextRange(2, 3), "\u3105", null, RubyKind.Bopomofo, null),
            new RubySpan(new TextRange(3, 4), "\u3106", null, RubyKind.Bopomofo, "zh-TW")
        ]);
        final res = engine.layout(input);
        TracedAssertions.assertNotNullRendered(res != null, res == null ? "null" : TestTraceRender.cap(Std.string(res)));
    }
}
