package org.tiqian.layout;

import std.SortedMap;
import org.tiqian.core.Cluster;
import org.tiqian.core.RubySpan;
import org.tiqian.layout.AnnotationGeometryStage.RubyFontGeometry;

/** Extra advance after a cluster so adjacent ruby annotations keep the minimum gap. */
class RubySpread {
    private static inline final RUBY_MIN_GAP_EM_OF_RUBY:Float = 0.25;

    public static function compute(natural:Array<Cluster>, rubySize:Float, pinyinSpans:Array<RubySpan>,
            rubyFontGeometryBySpan:SortedMap<RubySpan, RubyFontGeometry>):SortedMap<Int, Float> {
        if (pinyinSpans.length == 0)
            return SortedMap.builder().build();
        final wordSpace = rubySize * RUBY_MIN_GAP_EM_OF_RUBY;
        final leftX = new Array<Float>();
        var acc = 0.0;
        for (i in 0...natural.length) {
            leftX.push(acc);
            acc += natural[i].advance;
        }

        final measuresFirstCluster = new Array<Int>();
        final measuresCenter = new Array<Float>();
        final measuresRw = new Array<Float>();
        for (i in 0...pinyinSpans.length) {
            final ruby = pinyinSpans[i];
            final idxRange = PunctuationGeometryLedger.clusterIndexRangeFor(natural, ruby.baseRange);
            if (idxRange == null)
                continue;
            final center = (leftX[idxRange.start] + leftX[idxRange.end] + natural[idxRange.end].advance) / 2.0;
            final geom = rubyFontGeometryBySpan.get(ruby);
            measuresFirstCluster.push(idxRange.start);
            measuresCenter.push(center);
            measuresRw.push(geom.width);
        }
        var mIdx = 1;
        while (mIdx < measuresFirstCluster.length) {
            final currFc = measuresFirstCluster[mIdx];
            final currCenter = measuresCenter[mIdx];
            final currRw = measuresRw[mIdx];
            var j = mIdx - 1;
            while (j >= 0 && measuresFirstCluster[j] > currFc) {
                measuresFirstCluster[j + 1] = measuresFirstCluster[j];
                measuresCenter[j + 1] = measuresCenter[j];
                measuresRw[j + 1] = measuresRw[j];
                j--;
            }
            measuresFirstCluster[j + 1] = currFc;
            measuresCenter[j + 1] = currCenter;
            measuresRw[j + 1] = currRw;
            mIdx++;
        }

        final spreadBuilder = SortedMap.builder();
        final spreadKeys = new Array<Int>();
        final spreadValues = new Array<Float>();
        function getSpread(key:Int):Float {
            for (i in 0...spreadKeys.length) {
                if (spreadKeys[i] == key)
                    return spreadValues[i];
            }
            return 0.0;
        }
        function putSpread(key:Int, val:Float):Void {
            for (i in 0...spreadKeys.length) {
                if (spreadKeys[i] == key) {
                    spreadValues[i] = val;
                    return;
                }
            }
            spreadKeys.push(key);
            spreadValues.push(val);
        }

        var shift = 0.0;
        var prevRight = -1e9;
        for (m in 0...measuresFirstCluster.length) {
            final firstCluster = measuresFirstCluster[m];
            final rw = measuresRw[m];
            var center = measuresCenter[m] + shift;
            final needed = prevRight + wordSpace - (center - rw / 2.0);
            if (needed > 0.0 && firstCluster > 0) {
                final key = firstCluster - 1;
                putSpread(key, getSpread(key) + needed);
                shift += needed;
                center += needed;
            }
            prevRight = center + rw / 2.0;
        }
        for (i in 0...spreadKeys.length) {
            spreadBuilder.put(spreadKeys[i], spreadValues[i]);
        }
        return spreadBuilder.build();
    }
}
