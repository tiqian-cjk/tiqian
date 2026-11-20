package org.tiqian.core;

import std.ReadOnlyArray;
import std.HashMap;

/**
 * Immutable lookup data derived exclusively from one LayoutResult.
 *
 * Port of the handwritten engine's LayoutResultReplayIndex.kt. It makes no
 * layout decisions and changes no geometry: it retains the core query results
 * and glyph grouping that Kotlin frontends otherwise rebuilt on every draw.
 * @:extension emits the published Kotlin receiver shapes
 * (result.toReplayIndex(spans), index.selectionBoxes(result, range)).
 */
@:dataClass
class LayoutResultReplayIndex {
    public final positionedClusters:Array<PositionedCluster>;
    public final positionedClustersByLine:Array<Array<PositionedCluster>>;
    public final richTextSegments:Array<RichTextLineSegment>;
    public final richTextBackgroundSegments:Array<RichTextLineSegment>;
    public final richTextDecorationSegments:Array<RichTextLineSegment>;
    public final glyphsByClusterRange:HashMap<TextRange, ReadOnlyArray<Glyph>>;
    public final openTypeFeaturesByClusterRange:HashMap<TextRange, ReadOnlyArray<String>>;
    public final fontRoleByClusterRange:HashMap<TextRange, Null<String>>;

    public function new(positionedClusters:Array<PositionedCluster>, positionedClustersByLine:Array<Array<PositionedCluster>>,
            richTextSegments:Array<RichTextLineSegment>, richTextBackgroundSegments:Array<RichTextLineSegment>,
            richTextDecorationSegments:Array<RichTextLineSegment>, glyphsByClusterRange:HashMap<TextRange, ReadOnlyArray<Glyph>>,
            openTypeFeaturesByClusterRange:HashMap<TextRange, ReadOnlyArray<String>>,
            fontRoleByClusterRange:HashMap<TextRange, Null<String>>) {
        this.positionedClusters = positionedClusters;
        this.positionedClustersByLine = positionedClustersByLine;
        this.richTextSegments = richTextSegments;
        this.richTextBackgroundSegments = richTextBackgroundSegments;
        this.richTextDecorationSegments = richTextDecorationSegments;
        this.glyphsByClusterRange = glyphsByClusterRange;
        this.openTypeFeaturesByClusterRange = openTypeFeaturesByClusterRange;
        this.fontRoleByClusterRange = fontRoleByClusterRange;
    }
}

@:keep
class LayoutResultReplayIndexFns {
    @:extension
    public static function toReplayIndex(result:LayoutResult, richTextSpans:ReadOnlyArray<RichTextSpan>):LayoutResultReplayIndex {
        final positioned = LayoutQueries.positionedClusters(result);
        final positionedByLine = new Array<Array<PositionedCluster>>();
        var lineIndex = 0;
        while (lineIndex < result.lines.length) {
            positionedByLine.push(new Array<PositionedCluster>());
            lineIndex += 1;
        }
        var positionedIndex = 0;
        while (positionedIndex < positioned.length) {
            final cluster = positioned[positionedIndex];
            if (cluster.lineIndex >= 0 && cluster.lineIndex < positionedByLine.length) {
                positionedByLine[cluster.lineIndex].push(cluster);
            }
            positionedIndex += 1;
        }
        final spansArray = new Array<RichTextSpan>();
        var spanIndex = 0;
        while (spanIndex < richTextSpans.length) {
            spansArray.push(richTextSpans[spanIndex]);
            spanIndex += 1;
        }
        final richTextSegments = LayoutQueries.positionedRichTextSegments(result, spansArray);

        final openTypeFeaturesByClusterRange = new HashMap<TextRange, ReadOnlyArray<String>>();
        var runIndex = 0;
        var clusterIndex = 0;
        while (clusterIndex < result.clusters.length) {
            final cluster = result.clusters[clusterIndex];
            while (runIndex < result.glyphRuns.length && result.glyphRuns[runIndex].range.end <= cluster.range.start) {
                runIndex += 1;
            }
            final features = new Array<String>();
            if (runIndex < result.glyphRuns.length) {
                final run = result.glyphRuns[runIndex];
                if (cluster.range.start >= run.range.start && cluster.range.end <= run.range.end) {
                    var featureIndex = 0;
                    while (featureIndex < run.openTypeFeatures.length) {
                        features.push(run.openTypeFeatures[featureIndex]);
                        featureIndex += 1;
                    }
                }
            }
            openTypeFeaturesByClusterRange.set(cluster.range, features);
            clusterIndex += 1;
        }

        final fontRoleByClusterRange = new HashMap<TextRange, Null<String>>();
        var decisionIndex = 0;
        var positionedIndex2 = 0;
        while (positionedIndex2 < positioned.length) {
            final cluster = positioned[positionedIndex2];
            final range = result.clusters[cluster.clusterIndex].range;
            while (decisionIndex < result.debug.fontDecisions.length
                && result.debug.fontDecisions[decisionIndex].range.end <= range.start) {
                decisionIndex += 1;
            }
            var role:Null<String> = null;
            if (decisionIndex < result.debug.fontDecisions.length) {
                final decision = result.debug.fontDecisions[decisionIndex];
                if (range.start >= decision.range.start && range.end <= decision.range.end) {
                    role = decision.role;
                }
            }
            fontRoleByClusterRange.set(range, role);
            positionedIndex2 += 1;
        }

        final glyphKeys = new Array<TextRange>();
        final glyphValues = new Array<Array<Glyph>>();
        var glyphRunIndex = 0;
        while (glyphRunIndex < result.glyphRuns.length) {
            final run = result.glyphRuns[glyphRunIndex];
            var runGlyphIndex = 0;
            while (runGlyphIndex < run.glyphs.length) {
                final glyph = run.glyphs[runGlyphIndex];
                var found = -1;
                var glyphIndex = 0;
                while (glyphIndex < glyphKeys.length) {
                    if (glyphKeys[glyphIndex].start == glyph.clusterRange.start && glyphKeys[glyphIndex].end == glyph.clusterRange.end) {
                        found = glyphIndex;
                        break;
                    }
                    glyphIndex += 1;
                }
                if (found >= 0) {
                    glyphValues[found].push(glyph);
                } else {
                    glyphKeys.push(glyph.clusterRange);
                    glyphValues.push([glyph]);
                }
                runGlyphIndex += 1;
            }
            glyphRunIndex += 1;
        }
        final glyphsByClusterRange = new HashMap<TextRange, ReadOnlyArray<Glyph>>();
        var glyphKeyIndex = 0;
        while (glyphKeyIndex < glyphKeys.length) {
            glyphsByClusterRange.set(glyphKeys[glyphKeyIndex], glyphValues[glyphKeyIndex]);
            glyphKeyIndex += 1;
        }

        return new LayoutResultReplayIndex(
            positioned,
            positionedByLine,
            richTextSegments,
            LayoutQueries.richTextBackgroundSegments(result, richTextSegments),
            LayoutQueries.trimmedRichTextDecorationSegments(result, richTextSegments),
            glyphsByClusterRange,
            openTypeFeaturesByClusterRange,
            fontRoleByClusterRange
        );
    }

    /** Hot-path selection hit test over the immutable replay geometry. */
    @:extension
    public static function selectionOffsetForPosition(index:LayoutResultReplayIndex, result:LayoutResult, x:Float, y:Float):Int {
        if (result.lines.length == 0) {
            return 0;
        }
        final lineIndex = nearestLineIndex(result, y);
        final positioned = positionedForLine(index, lineIndex);
        if (positioned.length == 0) {
            return LayoutQueries.coerceSelectionOffset(result, result.lines[lineIndex].range.start, SourceBoundaryBias.Nearest);
        }
        if (x <= positioned[0].left) {
            return LayoutQueries.coerceSelectionOffset(result, positioned[0].range.start, SourceBoundaryBias.Nearest);
        }
        if (x >= positioned[positioned.length - 1].right) {
            return LayoutQueries.coerceSelectionOffset(result, positioned[positioned.length - 1].range.end, SourceBoundaryBias.Nearest);
        }
        var cluster:Null<PositionedCluster> = firstClusterContaining(positioned, x);
        if (cluster == null) {
            cluster = nearestCluster(positioned, x);
        }
        final rawOffset = clusterOffsetForX(cluster, x);
        final backward = LayoutQueries.coerceSelectionOffset(result, rawOffset, SourceBoundaryBias.Backward);
        final forward = LayoutQueries.coerceSelectionOffset(result, rawOffset, SourceBoundaryBias.Forward);
        if (backward == forward) {
            return backward;
        }
        final backwardDistance = Math.abs(cursorRect(index, result, backward).left - x);
        final forwardDistance = Math.abs(cursorRect(index, result, forward).left - x);
        return backwardDistance < forwardDistance ? backward : forward;
    }

    @:extension
    public static function selectionWordRangeForPosition(index:LayoutResultReplayIndex, result:LayoutResult, x:Float, y:Float):Null<TextRange> {
        if (result.lines.length == 0 || result.input.content.text.length == 0) {
            return null;
        }
        final lineIndex = nearestLineIndex(result, y);
        final positioned = positionedForLine(index, lineIndex);
        if (positioned.length == 0) {
            return null;
        }
        var cluster:Null<PositionedCluster> = firstClusterContaining(positioned, x);
        if (cluster == null) {
            cluster = nearestCluster(positioned, x);
        }
        if (cluster.range.isEmpty) {
            return null;
        }
        final sourceUnitOffset = clampInt(clusterOffsetForX(cluster, x), cluster.range.start, cluster.range.end - 1);
        return LayoutQueries.getSelectionWordBoundary(result, sourceUnitOffset);
    }

    @:extension
    public static function cursorRect(index:LayoutResultReplayIndex, result:LayoutResult, offset:Int):Rect {
        if (result.lines.length == 0) {
            return new Rect(0.0, 0.0, 0.0, 0.0);
        }
        final clamped = clampInt(offset, 0, result.input.content.text.length);
        final lineIndex = maxInt(LayoutQueries.getLineForOffset(result, clamped), 0);
        final line = result.lines[lineIndex];
        final positioned = positionedForLine(index, lineIndex);
        var x:Float = line.indent;
        if (positioned.length == 0) {
            x = line.indent;
        } else if (clamped <= positioned[0].range.start) {
            x = positioned[0].left;
        } else if (clamped >= positioned[positioned.length - 1].range.end) {
            x = positioned[positioned.length - 1].right;
        } else {
            var cursor = positioned[0];
            var i = 0;
            while (i < positioned.length) {
                final candidate = positioned[i];
                if (clamped >= candidate.range.start && clamped <= candidate.range.end) {
                    cursor = candidate;
                    break;
                }
                i += 1;
            }
            x = clusterXForOffset(cursor, clamped);
        }
        return new Rect(x, line.top, x + 1.0, line.bottom);
    }

    @:extension
    public static function selectionBoxes(index:LayoutResultReplayIndex, result:LayoutResult, range:TextRange):Array<Rect> {
        final boxes = new Array<Rect>();
        if (range.isEmpty || result.lines.length == 0) {
            return boxes;
        }
        final textLength = result.input.content.text.length;
        final start = clampInt(range.start, 0, textLength);
        final end = clampInt(range.end, start, textLength);
        if (start == end) {
            return boxes;
        }
        final firstLine = clampInt(LayoutQueries.getLineForOffset(result, start), 0, result.lines.length - 1);
        final lastLine = clampInt(LayoutQueries.getLineForOffset(result, end), firstLine, result.lines.length - 1);
        var lineIndex = firstLine;
        while (lineIndex <= lastLine) {
            final line = result.lines[lineIndex];
            final positioned = positionedForLine(index, lineIndex);
            if (positioned.length > 0) {
                final lineStart = maxInt(start, positioned[0].range.start);
                final lineEnd = minInt(end, positioned[positioned.length - 1].range.end);
                if (lineStart < lineEnd) {
                    final leftX = lineStart > positioned[0].range.start
                        ? cursorRect(index, result, lineStart).left : positioned[0].left;
                    final rightX = lineEnd < positioned[positioned.length - 1].range.end
                        ? cursorRect(index, result, lineEnd).left : positioned[positioned.length - 1].right;
                    if (rightX > leftX) {
                        boxes.push(new Rect(leftX, line.top, rightX, line.bottom));
                    }
                }
            }
            lineIndex += 1;
        }
        return boxes;
    }

    @:allow(org.tiqian.core.LayoutResultReplayIndexFns)
    private static function positionedForLine(index:LayoutResultReplayIndex, lineIndex:Int):Array<PositionedCluster> {
        if (lineIndex >= 0 && lineIndex < index.positionedClustersByLine.length) {
            return index.positionedClustersByLine[lineIndex];
        }
        return new Array<PositionedCluster>();
    }

    @:allow(org.tiqian.core.LayoutResultReplayIndexFns)
    private static function nearestLineIndex(result:LayoutResult, y:Float):Int {
        var bestIndex = 0;
        var bestDistance = Math.POSITIVE_INFINITY;
        var index = 0;
        while (index < result.lines.length) {
            final line = result.lines[index];
            final distance = y < line.top ? line.top - y : (y > line.bottom ? y - line.bottom : 0.0);
            if (distance < bestDistance) {
                bestDistance = distance;
                bestIndex = index;
            }
            index += 1;
        }
        return bestIndex;
    }

    @:allow(org.tiqian.core.LayoutResultReplayIndexFns)
    private static function firstClusterContaining(clusters:Array<PositionedCluster>, x:Float):Null<PositionedCluster> {
        var index = 0;
        while (index < clusters.length) {
            final cluster = clusters[index];
            if (x >= cluster.left && x <= cluster.right) {
                return cluster;
            }
            index += 1;
        }
        return null;
    }

    @:allow(org.tiqian.core.LayoutResultReplayIndexFns)
    private static function nearestCluster(clusters:Array<PositionedCluster>, x:Float):PositionedCluster {
        var best = clusters[0];
        var bestDistance = distanceToCluster(best, x);
        var index = 1;
        while (index < clusters.length) {
            final candidate = clusters[index];
            final distance = distanceToCluster(candidate, x);
            if (distance < bestDistance) {
                best = candidate;
                bestDistance = distance;
            }
            index += 1;
        }
        return best;
    }

    @:allow(org.tiqian.core.LayoutResultReplayIndexFns)
    private static function distanceToCluster(cluster:PositionedCluster, x:Float):Float {
        if (x < cluster.left) {
            return cluster.left - x;
        }
        if (x > cluster.right) {
            return x - cluster.right;
        }
        return 0.0;
    }

    @:allow(org.tiqian.core.LayoutResultReplayIndexFns)
    private static function clusterXForOffset(cluster:PositionedCluster, offset:Int):Float {
        if (cluster.range.length <= 0) {
            return cluster.left;
        }
        final index = clampInt(offset - cluster.range.start, 0, cluster.range.length);
        final stops = cluster.sourceStops;
        if (stops != null) {
            return stops[index];
        }
        return cluster.left + cluster.width * ((index * 1.0) / cluster.range.length);
    }

    @:allow(org.tiqian.core.LayoutResultReplayIndexFns)
    private static function clusterOffsetForX(cluster:PositionedCluster, x:Float):Int {
        if (cluster.range.length <= 0) {
            return cluster.range.start;
        }
        final stops = cluster.sourceStops;
        if (stops != null) {
            var bestIndex = 0;
            var bestDistance = Math.POSITIVE_INFINITY;
            var index = 0;
            while (index < stops.length) {
                final distance = Math.abs(x - stops[index]);
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
        final ratio = clampFloat((x - cluster.left) / cluster.width, 0.0, 1.0);
        return clampInt(cluster.range.start + Math.round(ratio * cluster.range.length), cluster.range.start, cluster.range.end);
    }

    @:allow(org.tiqian.core.LayoutResultReplayIndexFns)
    private static function clampInt(value:Int, minimum:Int, maximum:Int):Int {
        return value < minimum ? minimum : (value > maximum ? maximum : value);
    }

    @:allow(org.tiqian.core.LayoutResultReplayIndexFns)
    private static function maxInt(a:Int, b:Int):Int {
        return a > b ? a : b;
    }

    @:allow(org.tiqian.core.LayoutResultReplayIndexFns)
    private static function minInt(a:Int, b:Int):Int {
        return a < b ? a : b;
    }

    @:allow(org.tiqian.core.LayoutResultReplayIndexFns)
    private static function clampFloat(value:Float, minimum:Float, maximum:Float):Float {
        return value < minimum ? minimum : (value > maximum ? maximum : value);
    }
}

