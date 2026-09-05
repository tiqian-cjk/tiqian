package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.font.FontMetrics.FontMetricsRequest;
import org.tiqian.font.FontRole;
import org.tiqian.font.RawFontMetrics;
import org.tiqian.font.LayoutFontMetrics;
import org.tiqian.font.FontMetricsPolicy;
import org.tiqian.font.BaselinePolicy;
import org.tiqian.layout.AnnotationGeometryStage.RubyFontGeometry;
import org.tiqian.layout.LineGeometryStage.LineGeometryStageFns;
import org.tiqian.layout.LineGeometryStage.LineVerticalGeometryStageResult;
import org.tiqian.layout.LineGeometryStage.ClusterMetricDecision;
import org.tiqian.layout.LineGeometryStage.ResolvedLineMetrics;
import org.tiqian.layout.LineOptimization.LineCandidate;
import org.tiqian.layout.LineOptimization.LineSolution;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedMap;

@:test class LineGeometryDirectTailTest {
    @:test public static function rubyBaseRangeCrossingClusterBoundariesDropsOutOfPerLineExtents():Void {
        LineGeometryDirectTailSupport.start("rubyBaseRangeCrossingClusterBoundariesDropsOutOfPerLineExtents");
        var a = LineGeometryDirectTailSupport.ruby(new TextRange(4, 8), "y");
        var m = LineGeometryDirectTailSupport.ruby(new TextRange(1, 3), "w");
        var z = LineGeometryDirectTailSupport.ruby(new TextRange(0, 4), "z");
        var r = LineGeometryDirectTailSupport.geometry([a, m, z], [
            LineGeometryDirectTailSupport.line(new IntRange(0, 3), LineGeometryDirectTailSupport.clusters())
        ], LineGeometryDirectTailSupport.mapRuby([
            {
                s: a,
                g: LineGeometryDirectTailSupport.rg(12, 8)
            }
            ]));
        TracedAssertions.assertEqualsInt(1, r.lineBaseline.length);
        TracedAssertions.assertTrue(r.lineBaseline[0] > 0);
    }

    @:test public static function rubiesOnBothLinesExerciseBothSidesOfTheOverlapTest():Void {
        LineGeometryDirectTailSupport.start("rubiesOnBothLinesExerciseBothSidesOfTheOverlapTest");
        var a = LineGeometryDirectTailSupport.ruby(new TextRange(0, 4), "a");
        var b = LineGeometryDirectTailSupport.ruby(new TextRange(4, 8), "b");
        var r = LineGeometryDirectTailSupport.geometry([a, b], [
            LineGeometryDirectTailSupport.line(new IntRange(0, 1), LineGeometryDirectTailSupport.clusters()),
            LineGeometryDirectTailSupport.line(new IntRange(2, 3), LineGeometryDirectTailSupport.clusters())
        ], LineGeometryDirectTailSupport.mapRuby([
            {
                s: a,
                g: LineGeometryDirectTailSupport.rg(12, 8)
            },
            {s: b, g: LineGeometryDirectTailSupport.rg(12, 6)}
            ]));
        TracedAssertions.assertEqualsInt(2, r.lineBaseline.length);
        TracedAssertions.assertTrue(r.lineBaseline[1] > r.lineBaseline[0]);
    }

    @:test public static function emptyLineSolutionYieldsZeroArraysAndZeroMaxExtra():Void {
        LineGeometryDirectTailSupport.start("emptyLineSolutionYieldsZeroArraysAndZeroMaxExtra");
        var r = LineGeometryDirectTailSupport.geometry([LineGeometryDirectTailSupport.ruby(new TextRange(0, 2), "y")], []);
        TracedAssertions.assertEqualsInt(0, r.lineBaseline.length);
        TracedAssertions.assertEqualsInt(0, r.lineTop.length);
        TracedAssertions.assertEqualsInt(0, r.lineBottom.length);
        TracedAssertions.assertNotNullRendered(r.rubyLineHeightDecision != null,
            r.rubyLineHeightDecision == null ? "null" : Std.string(r.rubyLineHeightDecision));
        TracedAssertions.assertEqualsFloat(0, r.rubyLineHeightDecision.maxExtra);
    }

    @:test public static function objectTopIntrusionBelowRubyDemandKeepsBoundaryClearanceZero():Void {
        LineGeometryDirectTailSupport.start("objectTopIntrusionBelowRubyDemandKeepsBoundaryClearanceZero");
        var r = LineGeometryDirectTailSupport.objectCase(10, 8);
        TracedAssertions.assertEqualsInt(2, r.lineBaseline.length);
        TracedAssertions.assertTrue(r.lineBaseline[1] > r.lineBaseline[0]);
    }

    @:test public static function objectTopIntrusionDominatingRubyDemandAddsBoundaryClearance():Void {
        LineGeometryDirectTailSupport.start("objectTopIntrusionDominatingRubyDemandAddsBoundaryClearance");
        var r = LineGeometryDirectTailSupport.objectCase(20, 8);
        TracedAssertions.assertEqualsInt(2, r.lineBaseline.length);
        TracedAssertions.assertTrue(r.lineBaseline[1] > r.lineBaseline[0]);
    }

    @:test public static function objectFlushWithBaseTopSkipsIntrusionConjunctionEarly():Void {
        LineGeometryDirectTailSupport.start("objectFlushWithBaseTopSkipsIntrusionConjunctionEarly");
        var r = LineGeometryDirectTailSupport.objectCase(8, 8);
        TracedAssertions.assertEqualsInt(2, r.lineBaseline.length);
        TracedAssertions.assertTrue(r.lineBaseline[1] > r.lineBaseline[0]);
    }

    @:test public static function metricListWithoutIdeographicEmBoxFallsBackToAllClusters():Void {
        LineGeometryDirectTailSupport.start("metricListWithoutIdeographicEmBoxFallsBackToAllClusters");
        var q = new FontMetricsRequest("latin", 16, FontRole.LatinText, "zh-Hans");
        var d = new ClusterMetricDecision(new TextRange(0, 1), "a", q, new RawFontMetrics(14, 4),
            new LayoutFontMetrics(14, 4, 0, FontMetricsPolicy.Raw, BaselinePolicy.Alphabetic));
        var r = LineGeometryStageFns.lineMetrics([d], null, 24, 0);
        TracedAssertions.assertTrue(r.baseline >= 14);
        TracedAssertions.assertTrue(r.height >= 18);
    }

    @:test public static function emptyMetricListTakesEmptyParagraphBaselineFallback():Void {
        LineGeometryDirectTailSupport.start("emptyMetricListTakesEmptyParagraphBaselineFallback");
        var a = LineGeometryStageFns.lineMetrics([], null, 24, 0);
        TracedAssertions.assertEqualsFloat(24, a.height);
        TracedAssertions.assertEqualsFloat(18, a.baseline);
        var b = LineGeometryStageFns.lineMetrics([], 30, 24, 0);
        TracedAssertions.assertEqualsFloat(30, b.height);
        TracedAssertions.assertEqualsFloat(22.5, b.baseline);
    }
}

/** Shared fixtures and geometry builders for LineGeometryDirectTailTest; the Kotlin test-class lowering admits test functions only. */
typedef RubyEntry = {s:RubySpan, g:RubyFontGeometry};

class LineGeometryDirectTailSupport {
    public static function start(n:String):Void
        new TestTraceRecorder("LineGeometryDirectTailTest").section(n);

    public static function c(index:Int):Cluster
        return new Cluster(new TextRange(index * 2, index * 2 + 2), "𠀀", "k", 16.0, "𠀀");

    public static function clusters():Array<Cluster> {
        var r:Array<Cluster> = [];
        var i = 0;
        while (i < 4) {
            r.push(c(i));
            i++;
        }
        return r;
    }

    public static function input():LayoutInput
        return new LayoutInput(new TiqianTextContent("中文测试"), new TextStyle(),
            new ParagraphStyle(LastLineAlignment.Start, WritingMode.HorizontalTb, null, null, Ic.Zero, new MeasureAdaptiveFirstLineIndent(14.0, 1.0, 2.0),
                new LineLengthGrid(true, null)),
            new LayoutConstraints(320.0));

    public static function line(range:IntRange, cs:Array<Cluster>):LineCandidate
        return new LineCandidate(range, new TextRange(range.start * 2, (range.end + 1) * 2), 32.0, 32.0);

    public static function mapRuby(entries:Array<RubyEntry>):SortedMap<RubySpan, RubyFontGeometry> {
        var b = SortedMap.builder();
        var i = 0;
        while (i < entries.length) {
            b.put(entries[i].s, entries[i].g);
            i++;
        }
        return b.build();
    }

    public static function geometry(?spans:Array<RubySpan>, lines:Array<LineCandidate>, ?rmap:SortedMap<RubySpan, RubyFontGeometry>,
            ?objects:Map<Int, InlineObjectSpan>, ?existing:Float = 0.0, ?ascent:Float = 8.0, ?descent:Float = 4.0):LineVerticalGeometryStageResult {
        var cs = clusters();
        return LineGeometryStageFns.resolveLineVerticalGeometry(input(), 16.0, spans == null ? [] : spans, cs, new LineSolution(lines),
            rmap == null ? SortedMap.builder().build() : rmap, existing, new ResolvedLineMetrics(12.0, 16.0), 16.0, 0.0, objects, ascent, descent);
    }

    public static function ruby(range:TextRange, text:String):RubySpan
        return new RubySpan(range, text, [], RubyKind.Pinyin);

    public static function rg(width:Float, required:Float):RubyFontGeometry
        return new RubyFontGeometry(width, 6.0, 2.0, required, []);

    public static function objectCase(objectAscent:Float, extent:Float):LineVerticalGeometryStageResult {
        var r = ruby(new TextRange(4, 8), "y");
        return geometry([r], [line(new IntRange(0, 1), clusters()), line(new IntRange(2, 3), clusters())], mapRuby([{s: r, g: rg(12, extent)}]), null, 0, 8, 4);
    }
}
