package org.tiqian.layout;

using std.Functional;

import org.tiqian.core.Cluster;
import org.tiqian.core.IntRange;
import org.tiqian.core.LineEndReason;
import org.tiqian.core.TextRange;
import org.tiqian.core.TiqianIllegalArgumentException;
import org.tiqian.core.TextRangeError.Message;
import org.tiqian.layout.LineOptimization.LineSolution;
import org.tiqian.layout.LineOptimization.LineCandidate;
import org.tiqian.layout.LineOptimization.RepairOption;
import org.tiqian.layout.LineOptimization.RepairCandidate;
import org.tiqian.layout.LineOptimization.RepairOptions;
import org.tiqian.layout.KinsokuRule.ClreqKinsokuRule;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.UnbreakableRanges;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import std.SortedSet;
import std.SortedMap;

/**
 * Haxe port of Kotlin LineBreaker.kt: the LineBreaker contract, the greedy
 * implementation (GreedyLineBreaker), and the lookahead implementation
 * (LookaheadLineBreaker with scoreCandidate, rawGreedyLinesFrom, badness).
 */
interface LineBreaker {
    var strategyName(get, never):String;
    function breakLines(naturalClusters:Array<Cluster>, adjustedClusters:Array<Cluster>, maxWidth:Float, ?shrinkOpportunities:Array<ShrinkOpportunity>,
        ?unbreakableRanges:UnbreakableRanges, firstLineIndent:Float = 0.0, ?hangableClusters:SortedSet<Int>, ?extendableHangRanges:Array<IntRange>,
        ?forbiddenLineStartClusters:Null<SortedSet<Int>>, ?forbiddenLineEndClusters:SortedSet<Int>, ?hyphenBreakClusters:SortedSet<Int>,
        ?cjkInterCharBoundaries:SortedSet<Int>, ?maxCjkStretchPerGap:Float, ?sinoWesternBoundaries:SortedSet<Int>, sinoWesternStretchCap:Float = 0.0,
        lineAdjustmentPushIn:Bool = false, lineAdjustmentCompressBias:Float = 1.0, ?hardBreakAfterClusters:SortedSet<Int>, ?nonRenderingControlClusters:SortedSet<Int>,
        ?progressiveBreakOpportunities:SortedMap<Int, ProgressiveBreakOpportunity>,
            ?lineGapBoundaries:SortedSet<Int>):LineSolution;
}

/**
 * GreedyLineBreaker: fills each line until the next cluster would overflow,
 * then starts a new line. The kinsoku pass then repairs breaks that would
 * place a forbidden-at-line-start cluster at a line start: PushIn first, then
 * Hang (opt-in), then CarryPrevious, falling back to LeaveRagged.
 */
class GreedyLineBreaker implements LineBreaker {
    var kinsoku:KinsokuRule;
    var pushInPenalty:Int;
    var carryPreviousPenalty:Int;
    var leaveRaggedPenalty:Int;

    public function new(?kinsoku:KinsokuRule, pushInPenalty:Int = 2, carryPreviousPenalty:Int = 10, leaveRaggedPenalty:Int = 20) {
        if (kinsoku == null)
            this.kinsoku = new ClreqKinsokuRule();
        else
            this.kinsoku = kinsoku;
        this.pushInPenalty = pushInPenalty;
        this.carryPreviousPenalty = carryPreviousPenalty;
        this.leaveRaggedPenalty = leaveRaggedPenalty;
    }

    public var strategyName(get, never):String;

    function get_strategyName():String
        return "greedy";

    public function breakLines(n:Array<Cluster>, a:Array<Cluster>, maxWidth:Float, ?shrinkOpportunities:Array<ShrinkOpportunity>,
            ?unbreakableRanges:UnbreakableRanges, firstLineIndent:Float = 0.0, ?hangableClusters:SortedSet<Int>, ?extendableHangRanges:Array<IntRange>,
            ?forbiddenLineStartClusters:Null<SortedSet<Int>>, ?forbiddenLineEndClusters:SortedSet<Int>, ?hyphenBreakClusters:SortedSet<Int>,
            ?cjkInterCharBoundaries:SortedSet<Int>, ?maxCjkStretchPerGap:Float, ?sinoWesternBoundaries:SortedSet<Int>, sinoWesternStretchCap:Float = 0.0,
            lineAdjustmentPushIn:Bool = false, lineAdjustmentCompressBias:Float = 1.0, ?hardBreakAfterClusters:SortedSet<Int>,
            ?nonRenderingControlClusters:SortedSet<Int>, ?progressiveBreakOpportunities:SortedMap<Int, ProgressiveBreakOpportunity>,
            ?lineGapBoundaries:SortedSet<Int>):LineSolution {
        if (a.length == 0)
            return new LineSolution([]);
        if (n.length != a.length)
            throw new TiqianIllegalArgumentException(Message("naturalClusters and adjustedClusters must align cluster-for-cluster."));
        final shrinkOps = shrinkOpportunities == null ? [] : shrinkOpportunities;
        final ranges = unbreakableRanges == null ? UnbreakableRanges.Empty : unbreakableRanges;
        final indent = firstLineIndent;
        final hangables = hangableClusters == null ? LineBreakerLines.emptyIntSet() : hangableClusters;
        final extendables = extendableHangRanges == null ? [] : extendableHangRanges;
        final forbidEnd = forbiddenLineEndClusters == null ? LineBreakerLines.emptyIntSet() : forbiddenLineEndClusters;
        final hyphens = hyphenBreakClusters == null ? LineBreakerLines.emptyIntSet() : hyphenBreakClusters;
        final cjk = cjkInterCharBoundaries == null ? LineBreakerLines.emptyIntSet() : cjkInterCharBoundaries;
        final maxStretch = maxCjkStretchPerGap == null ? Math.POSITIVE_INFINITY : maxCjkStretchPerGap;
        final sino = sinoWesternBoundaries == null ? LineBreakerLines.emptyIntSet() : sinoWesternBoundaries;
        final sinoCap = sinoWesternStretchCap;
        final hard = hardBreakAfterClusters == null ? LineBreakerLines.emptyIntSet() : hardBreakAfterClusters;
        final controls = nonRenderingControlClusters == null ? LineBreakerLines.emptyIntSet() : nonRenderingControlClusters;
        final progressive = progressiveBreakOpportunities == null ? LineBreakerLines.emptyProgressiveMap() : progressiveBreakOpportunities;
        final naturalAdvances = LineBreakerLines.advancesOf(n);
        final adjustedAdvances = LineBreakerLines.advancesOf(a);
        final greedy = greedyFill(n, a, naturalAdvances, adjustedAdvances, maxWidth, ranges, indent, forbidEnd, hyphens, cjk, maxStretch, sino, sinoCap, hard,
            controls, progressive);
        final repaired = LineRepair.applyKinsokuRepairs(greedy, a, naturalAdvances, adjustedAdvances, maxWidth, this.kinsoku, shrinkOps, pushInPenalty, carryPreviousPenalty,
            leaveRaggedPenalty, ranges, indent, hangables, extendables, 5, forbiddenLineStartClusters);
        final gapBoundaries = lineGapBoundaries == null ? LineBreakerLines.unionLineGapBoundaries(cjk, sino) : lineGapBoundaries;
        final pushIn = lineAdjustmentPushIn;
        final compressBias = lineAdjustmentCompressBias;
        return LineRepair.withFillPushIn(repaired, pushIn, a, naturalAdvances, adjustedAdvances, maxWidth, shrinkOps, indent, compressBias, forbiddenLineStartClusters, forbidEnd, ranges,
            pushInPenalty, gapBoundaries, progressive);
    }

    function greedyFill(n:Array<Cluster>, a:Array<Cluster>, naturalAdvances:Array<Float>, adjustedAdvances:Array<Float>, maxWidth:Float, unbreakableRanges:UnbreakableRanges, firstLineIndent:Float,
            forbiddenLineEndClusters:SortedSet<Int>, hyphenBreakClusters:SortedSet<Int>, cjkInterCharBoundaries:SortedSet<Int>, maxCjkStretchPerGap:Float,
            sinoWesternBoundaries:SortedSet<Int>, sinoWesternStretchCap:Float, hardBreakAfterClusters:SortedSet<Int>,
            nonRenderingControlClusters:SortedSet<Int>, progressiveBreakOpportunities:SortedMap<Int, ProgressiveBreakOpportunity>):Array<LineCandidate> {
        final lines:Array<LineCandidate> = [];
        var lineStart = 0;
        var adjustedAccum = 0.0;
        var naturalAccum = 0.0;
        var hasRenderingContent = false;
        var i = 0;
        while (i < a.length) {
            final nextAdjusted = adjustedAccum + a[i].advance;
            final limit = ProgressiveBreakDecisions.lineLimit(maxWidth, firstLineIndent, lineStart);
            if (nextAdjusted > limit && hasRenderingContent) {
                final progressive = ProgressiveBreakDecisions.decideProgressiveBreak(lineStart, i, progressiveBreakOpportunities, a, limit,
                    cjkInterCharBoundaries, maxCjkStretchPerGap, sinoWesternBoundaries, sinoWesternStretchCap);
                final decided = ProgressiveBreakDecisions.decideHyphenBreak(lineStart, progressive, a, limit, hyphenBreakClusters, cjkInterCharBoundaries,
                    maxCjkStretchPerGap, sinoWesternBoundaries, sinoWesternStretchCap);
                final afterUnbreak = ProgressiveBreakDecisions.adjustBreakForUnbreakables(decided, lineStart, unbreakableRanges);
                final breakAt = ProgressiveBreakDecisions.adjustBreakForLineEnd(afterUnbreak, lineStart, forbiddenLineEndClusters);
                lines.push(LineBreakerLines.closeFilledLine(new IntRange(lineStart, breakAt - 1), afterUnbreak, a, naturalAdvances, adjustedAdvances));
                lineStart = breakAt;
                adjustedAccum = a[breakAt].advance;
                naturalAccum = n[breakAt].advance;
                hasRenderingContent = !nonRenderingControlClusters.has(breakAt);
                i = breakAt + 1;
            } else {
                adjustedAccum = nextAdjusted;
                naturalAccum += n[i].advance;
                if (!nonRenderingControlClusters.has(i))
                    hasRenderingContent = true;
                if (hardBreakAfterClusters.has(i)) {
                    lines.push(LineBreakerLines.rebuildLine(new IntRange(lineStart, i), a, naturalAdvances, adjustedAdvances, LineEndReason.MandatoryBreak));
                    lineStart = i + 1;
                    adjustedAccum = 0;
                    naturalAccum = 0;
                    hasRenderingContent = false;
                }
                i++;
            }
        }
        if (lineStart < a.length)
            lines.push(LineBreakerLines.rebuildLine(new IntRange(lineStart, a.length - 1), a, naturalAdvances, adjustedAdvances,
                LineEndReason.ParagraphEnd));
        else if (hardBreakAfterClusters.has(a.length - 1))
            lines.push(LineBreakerLines.emptyLineCandidate(a[a.length - 1].range.end, LineEndReason.ParagraphEnd));
        return lines;
    }
}

/**
 * LookaheadLineBreaker: scores alternative break choices against a bounded
 * lookahead window, balancing raggedness, kinsoku repair costs, and
 * amortized spacing density across lines.
 */
class LookaheadLineBreaker implements LineBreaker {
    final window:Int;
    final futureLineHorizon:Int;
    final raggednessWeight:Float;
    final kinsoku:KinsokuRule;
    final pushInPenalty:Int;
    final carryPreviousPenalty:Int;
    final leaveRaggedPenalty:Int;
    final consecutiveSyntheticHyphenPenalty:Float;

    public function new(?window:Null<Int>, ?futureLineHorizon:Null<Int>, ?raggednessWeight:Null<Float>, ?kinsoku:Null<KinsokuRule>, ?pushInPenalty:Null<Int>,
            ?carryPreviousPenalty:Null<Int>, ?leaveRaggedPenalty:Null<Int>, ?consecutiveSyntheticHyphenPenalty:Null<Float>) {
        this.window = window == null ? 2 : window;
        this.futureLineHorizon = futureLineHorizon == null ? 2 : futureLineHorizon;
        this.raggednessWeight = raggednessWeight == null ? 0.5 : raggednessWeight;
        this.kinsoku = kinsoku == null ? new ClreqKinsokuRule() : kinsoku;
        this.pushInPenalty = pushInPenalty == null ? 2 : pushInPenalty;
        this.carryPreviousPenalty = carryPreviousPenalty == null ? 10 : carryPreviousPenalty;
        this.leaveRaggedPenalty = leaveRaggedPenalty == null ? 20 : leaveRaggedPenalty;
        this.consecutiveSyntheticHyphenPenalty = consecutiveSyntheticHyphenPenalty == null ? 12.0 : consecutiveSyntheticHyphenPenalty;
    }

    public var strategyName(get, never):String;

    function get_strategyName():String
        return "lookahead";

    public function breakLines(naturalClusters:Array<Cluster>, adjustedClusters:Array<Cluster>, maxWidth:Float, ?shrinkOpportunities:Array<ShrinkOpportunity>,
            ?unbreakableRanges:UnbreakableRanges, firstLineIndent:Float = 0.0, ?hangableClusters:SortedSet<Int>, ?extendableHangRanges:Array<IntRange>,
            ?forbiddenLineStartClusters:Null<SortedSet<Int>>, ?forbiddenLineEndClusters:SortedSet<Int>, ?hyphenBreakClusters:SortedSet<Int>,
            ?cjkInterCharBoundaries:SortedSet<Int>, ?maxCjkStretchPerGap:Float, ?sinoWesternBoundaries:SortedSet<Int>, sinoWesternStretchCap:Float = 0.0,
            lineAdjustmentPushIn:Bool = false, lineAdjustmentCompressBias:Float = 1.0, ?hardBreakAfterClusters:SortedSet<Int>,
            ?nonRenderingControlClusters:SortedSet<Int>, ?progressiveBreakOpportunities:SortedMap<Int, ProgressiveBreakOpportunity>,
            ?lineGapBoundaries:SortedSet<Int>):LineSolution {
        if (adjustedClusters.length == 0)
            return new LineSolution([]);
        if (naturalClusters.length != adjustedClusters.length)
            throw new TiqianIllegalArgumentException(Message("naturalClusters and adjustedClusters must align cluster-for-cluster."));
        if (window < 0)
            throw new TiqianIllegalArgumentException(Message("window must be non-negative."));
        if (futureLineHorizon < 0)
            throw new TiqianIllegalArgumentException(Message("futureLineHorizon must be non-negative."));

        final shrinkOps = shrinkOpportunities == null ? [] : shrinkOpportunities;
        final ranges = unbreakableRanges == null ? UnbreakableRanges.Empty : unbreakableRanges;
        final indent = firstLineIndent;
        final hangables = hangableClusters == null ? LineBreakerLines.emptyIntSet() : hangableClusters;
        final extendables = extendableHangRanges == null ? [] : extendableHangRanges;
        final forbidEnd = forbiddenLineEndClusters == null ? LineBreakerLines.emptyIntSet() : forbiddenLineEndClusters;
        final hyphens = hyphenBreakClusters == null ? LineBreakerLines.emptyIntSet() : hyphenBreakClusters;
        final cjk = cjkInterCharBoundaries == null ? LineBreakerLines.emptyIntSet() : cjkInterCharBoundaries;
        final maxStretch = maxCjkStretchPerGap == null ? Math.POSITIVE_INFINITY : maxCjkStretchPerGap;
        final sino = sinoWesternBoundaries == null ? LineBreakerLines.emptyIntSet() : sinoWesternBoundaries;
        final sinoCap = sinoWesternStretchCap;
        final pushIn = lineAdjustmentPushIn;
        final compressBias = lineAdjustmentCompressBias;
        final hard = hardBreakAfterClusters == null ? LineBreakerLines.emptyIntSet() : hardBreakAfterClusters;
        final controls = nonRenderingControlClusters == null ? LineBreakerLines.emptyIntSet() : nonRenderingControlClusters;
        final progressive = progressiveBreakOpportunities == null ? LineBreakerLines.emptyProgressiveMap() : progressiveBreakOpportunities;

        final naturalAdvances = LineBreakerLines.advancesOf(naturalClusters);
        final adjustedAdvances = LineBreakerLines.advancesOf(adjustedClusters);
        final committed:Array<LineCandidate> = [];
        var lineStart = 0;

        final gapBoundaries = lineGapBoundaries == null ? LineBreakerLines.unionLineGapBoundaries(cjk, sino) : lineGapBoundaries;
        final dRef = maxStretch;
        var committedDensity = 0.0;
        var committedSyntheticHyphenRun = 0;

        final sortedBreaks:Array<Int> = [];
        var bi = 0;
        while (bi < hard.size()) {
            sortedBreaks.push(hard.at(bi));
            bi++;
        }
        var breakCursor = 0;

        while (lineStart < adjustedClusters.length) {
            while (breakCursor < sortedBreaks.length && sortedBreaks[breakCursor] < lineStart)
                breakCursor++;
            final mandatoryEnd:Null<Int> = breakCursor < sortedBreaks.length ? sortedBreaks[breakCursor] : null;
            final segmentEndExclusive = mandatoryEnd != null ? mandatoryEnd + 1 : adjustedClusters.length;

            final rawGreedyEnd = LineBreakerLines.findGreedyEnd(adjustedClusters, lineStart, ProgressiveBreakDecisions.lineLimit(maxWidth, indent, lineStart),
                segmentEndExclusive, controls);
            final progBreak = ProgressiveBreakDecisions.decideProgressiveBreak(lineStart, rawGreedyEnd, progressive, adjustedClusters,
                ProgressiveBreakDecisions.lineLimit(maxWidth, indent, lineStart), cjk, maxStretch, sino, sinoCap);
            final hyphenBreak = ProgressiveBreakDecisions.decideHyphenBreak(lineStart, progBreak, adjustedClusters,
                ProgressiveBreakDecisions.lineLimit(maxWidth, indent, lineStart), hyphens, cjk, maxStretch, sino, sinoCap);
            final greedyEnd = ProgressiveBreakDecisions.adjustBreakForUnbreakables(hyphenBreak, lineStart, ranges);

            if (greedyEnd >= segmentEndExclusive) {
                if (mandatoryEnd != null) {
                    committed.push(LineBreakerLines.rebuildLine(new IntRange(lineStart, mandatoryEnd), adjustedClusters, naturalAdvances,
                        adjustedAdvances, LineEndReason.MandatoryBreak));
                    committedDensity = 0.0;
                    committedSyntheticHyphenRun = 0;
                    lineStart = mandatoryEnd + 1;
                    if (lineStart == adjustedClusters.length) {
                        committed.push(LineBreakerLines.emptyLineCandidate(adjustedClusters[adjustedClusters.length - 1].range.end,
                            LineEndReason.ParagraphEnd));
                    }
                    continue;
                }
                committed.push(LineBreakerLines.rebuildLine(new IntRange(lineStart, adjustedClusters.length - 1), adjustedClusters, naturalAdvances,
                    adjustedAdvances, LineEndReason.ParagraphEnd));
                break;
            }

            final candidates:Array<Int> = [];
            final candStart = greedyEnd - window;
            var c = candStart;
            while (c <= greedyEnd) {
                if (c >= lineStart + 1
                    && c <= adjustedClusters.length
                    && c <= segmentEndExclusive
                    && !ranges.containsBoundary(c)
                    && ProgressiveBreakDecisions.progressiveCandidateAllowed(lineStart, rawGreedyEnd, c, progressive, adjustedClusters,
                        ProgressiveBreakDecisions.lineLimit(maxWidth, indent, lineStart), cjk, maxStretch, sino, sinoCap)
                    && (hasRenderingContentInRange(lineStart, c, controls) || c == segmentEndExclusive)) {
                    if (candidates.indexOf(c) == -1)
                        candidates.push(c);
                }
                c++;
            }
            if (candidates.length == 0) {
                candidates.push(ProgressiveBreakDecisions.adjustBreakForUnbreakables(greedyEnd, lineStart, ranges));
            }

            var bestEnd = greedyEnd;
            var bestScore = Math.POSITIVE_INFINITY;
            for (e in candidates) {
                final score = scoreCandidate(lineStart, e, adjustedClusters, naturalAdvances, adjustedAdvances, maxWidth, shrinkOps, indent, hangables, extendables,
                    forbiddenLineStartClusters, hyphens, cjk, maxStretch, sino, sinoCap, segmentEndExclusive, committedDensity, committedSyntheticHyphenRun,
                    gapBoundaries, dRef, ranges, controls, progressive);
                if (score < bestScore) {
                    bestScore = score;
                    bestEnd = e;
                }
            }

            final committedEnd = ProgressiveBreakDecisions.adjustBreakForLineEnd(bestEnd, lineStart, forbidEnd);
            if (hard.has(committedEnd) && lineStart < committedEnd) {
                committed.push(LineBreakerLines.rebuildLine(new IntRange(lineStart, committedEnd), adjustedClusters, naturalAdvances,
                    adjustedAdvances, LineEndReason.MandatoryBreak));
                committedDensity = 0.0;
                committedSyntheticHyphenRun = 0;
                lineStart = committedEnd + 1;
                if (lineStart == adjustedClusters.length) {
                    committed.push(LineBreakerLines.emptyLineCandidate(adjustedClusters[adjustedClusters.length - 1].range.end, LineEndReason.ParagraphEnd));
                }
                continue;
            }

            committed.push(LineBreakerLines.closeFilledLine(new IntRange(lineStart, committedEnd - 1), bestEnd, adjustedClusters, naturalAdvances,
                adjustedAdvances));
            final lastLine = committed[committed.length - 1];
            final limit = ProgressiveBreakDecisions.lineLimit(maxWidth, indent, lastLine.clusterRange.start);
            committedDensity = LineBreakerLines.lineAdjustmentDensity(lastLine, limit, false, gapBoundaries);
            committedSyntheticHyphenRun = LineBreakerLines.endsWithSyntheticHyphen(lastLine, hyphens) ? committedSyntheticHyphenRun + 1 : 0;
            lineStart = committedEnd;
        }

        final repaired = LineRepair.applyKinsokuRepairs(committed, adjustedClusters, naturalAdvances, adjustedAdvances, maxWidth, kinsoku, shrinkOps, pushInPenalty,
            carryPreviousPenalty, leaveRaggedPenalty, ranges, indent, hangables, extendables, 5, forbiddenLineStartClusters);
        return LineRepair.withFillPushIn(repaired, pushIn, adjustedClusters, naturalAdvances, adjustedAdvances, maxWidth, shrinkOps, indent, compressBias,
            forbiddenLineStartClusters, forbidEnd, ranges, pushInPenalty, gapBoundaries, progressive);
    }

    function scoreCandidate(s:Int, e:Int, adjusted:Array<Cluster>, naturalAdvances:Array<Float>, adjustedAdvances:Array<Float>, maxWidth:Float, shrinkOpportunities:Array<ShrinkOpportunity>,
            firstLineIndent:Float, hangableClusters:SortedSet<Int>, extendableHangRanges:Array<IntRange>, forbiddenLineStartClusters:Null<SortedSet<Int>>,
            hyphenBreakClusters:SortedSet<Int>, cjkInterCharBoundaries:SortedSet<Int>, maxCjkStretchPerGap:Float, sinoWesternBoundaries:SortedSet<Int>,
            sinoWesternStretchCap:Float, segmentEndExclusive:Int, prevCommittedDensity:Float, prevSyntheticHyphenRun:Int, gapBoundaries:SortedSet<Int>,
            dRef:Float, unbreakableRanges:UnbreakableRanges, nonRenderingControlClusters:SortedSet<Int>,
            progressiveBreakOpportunities:SortedMap<Int, ProgressiveBreakOpportunity>):Float {
        final firstLine = LineBreakerLines.rebuildLine(new IntRange(s, e - 1), adjusted, naturalAdvances, adjustedAdvances);
        final future = rawGreedyLinesFrom(e, adjusted, naturalAdvances, adjustedAdvances, maxWidth, hyphenBreakClusters, cjkInterCharBoundaries, maxCjkStretchPerGap,
            sinoWesternBoundaries, sinoWesternStretchCap, segmentEndExclusive, unbreakableRanges, nonRenderingControlClusters, futureLineHorizon + 1,
            progressiveBreakOpportunities);
        final spliced = LineRepair.applyKinsokuRepairs([firstLine].concat(future), adjusted, naturalAdvances, adjustedAdvances, maxWidth, kinsoku, shrinkOpportunities, pushInPenalty,
            carryPreviousPenalty, leaveRaggedPenalty, unbreakableRanges, firstLineIndent, hangableClusters, extendableHangRanges, 5, forbiddenLineStartClusters)
            .lines;

        final horizon = Std.int(Math.min(1 + futureLineHorizon, spliced.length));
        var score = 0.0;
        var prevD = prevCommittedDensity;
        var syntheticHyphenRun = prevSyntheticHyphenRun;
        var idx = 0;
        while (idx < horizon) {
            final line = spliced[idx];
            final isLast = idx == spliced.length - 1;
            score += badness(line, maxWidth, isLast, firstLineIndent, prevD, gapBoundaries, dRef);
            if (LineBreakerLines.endsWithSyntheticHyphen(line, hyphenBreakClusters)) {
                score += consecutiveSyntheticHyphenPenalty * syntheticHyphenRun;
                syntheticHyphenRun += 1;
            } else {
                syntheticHyphenRun = 0;
            }
            final limit = ProgressiveBreakDecisions.lineLimit(maxWidth, firstLineIndent, line.clusterRange.start);
            prevD = LineBreakerLines.lineAdjustmentDensity(line, limit, isLast, gapBoundaries);
            idx++;
        }
        return score;
    }

    function rawGreedyLinesFrom(start:Int, adjusted:Array<Cluster>, naturalAdvances:Array<Float>, adjustedAdvances:Array<Float>, maxWidth:Float, hyphenBreakClusters:SortedSet<Int>,
            cjkInterCharBoundaries:SortedSet<Int>, maxCjkStretchPerGap:Float, sinoWesternBoundaries:SortedSet<Int>, sinoWesternStretchCap:Float,
            endExclusive:Int, unbreakableRanges:UnbreakableRanges, nonRenderingControlClusters:SortedSet<Int>, maxLines:Int,
            progressiveBreakOpportunities:SortedMap<Int, ProgressiveBreakOpportunity>):Array<LineCandidate> {
        if (start >= endExclusive)
            return [];
        if (maxLines <= 0)
            throw new TiqianIllegalArgumentException(Message("maxLines must be positive"));

        final lines:Array<LineCandidate> = [];
        var lineStart = start;
        var adjustedAccum = 0.0;
        var hasRenderingContent = false;

        var i = start;
        while (i < endExclusive) {
            final nextAdjusted = adjustedAccum + adjusted[i].advance;
            final overflows = nextAdjusted > maxWidth && hasRenderingContent;
            if (overflows) {
                final prog = ProgressiveBreakDecisions.decideProgressiveBreak(lineStart, i, progressiveBreakOpportunities, adjusted, maxWidth,
                    cjkInterCharBoundaries, maxCjkStretchPerGap, sinoWesternBoundaries, sinoWesternStretchCap);
                final decided = ProgressiveBreakDecisions.decideHyphenBreak(lineStart, prog, adjusted, maxWidth, hyphenBreakClusters, cjkInterCharBoundaries,
                    maxCjkStretchPerGap, sinoWesternBoundaries, sinoWesternStretchCap);
                final breakAt = ProgressiveBreakDecisions.adjustBreakForUnbreakables(decided, lineStart, unbreakableRanges);
                lines.push(LineBreakerLines.rebuildLine(new IntRange(lineStart, breakAt - 1), adjusted, naturalAdvances, adjustedAdvances));
                if (lines.length >= maxLines)
                    return lines;
                lineStart = breakAt;
                adjustedAccum = adjusted[breakAt].advance;
                hasRenderingContent = !nonRenderingControlClusters.has(breakAt);
                i = breakAt + 1;
            } else {
                adjustedAccum = nextAdjusted;
                if (!nonRenderingControlClusters.has(i))
                    hasRenderingContent = true;
                i++;
            }
        }

        lines.push(LineBreakerLines.rebuildLine(new IntRange(lineStart, endExclusive - 1), adjusted, naturalAdvances, adjustedAdvances,
            LineEndReason.ParagraphEnd));
        return lines;
    }

    function badness(line:LineCandidate, maxWidth:Float, isLast:Bool, firstLineIndent:Float, prevDensity:Float, gapBoundaries:SortedSet<Int>,
            dRef:Float):Float {
        final limit = ProgressiveBreakDecisions.lineLimit(maxWidth, firstLineIndent, line.clusterRange.start);
        final ragged = isLast ? 0.0 : Math.max(0.0, limit - line.adjustedWidth);
        final inMeasureRange = line.inMeasureClusterRange;
        final gaps = LineBreakerLines.lineGapCount(inMeasureRange, gapBoundaries);
        final residual = gaps == 0 ? ragged : 0.0;
        final d = LineBreakerLines.lineAdjustmentDensity(line, limit, isLast, gapBoundaries);
        final orphan = (!isLast && !inMeasureRange.isEmpty && inMeasureRange.start == inMeasureRange.end) ? leaveRaggedPenalty * 1.0 : 0.0;
        final repairPenalty = line.repair != null ? RepairOptions.penalty(line.repair) * 1.0 : 0.0;
        return residual * raggednessWeight
            + orphan
            + LineBreakerLines.amortizedAdjustmentCost(d, prevDensity, dRef) * raggednessWeight
            + repairPenalty;
    }

    static function hasRenderingContentInRange(start:Int, end:Int, controls:SortedSet<Int>):Bool {
        var i = start;
        while (i < end) {
            if (!controls.has(i))
                return true;
            i++;
        }
        return false;
    }
}

/**
 * Kotlin LineBreaker.kt keeps rebuildLine, emptyLineCandidate and
 * closeFilledLine as package-level internal functions shared with
 * LineRepair.kt; the port groups them as statics of this class.
 */
class LineBreakerLines {
    /**
     * Builds a line for [range]; if the break retreated from [naturalBreakAt]
     * (line-end kinsoku), records CarryNext for the mark moved to the next
     * line.
     */
    public static function closeFilledLine(range:IntRange, naturalBreakAt:Int, a:Array<Cluster>, naturalAdvances:Array<Float>,
            adjustedAdvances:Array<Float>):LineCandidate {
        final line = rebuildLine(range, a, naturalAdvances, adjustedAdvances);
        if (range.end + 1 == naturalBreakAt)
            return line;
        final moved = range.end + 1;
        return new LineCandidate(line.clusterRange, line.sourceRange, line.naturalWidth, line.adjustedWidth, line.endReason,
            RepairOption.CarryNext(0, "ForbiddenAtLineEnd:" + a[moved].text + ":moved-to-next-line", moved), line.repairCandidates, line.hangingClusterIndices);
    }

    /**
     * Builds the line candidate for `clusterRange`. The widths add `naturalAdvances` and
     * `adjustedAdvances` (`advancesOf` of the natural and adjusted clusters) from the range start
     * in index order.
     */
    public static function rebuildLine(clusterRange:IntRange, a:Array<Cluster>, naturalAdvances:Array<Float>, adjustedAdvances:Array<Float>,
            ?endReason:Null<LineEndReason>, ?repair:Null<RepairOption>, ?repairCandidates:Null<Array<RepairCandidate>>):LineCandidate {
        if (clusterRange.isEmpty)
            throw new TiqianIllegalArgumentException(Message("Use emptyLineCandidate for an empty line."));
        var natural = 0.0;
        var adjusted = 0.0;
        var idx = clusterRange.start;
        while (idx <= clusterRange.end) {
            natural += naturalAdvances[idx];
            adjusted += adjustedAdvances[idx];
            idx++;
        }
        return new LineCandidate(clusterRange, new TextRange(a[clusterRange.start].range.start, a[clusterRange.end].range.end), natural, adjusted, endReason,
            repair, repairCandidates);
    }

    /**
     * The advance of every cluster, in cluster order. A breaker computes the natural and adjusted
     * advances once per `breakLines` call; `rebuildLine` then sums numbers instead of reading
     * each `Cluster` object.
     */
    public static function advancesOf(clusters:Array<Cluster>):Array<Float> {
        final out = new Array<Float>();
        for (i in 0...clusters.length)
            out.push(clusters[i].advance);
        return out;
    }

    public static function emptyLineCandidate(sourceOffset:Int, ?endReason:Null<LineEndReason>):LineCandidate {
        return new LineCandidate(new IntRange(1, 0), new TextRange(sourceOffset, sourceOffset), 0, 0, endReason);
    }

    /**
     * The line gap boundaries: the boundaries whose gaps line adjustment may stretch, the union of
     * the CJK inter-character and Sino-Western boundaries. A breaker receives the union as its
     * `lineGapBoundaries` argument (`KinsokuDependentPlanning.lineGapBoundaries`) or builds it with
     * this function. The name differs from that parameter because boring's Dart target emits the
     * static call without its class name.
     */
    public static function unionLineGapBoundaries(cjkInterCharBoundaries:SortedSet<Int>, sinoWesternBoundaries:SortedSet<Int>):SortedSet<Int> {
        final builder = SortedSet.builder();
        for (i in 0...cjkInterCharBoundaries.size())
            builder.put(cjkInterCharBoundaries.at(i));
        for (i in 0...sinoWesternBoundaries.size())
            builder.put(sinoWesternBoundaries.at(i));
        return builder.build();
    }

    public static function emptyIntSet():SortedSet<Int> {
        final b = SortedSet.builder();
        return b.build();
    }

    public static function emptyProgressiveMap():SortedMap<Int, ProgressiveBreakOpportunity> {
        final b = SortedMap.builder();
        return b.build();
    }

    public static function endsWithSyntheticHyphen(line:LineCandidate, hyphenBreakClusters:SortedSet<Int>):Bool {
        return line.endReason == LineEndReason.AutoWrap
            && !line.clusterRange.isEmpty
            && hyphenBreakClusters.has(line.clusterRange.end + 1);
    }

    public static function endsWithProgressiveBreak(candidate:LineCandidate, opportunities:SortedMap<Int, ProgressiveBreakOpportunity>):Bool {
        return candidate.endReason == LineEndReason.AutoWrap
            && !candidate.clusterRange.isEmpty
            && opportunities.get(candidate.clusterRange.end + 1) != null;
    }

    /**
     * The number of gap boundaries `g` with `range.start <= g < range.end`. The set is sorted, so
     * the count is the difference of two binary searches instead of one membership test per
     * cluster of the line.
     */
    @:topLevel
    public static function lineGapCount(range:IntRange, gapBoundaries:SortedSet<Int>):Int {
        if (range.isEmpty)
            return 0;
        return countSortedBelow(gapBoundaries, range.end) - countSortedBelow(gapBoundaries, range.start);
    }

    /**
     * The number of elements of `values` that are less than `bound`. Public because boring emits
     * the `@:topLevel` caller `lineGapCount` outside the class.
     */
    public static function countSortedBelow(values:SortedSet<Int>, bound:Int):Int {
        var low = 0;
        var high = values.size();
        while (low < high) {
            final middle = low + Std.int((high - low) / 2);
            if (values.at(middle) < bound)
                low = middle + 1;
            else
                high = middle;
        }
        return low;
    }

    @:topLevel
    public static function lineAdjustmentDensity(line:LineCandidate, limit:Float, isLast:Bool, gapBoundaries:SortedSet<Int>):Float {
        if (isLast || line.endReason != LineEndReason.AutoWrap)
            return 0.0;
        final gaps = lineGapCount(line.inMeasureClusterRange, gapBoundaries);
        if (gaps == 0)
            return 0.0;
        final delta = Math.max(0.0, limit - line.adjustedWidth);
        return delta / gaps;
    }

    public static function amortizedAdjustmentCost(d:Float, prevD:Float, dRef:Float):Float {
        final ref = dRef < 1.0 ? 1.0 : dRef;
        final diff = d - prevD;
        return (d * d + diff * diff) / ref;
    }

    public static function findGreedyEnd(clusters:Array<Cluster>, start:Int, maxWidth:Float, ?endExclusive:Null<Int>,
            ?nonRenderingControlClusters:Null<SortedSet<Int>>):Int {
        final end = endExclusive == null ? clusters.length : endExclusive;
        final controls = nonRenderingControlClusters == null ? emptyIntSet() : nonRenderingControlClusters;
        var accum = 0.0;
        var i = start;
        var hasRenderingContent = false;
        while (i < end) {
            final next = accum + clusters[i].advance;
            if (next > maxWidth && hasRenderingContent)
                return i;
            accum = next;
            if (!controls.has(i))
                hasRenderingContent = true;
            i++;
        }
        return end;
    }
}
