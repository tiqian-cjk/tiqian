package org.tiqian.core;

using std.Functional;
using org.tiqian.core.LayoutResultFns;
using org.tiqian.core.LayoutResultLineFns;
using org.tiqian.core.IntRangeFns;

import org.tiqian.core.RichTextRole.Background;
import org.tiqian.core.RichTextRole.Underline;
import org.tiqian.core.RichTextRole.LineThrough;
import org.tiqian.core.RichTextRole.InlineCode;
import std.ReadOnlyArray;

/**
 * `RichTextLayoutQueries`: the rich-text segment queries of `LayoutQueries` (positioned rich-text
 * segments, trimmed decoration segments, background segments, decoration line position and
 * background corner radii) with the helpers only they use. `LayoutQueries` keeps the public entry
 * points and forwards to this class; the shared geometry helpers stay in `LayoutQueries` and are
 * opened to this class with `@:allow`.
 */
class RichTextLayoutQueries {
    private static final INTERLINEAR_UNDERLINE_OFFSET_EM:Float = 0.18;
    private static final IDEOGRAPHIC_EM_BOX_NAME:String = "IdeographicEmBox";
    private static final BACKGROUND_FALLBACK_ASCENT_EM:Float = 0.88;
    private static final BACKGROUND_FALLBACK_DESCENT_EM:Float = 0.12;

    public static function resolvedBackgroundCornerRadii(segment:RichTextLineSegment, inset:Float):RichTextCornerRadii {
        requireFiniteNonNegative(inset, "Failed requirement.");
        final boxWidth:Float = LayoutQueries.maxFloat(segment.width - inset * 2.0, 0.0);
        final boxHeight:Float = LayoutQueries.maxFloat(segment.height - inset * 2.0, 0.0);
        final maximum:Float = LayoutQueries.minFloat(boxWidth / 2.0, boxHeight / 2.0);
        final paint:RichTextBackgroundPaint = segment.span.paint.background;
        final leftRadius:Float = resolveRadius(segment.continuesFromPreviousLine ? paint.continuationCornerRadius : paint.cornerRadius, inset, maximum);
        final rightRadius:Float = resolveRadius(segment.continuesOnNextLine ? paint.continuationCornerRadius : paint.cornerRadius, inset, maximum);
        return new RichTextCornerRadii(leftRadius, rightRadius, rightRadius, leftRadius);
    }

    public static function positionedRichTextSegments(result:LayoutResult, spans:Array<RichTextSpan>):Array<RichTextLineSegment> {
        if (spans.length == 0 || result.lines.length == 0) {
            return [];
        }
        final clusters:Array<PositionedCluster> = LayoutQueries.positionedClusters(result);
        final textLength:Int = result.input.content.text.length;
        final output:Array<RichTextLineSegment> = [];
        var spanIndex:Int = 0;
        while (spanIndex < spans.length) {
            final span:RichTextSpan = spans[spanIndex];
            final start:Int = LayoutQueries.clampInt(span.range.start, 0, textLength);
            final end:Int = LayoutQueries.clampInt(span.range.end, start, textLength);
            if (start != end) {
                final normalized:RichTextSpan = new RichTextSpan(new TextRange(start, end), span.role, span.paint);
                var pending:Null<RichTextLineSegment> = null;
                var clusterIndex:Int = 0;
                while (clusterIndex < clusters.length) {
                    final cluster:PositionedCluster = clusters[clusterIndex];
                    if (cluster.range.start >= end) {
                        break;
                    }
                    if (cluster.range.end > start) {
                        final sliceStart:Int = LayoutQueries.maxInt(start, cluster.range.start);
                        final sliceEnd:Int = LayoutQueries.minInt(end, cluster.range.end);
                        if (sliceStart < sliceEnd) {
                            final rect:Rect = LayoutQueries.sliceRect(cluster, sliceStart, sliceEnd);
                            final next:RichTextLineSegment = new RichTextLineSegment(normalized, cluster.lineIndex, new TextRange(sliceStart, sliceEnd),
                                rect.left, rect.top, rect.right, rect.bottom, cluster.baseline);
                            if (pending != null && pending.lineIndex == next.lineIndex && pending.span == next.span && pending.range.end == next.range.start) {
                                pending = new RichTextLineSegment(pending.span, pending.lineIndex, new TextRange(pending.range.start, next.range.end),
                                    pending.left, LayoutQueries.minFloat(pending.top, next.top), next.right, LayoutQueries.maxFloat(pending.bottom, next.bottom), pending.baseline);
                            } else {
                                if (pending != null) {
                                    output.push(pending);
                                }
                                pending = next;
                            }
                        }
                    }
                    clusterIndex += 1;
                }
                if (pending != null) {
                    output.push(pending);
                }
            }
            spanIndex += 1;
        }
        return output;
    }

    public static function trimmedRichTextDecorationSegments(result:LayoutResult, occupiedSegments:Array<RichTextLineSegment>):Array<RichTextLineSegment> {
        if (occupiedSegments.length == 0) {
            return [];
        }
        final decorations:Array<RichTextLineSegment> = occupiedSegments.filter(segment -> isDecorationRole(segment.span.role));
        if (decorations.length == 0) {
            return [];
        }
        return withAdjacentSameStyleClearance(result, trimOuterPunctuationGlue(result, decorations));
    }

    public static function richTextBackgroundSegments(result:LayoutResult, occupiedSegments:Array<RichTextLineSegment>):Array<RichTextLineSegment> {
        if (occupiedSegments.length == 0) {
            return [];
        }
        final backgrounds:Array<RichTextLineSegment> = occupiedSegments.filter(segment -> isBackgroundRole(segment.span.role));
        if (backgrounds.length == 0) {
            return [];
        }

        final positioned:Array<PositionedCluster> = LayoutQueries.positionedClusters(result);
        final trimmed:Array<RichTextLineSegment> = trimOuterPunctuationGlue(result, backgrounds);
        final output:Array<RichTextLineSegment> = [];
        var index:Int = 0;
        while (index < trimmed.length) {
            final segment:RichTextLineSegment = trimmed[index];
            final covered:Array<PositionedCluster> = clustersOnSegmentLine(positioned, segment);
            if (covered.length == 0) {
                output.push(segment);
                index += 1;
                continue;
            }
            final first:PositionedCluster = covered[0];
            final last:PositionedCluster = covered[covered.length - 1];
            final horizontalPadding:Float = segment.span.paint.background.horizontalPadding;
            final leadingPadding:Float = segment.range.start == segment.span.range.start ? horizontalPadding : 0.0;
            final trailingPadding:Float = segment.range.end == segment.span.range.end ? horizontalPadding : 0.0;
            final left:Float = LayoutQueries.minFloat(segment.right, LayoutQueries.maxFloat(segment.left, first.drawX - leadingPadding));
            final naturalLastRight:Float = naturalLastRight(result, last);
            final right:Float = LayoutQueries.maxFloat(left, LayoutQueries.minFloat(segment.right, naturalLastRight + trailingPadding));
            var faceTop:Float = 0.0;
            var faceBottom:Float = 0.0;
            switch (segment.span.paint.background.metricPolicy) {
                case MarkedFaces:
                    final faces:Array<Float> = markedFaceVerticalBounds(result, covered);
                    faceTop = faces[0];
                    faceBottom = faces[1];
                case UniformTextStyle:
                    final uniform:Array<Float> = uniformTextStyleVerticalBounds(result, segment, resolvedTextStyleAt(result, segment.range.start));
                    faceTop = uniform[0];
                    faceBottom = uniform[1];
                case UniformParagraphStyle:
                    final paragraph:Array<Float> = uniformTextStyleVerticalBounds(result, segment, result.input.textStyle);
                    faceTop = paragraph[0];
                    faceBottom = paragraph[1];
            }
            final verticalPadding:Float = segment.span.paint.background.verticalPadding;
            output.push(new RichTextLineSegment(segment.span, segment.lineIndex, segment.range, left, LayoutQueries.maxFloat(faceTop - verticalPadding, segment.top), right,
                LayoutQueries.minFloat(faceBottom + verticalPadding, segment.bottom), segment.baseline));
            index += 1;
        }
        return withAdjacentSameStyleClearance(result, output);
    }

    public static function richTextDecorationLineY(result:LayoutResult, segment:RichTextLineSegment, strokeWidth:Float):Float {
        requireFiniteNonNegative(strokeWidth, "strokeWidth must be finite and non-negative");
        if (!isDecorationRole(segment.span.role)) {
            throw new TiqianIllegalArgumentException(Message("richTextDecorationLineY only supports underline and line-through segments"));
        }
        final style:TextStyle = resolvedTextStyleAt(result, segment.range.start);
        var rawLineY:Float = segment.baseline;
        if (Std.isOfType(segment.span.role, Underline)) {
            rawLineY = segment.baseline + style.fontSize * INTERLINEAR_UNDERLINE_OFFSET_EM;
        } else if (Std.isOfType(segment.span.role, LineThrough)) {
            final face:Array<Float> = uniformTextStyleVerticalBounds(result, segment, style);
            rawLineY = (face[0] + face[1]) / 2.0;
        } else {
            rawLineY = segment.baseline;
        }
        return LayoutQueries.clampFloat(rawLineY, segment.top + strokeWidth / 2.0, segment.bottom - strokeWidth / 2.0);
    }

    private static function trimOuterPunctuationGlue(result:LayoutResult, segments:Array<RichTextLineSegment>):Array<RichTextLineSegment> {
        final output:Array<RichTextLineSegment> = [];
        var segmentIndex:Int = 0;
        while (segmentIndex < segments.length) {
            final segment:RichTextLineSegment = segments[segmentIndex];
            if (segment.lineIndex < 0 || segment.lineIndex >= result.lines.length) {
                output.push(segment);
                segmentIndex += 1;
                continue;
            }
            final line:LineBox = result.lines[segment.lineIndex];
            var first:Null<Cluster> = null;
            var last:Null<Cluster> = null;
            var clusterIndex:Int = line.clusterRange.start;
            while (!line.clusterRange.isEmpty && clusterIndex <= line.clusterRange.end) {
                if (clusterIndex >= 0 && clusterIndex < result.clusters.length) {
                    final cluster:Cluster = result.clusters[clusterIndex];
                    if (cluster.range.end > segment.range.start && first == null) {
                        first = cluster;
                    }
                    if (cluster.range.start < segment.range.end) {
                        last = cluster;
                    }
                }
                clusterIndex += 1;
            }
            var leadingGlue:Float = 0.0;
            var trailingGlue:Float = 0.0;
            if (first != null && segment.range.start == first.range.start) {
                final decision:Null<ClusterGeometryDecisionInfo> = geometryDecisionForRange(result, first.range);
                if (decision != null) {
                    leadingGlue = LayoutQueries.maxFloat(decision.leadingGlueNatural - decision.leadingGlueConsumed, 0.0);
                }
            }
            if (last != null && segment.range.end == last.range.end) {
                final decision:Null<ClusterGeometryDecisionInfo> = geometryDecisionForRange(result, last.range);
                if (decision != null) {
                    trailingGlue = LayoutQueries.maxFloat(decision.trailingGlueNatural - decision.trailingGlueConsumed, 0.0);
                }
            }
            final left:Float = LayoutQueries.minFloat(segment.right, segment.left + leadingGlue);
            output.push(new RichTextLineSegment(segment.span, segment.lineIndex, segment.range, left, segment.top,
                LayoutQueries.maxFloat(left, segment.right - trailingGlue), segment.bottom, segment.baseline));
            segmentIndex += 1;
        }
        return output;
    }

    private static function withAdjacentSameStyleClearance(result:LayoutResult, segments:Array<RichTextLineSegment>):Array<RichTextLineSegment> {
        if (segments.length < 2) {
            return segments;
        }
        final output:Array<RichTextLineSegment> = [];
        var index:Int = 0;
        while (index < segments.length) {
            final segment:RichTextLineSegment = segments[index];
            var leadingNeighbour:Null<RichTextLineSegment> = null;
            var trailingNeighbour:Null<RichTextLineSegment> = null;
            var otherIndex:Int = 0;
            while (otherIndex < segments.length) {
                final other:RichTextLineSegment = segments[otherIndex];
                if (other.lineIndex == segment.lineIndex && sameVisibleStyle(segment, other)) {
                    if (other.range.end == segment.range.start) {
                        leadingNeighbour = other;
                    }
                    if (other.range.start == segment.range.end) {
                        trailingNeighbour = other;
                    }
                }
                otherIndex += 1;
            }
            final leadingClearance:Float = sharedClearance(segment, leadingNeighbour);
            final trailingClearance:Float = sharedClearance(segment, trailingNeighbour);
            final left:Float = LayoutQueries.minFloat(segment.right, segment.left + leadingClearance / 2.0);
            output.push(new RichTextLineSegment(segment.span, segment.lineIndex, segment.range, left, segment.top,
                LayoutQueries.maxFloat(left, segment.right - trailingClearance / 2.0), segment.bottom, segment.baseline));
            index += 1;
        }
        return output;
    }

    private static function markedFaceVerticalBounds(result:LayoutResult, covered:Array<PositionedCluster>):Array<Float> {
        var top:Float = Math.POSITIVE_INFINITY;
        var bottom:Float = Math.NEGATIVE_INFINITY;
        covered.forEach(cluster -> {
            final metric:Null<MetricDecisionInfo> = lastMetricContaining(result, cluster.range);
            if (metric != null) {
                top = LayoutQueries.minFloat(top, cluster.baseline - metric.layoutAscent);
                bottom = LayoutQueries.maxFloat(bottom, cluster.baseline + metric.layoutDescent);
            } else {
                final style:TextStyle = resolvedTextStyleAt(result, cluster.range.start);
                top = LayoutQueries.minFloat(top, cluster.baseline - style.fontSize * BACKGROUND_FALLBACK_ASCENT_EM);
                bottom = LayoutQueries.maxFloat(bottom, cluster.baseline + style.fontSize * BACKGROUND_FALLBACK_DESCENT_EM);
            }
        });
        return [top, bottom];
    }

    private static function uniformTextStyleVerticalBounds(result:LayoutResult, segment:RichTextLineSegment, style:TextStyle):Array<Float> {
        var reference:Null<MetricDecisionInfo> = null;
        var firstMatch:Null<MetricDecisionInfo> = null;
        var index:Int = 0;
        while (index < result.presentation.metricDecisions.length) {
            final decision:MetricDecisionInfo = result.presentation.metricDecisions[index];
            if (sameFontMetricStyle(resolvedTextStyleAt(result, decision.range.start), style)) {
                if (firstMatch == null)
                    firstMatch = decision;
                if (decision.metricBox == IDEOGRAPHIC_EM_BOX_NAME)
                    reference = decision;
            }
            index += 1;
        }
        if (reference == null)
            reference = firstMatch;
        final ascent:Float = reference == null ? style.fontSize * BACKGROUND_FALLBACK_ASCENT_EM : reference.layoutAscent;
        final descent:Float = reference == null ? style.fontSize * BACKGROUND_FALLBACK_DESCENT_EM : reference.layoutDescent;
        return [segment.baseline - ascent, segment.baseline + descent];
    }

    private static function resolvedTextStyleAt(result:LayoutResult, offset:Int):TextStyle {
        var index:Int = result.input.content.spans.length - 1;
        while (index >= 0) {
            final span:TextSpan = result.input.content.spans[index];
            if (offset >= span.range.start && offset < span.range.end) {
                return span.style;
            }
            index -= 1;
        }
        return result.input.textStyle;
    }

    private static function sameFontMetricStyle(first:TextStyle, second:TextStyle):Bool {
        return sameStringArray(first.fontFamilies, second.fontFamilies)
            && first.fontSize == second.fontSize
            && first.locale == second.locale
            && first.fontWeight == second.fontWeight
            && first.italic == second.italic
            && first.baselineShift == second.baselineShift;
    }

    private static function naturalLastRight(result:LayoutResult, cluster:PositionedCluster):Float {
        final glyphs:Array<Glyph> = LayoutQueries.glyphsForCluster(result, cluster.range);
        if (glyphs.length == 0) {
            return cluster.right;
        }
        var right:Float = Math.NEGATIVE_INFINITY;
        var index:Int = 0;
        while (index < glyphs.length) {
            right = LayoutQueries.maxFloat(right, cluster.drawX + glyphs[index].x + glyphs[index].advance);
            index += 1;
        }
        return right;
    }

    private static function clustersOnSegmentLine(positioned:Array<PositionedCluster>, segment:RichTextLineSegment):Array<PositionedCluster> {
        final output:Array<PositionedCluster> = [];
        var index:Int = 0;
        while (index < positioned.length) {
            final cluster:PositionedCluster = positioned[index];
            if (cluster.lineIndex == segment.lineIndex
                && cluster.range.end > segment.range.start
                && cluster.range.start < segment.range.end) {
                output.push(cluster);
            }
            index += 1;
        }
        return output;
    }

    private static function geometryDecisionForRange(result:LayoutResult, range:TextRange):Null<ClusterGeometryDecisionInfo> {
        var found:Null<ClusterGeometryDecisionInfo> = null;
        var index:Int = 0;
        while (index < result.presentation.geometryDecisions.length) {
            final decision:ClusterGeometryDecisionInfo = result.presentation.geometryDecisions[index];
            if (LayoutQueries.sameRange(decision.range, range)) {
                found = decision;
            }
            index += 1;
        }
        return found;
    }

    private static function lastMetricContaining(result:LayoutResult, range:TextRange):Null<MetricDecisionInfo> {
        var found:Null<MetricDecisionInfo> = null;
        var index:Int = 0;
        while (index < result.presentation.metricDecisions.length) {
            final decision:MetricDecisionInfo = result.presentation.metricDecisions[index];
            if (range.start >= decision.range.start && range.end <= decision.range.end) {
                found = decision;
            }
            index += 1;
        }
        return found;
    }

    private static function sameStringArray(first:ReadOnlyArray<String>, second:ReadOnlyArray<String>):Bool {
        if (first.length != second.length) {
            return false;
        }
        var index:Int = 0;
        while (index < first.length) {
            if (first[index] != second[index]) {
                return false;
            }
            index += 1;
        }
        return true;
    }

    private static function sameVisibleStyle(first:RichTextLineSegment, second:RichTextLineSegment):Bool {
        return RichTextSpan.sameRole(first.span.role, second.span.role) && first.span.paint.sameVisibleStyle(second.span.paint);
    }

    private static function sharedClearance(segment:RichTextLineSegment, neighbour:Null<RichTextLineSegment>):Float {
        if (neighbour == null || !sameVisibleStyle(segment, neighbour)) {
            return 0.0;
        }
        return LayoutQueries.minFloat(segment.span.paint.adjacentSameStyleClearance, neighbour.span.paint.adjacentSameStyleClearance);
    }

    private static function isDecorationRole(role:RichTextRole):Bool {
        if (Std.isOfType(role, Underline) || Std.isOfType(role, LineThrough))
            return true;
        return false;
    }

    private static function isBackgroundRole(role:RichTextRole):Bool {
        if (Std.isOfType(role, Background) || Std.isOfType(role, InlineCode))
            return true;
        return false;
    }

    private static function resolveRadius(radius:Float, inset:Float, maximum:Float):Float {
        return LayoutQueries.clampFloat(radius - inset, 0.0, maximum);
    }

    private static function requireFiniteNonNegative(value:Float, message:String):Void {
        if (!LayoutQueries.isFinite(value) || value < 0.0) {
            throw new TiqianIllegalArgumentException(Message(message));
        }
    }
}
