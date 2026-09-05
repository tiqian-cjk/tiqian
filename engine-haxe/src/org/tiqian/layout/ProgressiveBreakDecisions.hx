package org.tiqian.layout;

using std.Functional;

import org.tiqian.core.Cluster;
import org.tiqian.core.TextRange;
import std.SortedMap;
import std.SortedSet;

/** Ordered fallback tier for a break inside one progressive technical span. */
@:enum abstract ProgressiveBreakTier(Int) from Int to Int {
    var Whitespace = 0;
    var Structural = 1;
    var Syllable = 2;
    var WholeToken = 3;
    var Emergency = 4;
    public var priority(get, never):Int;

    private inline function get_priority():Int
        return this;
}

/** One cluster boundary exposed by a line-break span. */
@:dataClass class ProgressiveBreakOpportunity {
    public final tier:ProgressiveBreakTier;
    public final spanRange:TextRange;

    /** Bounded positive glue owned by the source whitespace immediately before this boundary. */
    public final precedingWhitespaceStretchCapacity:Float;

    public function new(tier:ProgressiveBreakTier, spanRange:TextRange, ?precedingWhitespaceStretchCapacity:Null<Float>) {
        this.tier = tier;
        this.spanRange = spanRange;
        this.precedingWhitespaceStretchCapacity = precedingWhitespaceStretchCapacity == null ? 0.0 : precedingWhitespaceStretchCapacity;
    }
}

/** Progressive technical break selection and its supporting decisions. */
class ProgressiveBreakDecisions {
    public static inline final PROGRESSIVE_TECHNICAL_VISIBLE_STRETCH_FRACTION:Float = 0.0;

    public static function decideProgressiveBreak(lineStart:Int, overflowAt:Int, opportunities:SortedMap<Int, ProgressiveBreakOpportunity>,
            ?adjustedClusters:Null<Array<Cluster>>, ?lineLimit:Null<Float>, ?cjkInterCharBoundaries:Null<SortedSet<Int>>, ?maxCjkStretchPerGap:Null<Float>,
            ?sinoWesternBoundaries:Null<SortedSet<Int>>, ?sinoWesternStretchCap:Null<Float>):Int {
        final limit = lineLimit == null ? Math.POSITIVE_INFINITY : lineLimit;
        final cjk = cjkInterCharBoundaries == null ? SortedSet.builder().build() : cjkInterCharBoundaries;
        final max = maxCjkStretchPerGap == null ? Math.POSITIVE_INFINITY : maxCjkStretchPerGap;
        final sino = sinoWesternBoundaries == null ? SortedSet.builder().build() : sinoWesternBoundaries;
        final cap = sinoWesternStretchCap == null ? 0.0 : sinoWesternStretchCap;
        final active = opportunities.get(overflowAt);
        if (active == null)
            return overflowAt;
        final bestPriority = progressiveBreakPriorityForLine(lineStart, overflowAt, active, opportunities, adjustedClusters, limit, cjk, max, sino, cap);
        var best:Null<Int> = null;
        var boundary = lineStart + 1;
        while (boundary <= overflowAt) {
            final o = opportunities.get(boundary);
            if (o != null
                && o.spanRange.start == active.spanRange.start
                && o.spanRange.end == active.spanRange.end
                && o.tier.priority == bestPriority
                && (best == null || boundary > best))
                best = boundary;
            boundary++;
        }
        return best == null ? overflowAt : best;
    }

    public static function progressiveCandidateAllowed(lineStart:Int, rawGreedy:Int, candidateEnd:Int,
            opportunities:SortedMap<Int, ProgressiveBreakOpportunity>, ?adjustedClusters:Null<Array<Cluster>>, ?lineLimit:Null<Float>,
            ?cjkInterCharBoundaries:Null<SortedSet<Int>>, ?maxCjkStretchPerGap:Null<Float>, ?sinoWesternBoundaries:Null<SortedSet<Int>>,
            ?sinoWesternStretchCap:Null<Float>):Bool {
        final limit = lineLimit == null ? Math.POSITIVE_INFINITY : lineLimit;
        final cjk = cjkInterCharBoundaries == null ? SortedSet.builder().build() : cjkInterCharBoundaries;
        final max = maxCjkStretchPerGap == null ? Math.POSITIVE_INFINITY : maxCjkStretchPerGap;
        final sino = sinoWesternBoundaries == null ? SortedSet.builder().build() : sinoWesternBoundaries;
        final cap = sinoWesternStretchCap == null ? 0.0 : sinoWesternStretchCap;
        final active = opportunities.get(rawGreedy);
        if (active == null)
            return true;
        final candidate = opportunities.get(candidateEnd);
        if (candidate == null) {
            if (adjustedClusters == null || candidateEnd < 0 || candidateEnd >= adjustedClusters.length)
                return true;
            final source = adjustedClusters[candidateEnd].range.start;
            return source <= active.spanRange.start || source >= active.spanRange.end;
        }
        if (candidate.spanRange.start != active.spanRange.start || candidate.spanRange.end != active.spanRange.end)
            return true;
        if (candidateEnd > rawGreedy)
            return candidate.tier.priority <= active.tier.priority;
        final selected = decideProgressiveBreak(lineStart, rawGreedy, opportunities, adjustedClusters, limit, cjk, max, sino, cap);
        return candidateEnd == selected;
    }

    private static function progressiveBreakPriorityForLine(lineStart:Int, overflowAt:Int, active:ProgressiveBreakOpportunity,
            opportunities:SortedMap<Int, ProgressiveBreakOpportunity>, adjustedClusters:Null<Array<Cluster>>, lineLimit:Float,
            cjkInterCharBoundaries:SortedSet<Int>, maxCjkStretchPerGap:Float, sinoWesternBoundaries:SortedSet<Int>, sinoWesternStretchCap:Float):Int {
        final prioritiesBuilder = SortedSet.builder();
        var i = lineStart + 1;
        while (i <= overflowAt) {
            final o = opportunities.get(i);
            if (o != null && o.spanRange.start == active.spanRange.start && o.spanRange.end == active.spanRange.end)
                prioritiesBuilder.put(o.tier.priority);
            i++;
        }
        final priorities = prioritiesBuilder.build();
        if (priorities.size() == 0)
            return active.tier.priority;
        if (adjustedClusters == null || !Math.isFinite(lineLimit) || !Math.isFinite(maxCjkStretchPerGap))
            return priorities.at(0);
        final stretch = maxCjkStretchPerGap * PROGRESSIVE_TECHNICAL_VISIBLE_STRETCH_FRACTION;
        var least = priorities.at(0);
        var density = Math.POSITIVE_INFINITY;
        var leastBoundary = lineStart + 1;
        var pi = 0;
        while (pi < priorities.size()) {
            final priority = priorities.at(pi);
            var b = 0;
            i = lineStart + 1;
            while (i <= overflowAt) {
                final o = opportunities.get(i);
                if (o != null
                    && o.spanRange.start == active.spanRange.start
                    && o.spanRange.end == active.spanRange.end
                    && o.tier.priority == priority)
                    b = i;
                i++;
            }
            if (b == 0) {
                pi++;
                continue;
            }
            final d = progressiveCandidateStretchDensity(lineStart, b, opportunities, adjustedClusters, lineLimit, cjkInterCharBoundaries,
                sinoWesternBoundaries, sinoWesternStretchCap);
            if (d < density) {
                density = d;
                least = priority;
                leastBoundary = b;
            }
            if (d <= stretch)
                return priority;
            pi++;
        }
        var emergency = 0;
        i = lineStart + 1;
        while (i <= overflowAt) {
            final o = opportunities.get(i);
            if (o != null
                && o.spanRange.start == active.spanRange.start
                && o.spanRange.end == active.spanRange.end
                && o.tier == ProgressiveBreakTier.Emergency)
                emergency = i;
            i++;
        }
        return emergency != 0 && emergency >= leastBoundary ? ProgressiveBreakTier.Emergency : least;
    }

    private static function progressiveCandidateStretchDensity(lineStart:Int, boundary:Int, opportunities:SortedMap<Int, ProgressiveBreakOpportunity>,
            adjustedClusters:Array<Cluster>, lineLimit:Float, cjkInterCharBoundaries:SortedSet<Int>, sinoWesternBoundaries:SortedSet<Int>,
            sinoWesternStretchCap:Float):Float {
        var width = 0.0;
        var i = lineStart;
        while (i < boundary) {
            width += adjustedClusters[i].advance;
            i++;
        }
        final deficit = Math.max(lineLimit - width, 0);
        var technical = 0.0;
        i = lineStart + 1;
        while (i < boundary) {
            final o = opportunities.get(i);
            if (o != null && o.tier == ProgressiveBreakTier.Whitespace)
                technical += o.precedingWhitespaceStretchCapacity;
            i++;
        }
        var sino = 0;
        i = lineStart + 1;
        while (i < boundary) {
            if (sinoWesternBoundaries.has(i))
                sino++;
            i++;
        }
        final cjkDeficit = Math.max(deficit - technical - sino * sinoWesternStretchCap, 0);
        final active = opportunities.get(boundary);
        var units = 0;
        if (active != null) {
            i = lineStart;
            while (i < boundary) {
                final c = adjustedClusters[i];
                if (c.range.start >= active.spanRange.start && c.range.end <= active.spanRange.end && !hasWhitespaceUnit(c.text))
                    units += c.text.length;
                i++;
            }
        }
        final technicalGaps = Math.max(units - 1, 0);
        if (technicalGaps > 0)
            return cjkDeficit / technicalGaps;
        var gaps = 0;
        i = lineStart + 1;
        while (i < boundary) {
            if (cjkInterCharBoundaries.has(i))
                gaps++;
            i++;
        }
        return gaps == 0 ? cjkDeficit : cjkDeficit / gaps;
    }

    /** True when any UTF-16 unit is whitespace under the JVM union
     * (Character.isWhitespace union Character.isSpaceChar). */
    private static function hasWhitespaceUnit(s:String):Bool {
        var i = 0;
        while (i < s.length) {
            final c = s.charCodeAt(i);
            if ((c >= 0x0009 && c <= 0x000D) || (c >= 0x001C && c <= 0x0020) || c == 0x00A0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200A) || c == 0x2028
                || c == 0x2029 || c == 0x202F || c == 0x205F || c == 0x3000)
                return true;
            i++;
        }
        return false;
    }

    public static function decideHyphenBreak(lineStart:Int, overflowAt:Int, adjustedClusters:Array<Cluster>, lineLimit:Float,
            hyphenBreakClusters:SortedSet<Int>, cjkInterCharBoundaries:SortedSet<Int>, maxCjkStretchPerGap:Float, ?sinoWesternBoundaries:Null<SortedSet<Int>>,
            ?sinoWesternStretchCap:Null<Float>):Int {
        final sino = sinoWesternBoundaries == null ? SortedSet.builder().build() : sinoWesternBoundaries;
        final cap = sinoWesternStretchCap == null ? 0.0 : sinoWesternStretchCap;
        if (!hyphenBreakClusters.has(overflowAt))
            return overflowAt;
        var whole = overflowAt;
        while (whole > lineStart && hyphenBreakClusters.has(whole))
            whole--;
        if (whole <= lineStart)
            return overflowAt;
        var width = 0.0;
        var k = lineStart;
        while (k < whole) {
            width += adjustedClusters[k].advance;
            k++;
        }
        final deficit = lineLimit - width;
        if (deficit <= 0)
            return whole;
        var sw = 0;
        k = lineStart + 1;
        while (k < whole) {
            if (sino.has(k))
                sw++;
            k++;
        }
        final cjk = Math.max(deficit - sw * cap, 0);
        var gaps = 0;
        k = lineStart + 1;
        while (k < whole) {
            if (cjkInterCharBoundaries.has(k))
                gaps++;
            k++;
        }
        return gaps == 0 || cjk / gaps > maxCjkStretchPerGap ? overflowAt : whole;
    }

    public static function adjustBreakForLineEnd(breakAt:Int, lineStart:Int, forbiddenLineEndClusters:SortedSet<Int>):Int {
        var b = breakAt;
        while (b - 1 > lineStart && forbiddenLineEndClusters.has(b - 1))
            b--;
        return b;
    }

    public static function lineLimit(maxWidth:Float, firstLineIndent:Float, lineStartCluster:Int):Float
        return lineStartCluster == 0 ? maxWidth - firstLineIndent : maxWidth;

    public static function adjustBreakForUnbreakables(breakAt:Int, lineStart:Int, unbreakableRanges:UnbreakableRanges):Int {
        var candidate = breakAt;
        while (true) {
            final containing = unbreakableRanges.containingOrNull(candidate);
            if (containing == null)
                return candidate;
            if (containing.start <= lineStart)
                return breakAt;
            candidate = containing.start;
        }
    }
}

@:dataClass class ShrinkOpportunity {
    public final clusterIndex:Int;
    public final tier:Int;
    public final capacity:Float;
    public final channel:ShrinkChannel;
    public final lineEndOnly:Bool;

    public function new(clusterIndex:Int, tier:Int, capacity:Float, channel:ShrinkChannel, ?lineEndOnly:Null<Bool>) {
        this.clusterIndex = clusterIndex;
        this.tier = tier;
        this.capacity = capacity;
        this.channel = channel;
        this.lineEndOnly = lineEndOnly == null ? false : lineEndOnly;
    }
}

enum ShrinkChannel {
    TrailingGlue;
    LeadingGlue;
    LeadingAndTrailingGlue;
    RawAdvance;
}

/** Unbreakable cluster ranges indexed by sorted start and prefix maximum end. */
class UnbreakableRanges {
    public final ranges:Array<org.tiqian.core.IntRange>;

    private final byStart:Array<org.tiqian.core.IntRange>;
    private final startsSorted:Array<Int>;
    private final prefixMaxLast:Array<Int>;

    public function new(ranges:Array<org.tiqian.core.IntRange>) {
        this.ranges = ranges;
        byStart = ranges.copy();
        var s0 = 1;
        while (s0 < byStart.length) {
            final key = byStart[s0];
            var s1 = s0;
            while (s1 > 0 && byStart[s1 - 1].start > key.start) {
                byStart[s1] = byStart[s1 - 1];
                s1--;
            }
            byStart[s1] = key;
            s0++;
        }
        startsSorted = [];
        var si = 0;
        while (si < byStart.length) {
            startsSorted.push(byStart[si].start);
            si++;
        }
        prefixMaxLast = [];
        var running = -2147483648;
        var sj = 0;
        while (sj < byStart.length) {
            running = Std.int(Math.max(running, byStart[sj].end));
            prefixMaxLast.push(running);
            sj++;
        }
    }

    public function containsBoundary(candidate:Int):Bool {
        var low = 0;
        var high = startsSorted.length;
        while (low < high) {
            var mid = (low + high) >> 1;
            if (startsSorted[mid] < candidate)
                low = mid + 1;
            else
                high = mid;
        }
        return low > 0 && prefixMaxLast[low - 1] >= candidate;
    }

    public function containingOrNull(candidate:Int):Null<org.tiqian.core.IntRange> {
        if (!containsBoundary(candidate))
            return null;
        var ri = 0;
        while (ri < ranges.length) {
            final r = ranges[ri];
            if (candidate > r.start && candidate <= r.end)
                return r;
            ri++;
        }
        return null;
    }

    public function containingFromClosedStartOrNull(index:Int):Null<org.tiqian.core.IntRange> {
        var low = 0;
        var high = startsSorted.length;
        while (low < high) {
            var mid = (low + high) >> 1;
            if (startsSorted[mid] <= index)
                low = mid + 1;
            else
                high = mid;
        }
        if (low == 0 || prefixMaxLast[low - 1] <= index)
            return null;
        var rj = 0;
        while (rj < ranges.length) {
            final r = ranges[rj];
            if (index >= r.start && index <= r.end && r.end > index)
                return r;
            rj++;
        }
        return null;
    }

    public static final Empty = new UnbreakableRanges([]);
}
