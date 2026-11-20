package org.tiqian.core;

import std.ReadOnlyArray;
import std.HashMap;

/** Paint overhang belonging to already-visible occupied text geometry. */
@:dataClass
class LayoutPaintOverhang {
    public final left:Float;
    public final top:Float;
    public final right:Float;
    public final bottom:Float;

    public function new(?left:Null<Float>, ?top:Null<Float>, ?right:Null<Float>, ?bottom:Null<Float>) {
        this.left = left == null ? 0.0 : left;
        this.top = top == null ? 0.0 : top;
        this.right = right == null ? 0.0 : right;
        this.bottom = bottom == null ? 0.0 : bottom;
    }
}

@:keep
class LayoutPaintBoundsFns {
    /**
     * Right clip edge authorized by an engine-selected punctuation hang.
     * Ordinary over-long text remains clipped to viewportWidth; only an
     * explicit hanging mark may extend the legal clip edge.
     */
    @:extension
    public static function legalHangingPunctuationClipEdge(line:LineBox, viewportWidth:Float):Float {
        return line.hangingPunctuationAdvance > 0.0 ? line.indent + line.visualWidth : viewportWidth;
    }

    /**
     * Paint overhang for glyph ink and annotations attached to occupied
     * geometry visible in the viewport. Layout ownership does not move into
     * the frontend: callers use the result only to avoid clipping legal ink
     * emitted by the engine.
     */
    @:extension
    public static function visiblePaintOverhang(result:LayoutResult, viewportWidth:Float, viewportHeight:Float,
            ?positionedClusters:ReadOnlyArray<PositionedCluster>):LayoutPaintOverhang {
        final positioned = positionedClusters == null
            ? LayoutQueries.positionedClusters(result) : copyPositioned(positionedClusters);
        final positionsByRange = new HashMap<TextRange, PositionedCluster>();
        var positionedIndex = 0;
        while (positionedIndex < positioned.length) {
            final cluster = positioned[positionedIndex];
            positionsByRange.set(cluster.range, cluster);
            positionedIndex += 1;
        }
        final acc = [0.0, 0.0, 0.0, 0.0];
        function includePaint(cluster:PositionedCluster, paintLeft:Float, paintTop:Float, paintRight:Float, paintBottom:Float):Void {
            if (cluster.right <= 0.0 || cluster.left >= viewportWidth
                || cluster.bottom <= 0.0 || cluster.top >= viewportHeight) {
                return;
            }
            acc[0] = maxFloat(acc[0], cluster.left - paintLeft);
            acc[1] = maxFloat(acc[1], cluster.top - paintTop);
            acc[2] = maxFloat(acc[2], paintRight - cluster.right);
            acc[3] = maxFloat(acc[3], paintBottom - cluster.bottom);
        }

        var runIndex = 0;
        while (runIndex < result.glyphRuns.length) {
            final run = result.glyphRuns[runIndex];
            var runGlyphIndex = 0;
            while (runGlyphIndex < run.glyphs.length) {
                final glyph = run.glyphs[runGlyphIndex];
                final bounds = glyph.bounds;
                if (bounds != null) {
                    final cluster = positionsByRange.get(glyph.clusterRange);
                    if (cluster != null) {
                        includePaint(cluster, cluster.drawX + glyph.x + bounds.left, cluster.baseline + glyph.y + bounds.top,
                            cluster.drawX + glyph.x + bounds.right, cluster.baseline + glyph.y + bounds.bottom);
                    }
                }
                runGlyphIndex += 1;
            }
            runIndex += 1;
        }
        var dotIndex = 0;
        while (dotIndex < result.debug.decorationDecisions.length) {
            final dot = result.debug.decorationDecisions[dotIndex];
            if (dot.applied && dot.dotDiameter > 0.0) {
                final cluster = positionsByRange.get(dot.clusterRange);
                if (cluster != null) {
                    final radius = dot.dotDiameter / 2.0;
                    includePaint(cluster, dot.anchorX - radius, dot.anchorY - radius, dot.anchorX + radius, dot.anchorY + radius);
                }
            }
            dotIndex += 1;
        }
        var rubyIndex = 0;
        while (rubyIndex < result.debug.rubyDecisions.length) {
            final ruby = result.debug.rubyDecisions[rubyIndex];
            final base = new Array<PositionedCluster>();
            var baseIndex = 0;
            while (baseIndex < positioned.length) {
                final candidate = positioned[baseIndex];
                if (candidate.lineIndex == ruby.lineIndex && candidate.range.start >= ruby.baseRange.start
                    && candidate.range.end <= ruby.baseRange.end) {
                    base.push(candidate);
                }
                baseIndex += 1;
            }
            if (base.length > 0) {
                var occupiedLeft = base[0].left;
                var occupiedTop = base[0].top;
                var occupiedRight = base[0].right;
                var occupiedBottom = base[0].bottom;
                var boundsIndex = 0;
                while (boundsIndex < base.length) {
                    final candidate = base[boundsIndex];
                    occupiedLeft = minFloat(occupiedLeft, candidate.left);
                    occupiedTop = minFloat(occupiedTop, candidate.top);
                    occupiedRight = maxFloat(occupiedRight, candidate.right);
                    occupiedBottom = maxFloat(occupiedBottom, candidate.bottom);
                    boundsIndex += 1;
                }
                if (!(occupiedRight <= 0.0 || occupiedLeft >= viewportWidth
                    || occupiedBottom <= 0.0 || occupiedTop >= viewportHeight)) {
                    final paintLeft = ruby.centerX - ruby.width / 2.0;
                    final paintTop = ruby.baselineY - ruby.ascent;
                    final paintRight = ruby.centerX + ruby.width / 2.0;
                    final paintBottom = ruby.baselineY + ruby.descent;
                    acc[0] = maxFloat(acc[0], occupiedLeft - paintLeft);
                    acc[1] = maxFloat(acc[1], occupiedTop - paintTop);
                    acc[2] = maxFloat(acc[2], paintRight - occupiedRight);
                    acc[3] = maxFloat(acc[3], paintBottom - occupiedBottom);
                }
            }
            rubyIndex += 1;
        }
        return new LayoutPaintOverhang(acc[0], acc[1], acc[2], acc[3]);
    }

    @:allow(org.tiqian.core.LayoutPaintBoundsFns)
    private static function copyPositioned(values:ReadOnlyArray<PositionedCluster>):Array<PositionedCluster> {
        final out = new Array<PositionedCluster>();
        var index = 0;
        while (index < values.length) {
            out.push(values[index]);
            index += 1;
        }
        return out;
    }

    @:allow(org.tiqian.core.LayoutPaintBoundsFns)
    private static function minFloat(a:Float, b:Float):Float {
        return a < b ? a : b;
    }

    @:allow(org.tiqian.core.LayoutPaintBoundsFns)
    private static function maxFloat(a:Float, b:Float):Float {
        return a > b ? a : b;
    }
}

