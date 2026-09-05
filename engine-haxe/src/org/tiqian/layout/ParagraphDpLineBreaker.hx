package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.IntRange;
import org.tiqian.core.LineEndReason;
import org.tiqian.core.TextRange;
import org.tiqian.layout.KinsokuRule;
import org.tiqian.layout.KinsokuRule.ClreqKinsokuRule;
import org.tiqian.layout.LineBreaker;
import org.tiqian.layout.LineOptimization.LineCandidate;
import org.tiqian.layout.LineOptimization.LineSolution;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.UnbreakableRanges;
import std.SortedMap;
import std.SortedSet;

/** Partial from-zero port. TODO markers deliberately identify members pending r3. */
class ParagraphDpLineBreaker implements LineBreaker {
    private final candidateWindow:Int;
    private final raggednessWeight:Float;
    private final kinsoku:KinsokuRule;
    private final pushInPenalty:Int;
    private final carryPreviousPenalty:Int;
    private final leaveRaggedPenalty:Int;
    private final syntheticHyphenBreakPenalty:Float;
    private final consecutiveSyntheticHyphenPenalty:Float;
    private final consecutiveStretchPenalty:Float;
    private final compressionVisibility:Float;

    public function new(?candidateWindow:Int, ?raggednessWeight:Float, ?kinsoku:KinsokuRule, ?pushInPenalty:Int, ?carryPreviousPenalty:Int,
            ?leaveRaggedPenalty:Int, ?syntheticHyphenBreakPenalty:Float, ?consecutiveSyntheticHyphenPenalty:Float, ?consecutiveStretchPenalty:Float,
            ?compressionVisibility:Float) {
        this.candidateWindow = candidateWindow == null ? 8 : candidateWindow;
        if (this.candidateWindow < 0)
            throw new org.tiqian.core.TiqianIllegalArgumentException(org.tiqian.core.TextRangeError.Message("candidateWindow must be non-negative."));
        this.raggednessWeight = raggednessWeight == null ? 0.5 : raggednessWeight;
        this.kinsoku = kinsoku == null ? new ClreqKinsokuRule() : kinsoku;
        this.pushInPenalty = pushInPenalty == null ? 2 : pushInPenalty;
        this.carryPreviousPenalty = carryPreviousPenalty == null ? 10 : carryPreviousPenalty;
        this.leaveRaggedPenalty = leaveRaggedPenalty == null ? 20 : leaveRaggedPenalty;
        this.syntheticHyphenBreakPenalty = syntheticHyphenBreakPenalty == null ? 12 : syntheticHyphenBreakPenalty;
        this.consecutiveSyntheticHyphenPenalty = consecutiveSyntheticHyphenPenalty == null ? 12 : consecutiveSyntheticHyphenPenalty;
        this.consecutiveStretchPenalty = consecutiveStretchPenalty == null ? 3 : consecutiveStretchPenalty;
        this.compressionVisibility = compressionVisibility == null ? 1 : compressionVisibility;
    }

    public var strategyName(get, never):String;

    public function get_strategyName():String
        return "paragraph-dp";

    public function breakLines(naturalClusters:Array<Cluster>, adjustedClusters:Array<Cluster>, maxWidth:Float, ?shrinkOpportunities:Array<ShrinkOpportunity>,
            ?unbreakableRanges:UnbreakableRanges, ?firstLineIndent:Float, ?hangableClusters:SortedSet<Int>, ?extendableHangRanges:Array<IntRange>,
            ?forbiddenLineStartClusters:Null<SortedSet<Int>>, ?forbiddenLineEndClusters:SortedSet<Int>, ?hyphenBreakClusters:SortedSet<Int>,
            ?cjkInterCharBoundaries:SortedSet<Int>, ?maxCjkStretchPerGap:Float, ?sinoWesternBoundaries:SortedSet<Int>, ?sinoWesternStretchCap:Float,
            ?lineAdjustmentPushIn:Bool, ?lineAdjustmentCompressBias:Float, ?hardBreakAfterClusters:SortedSet<Int>,
            ?nonRenderingControlClusters:SortedSet<Int>, ?progressiveBreakOpportunities:SortedMap<Int, ProgressiveBreakOpportunity>):LineSolution {
        if (adjustedClusters.length == 0)
            return new LineSolution([]);
        if (naturalClusters.length != adjustedClusters.length)
            throw new org.tiqian.core.TiqianIllegalArgumentException(org.tiqian.core.TextRangeError.Message("naturalClusters and adjustedClusters must align cluster-for-cluster."));
        final shrink = shrinkOpportunities == null ? [] : shrinkOpportunities;
        final ranges = unbreakableRanges == null ? new UnbreakableRanges([]) : unbreakableRanges;
        final indent = firstLineIndent == null ? 0.0 : firstLineIndent;
        final forbidStart = forbiddenLineStartClusters;
        final forbidEnd = forbiddenLineEndClusters == null ? SortedSet.builder().build() : forbiddenLineEndClusters;
        final hyphens = hyphenBreakClusters == null ? SortedSet.builder().build() : hyphenBreakClusters;
        final cjk = cjkInterCharBoundaries == null ? SortedSet.builder().build() : cjkInterCharBoundaries;
        final sino = sinoWesternBoundaries == null ? SortedSet.builder().build() : sinoWesternBoundaries;
        final gapBoundariesBuilder = SortedSet.builder();
        for (i in 0...cjk.size())
            gapBoundariesBuilder.put(cjk.at(i));
        for (i in 0...sino.size())
            gapBoundariesBuilder.put(sino.at(i));
        final gapBoundaries = gapBoundariesBuilder.build();
        final controls = nonRenderingControlClusters == null ? SortedSet.builder().build() : nonRenderingControlClusters;
        final progressive = progressiveBreakOpportunities == null ? SortedMap.builder().build() : progressiveBreakOpportunities;
        final hard = hardBreakAfterClusters == null ? SortedSet.builder().build() : hardBreakAfterClusters;
        final hangables = hangableClusters == null ? SortedSet.builder().build() : hangableClusters;
        final maxStretch = maxCjkStretchPerGap == null ? Math.POSITIVE_INFINITY : maxCjkStretchPerGap;
        final sinoCap = sinoWesternStretchCap == null ? 0.0 : sinoWesternStretchCap;
        final context = new DpContext(naturalClusters, adjustedClusters, maxWidth, shrink, ranges, indent, forbiddenLineStartClusters, forbidEnd, hyphens,
            cjk, maxStretch, sino, sinoCap, controls, gapBoundaries, maxStretch, lineAdjustmentPushIn == true, progressive);
        final committed:Array<LineCandidate> = [];
        final sortedBreaks:Array<Int> = [];
        if (hard.size() > 0)
            for (i in 0...hard.size())
                sortedBreaks.push(hard.at(i));
        var cursor = 0;
        var segmentStart = 0;
        while (segmentStart < adjustedClusters.length) {
            while (cursor < sortedBreaks.length && sortedBreaks[cursor] < segmentStart)
                cursor++;
            final mandatory = cursor < sortedBreaks.length ? sortedBreaks[cursor] : null;
            final end = mandatory == null ? adjustedClusters.length : mandatory + 1;
            final ends = solveSegment(context, segmentStart, end, mandatory != null);
            commitSegment(committed, ends, segmentStart, mandatory, context, hard);
            segmentStart = end;
        }
        return LineRepair.applyKinsokuRepairs(committed, naturalClusters, adjustedClusters, maxWidth, kinsoku, shrink, pushInPenalty, carryPreviousPenalty,
            leaveRaggedPenalty, ranges, indent, hangables, extendableHangRanges == null ? [] : extendableHangRanges, 5, forbidStart);
    }

    private function candidateEnds(context:DpContext, start:Int, segmentEndExclusive:Int, endsWithMandatory:Bool):Array<Int> {
        final limit = ProgressiveBreakDecisions.lineLimit(context.maxWidth, context.firstLineIndent, start);
        final raw = LineBreakerLines.findGreedyEnd(context.adjustedClusters, start, limit, segmentEndExclusive, context.nonRenderingControlClusters);
        if (raw >= segmentEndExclusive)
            return [segmentEndExclusive];
        final progressive = ProgressiveBreakDecisions.decideProgressiveBreak(start, raw, context.progressiveBreakOpportunities, context.adjustedClusters,
            limit, context.cjkInterCharBoundaries, context.maxCjkStretchPerGap, context.sinoWesternBoundaries, context.sinoWesternStretchCap);
        final baseline = ProgressiveBreakDecisions.adjustBreakForUnbreakables(ProgressiveBreakDecisions.decideHyphenBreak(start, progressive,
            context.adjustedClusters, limit, context.hyphenBreakClusters, context.cjkInterCharBoundaries, context.maxCjkStretchPerGap,
            context.sinoWesternBoundaries, context.sinoWesternStretchCap),
            start, context.unbreakableRanges);
        // CompressionAsDpEdge: collect lookahead ends before applying legality filters.
        final compressed:Array<Int> = [];
        if (context.allowCompressionEdges) {
            var width = 0.0;
            var i = start;
            while (i < raw) {
                width += context.adjustedClusters[i].advance;
                i++;
            }
            var e = raw + 1;
            while (e <= segmentEndExclusive && compressed.length < candidateWindow) {
                width += context.adjustedClusters[e - 1].advance;
                if (width - limit > context.shrinkCapacity(new IntRange(start, e - 1)))
                    break;
                compressed.push(e);
                e++;
            }
        }
        final isPromotion = function(e:Int):Bool {
            if (e <= raw)
                return false;
            final current = context.progressiveBreakOpportunities.get(progressive);
            final resulting = context.progressiveBreakOpportunities.get(e);
            return current != null
                && resulting != null
                && current.spanRange.start == resulting.spanRange.start
                && current.spanRange.end == resulting.spanRange.end
                && resulting.tier.priority < current.tier.priority;
        };
        final filtered:Array<Int> = [];
        var i = raw - candidateWindow;
        if (i < start + 1)
            i = start + 1;
        while (i <= raw) {
            if ((!endsWithMandatory || i != segmentEndExclusive - 1)
                && !context.unbreakableRanges.containsBoundary(i)
                && (isPromotion(i)
                    || ProgressiveBreakDecisions.progressiveCandidateAllowed(start, raw, i, context.progressiveBreakOpportunities, context.adjustedClusters,
                        limit, context.cjkInterCharBoundaries, context.maxCjkStretchPerGap, context.sinoWesternBoundaries, context.sinoWesternStretchCap))
                && (i == segmentEndExclusive || rangeHasOnlyNonControlClusters(start, i, context.nonRenderingControlClusters)))
                filtered.push(i);
            i++;
        }
        for (e in compressed)
            if ((!endsWithMandatory || e != segmentEndExclusive - 1)
                && !context.unbreakableRanges.containsBoundary(e)
                && (isPromotion(e)
                    || ProgressiveBreakDecisions.progressiveCandidateAllowed(start, raw, e, context.progressiveBreakOpportunities, context.adjustedClusters,
                        limit, context.cjkInterCharBoundaries, context.maxCjkStretchPerGap, context.sinoWesternBoundaries, context.sinoWesternStretchCap))
                && (e == segmentEndExclusive || rangeHasOnlyNonControlClusters(start, e, context.nonRenderingControlClusters)))
                filtered.push(e);
        // KinsokuAvoidanceOverRepair: preserve conflicted ends only if necessary.
        final clean:Array<Int> = [];
        for (e in filtered)
            if (e == segmentEndExclusive
                || (context.forbiddenLineStartClusters == null || !context.forbiddenLineStartClusters.has(e))
                && !context.forbiddenLineEndClusters.has(e - 1))
                clean.push(e);
        var pool = clean.length == 0 ? filtered : clean;
        final promotions:Array<Int> = [];
        for (e in pool)
            if (isPromotion(e))
                promotions.push(e);
        if (promotions.length > 0) {
            // ProgressiveTechnicalTierPromotion: prefer the best reachable technical tier.
            var best = 999999;
            final promoted = context.progressiveBreakOpportunities.get(promotions[0]).spanRange;
            for (e in promotions) {
                final o = context.progressiveBreakOpportunities.get(e);
                if (o.tier.priority < best)
                    best = o.tier.priority;
            }
            final preferred:Array<Int> = [];
            for (e in pool) {
                final o = context.progressiveBreakOpportunities.get(e);
                if (o == null || o.spanRange.start != promoted.start || o.spanRange.end != promoted.end || o.tier.priority <= best)
                    preferred.push(e);
            }
            pool = preferred;
        }
        if (baseline >= start + 1 && baseline <= segmentEndExclusive && promotions.length == 0)
            pool.push(baseline);
        final unique:Array<Int> = [];
        for (e in pool) {
            var seen = false;
            for (v in unique)
                if (v == e)
                    seen = true;
            if (!seen)
                unique.push(e);
        }
        return unique.length > 0 ? unique : [baseline < start + 1 ? start + 1 : baseline];
    }

    private function edgeGeometry(context:DpContext, line:LineCandidate, isSegmentLast:Bool, hyphenEnd:Bool):EdgeGeometry {
        final limit = ProgressiveBreakDecisions.lineLimit(context.maxWidth, context.firstLineIndent, line.clusterRange.start);
        final inMeasure = line.clusterRange;
        final overflow = line.adjustedWidth - limit;
        final orphan = !isSegmentLast && inMeasure.start == inMeasure.end ? leaveRaggedPenalty : 0.0;
        final hyphen = hyphenEnd ? syntheticHyphenBreakPenalty : 0.0;
        final ref = context.dRef < 1.0 ? 1.0 : context.dRef;
        if (overflow > 0.0) {
            final gaps = context.gapCount(inMeasure) < 1 ? 1 : context.gapCount(inMeasure);
            final d = overflow / gaps * compressionVisibility;
            return new EdgeGeometry(orphan + hyphen + d * d / ref * raggednessWeight, false);
        }
        final deficit = isSegmentLast ? 0.0 : Math.max(limit - line.adjustedWidth, 0.0);
        final sinoGaps = context.sinoGapCount(inMeasure);
        final cjkGaps = context.cjkGapCount(inMeasure);
        final sinoFill = sinoGaps > 0 ? Math.min(deficit, sinoGaps * context.sinoWesternStretchCap) : 0.0;
        final dSino = sinoGaps > 0 ? sinoFill / sinoGaps : 0.0;
        final cjkDeficit = deficit - sinoFill;
        final dCjk = cjkGaps > 0 ? cjkDeficit / cjkGaps : 0.0;
        final residual = cjkGaps == 0 ? cjkDeficit : 0.0;
        return new EdgeGeometry(residual * raggednessWeight + orphan + hyphen + (dSino * dSino + dCjk * dCjk) / ref * raggednessWeight,
            Math.max(dSino, dCjk) > VISIBLE_STRETCH_FLOOR_PX);
    }

    private function solveSegment(context:DpContext, segmentStart:Int, segmentEndExclusive:Int, endsWithMandatory:Bool):Array<Int> {
        // SortedMap is an immutable extern: build() snapshots, so late builder
        // puts never reach the built map. Keep the builders as the live stores
        // and read through builder.get for the whole segment.
        final statesBuilder:SortedMapBuilder<Int, Array<EdgeState>> = SortedMap.builder();
        statesBuilder.put(segmentStart, []);
        final bestBuilder:SortedMapBuilder<String, EdgeState> = SortedMap.builder();
        var terminalBest:Null<EdgeState> = null;
        var start = segmentStart;
        while (start < segmentEndExclusive) {
            final bucket = statesBuilder.get(start);
            final incoming:Array<Null<EdgeState>> = [];
            if (start == segmentStart)
                incoming.push(null);
            else if (bucket != null)
                for (state in bucket)
                    incoming.push(state);
            if (incoming.length == 0) {
                start++;
                continue;
            }
            for (e in candidateEnds(context, start, segmentEndExclusive, endsWithMandatory)) {
                final last = e >= segmentEndExclusive;
                final reason = !last ? LineEndReason.AutoWrap : (endsWithMandatory ? LineEndReason.MandatoryBreak : LineEndReason.ParagraphEnd);
                final lineEnd = e - 1 < segmentEndExclusive - 1 ? e - 1 : segmentEndExclusive - 1;
                final line = context.buildLine(new IntRange(start, lineEnd), reason);
                final hyphenEnd = !last && context.hyphenBreakClusters.has(e);
                final geometry = edgeGeometry(context, line, last, hyphenEnd);
                for (prev in incoming) {
                    final ph = prev == null ? 0 : prev.hyphenRun;
                    final ps = prev == null ? 0 : prev.stretchRun;
                    final cost = (prev == null ? 0.0 : prev.cost)
                        + geometry.baseCost
                        + (hyphenEnd ? consecutiveSyntheticHyphenPenalty * ph : 0.0)
                        + (geometry.visibleStretch ? consecutiveStretchPenalty * ps : 0.0);
                    var hr:Int = 0;
                    if (hyphenEnd)
                        hr = ph + 1 > HYPHEN_RUN_STATE_CAP ? HYPHEN_RUN_STATE_CAP : ph + 1;
                    var sr:Int = 0;
                    if (geometry.visibleStretch)
                        sr = ps + 1 > STRETCH_RUN_STATE_CAP ? STRETCH_RUN_STATE_CAP : ps + 1;
                    final key = start + ":" + e + ":" + hr + ":" + sr;
                    final existing = bestBuilder.get(key);
                    if (existing != null && existing.cost <= cost)
                        continue;
                    final state = new EdgeState(start, e, hr, sr, cost, prev);
                    bestBuilder.put(key, state);
                    if (last) {
                        if (terminalBest == null || cost < terminalBest.cost)
                            terminalBest = state;
                    } else {
                        var next = statesBuilder.get(e);
                        if (next == null)
                            next = [];
                        final kept:Array<EdgeState> = [];
                        for (old in next)
                            if (!(old.start == start && old.hyphenRun == hr && old.stretchRun == sr))
                                kept.push(old);
                        kept.push(state);
                        statesBuilder.put(e, kept);
                    }
                }
            }
            start++;
        }
        if (terminalBest == null)
            return greedyFallbackEnds(context, segmentStart, segmentEndExclusive);
        final result:Array<Int> = [];
        var cursor:Null<EdgeState> = terminalBest;
        while (cursor != null) {
            result.push(cursor.end);
            cursor = cursor.parent;
        }
        result.reverse();
        return result;
    }

    private function greedyFallbackEnds(context:DpContext, segmentStart:Int, segmentEndExclusive:Int):Array<Int> {
        final ends:Array<Int> = [];
        var start = segmentStart;
        while (start < segmentEndExclusive) {
            final limit = ProgressiveBreakDecisions.lineLimit(context.maxWidth, context.firstLineIndent, start);
            final raw = LineBreakerLines.findGreedyEnd(context.adjustedClusters, start, limit, segmentEndExclusive, context.nonRenderingControlClusters);
            var e = raw >= segmentEndExclusive ? segmentEndExclusive : ProgressiveBreakDecisions.adjustBreakForUnbreakables(ProgressiveBreakDecisions.decideHyphenBreak(start,
                raw, context.adjustedClusters, limit, context.hyphenBreakClusters, context.cjkInterCharBoundaries, context.maxCjkStretchPerGap,
                context.sinoWesternBoundaries, context.sinoWesternStretchCap),
                start, context.unbreakableRanges);
            if (e <= start)
                e = start + 1;
            ends.push(e);
            start = e;
        }
        return ends;
    }

    private function commitSegment(committed:Array<LineCandidate>, ends:Array<Int>, segmentStart:Int, mandatoryEnd:Null<Int>, context:DpContext,
            hardBreakAfterClusters:SortedSet<Int>):Void {
        var lineStart = segmentStart;
        for (chosenEnd in ends) {
            if (lineStart >= chosenEnd)
                continue;
            final finalLine = chosenEnd == ends[ends.length - 1];
            final reason = finalLine
                && mandatoryEnd != null ? LineEndReason.MandatoryBreak : (finalLine ? LineEndReason.ParagraphEnd : LineEndReason.AutoWrap);
            final lastIndex = finalLine && mandatoryEnd != null ? mandatoryEnd : chosenEnd - 1;
            final limit = ProgressiveBreakDecisions.lineLimit(context.maxWidth, context.firstLineIndent, lineStart);
            final naturalLine = LineBreakerLines.rebuildLine(new IntRange(lineStart, lastIndex), context.naturalClusters, context.adjustedClusters, reason);
            var compressed:Null<LineCandidate> = null;
            if (naturalLine.adjustedWidth > limit && lastIndex > lineStart) {
                final resultingBreak = context.progressiveBreakOpportunities.get(chosenEnd);
                final rawGreedy = LineBreakerLines.findGreedyEnd(context.adjustedClusters, lineStart, limit, ends[ends.length - 1],
                    context.nonRenderingControlClusters);
                final originalBreak = context.progressiveBreakOpportunities.get(ProgressiveBreakDecisions.decideProgressiveBreak(lineStart, rawGreedy,
                    context.progressiveBreakOpportunities, context.adjustedClusters, limit, context.cjkInterCharBoundaries, context.maxCjkStretchPerGap,
                    context.sinoWesternBoundaries, context.sinoWesternStretchCap));
                final promotesProgressiveTier = originalBreak != null
                    && resultingBreak != null
                    && originalBreak.spanRange.start == resultingBreak.spanRange.start
                    && originalBreak.spanRange.end == resultingBreak.spanRange.end
                    && resultingBreak.tier.priority < originalBreak.tier.priority;
                // CompressionAsDpEdge realization: identical repair records to
                // the fill pass. Same tiered capacity, same promotion reason.
                final result = LineRepair.tryPushIn(LineBreakerLines.rebuildLine(new IntRange(lineStart, lineStart), context.naturalClusters,
                    context.adjustedClusters),
                    LineBreakerLines.rebuildLine(new IntRange(lineStart + 1, lastIndex), context.naturalClusters, context.adjustedClusters, reason),
                    context.naturalClusters, context.adjustedClusters, limit, context.shrinkOpportunities, pushInPenalty, lastIndex,
                    promotesProgressiveTier ? "ProgressiveTechnicalTierPromotion" : "LineAdjustmentPushIn");
                if (result.candidate.accepted && result.current == null)
                    compressed = result.previous;
            }
            if (finalLine) {
                committed.push(compressed == null ? naturalLine : compressed);
                lineStart = chosenEnd;
                if (mandatoryEnd != null && lineStart == context.adjustedClusters.length)
                    committed.push(LineBreakerLines.emptyLineCandidate(context.adjustedClusters[context.adjustedClusters.length - 1].range.end,
                        LineEndReason.ParagraphEnd));
            } else if (compressed != null) {
                committed.push(compressed);
                lineStart = chosenEnd;
            } else {
                final committedEnd = ProgressiveBreakDecisions.adjustBreakForLineEnd(chosenEnd, lineStart, context.forbiddenLineEndClusters);
                if (hardBreakAfterClusters.has(committedEnd) && lineStart < committedEnd) {
                    committed.push(LineBreakerLines.rebuildLine(new IntRange(lineStart, committedEnd), context.naturalClusters, context.adjustedClusters,
                        LineEndReason.MandatoryBreak));
                    lineStart = committedEnd + 1;
                } else {
                    committed.push(LineBreakerLines.closeFilledLine(new IntRange(lineStart, committedEnd - 1), chosenEnd, context.naturalClusters,
                        context.adjustedClusters));
                    lineStart = committedEnd;
                }
            }
        }
    }

    private static function rangeHasOnlyNonControlClusters(start:Int, endExclusive:Int, set:SortedSet<Int>):Bool {
        var i = start;
        while (i < endExclusive) {
            if (!set.has(i))
                return true;
            i++;
        }
        return false;
    }

    private static final HYPHEN_RUN_STATE_CAP:Int = 3;
    private static final STRETCH_RUN_STATE_CAP:Int = 3;
    private static final VISIBLE_STRETCH_FLOOR_PX:Float = 0.5;
}

class DpContext {
    public final naturalClusters:Array<Cluster>;
    public final adjustedClusters:Array<Cluster>;
    public final maxWidth:Float;
    public final shrinkOpportunities:Array<ShrinkOpportunity>;
    public final unbreakableRanges:UnbreakableRanges;
    public final firstLineIndent:Float;
    public final forbiddenLineStartClusters:Null<SortedSet<Int>>;
    public final forbiddenLineEndClusters:SortedSet<Int>;
    public final hyphenBreakClusters:SortedSet<Int>;
    public final cjkInterCharBoundaries:SortedSet<Int>;
    public final maxCjkStretchPerGap:Float;
    public final sinoWesternBoundaries:SortedSet<Int>;
    public final sinoWesternStretchCap:Float;
    public final nonRenderingControlClusters:SortedSet<Int>;
    public final gapBoundaries:SortedSet<Int>;
    public final dRef:Float;
    public final allowCompressionEdges:Bool;
    public final progressiveBreakOpportunities:SortedMap<Int, ProgressiveBreakOpportunity>;

    private final gapPrefix:Array<Int>;
    private final sinoPrefix:Array<Int>;
    private final cjkPrefix:Array<Int>;
    private final naturalPrefix:Array<Float>;
    private final adjustedPrefix:Array<Float>;
    private final shrinkPrefix:Array<Float>;
    private final lineEndOnlyCapacity:Array<Float>;

    public function new(naturalClusters:Array<Cluster>, adjustedClusters:Array<Cluster>, maxWidth:Float, shrinkOpportunities:Array<ShrinkOpportunity>,
            unbreakableRanges:UnbreakableRanges, firstLineIndent:Float, forbiddenLineStartClusters:Null<SortedSet<Int>>,
            forbiddenLineEndClusters:SortedSet<Int>, hyphenBreakClusters:SortedSet<Int>, cjkInterCharBoundaries:SortedSet<Int>, maxCjkStretchPerGap:Float,
            sinoWesternBoundaries:SortedSet<Int>, sinoWesternStretchCap:Float, nonRenderingControlClusters:SortedSet<Int>, gapBoundaries:SortedSet<Int>,
            dRef:Float, allowCompressionEdges:Bool, progressiveBreakOpportunities:SortedMap<Int, ProgressiveBreakOpportunity>) {
        this.naturalClusters = naturalClusters;
        this.adjustedClusters = adjustedClusters;
        this.maxWidth = maxWidth;
        this.shrinkOpportunities = shrinkOpportunities;
        this.unbreakableRanges = unbreakableRanges;
        this.firstLineIndent = firstLineIndent;
        this.forbiddenLineStartClusters = forbiddenLineStartClusters;
        this.forbiddenLineEndClusters = forbiddenLineEndClusters;
        this.hyphenBreakClusters = hyphenBreakClusters;
        this.cjkInterCharBoundaries = cjkInterCharBoundaries;
        this.maxCjkStretchPerGap = maxCjkStretchPerGap;
        this.sinoWesternBoundaries = sinoWesternBoundaries;
        this.sinoWesternStretchCap = sinoWesternStretchCap;
        this.nonRenderingControlClusters = nonRenderingControlClusters;
        this.gapBoundaries = gapBoundaries;
        this.dRef = dRef;
        this.allowCompressionEdges = allowCompressionEdges;
        this.progressiveBreakOpportunities = progressiveBreakOpportunities;
        final n = adjustedClusters.length;
        gapPrefix = [];
        sinoPrefix = [];
        cjkPrefix = [];
        naturalPrefix = [];
        adjustedPrefix = [];
        var init = 0;
        while (init <= n) {
            gapPrefix.push(0);
            sinoPrefix.push(0);
            cjkPrefix.push(0);
            adjustedPrefix.push(0.0);
            init++;
        }
        init = 0;
        while (init <= naturalClusters.length) {
            naturalPrefix.push(0.0);
            init++;
        }
        var k = 0;
        while (k < n) {
            gapPrefix[k + 1] = gapPrefix[k] + (gapBoundaries.has(k) ? 1 : 0);
            sinoPrefix[k + 1] = sinoPrefix[k] + (sinoWesternBoundaries.has(k) ? 1 : 0);
            cjkPrefix[k + 1] = cjkPrefix[k] + (cjkInterCharBoundaries.has(k) ? 1 : 0);
            naturalPrefix[k + 1] = naturalPrefix[k] + naturalClusters[k].advance;
            adjustedPrefix[k + 1] = adjustedPrefix[k] + adjustedClusters[k].advance;
            k++;
        }
        shrinkPrefix = [];
        lineEndOnlyCapacity = [];
        init = 0;
        while (init <= n) {
            shrinkPrefix.push(0.0);
            init++;
        }
        init = 0;
        while (init < n) {
            lineEndOnlyCapacity.push(0.0);
            init++;
        }
        for (opp in shrinkOpportunities) {
            if (opp.capacity <= 0 || opp.clusterIndex < 0 || opp.clusterIndex >= n)
                continue;
            if (opp.lineEndOnly)
                lineEndOnlyCapacity[opp.clusterIndex] += opp.capacity;
            else
                shrinkPrefix[opp.clusterIndex + 1] += opp.capacity;
        }
        k = 0;
        while (k < n) {
            shrinkPrefix[k + 1] += shrinkPrefix[k];
            k++;
        }
    }

    public function buildLine(clusterRange:IntRange, endReason:LineEndReason):LineCandidate {
        return new LineCandidate(clusterRange, new TextRange(adjustedClusters[clusterRange.start].range.start, adjustedClusters[clusterRange.end].range.end),
            naturalPrefix[clusterRange.end + 1] - naturalPrefix[clusterRange.start],
            adjustedPrefix[clusterRange.end + 1] - adjustedPrefix[clusterRange.start], endReason);
    }

    public function gapCount(range:IntRange):Int
        return range.isEmpty ? 0 : gapPrefix[range.end] - gapPrefix[range.start];

    public function sinoGapCount(range:IntRange):Int
        return range.isEmpty ? 0 : sinoPrefix[range.end] - sinoPrefix[range.start];

    public function cjkGapCount(range:IntRange):Int
        return range.isEmpty ? 0 : cjkPrefix[range.end] - cjkPrefix[range.start];

    public function shrinkCapacity(range:IntRange):Float
        return shrinkPrefix[range.end + 1] - shrinkPrefix[range.start] + lineEndOnlyCapacity[range.end];
}

class EdgeState {
    public final start:Int;
    public final end:Int;
    public final hyphenRun:Int;
    public final stretchRun:Int;
    public final cost:Float;
    public final parent:Null<EdgeState>;

    public function new(start:Int, end:Int, hyphenRun:Int, stretchRun:Int, cost:Float, parent:Null<EdgeState>) {
        this.start = start;
        this.end = end;
        this.hyphenRun = hyphenRun;
        this.stretchRun = stretchRun;
        this.cost = cost;
        this.parent = parent;
    }
}

class EdgeGeometry {
    public final baseCost:Float;
    public final visibleStretch:Bool;

    public function new(baseCost:Float, visibleStretch:Bool) {
        this.baseCost = baseCost;
        this.visibleStretch = visibleStretch;
    }
}
