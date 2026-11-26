package org.tiqian.core;

using std.Functional;
using org.tiqian.core.LayoutResultFns;
using org.tiqian.core.LayoutResultLineFns;
using org.tiqian.core.IntRangeFns;

import std.ReadOnlyArray;
import std.StringBuf;

// punctuation (a full-width glyph advancing past its half-width cluster box) and 两端对齐 stretch
// contract by appending a fully-selected ruby / 注音 reading in full-width parentheses after its
// One normalized span instance for ALL of this span's slices — allocated once
// the span, and stop past its end — each span scans only its own window.
// or background never acquires an internal sliver (涂). Outer punctuation glue is
// resolved style's declared 字身框. Prefer its real ideographic metric decision; the
// negative reduction, `AutoSpacePolicy.gapEm` at apply time) — geometry reads
// callers interpolate linearly. The two ends are always the occupied box edges — a
// Layout runs on the FULL text (breaking/justification are unaffected — a
// so non-Roman mixed fonts/sizes align by their **字身框底部**. Roman clusters
// `LineEndHangingPunctuation` (CLREQ 行尾点号悬挂). It is part of the emitted
// Start-edge inset of this line along the inline axis (段首缩进 on a
// width fields, mirroring 行尾点号悬挂) — renderers draw a '-' at
// [containerWidth] was floored to an integer number of [cells] (字) of
// (`MeasureAdaptiveKinsoku` keys on the measure in 字; `Fixed` pins it).
// downstream — punctuation geometry falls back to shaped-advance-only.
// `SubstitutionRollbackOnMissingGlyph` — the engine re-shapes with the
// source text instead of showing tofu (e.g. `⸺` is absent from
// Structural advance added by ruby/注音 avoidance. Selection geometry may
// Per-cluster PushIn distribution for CLREQ 推入. Empty for non-PushIn

private typedef CopyAnnotation = {
    var end:Int;
    var text:String;
};

private typedef FloatRangeValue = {
    var range:TextRange;
    var value:Float;
};

private enum SelectionWordKind {
    Word;
    Whitespace;
    Single;
}

private class SelectionBounds {
    public var left:Float;
    public var right:Float;

    public function new(left:Float, right:Float) {
        this.left = left;
        this.right = right;
    }
}

/**
 * Read-only geometry, hit-testing, selection, and rich-text queries over a layout result.
 *
 * Haxe has no direct equivalent of Kotlin extension functions, so the translated public
 * functions take the receiver as their first argument.
 */
class LayoutQueries {
    private static final CR:Int = 0x000D;
    private static final LF:Int = 0x000A;
    private static final NEL:Int = 0x0085;
    private static final LINE_SEPARATOR:Int = 0x2028;
    private static final PARAGRAPH_SEPARATOR:Int = 0x2029;

    public static function resolvedBackgroundCornerRadii(segment:RichTextLineSegment, inset:Float):RichTextCornerRadii {
        return RichTextLayoutQueries.resolvedBackgroundCornerRadii(segment, inset);
    }

    public static function getTextForCopy(result:LayoutResult, range:TextRange):String {
        final source:String = result.input.content.text;
        final start:Int = clampInt(range.start, 0, source.length);
        final end:Int = clampInt(range.end, start, source.length);
        if (start == end) {
            return "";
        }

        final annotations:Array<CopyAnnotation> = [];
        var index:Int = 0;
        while (index < result.presentation.rubyDecisions.length) {
            final decision:RubyDecisionInfo = result.presentation.rubyDecisions[index];
            addCopyAnnotation(annotations, decision.baseRange, decision.text, start, end);
            index += 1;
        }
        index = 0;
        while (index < result.presentation.bopomofoDecisions.length) {
            final decision:BopomofoDecisionInfo = result.presentation.bopomofoDecisions[index];
            addCopyAnnotation(annotations, decision.baseRange, decision.text, start, end);
            index += 1;
        }
        insertionSortAnnotations(annotations);

        final output:StringBuf = new StringBuf();
        var cursor:Int = start;
        index = 0;
        while (index < annotations.length) {
            final annotation:CopyAnnotation = annotations[index];
            if (annotation.end >= cursor && annotation.end <= end) {
                output.add(source.substring(cursor, annotation.end));
                output.add("\uFF08");
                output.add(annotation.text);
                output.add("\uFF09");
                cursor = annotation.end;
            }
            index += 1;
        }
        output.add(source.substring(cursor, end));
        return output.toString();
    }

    /**
     * Plain-text clipboard projection for [range] over a logical document that
     * outlives its layout. Mirrors the Web frontend's annotation contract: a
     * fully selected ruby reading follows its base in full-width parentheses.
     */
    @:topLevel
    public static function projectTextForCopy(source:String, range:TextRange, rubySpans:Array<RubySpan>):String {
        final start:Int = range.start < 0 ? 0 : (range.start > source.length ? source.length : range.start);
        final end:Int = range.end < start ? start : (range.end > source.length ? source.length : range.end);
        if (start == end) {
            return "";
        }
        final annotations:Array<CopyAnnotation> = [];
        var index:Int = 0;
        while (index < rubySpans.length) {
            final span:RubySpan = rubySpans[index];
            if (span.baseRange.start >= start && span.baseRange.end <= end)
                annotations.push({end: span.baseRange.end, text: span.text});
            index += 1;
        }
        // Stable insertion sort by end offset, matching insertionSortAnnotations.
        index = 1;
        while (index < annotations.length) {
            final value:CopyAnnotation = annotations[index];
            var cursor:Int = index - 1;
            while (cursor >= 0 && annotations[cursor].end > value.end) {
                annotations[cursor + 1] = annotations[cursor];
                cursor -= 1;
            }
            annotations[cursor + 1] = value;
            index += 1;
        }
        final output:StringBuf = new StringBuf();
        var cursor:Int = start;
        index = 0;
        while (index < annotations.length) {
            final annotation:CopyAnnotation = annotations[index];
            if (annotation.end >= cursor && annotation.end <= end) {
                output.add(source.substring(cursor, annotation.end));
                output.add("\uFF08");
                output.add(annotation.text);
                output.add("\uFF09");
                cursor = annotation.end;
            }
            index += 1;
        }
        output.add(source.substring(cursor, end));
        return output.toString();
    }

    public static function positionedClusters(result:LayoutResult):Array<PositionedCluster> {
        final output:Array<PositionedCluster> = [];
        var lineIndex:Int = 0;
        while (lineIndex < result.lines.length) {
            final linePositions:Array<PositionedCluster> = positionedClustersAt(result, lineIndex, result.lines[lineIndex]);
            var index:Int = 0;
            while (index < linePositions.length) {
                output.push(linePositions[index]);
                index += 1;
            }
            lineIndex += 1;
        }
        return output;
    }

    public static function positionedClustersForLine(result:LayoutResult, line:LineBox):Array<PositionedCluster> {
        var lineIndex:Int = 0;
        while (lineIndex < result.lines.length && result.lines[lineIndex] != line) {
            lineIndex += 1;
        }
        if (lineIndex >= result.lines.length) {
            throw new TiqianIllegalArgumentException(Message("line must belong to this LayoutResult."));
        }
        return positionedClustersAt(result, lineIndex, line);
    }

    public static function glyphInkBounds(result:LayoutResult):Null<Rect> {
        final positioned:Array<PositionedCluster> = positionedClusters(result);
        var left:Float = Math.POSITIVE_INFINITY;
        var top:Float = Math.POSITIVE_INFINITY;
        var right:Float = Math.NEGATIVE_INFINITY;
        var bottom:Float = Math.NEGATIVE_INFINITY;
        var runIndex:Int = 0;
        while (runIndex < result.glyphRuns.length) {
            final run:GlyphRun = result.glyphRuns[runIndex];
            var glyphIndex:Int = 0;
            while (glyphIndex < run.glyphs.length) {
                final glyph:Glyph = run.glyphs[glyphIndex];
                if (glyph.bounds != null) {
                    final cluster:Null<PositionedCluster> = findPositionedByRange(positioned, glyph.clusterRange);
                    if (cluster != null) {
                        final bounds:Rect = glyph.bounds;
                        left = minFloat(left, cluster.drawX + glyph.x + bounds.left);
                        top = minFloat(top, cluster.baseline + glyph.y + bounds.top);
                        right = maxFloat(right, cluster.drawX + glyph.x + bounds.right);
                        bottom = maxFloat(bottom, cluster.baseline + glyph.y + bounds.bottom);
                    }
                }
                glyphIndex += 1;
            }
            runIndex += 1;
        }
        if (!isFinite(left) || !isFinite(top) || !isFinite(right) || !isFinite(bottom)) {
            return null;
        }
        return new Rect(left, top, right, bottom);
    }

    public static function getLineForOffset(result:LayoutResult, offset:Int):Int {
        if (result.lines.length == 0) {
            return -1;
        }
        final clamped:Int = clampInt(offset, 0, result.input.content.text.length);
        if (clamped == result.input.content.text.length) {
            return result.lines.length - 1;
        }
        var index:Int = 0;
        while (index < result.lines.length) {
            final line:LineBox = result.lines[index];
            if (clamped >= line.range.start && clamped < line.range.end) {
                return index;
            }
            index += 1;
        }
        return nearestLineForOffset(result, clamped);
    }

    public static function getBoundingBox(result:LayoutResult, offset:Int):Rect {
        if (result.lines.length == 0) {
            return new Rect(0.0, 0.0, 0.0, 0.0);
        }
        final clamped:Int = clampInt(offset, 0, result.input.content.text.length);
        if (clamped == result.input.content.text.length) {
            return getCursorRect(result, clamped);
        }
        final positioned:Array<PositionedCluster> = positionedClusters(result);
        final match:Null<PositionedCluster> = positioned.firstOrNull(cluster -> clamped >= cluster.range.start && clamped < cluster.range.end);
        return match == null ? getCursorRect(result, clamped) : match.rect;
    }

    public static function getBoundingBoxes(result:LayoutResult, range:TextRange):Array<Rect> {
        if (range.isEmpty || result.lines.length == 0) {
            return [];
        }
        final start:Int = clampInt(range.start, 0, result.input.content.text.length);
        final end:Int = clampInt(range.end, start, result.input.content.text.length);
        if (start == end) {
            return [];
        }
        final positioned:Array<PositionedCluster> = positionedClusters(result);
        return positioned.mapNotNull(cluster -> sliceRectIfCovered(cluster, start, end));
    }

    public static function getBoundingBoxesInt(result:LayoutResult, start:Int, end:Int):Array<Rect> {
        return getBoundingBoxes(result, new TextRange(start, end));
    }

    public static function positionedRichTextSegments(result:LayoutResult, spans:Array<RichTextSpan>):Array<RichTextLineSegment> {
        return RichTextLayoutQueries.positionedRichTextSegments(result, spans);
    }

    public static function trimmedRichTextDecorationSegments(result:LayoutResult, occupiedSegments:Array<RichTextLineSegment>):Array<RichTextLineSegment> {
        return RichTextLayoutQueries.trimmedRichTextDecorationSegments(result, occupiedSegments);
    }

    public static function richTextBackgroundSegments(result:LayoutResult, occupiedSegments:Array<RichTextLineSegment>):Array<RichTextLineSegment> {
        return RichTextLayoutQueries.richTextBackgroundSegments(result, occupiedSegments);
    }

    public static function richTextDecorationLineY(result:LayoutResult, segment:RichTextLineSegment, strokeWidth:Float):Float {
        return RichTextLayoutQueries.richTextDecorationLineY(result, segment, strokeWidth);
    }

    public static function getCursorRect(result:LayoutResult, offset:Int):Rect {
        if (result.lines.length == 0) {
            return new Rect(0.0, 0.0, 0.0, 0.0);
        }
        final clamped:Int = clampInt(offset, 0, result.input.content.text.length);
        final lineIndex:Int = maxInt(getLineForOffset(result, clamped), 0);
        final line:LineBox = result.lines[lineIndex];
        final positioned:Array<PositionedCluster> = positionedClustersAt(result, lineIndex, line);
        var x:Float = line.indent;
        if (positioned.length > 0) {
            if (clamped <= positioned[0].range.start) {
                x = positioned[0].left;
            } else if (clamped >= positioned[positioned.length - 1].range.end) {
                x = positioned[positioned.length - 1].right;
            } else {
                var index:Int = 0;
                var found:Bool = false;
                while (index < positioned.length) {
                    final cluster:PositionedCluster = positioned[index];
                    if (clamped >= cluster.range.start && clamped <= cluster.range.end) {
                        x = xForOffset(cluster, clamped);
                        found = true;
                        break;
                    }
                    index += 1;
                }
                if (!found) {
                    throw new TiqianNoSuchElementException(Message("Collection contains no element matching the predicate."));
                }
            }
        }
        return new Rect(x, line.top, x + 1.0, line.bottom);
    }

    public static function getOffsetForPosition(result:LayoutResult, x:Float, y:Float):Int {
        if (result.lines.length == 0) {
            return 0;
        }
        final lineIndex:Int = nearestLineForY(result, y);
        final positioned:Array<PositionedCluster> = positionedClustersAt(result, lineIndex, result.lines[lineIndex]);
        if (positioned.length == 0) {
            return result.lines[lineIndex].range.start;
        }
        if (x <= positioned[0].left) {
            return positioned[0].range.start;
        }
        if (x >= positioned[positioned.length - 1].right) {
            return positioned[positioned.length - 1].range.end;
        }
        final cluster:PositionedCluster = nearestCluster(positioned, x);
        return offsetForX(cluster, x);
    }

    public static function getSelectionOffsetForPosition(result:LayoutResult, x:Float, y:Float):Int {
        if (result.lines.length == 0) {
            return 0;
        }
        final lineIndex:Int = nearestLineForY(result, y);
        final positioned:Array<PositionedCluster> = positionedClustersAt(result, lineIndex, result.lines[lineIndex]);
        if (positioned.length == 0) {
            return coerceSelectionOffset(result, result.lines[lineIndex].range.start, SourceBoundaryBias.Nearest);
        }
        if (x <= positioned[0].left) {
            return coerceSelectionOffset(result, positioned[0].range.start, SourceBoundaryBias.Nearest);
        }
        if (x >= positioned[positioned.length - 1].right) {
            return coerceSelectionOffset(result, positioned[positioned.length - 1].range.end, SourceBoundaryBias.Nearest);
        }
        final candidate:Null<PositionedCluster> = positioned.firstOrNull(cluster -> x >= cluster.left && x <= cluster.right);
        final cluster:PositionedCluster = candidate != null ? candidate : nearestCluster(positioned, x);
        final rawOffset:Int = offsetForX(cluster, x);
        final backward:Int = coerceSelectionOffset(result, rawOffset, SourceBoundaryBias.Backward);
        final forward:Int = coerceSelectionOffset(result, rawOffset, SourceBoundaryBias.Forward);
        if (backward == forward) {
            return backward;
        }
        final backwardDistance:Float = Math.abs(getCursorRect(result, backward).left - x);
        final forwardDistance:Float = Math.abs(getCursorRect(result, forward).left - x);
        return backwardDistance < forwardDistance ? backward : forward;
    }

    public static function coerceSelectionOffset(result:LayoutResult, offset:Int, bias:SourceBoundaryBias):Int {
        return coerceTextSelectionOffset(result.input.content.text, result.input.inlineObjects, offset, bias);
    }

    /**
     * Safe source-boundary coercion for logical documents that outlive their
     * attached layout. This is the receiver-free form of
     * [coerceSelectionOffset].
     */
    @:topLevel
    public static function coerceTextSelectionOffset(text:String, inlineObjects:ReadOnlyArray<InlineObjectSpan>, offset:Int, bias:SourceBoundaryBias):Int {
        final clamped:Int = offset < 0 ? 0 : (offset > text.length ? text.length : offset);
        var index:Int = 0;
        while (index < inlineObjects.length) {
            final inlineObject:InlineObjectSpan = inlineObjects[index];
            if (clamped > inlineObject.range.start && clamped < inlineObject.range.end) {
                var snapped:Int = inlineObject.range.start;
                switch (bias) {
                    case Backward:
                        snapped = inlineObject.range.start;
                    case Forward:
                        snapped = inlineObject.range.end;
                    case Nearest:
                        snapped = clamped - inlineObject.range.start < inlineObject.range.end - clamped ? inlineObject.range.start : inlineObject.range.end;
                }
                return snapped;
            }
            index += 1;
        }
        return SourceInteractionBoundaries.coerceToInteractionBoundary(text, clamped, new TextRange(0, text.length), bias);
    }

    public static function getSelectionWordBoundary(result:LayoutResult, offset:Int):TextRange {
        final text:String = result.input.content.text;
        if (text.length == 0) {
            return new TextRange(0, 0);
        }
        final clamped:Int = clampInt(offset, 0, text.length);
        var objectIndex:Int = 0;
        while (objectIndex < result.input.inlineObjects.length) {
            final inlineObject:InlineObjectSpan = result.input.inlineObjects[objectIndex];
            if (clamped >= inlineObject.range.start && clamped < inlineObject.range.end) {
                return inlineObject.range;
            }
            objectIndex += 1;
        }
        final boundaries:Array<Int> = SourceInteractionBoundaries.interactionBoundaries(text, new TextRange(0, text.length));
        var unitIndex:Int = 0;
        if (clamped == text.length) {
            unitIndex = boundaries.length - 2;
        } else {
            unitIndex = boundaryIndex(boundaries, clamped);
        }
        if (unitIndex < 0) {
            unitIndex = 0;
        }
        final kind:SelectionWordKind = selectionWordKind(text, boundaries[unitIndex], boundaries[unitIndex + 1]);
        if (kind == Single) {
            return new TextRange(boundaries[unitIndex], boundaries[unitIndex + 1]);
        }
        var first:Int = unitIndex;
        var last:Int = unitIndex;
        while (first > 0 && selectionWordKind(text, boundaries[first - 1], boundaries[first]) == kind) {
            first -= 1;
        }
        while (last + 2 < boundaries.length && selectionWordKind(text, boundaries[last + 1], boundaries[last + 2]) == kind) {
            last += 1;
        }
        return new TextRange(boundaries[first], boundaries[last + 1]);
    }

    public static function getSelectionWordBoundaryForPosition(result:LayoutResult, x:Float, y:Float):Null<TextRange> {
        if (result.lines.length == 0 || result.input.content.text.length == 0) {
            return null;
        }
        final lineIndex:Int = nearestLineForY(result, y);
        final positioned:Array<PositionedCluster> = positionedClustersAt(result, lineIndex, result.lines[lineIndex]);
        if (positioned.length == 0) {
            return null;
        }
        final candidate:Null<PositionedCluster> = positioned.firstOrNull(cluster -> x >= cluster.left && x <= cluster.right);
        final cluster:PositionedCluster = candidate != null ? candidate : nearestCluster(positioned, x);
        if (cluster.range.isEmpty) {
            return null;
        }
        final sourceUnitOffset:Int = clampInt(offsetForX(cluster, x), cluster.range.start, cluster.range.end - 1);
        return getSelectionWordBoundary(result, sourceUnitOffset);
    }

    private static function positionedClustersAt(result:LayoutResult, lineIndex:Int, line:LineBox):Array<PositionedCluster> {
        final leadingConsumed:Array<FloatRangeValue> = [];
        var index:Int = 0;
        while (index < result.presentation.geometryDecisions.length) {
            final decision:ClusterGeometryDecisionInfo = result.presentation.geometryDecisions[index];
            if (decision.leadingGlueConsumed > 0.0) {
                setFloatByRange(leadingConsumed, decision.range, decision.leadingGlueConsumed);
            }
            index += 1;
        }
        final leadingAutoSpaceGaps:Array<FloatRangeValue> = [];
        index = 0;
        while (index < result.presentation.autoSpaceDecisions.length) {
            final decision:AutoSpaceDecisionInfo = result.presentation.autoSpaceDecisions[index];
            if (decision.side == "leading") {
                setFloatByRange(leadingAutoSpaceGaps, decision.clusterRange, -decision.totalReduction);
            }
            index += 1;
        }

        final positioned:Array<PositionedCluster> = [];
        var x:Float = line.indent;
        var clusterIndex:Int = line.clusterRange.start;
        var indexInLine:Int = 0;
        while (!line.clusterRange.isEmpty && clusterIndex <= line.clusterRange.end) {
            if (clusterIndex >= 0 && clusterIndex < result.clusters.length) {
                final cluster:Cluster = result.clusters[clusterIndex];
                final leadingGap:Float = indexInLine == 0 ? 0.0 : floatByRange(leadingAutoSpaceGaps, cluster.range);
                final drawX:Float = x + cluster.leadingLayoutAdvance + cluster.glyphInlineShift + leadingGap - floatByRange(leadingConsumed, cluster.range);
                final right:Float = x + cluster.advance;
                final glyphs:Array<Glyph> = glyphsForCluster(result, cluster.range);
                var sourceStops:Null<Array<Float>> = null;
                if (cluster.range.length > 1 && glyphs.length == cluster.range.length) {
                    final stops:Array<Float> = [x];
                    var glyphIndex:Int = 1;
                    while (glyphIndex < cluster.range.length) {
                        stops.push(clampFloat(drawX + glyphs[glyphIndex].x, x, right));
                        glyphIndex += 1;
                    }
                    stops.push(right);
                    sourceStops = stops;
                }
                positioned.push(new PositionedCluster(lineIndex, clusterIndex, cluster.range, x, line.top, right, line.bottom,
                    line.baseline + cluster.baselineShift, drawX, sourceStops));
                x += cluster.advance;
                indexInLine += 1;
            }
            clusterIndex += 1;
        }
        return withRubySelectionGeometry(result, positioned, lineIndex);
    }

    private static function withRubySelectionGeometry(result:LayoutResult, positioned:Array<PositionedCluster>, lineIndex:Int):Array<PositionedCluster> {
        final rubies:Array<RubyDecisionInfo> = [];
        var rubyIndex:Int = 0;
        while (rubyIndex < result.presentation.rubyDecisions.length) {
            final ruby:RubyDecisionInfo = result.presentation.rubyDecisions[rubyIndex];
            if (ruby.lineIndex == lineIndex && ruby.width > 0.0)
                rubies.push(ruby);
            rubyIndex++;
        }
        if (rubies.length == 0)
            return positioned;
        final bounds:Array<SelectionBounds> = positioned.map(cluster -> {
            final spread:Float = floatByRangeFromGeometry(result, cluster.range);
            return new SelectionBounds(cluster.left, maxFloat(cluster.right - spread, cluster.left));
        });
        var rubyIndex:Int = 0;
        var index:Int = 0;
        while (rubyIndex < rubies.length) {
            final ruby = rubies[rubyIndex];
            final baseIndices:Array<Int> = [
                for (index in 0...positioned.length)
                    if (positioned[index].range.start >= ruby.baseRange.start && positioned[index].range.end <= ruby.baseRange.end) index
            ];
            if (baseIndices.length > 0) {
                final centers:Array<Float> = baseIndices.map(i -> centerOfCluster(result, positioned[i]));
                final rubyLeft = ruby.centerX - ruby.width / 2.0;
                final rubyRight = ruby.centerX + ruby.width / 2.0;
                index = 0;
                while (index < baseIndices.length) {
                    final idx = baseIndices[index];
                    final bound = bounds[idx];
                    bounds[idx] = new SelectionBounds(
                        minFloat(bound.left, index == 0 ? rubyLeft : maxFloat(rubyLeft, (centers[index - 1] + centers[index]) / 2.0)),
                        maxFloat(bound.right,
                            index == baseIndices.length - 1 ? rubyRight : minFloat(rubyRight, (centers[index] + centers[index + 1]) / 2.0)));
                    index++;
                }
            }
            rubyIndex++;
        }
        var index:Int = 0;
        while (index + 1 < bounds.length) {
            final left = bounds[index];
            final right = bounds[index + 1];
            if (left.right > right.left) {
                final center = clampFloat((centerOfCluster(result, positioned[index]) + centerOfCluster(result, positioned[index + 1])) / 2.0,
                    minFloat(left.left, right.left), maxFloat(left.right, right.right));
                bounds[index] = new SelectionBounds(left.left, maxFloat(minFloat(left.right, center), left.left));
                bounds[index + 1] = new SelectionBounds(minFloat(maxFloat(right.left, center), right.right), right.right);
            }
            index++;
        }
        final output:Array<PositionedCluster> = [];
        index = 0;
        while (index < positioned.length) {
            final cluster = positioned[index];
            final bound = bounds[index];
            output.push(new PositionedCluster(cluster.lineIndex, cluster.clusterIndex, cluster.range, bound.left, cluster.top, bound.right, cluster.bottom,
                cluster.baseline, cluster.drawX, null));
            index++;
        }
        return output;
    }

    private static function nearestLineForOffset(result:LayoutResult, offset:Int):Int {
        var bestIndex:Int = 0;
        var bestDistance:Int = 2147483647;
        var index:Int = 0;
        while (index < result.lines.length) {
            final line:LineBox = result.lines[index];
            final distance:Int = offset < line.range.start ? line.range.start - offset : offset > line.range.end ? offset - line.range.end : 0;
            if (distance < bestDistance) {
                bestDistance = distance;
                bestIndex = index;
            }
            index += 1;
        }
        return bestIndex;
    }

    private static function nearestLineForY(result:LayoutResult, y:Float):Int {
        var bestIndex:Int = 0;
        var bestDistance:Float = Math.POSITIVE_INFINITY;
        var index:Int = 0;
        while (index < result.lines.length) {
            final line:LineBox = result.lines[index];
            final distance:Float = y < line.top ? line.top - y : y > line.bottom ? y - line.bottom : 0.0;
            if (distance < bestDistance) {
                bestDistance = distance;
                bestIndex = index;
            }
            index += 1;
        }
        return bestIndex;
    }

    private static function nearestCluster(clusters:Array<PositionedCluster>, x:Float):PositionedCluster {
        var best:PositionedCluster = clusters[0];
        var bestDistance:Float = distanceToCluster(best, x);
        var index:Int = 1;
        while (index < clusters.length) {
            final candidate:PositionedCluster = clusters[index];
            final distance:Float = distanceToCluster(candidate, x);
            if (distance < bestDistance) {
                best = candidate;
                bestDistance = distance;
            }
            index += 1;
        }
        return best;
    }

    private static function distanceToCluster(cluster:PositionedCluster, x:Float):Float {
        if (x < cluster.left) {
            return cluster.left - x;
        }
        if (x > cluster.right) {
            return x - cluster.right;
        }
        return 0.0;
    }

    private static function xForOffset(cluster:PositionedCluster, offset:Int):Float {
        if (cluster.range.length <= 0) {
            return cluster.left;
        }
        final index:Int = clampInt(offset - cluster.range.start, 0, cluster.range.length);
        if (cluster.sourceStops != null) {
            return cluster.sourceStops[index];
        }
        // Legacy LayoutQueries.kt:818 divides as Float (`i.toFloat() /
        // range.length.toFloat()`). The Kotlin backend renders an Int/Int
        // division as Kotlin Int division, which truncates, so widen the
        // numerator the way LineBreaker.hx already widens leaveRaggedPenalty
        // (LineBreaker.kt:763 `leaveRaggedPenalty.toFloat()`).
        return cluster.left + cluster.width * ((index * 1.0) / cluster.range.length);
    }

    private static function offsetForX(cluster:PositionedCluster, x:Float):Int {
        if (cluster.range.length <= 0) {
            return cluster.range.start;
        }
        if (cluster.sourceStops != null) {
            var bestIndex:Int = 0;
            var bestDistance:Float = Math.POSITIVE_INFINITY;
            var index:Int = 0;
            while (index < cluster.sourceStops.length) {
                final distance:Float = Math.abs(x - cluster.sourceStops[index]);
                if (distance < bestDistance) {
                    bestDistance = distance;
                    bestIndex = index;
                }
                index += 1;
            }
            return clampInt(cluster.range.start + bestIndex, cluster.range.start, cluster.range.end);
        }
        if (cluster.width <= 0.0) {
            return cluster.range.start;
        }
        final ratio:Float = clampFloat((x - cluster.left) / cluster.width, 0.0, 1.0);
        return clampInt(cluster.range.start + Math.round(ratio * cluster.range.length), cluster.range.start, cluster.range.end);
    }

    @:allow(org.tiqian.core.RichTextLayoutQueries)
    private static function sliceRect(cluster:PositionedCluster, start:Int, end:Int):Rect {
        if (cluster.range.length <= 0 || cluster.width <= 0.0) {
            return cluster.rect;
        }
        return new Rect(xForOffset(cluster, start), cluster.top, xForOffset(cluster, end), cluster.bottom);
    }

    private static function sliceRectIfCovered(cluster:PositionedCluster, start:Int, end:Int):Null<Rect> {
        final sliceStart:Int = maxInt(start, cluster.range.start);
        final sliceEnd:Int = minInt(end, cluster.range.end);
        return sliceStart < sliceEnd ? sliceRect(cluster, sliceStart, sliceEnd) : null;
    }

    @:allow(org.tiqian.core.RichTextLayoutQueries)
    private static function glyphsForCluster(result:LayoutResult, range:TextRange):Array<Glyph> {
        final output:Array<Glyph> = [];
        var runIndex:Int = 0;
        while (runIndex < result.glyphRuns.length) {
            final glyphs:ReadOnlyArray<Glyph> = result.glyphRuns[runIndex].glyphs;
            var glyphIndex:Int = 0;
            while (glyphIndex < glyphs.length) {
                if (sameRange(glyphs[glyphIndex].clusterRange, range)) {
                    output.push(glyphs[glyphIndex]);
                }
                glyphIndex += 1;
            }
            runIndex += 1;
        }
        return output;
    }

    private static function centerOfCluster(result:LayoutResult, cluster:PositionedCluster):Float {
        final glyphs:Array<Glyph> = glyphsForCluster(result, cluster.range);
        var natural:Float = 0.0;
        var index:Int = 0;
        while (index < glyphs.length) {
            natural += glyphs[index].advance;
            index += 1;
        }
        if (glyphs.length == 0) {
            natural = cluster.width - floatByRangeFromGeometry(result, cluster.range);
        }
        return cluster.drawX + maxFloat(natural, 0.0) / 2.0;
    }

    private static function floatByRangeFromGeometry(result:LayoutResult, range:TextRange):Float {
        var index:Int = 0;
        while (index < result.presentation.geometryDecisions.length) {
            final decision:ClusterGeometryDecisionInfo = result.presentation.geometryDecisions[index];
            if (sameRange(decision.range, range) && decision.rubySpread != 0.0) {
                return decision.rubySpread;
            }
            index += 1;
        }
        return 0.0;
    }

    private static function findPositionedByRange(positioned:Array<PositionedCluster>, range:TextRange):Null<PositionedCluster> {
        var index:Int = 0;
        while (index < positioned.length) {
            if (sameRange(positioned[index].range, range)) {
                return positioned[index];
            }
            index += 1;
        }
        return null;
    }

    private static function setFloatByRange(values:Array<FloatRangeValue>, range:TextRange, value:Float):Void {
        var index:Int = 0;
        while (index < values.length) {
            if (sameRange(values[index].range, range)) {
                values[index].value = value;
                return;
            }
            index += 1;
        }
        values.push({range: range, value: value});
    }

    private static function floatByRange(values:Array<FloatRangeValue>, range:TextRange):Float {
        var index:Int = 0;
        while (index < values.length) {
            if (sameRange(values[index].range, range)) {
                return values[index].value;
            }
            index += 1;
        }
        return 0.0;
    }

    private static function selectionWordKind(text:String, start:Int, end:Int):SelectionWordKind {
        final codePoint:Int = SourceInteractionBoundaries.codePointAtCompat(text, start, end);
        if (codePoint == CR
            || codePoint == LF
            || codePoint == NEL
            || codePoint == LINE_SEPARATOR
            || codePoint == PARAGRAPH_SEPARATOR) {
            return Single;
        }
        if (isWhitespace(codePoint)) {
            return Whitespace;
        }
        if (isHanIdeograph(codePoint)) {
            return Single;
        }
        if (isLetterOrDigit(codePoint) || codePoint == 0x5F || codePoint == 0x27 || codePoint == 0x2019) {
            return Word;
        }
        return Single;
    }

    private static function isWhitespace(codePoint:Int):Bool {
        return (codePoint >= 0x0009 && codePoint <= 0x000D)
            || (codePoint >= 0x001C && codePoint <= 0x0020)
            || codePoint == 0x00A0
            || codePoint == 0x1680
            || (codePoint >= 0x2000 && codePoint <= 0x200A)
            || codePoint == 0x2028
            || codePoint == 0x2029
            || codePoint == 0x202F
            || codePoint == 0x205F
            || codePoint == 0x3000;
    }

    private static function isLetterOrDigit(codePoint:Int):Bool {
        if (codePoint >= 0xD800 && codePoint <= 0xDFFF) {
            return false;
        }
        if ((codePoint >= 0x0041 && codePoint <= 0x005A)
            || (codePoint >= 0x0061 && codePoint <= 0x007A)
            || (codePoint >= 0x0030 && codePoint <= 0x0039)) {
            return true;
        }
        if (codePoint < 0 || codePoint > 0x10FFFF) {
            return false;
        }
        return UnicodeWordCharacterData.contains(codePoint);
    }

    private static function isHanIdeograph(codePoint:Int):Bool {
        return (codePoint >= 0x3400 && codePoint <= 0x4DBF)
            || (codePoint >= 0x4E00 && codePoint <= 0x9FFF)
            || (codePoint >= 0xF900 && codePoint <= 0xFAFF)
            || (codePoint >= 0x20000 && codePoint <= 0x323AF);
    }

    private static function boundaryIndex(boundaries:Array<Int>, offset:Int):Int {
        var low:Int = 0;
        var high:Int = boundaries.length - 1;
        while (low <= high) {
            final middle:Int = (low + high) >> 1;
            final value:Int = boundaries[middle];
            if (value == offset) {
                return middle == boundaries.length - 1 ? middle - 1 : middle;
            }
            if (value < offset) {
                low = middle + 1;
            } else {
                high = middle - 1;
            }
        }
        return maxInt(0, high);
    }

    private static function addCopyAnnotation(values:Array<CopyAnnotation>, baseRange:TextRange, text:String, start:Int, end:Int):Void {
        if (baseRange.start >= start && baseRange.end <= end) {
            values.push({end: baseRange.end, text: text});
        }
    }

    private static function insertionSortAnnotations(values:Array<CopyAnnotation>):Void {
        var index:Int = 1;
        while (index < values.length) {
            final value:CopyAnnotation = values[index];
            var cursor:Int = index - 1;
            while (cursor >= 0 && values[cursor].end > value.end) {
                values[cursor + 1] = values[cursor];
                cursor -= 1;
            }
            values[cursor + 1] = value;
            index += 1;
        }
    }

    @:allow(org.tiqian.core.RichTextLayoutQueries)
    private static function sameRange(first:TextRange, second:TextRange):Bool {
        return first.start == second.start && first.end == second.end;
    }

    @:allow(org.tiqian.core.RichTextLayoutQueries)
    private static function isFinite(value:Float):Bool {
        return value == value && value != Math.POSITIVE_INFINITY && value != Math.NEGATIVE_INFINITY;
    }

    @:allow(org.tiqian.core.RichTextLayoutQueries)
    private static function clampInt(value:Int, low:Int, high:Int):Int {
        if (value < low) {
            return low;
        }
        if (value > high) {
            return high;
        }
        return value;
    }

    @:allow(org.tiqian.core.RichTextLayoutQueries)
    private static function maxInt(first:Int, second:Int):Int {
        return first > second ? first : second;
    }

    @:allow(org.tiqian.core.RichTextLayoutQueries)
    private static function minInt(first:Int, second:Int):Int {
        return first < second ? first : second;
    }

    @:allow(org.tiqian.core.RichTextLayoutQueries)
    private static function clampFloat(value:Float, low:Float, high:Float):Float {
        if (value < low) {
            return low;
        }
        if (value > high) {
            return high;
        }
        return value;
    }

    @:allow(org.tiqian.core.RichTextLayoutQueries)
    private static function maxFloat(first:Float, second:Float):Float {
        return first > second ? first : second;
    }

    @:allow(org.tiqian.core.RichTextLayoutQueries)
    private static function minFloat(first:Float, second:Float):Float {
        return first < second ? first : second;
    }
}
