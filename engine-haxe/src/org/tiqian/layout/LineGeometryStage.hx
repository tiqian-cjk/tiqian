package org.tiqian.layout;

using std.Functional;

import org.tiqian.core.Cluster;
import org.tiqian.core.Glyph;
import org.tiqian.core.IntRange;
import org.tiqian.core.InlineObjectLineHeightDecisionInfo;
import org.tiqian.core.InlineObjectSpan;
import org.tiqian.core.LastLineAlignment;
import org.tiqian.core.LayoutInput;
import org.tiqian.core.LineBox;
import org.tiqian.core.LineDebugInfo;
import org.tiqian.core.LineEndReason;
import org.tiqian.core.MaxLinesDecisionInfo;
import org.tiqian.core.RubyLineHeightDecisionInfo;
import org.tiqian.core.RubyLineHeightMode;
import org.tiqian.core.RubySpan;
import org.tiqian.core.TextRange;
import org.tiqian.font.FontMetrics.FontMetricsRequest;
import org.tiqian.font.LayoutFontMetrics;
import org.tiqian.font.MetricBox;
import org.tiqian.font.RawFontMetrics;
import org.tiqian.layout.AnnotationGeometryStage.RubyFontGeometry;
import org.tiqian.layout.Justifier.JustificationPlan;
import org.tiqian.layout.LineOptimization.LineSolution;
import org.tiqian.layout.LineOptimization.LineCandidate;

@:dataClass class LineBoxStageResult {
    public final laidOutLines:Array<LineBox>;
    public final visibleLines:Array<LineBox>;
    public final maxLinesDecision:Null<MaxLinesDecisionInfo>;
    public final visibleLineRanges:Array<IntRange>;

    public function new(laidOutLines:Array<LineBox>, visibleLines:Array<LineBox>, maxLinesDecision:Null<MaxLinesDecisionInfo>,
            visibleLineRanges:Array<IntRange>) {
        this.laidOutLines = laidOutLines;
        this.visibleLines = visibleLines;
        this.maxLinesDecision = maxLinesDecision;
        this.visibleLineRanges = visibleLineRanges;
    }
}

@:dataClass class LineVerticalGeometryStageResult {
    public final rubyLineHeightDecision:Null<RubyLineHeightDecisionInfo>;
    public final inlineObjectLineHeightDecision:Null<InlineObjectLineHeightDecisionInfo>;
    public final lineBaseline:Array<Float>;
    public final lineTop:Array<Float>;
    public final lineBottom:Array<Float>;

    public function new(rubyLineHeightDecision:Null<RubyLineHeightDecisionInfo>, inlineObjectLineHeightDecision:Null<InlineObjectLineHeightDecisionInfo>,
            lineBaseline:Array<Float>, lineTop:Array<Float>, lineBottom:Array<Float>) {
        this.rubyLineHeightDecision = rubyLineHeightDecision;
        this.inlineObjectLineHeightDecision = inlineObjectLineHeightDecision;
        this.lineBaseline = lineBaseline;
        this.lineTop = lineTop;
        this.lineBottom = lineBottom;
    }
}

@:dataClass class ClusterMetricDecision {
    public final range:TextRange;
    public final sourceText:String;
    public final request:FontMetricsRequest;
    public final rawMetrics:RawFontMetrics;
    public final layoutMetrics:LayoutFontMetrics;

    public function new(range:TextRange, sourceText:String, request:FontMetricsRequest, rawMetrics:RawFontMetrics, layoutMetrics:LayoutFontMetrics) {
        this.range = range;
        this.sourceText = sourceText;
        this.request = request;
        this.rawMetrics = rawMetrics;
        this.layoutMetrics = layoutMetrics;
    }
}

@:dataClass class ResolvedLineMetrics {
    public final baseline:Float;
    public final height:Float;
    public final extraLeading:Float;

    public function new(baseline:Float, height:Float, ?extraLeading:Null<Float>) {
        this.baseline = baseline;
        this.height = height;
        this.extraLeading = extraLeading == null ? 0 : extraLeading;
    }
}

class RubyClusterRange {
    public final ruby:RubySpan;
    public final range:IntRange;

    public function new(ruby:RubySpan, range:IntRange) {
        this.ruby = ruby;
        this.range = range;
    }
}

class LineGeometryStageFns {
    public static function resolveLineVerticalGeometry(input:LayoutInput, fontSize:Float, pinyinSpans:Array<RubySpan>, naturalClusters:Array<Cluster>,
            lineSolution:LineSolution, rubyFontGeometryBySpan:std.SortedMap<RubySpan, RubyFontGeometry>, existingInterlineSpace:Float,
            baseLineMetrics:ResolvedLineMetrics, baseFaceHeight:Float, rubyExtent:Float, inlineObjectByClusterIndex:Map<Int, InlineObjectSpan>,
            baseAscent:Float, baseDescent:Float):LineVerticalGeometryStageResult {
        return resolveLineVerticalGeometrySorted(input, fontSize, pinyinSpans, naturalClusters, lineSolution, rubyFontGeometryBySpan, existingInterlineSpace,
            baseLineMetrics, baseFaceHeight, rubyExtent, null, baseAscent, baseDescent);
    }

    public static function resolveLineVerticalGeometrySorted(input:LayoutInput, fontSize:Float, pinyinSpans:Array<RubySpan>, naturalClusters:Array<Cluster>,
            lineSolution:LineSolution, rubyFontGeometryBySpan:std.SortedMap<RubySpan, RubyFontGeometry>, existingInterlineSpace:Float,
            baseLineMetrics:ResolvedLineMetrics, baseFaceHeight:Float, rubyExtent:Float, inlineObjectByClusterIndex:std.SortedMap<Int, InlineObjectSpan>,
            baseAscent:Float, baseDescent:Float):LineVerticalGeometryStageResult {
        final pinyinClusterRanges:Array<RubyClusterRange> = [];
        for (ruby in pinyinSpans) {
            final range = clusterIndexRangeFor(naturalClusters, ruby.baseRange);
            if (range != null)
                pinyinClusterRanges.push(new RubyClusterRange(ruby, range));
        }
        final perLineRubyExtent:Array<Float> = [];
        for (line in lineSolution.lines) {
            var required = 0.0;
            for (pair in pinyinClusterRanges) {
                if (pair.range.start <= line.clusterRange.end
                    && pair.range.end >= line.clusterRange.start
                    && rubyFontGeometryBySpan.has(pair.ruby))
                    required = Math.max(required, rubyFontGeometryBySpan.get(pair.ruby).requiredExtent);
            }
            perLineRubyExtent.push(required);
        }
        final perLineRubyDeficit = perLineRubyExtent.map(x -> Math.max(0, x - existingInterlineSpace));
        var paragraphRubyDeficit = 0.0;
        for (x in perLineRubyDeficit)
            paragraphRubyDeficit = Math.max(paragraphRubyDeficit, x);
        final uniform = input.paragraphStyle.rubyLineHeightMode == RubyLineHeightMode.UniformParagraph;
        var paragraphRubyExtent = 0.0;
        for (x in perLineRubyExtent)
            paragraphRubyExtent = Math.max(paragraphRubyExtent, x);
        final lineRubyTopExtra:Array<Float> = [];
        final lineRubyInterlineDemand:Array<Float> = [];
        for (i in 0...lineSolution.lines.length) {
            lineRubyTopExtra.push(uniform ? paragraphRubyDeficit : perLineRubyDeficit[i]);
            lineRubyInterlineDemand.push(uniform ? paragraphRubyExtent : perLineRubyExtent[i]);
        }
        var maxExtra = 0.0;
        final expandedRuby:Array<Int> = [];
        for (i in 0...lineRubyTopExtra.length) {
            maxExtra = Math.max(maxExtra, lineRubyTopExtra[i]);
            if (lineRubyTopExtra[i] > 0)
                expandedRuby.push(i);
        }
        var hasRubyExtra = expandedRuby.length > 0;
        final rubyReason = hasRubyExtra ? "ConditionalRubyLineHeight" : "ExistingInterlineSpaceFitsRuby";
        final rd = pinyinSpans.length == 0 ? null : new RubyLineHeightDecisionInfo(Type.enumConstructor(input.paragraphStyle.rubyLineHeightMode),
            baseLineMetrics.height, baseFaceHeight, rubyExtent, existingInterlineSpace, maxExtra, lineRubyTopExtra, expandedRuby, rubyReason);

        final baseBaseline = f32(baseLineMetrics.baseline);
        final baseHeight = f32(baseLineMetrics.height);
        final baseTopExtent = baseBaseline;
        final baseBottomExtent = f32(baseHeight - baseBaseline);
        final fBaseAscent = f32(baseAscent);
        final fBaseDescent = f32(baseDescent);
        final lineObjectAscent:Array<Float> = [];
        final lineObjectDescent:Array<Float> = [];
        for (line in lineSolution.lines) {
            var ascent = 0.0;
            var descent = 0.0;
            var idx = line.clusterRange.start;
            while (idx <= line.clusterRange.end) {
                if (inlineObjectByClusterIndex != null && inlineObjectByClusterIndex.has(idx)) {
                    final obj = inlineObjectByClusterIndex.get(idx);
                    ascent = Math.max(ascent, f32(obj.ascent));
                    descent = Math.max(descent, f32(obj.descent));
                }
                idx++;
            }
            lineObjectAscent.push(ascent);
            lineObjectDescent.push(descent);
        }
        final lineObjectTopIntrusion = lineObjectAscent.map(x -> Math.max(0, f32(x - fBaseAscent)));
        final lineObjectBottomIntrusion = lineObjectDescent.map(x -> Math.max(0, f32(x - fBaseDescent)));
        final minimumClearance = f32(f32(input.paragraphStyle.inlineObjectMinimumClearanceEm) * f32(fontSize));
        final combinedLineExtra:Array<Float> = [];
        for (i in 0...lineSolution.lines.length) {
            if (i == 0) {
                combinedLineExtra.push(Math.max(f32(lineRubyTopExtra[i]), Math.max(0, f32(lineObjectAscent[i] - baseTopExtent))));
            } else {
                final topDemand = Math.max(f32(lineRubyInterlineDemand[i]), lineObjectTopIntrusion[i]);
                final intrudes = lineObjectBottomIntrusion[i - 1] > 0
                    || (lineObjectTopIntrusion[i] > 0 && lineObjectTopIntrusion[i] >= lineRubyInterlineDemand[i]);
                final clearance = intrudes ? minimumClearance : 0.0;
                combinedLineExtra.push(Math.max(0, f32(f32(f32(lineObjectBottomIntrusion[i - 1] + topDemand) + clearance) - f32(existingInterlineSpace))));
            }
        }
        final objectLineExtra:Array<Float> = [];
        for (i in 0...combinedLineExtra.length)
            objectLineExtra.push(Math.max(0, f32(combinedLineExtra[i] - f32(lineRubyTopExtra[i]))));
        final baselines:Array<Float> = [];
        if (lineSolution.lines.length > 0) {
            baselines.push(f32(baseBaseline + combinedLineExtra[0]));
            for (i in 1...lineSolution.lines.length)
                baselines.push(f32(f32(baselines[i - 1] + baseHeight) + combinedLineExtra[i]));
        }
        final tops:Array<Float> = [for (i in 0...lineSolution.lines.length) 0.0];
        final bottoms:Array<Float> = [for (i in 0...lineSolution.lines.length) 0.0];
        final boundaryCount:Int = lineSolution.lines.length > 1 ? lineSolution.lines.length - 1 : 0;
        final boundaryShifts:Array<Float> = [for (i in 0...boundaryCount) 0.0];
        for (i in 0...boundaryCount) {
            final current = Math.max(fBaseDescent, lineObjectDescent[i]);
            final boundaryExtent = resolveInlineObjectLineBoundaryExtent(baseBottomExtent, current, f32(baselines[i + 1] - baselines[i]),
                Math.max(fBaseAscent, lineObjectAscent[i + 1]));
            final nominal = f32(baselines[i] + baseBottomExtent);
            final boundary = f32(baselines[i] + boundaryExtent);
            bottoms[i] = boundary;
            tops[i + 1] = boundary;
            boundaryShifts[i] = f32(boundary - nominal);
        }
        final trailing = lineSolution.lines.length == 0 ? 0.0 : Math.max(0, f32(lineObjectDescent[lineObjectDescent.length - 1] - baseBottomExtent));
        if (lineSolution.lines.length > 0)
            bottoms[bottoms.length - 1] = f32(f32(baselines[baselines.length - 1] + baseBottomExtent) + trailing);
        final objectIndices:Array<Int> = [];
        for (i in 0...objectLineExtra.length)
            if (objectLineExtra[i] > 0)
                objectIndices.push(i);
        var hasInlineObjects = false;
        if (inlineObjectByClusterIndex != null)
            hasInlineObjects = inlineObjectByClusterIndex.size() > 0;
        final iod = hasInlineObjects ? new InlineObjectLineHeightDecisionInfo(baseLineMetrics.height, baseAscent, baseDescent, existingInterlineSpace,
            minimumClearance, lineObjectAscent, lineObjectDescent, objectLineExtra, boundaryShifts, trailing,
            objectIndices, objectIndices.length == 0 && trailing == 0 ? "ExistingInterlineSpaceFitsInlineObjects" : "InlineObjectInterlineCollision") : null;
        return new LineVerticalGeometryStageResult(rd, iod, baselines, tops, bottoms);
    }

    public static function lineMetrics(self:Array<ClusterMetricDecision>, explicitLineHeight:Null<Float>, defaultLineHeight:Float,
            ?spacingFloor:Null<Float>):ResolvedLineMetrics {
        var floorValue = 0.0;
        if (spacingFloor != null)
            floorValue = spacingFloor;
        final floor:Float = floorValue;
        if (self.length == 0) {
            var hValue = defaultLineHeight;
            if (explicitLineHeight != null)
                hValue = explicitLineHeight;
            final h:Float = hValue;
            return new ResolvedLineMetrics(h * .75, h);
        }
        var src = self.filter(x -> x.layoutMetrics.metricBox == MetricBox.IdeographicEmBox);
        if (src.length == 0)
            src = self;
        var a = src[0].layoutMetrics.ascent;
        var d = src[0].layoutMetrics.descent;
        for (x in src) {
            a = Math.max(a, x.layoutMetrics.ascent);
            d = Math.max(d, x.layoutMetrics.descent);
        }
        final natural = a + d;
        var requestedValue = defaultLineHeight;
        if (explicitLineHeight != null)
            requestedValue = explicitLineHeight;
        final requested:Float = requestedValue;
        final h = Math.max(requested, natural + floor);
        return new ResolvedLineMetrics(a + (h - natural) / 2, h, h - natural);
    }

    // Kotlin stores every line-geometry operand as Float; the JS test bundle
    // keeps the widened f64, so each Float op must snap back to the f32 grid
    // to reproduce the Kotlin arithmetic chain.
    static function f32(v:Float):Float {
        return haxe.io.FPHelper.i32ToFloat(haxe.io.FPHelper.floatToI32(v));
    }

    public static function resolveInlineObjectLineBoundaryExtent(nominalBoundaryExtent:Float, currentContentBottomExtent:Float, baselineDistance:Float,
            nextContentTopExtent:Float):Float {
        return Math.max(currentContentBottomExtent,
            Math.min(nominalBoundaryExtent, Math.max(currentContentBottomExtent, f32(baselineDistance - nextContentTopExtent))));
    }

    public static function clusterIndexRangeFor(self:Array<Cluster>, r:TextRange):Null<IntRange> {
        return PunctuationGeometryLedger.clusterIndexRangeFor(self, r);
    }
}
