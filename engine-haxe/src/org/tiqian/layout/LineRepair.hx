package org.tiqian.layout;

using std.Functional;

import org.tiqian.core.Cluster;
import org.tiqian.core.IntRange;
import org.tiqian.core.LineEndReason;
import org.tiqian.core.TextRange;
import org.tiqian.core.TiqianIllegalArgumentException;
import org.tiqian.core.TextRangeError.Message;
import org.tiqian.layout.LineOptimization.LineCandidate;
import org.tiqian.layout.LineOptimization.LineSolution;
import org.tiqian.layout.LineOptimization.RepairCandidate;
import org.tiqian.layout.LineOptimization.RepairOption;
import org.tiqian.layout.LineOptimization.PushInAllocation;
import org.tiqian.layout.LineOptimization.RepairOptions;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkChannel;
import org.tiqian.layout.ProgressiveBreakDecisions.UnbreakableRanges;
import org.tiqian.layout.LineBreaker.LineBreakerLines;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import std.SortedSet;
import std.SortedMap;

/**
 * Haxe port of Kotlin LineRepair.kt's kinsoku repair chain: applyKinsokuRepairs,
 * tryPushIn, distributePushInShrink, mandatoryBreakTailEnd, and the fill PushIn
 * pass (applyFillPushIn, withFillPushIn, fillPushInGroupEnd). Kotlin keeps these
 * as top-level functions; the port groups them as statics of this class so
 * cross-module calls stay explicit.
 */
@:dataClass class PushInResult {
    public final previous:LineCandidate;
    public final current:Null<LineCandidate>;
    public final candidate:RepairCandidate;

    public function new(previous:LineCandidate, current:Null<LineCandidate>, candidate:RepairCandidate) {
        this.previous = previous;
        this.current = current;
        this.candidate = candidate;
    }
}

typedef ShrinkTierEntry = {final key:Int; final value:ShrinkOpportunity;};

class LineRepair {
    public static function applyKinsokuRepairs(initial:Array<LineCandidate>, naturalClusters:Array<Cluster>, adjustedClusters:Array<Cluster>, maxWidth:Float,
            kinsoku:KinsokuRule, shrinkOpportunities:Array<ShrinkOpportunity>, pushInPenalty:Int, carryPreviousPenalty:Int, leaveRaggedPenalty:Int,
            ?unbreakableRanges:Null<UnbreakableRanges>, ?firstLineIndent:Null<Float>, ?hangableClusters:Null<SortedSet<Int>>,
            ?extendableHangRanges:Null<Array<IntRange>>, ?hangPenalty:Null<Int>, ?forbiddenLineStartClusters:Null<SortedSet<Int>>):LineSolution {
        if (initial.length < 2)
            return new LineSolution(initial);
        final ranges = unbreakableRanges == null ? UnbreakableRanges.Empty : unbreakableRanges;
        final indent = firstLineIndent == null ? 0 : firstLineIndent;
        final hangables = hangableClusters == null ? LineRepair.emptyIntSet() : hangableClusters;
        final extendables = extendableHangRanges == null ? [] : extendableHangRanges;
        final hangCost = hangPenalty == null ? 5 : hangPenalty;
        final mutable = initial.copy();
        var i = 1;
        while (i < mutable.length) {
            final curr = mutable[i];
            final firstIndex = curr.clusterRange.start;
            final prev = mutable[i - 1];
            if (prev.endReason == LineEndReason.MandatoryBreak || curr.clusterRange.isEmpty) {
                i++;
                continue;
            }
            final firstCluster = adjustedClusters[firstIndex];
            final forbidden = forbiddenLineStartClusters != null ? forbiddenLineStartClusters.has(firstIndex) : kinsoku.forbiddenAtLineStart(firstCluster);
            if (!forbidden) {
                i++;
                continue;
            }

            final repairCandidates:Array<RepairCandidate> = [];
            final pushIn = LineRepair.tryPushIn(prev, curr, naturalClusters, adjustedClusters,
                ProgressiveBreakDecisions.lineLimit(maxWidth, indent, prev.clusterRange.start), shrinkOpportunities, pushInPenalty, null,
                "ForbiddenAtLineStart");
            repairCandidates.push(pushIn.candidate);
            if (pushIn.candidate.accepted) {
                mutable[i - 1] = pushIn.previous;
                if (pushIn.current == null) {
                    mutable.splice(i, 1);
                } else {
                    mutable[i] = pushIn.current;
                }
                continue;
            }

            final offenderIndex = curr.clusterRange.start;
            final existingHanging = prev.hangingClusterIndices;
            var extendsContextualHang = false;
            if (existingHanging.size() > 0 && prev.clusterRange.end + 1 == offenderIndex) {
                var gi = 0;
                while (gi < extendables.length) {
                    final group = extendables[gi];
                    if (offenderIndex >= group.start && offenderIndex <= group.end) {
                        var all = true;
                        var hi = 0;
                        while (hi < existingHanging.size()) {
                            final idx = existingHanging.at(hi);
                            if (idx < group.start || idx > group.end) {
                                all = false;
                                break;
                            }
                            hi++;
                        }
                        if (all) {
                            extendsContextualHang = true;
                            break;
                        }
                    }
                    gi++;
                }
            }
            if (hangables.has(offenderIndex) && (existingHanging.size() == 0 || extendsContextualHang)) {
                final mergeEndIndex = LineRepair.mandatoryBreakTailEnd(curr, offenderIndex, adjustedClusters);
                final hangCandidate = new RepairCandidate("Hang", "ForbiddenAtLineStart", offenderIndex, hangCost, true);
                repairCandidates.push(hangCandidate);
                final mergedRange = new IntRange(prev.clusterRange.start, mergeEndIndex);
                var mergedNatural = prev.naturalWidth;
                var wi = prev.clusterRange.end + 1;
                while (wi <= mergeEndIndex) {
                    mergedNatural += naturalClusters[wi].advance;
                    wi++;
                }
                final hangIndices = SortedSet.builder();
                var ai = 0;
                while (ai < existingHanging.size()) {
                    hangIndices.put(existingHanging.at(ai));
                    ai++;
                }
                var xi = offenderIndex;
                while (xi <= mergeEndIndex) {
                    hangIndices.put(xi);
                    xi++;
                }
                final candidateList = prev.repairCandidates.copy();
                var cpi = 0;
                while (cpi < repairCandidates.length) {
                    candidateList.push(repairCandidates[cpi]);
                    cpi++;
                }
                mutable[i - 1] = new LineCandidate(mergedRange,
                    new TextRange(adjustedClusters[mergedRange.start].range.start, adjustedClusters[mergeEndIndex].range.end), mergedNatural,
                    prev.adjustedWidth, mergeEndIndex == curr.clusterRange.end ? curr.endReason : prev.endReason,
                    RepairOption.Hang(hangCost, "ForbiddenAtLineStart:" + firstCluster.text + ":hang", offenderIndex), candidateList, hangIndices.build());
                if (mergeEndIndex == curr.clusterRange.end) {
                    mutable.splice(i, 1);
                } else {
                    mutable[i] = LineBreakerLines.rebuildLine(new IntRange(mergeEndIndex + 1, curr.clusterRange.end), naturalClusters, adjustedClusters,
                        curr.endReason);
                }
                continue;
            }

            final canCarry = prev.clusterRange.start < prev.clusterRange.end;
            if (!canCarry) {
                repairCandidates.push(new RepairCandidate("CarryPrevious", "ForbiddenAtLineStart", firstIndex, carryPreviousPenalty, false,
                    "no-room-to-carry"));
                repairCandidates.push(new RepairCandidate("LeaveRagged", "ForbiddenAtLineStart", firstIndex, leaveRaggedPenalty, true));
                mutable[i] = new LineCandidate(curr.clusterRange, curr.sourceRange, curr.naturalWidth, curr.adjustedWidth, curr.endReason,
                    RepairOption.LeaveRagged(leaveRaggedPenalty, "ForbiddenAtLineStart:" + firstCluster.text + ":no-room-to-carry", firstIndex),
                    repairCandidates, curr.hangingClusterIndices);
                i++;
                continue;
            }

            final carriedIndex = prev.clusterRange.end;
            if (ranges.containsBoundary(carriedIndex)) {
                repairCandidates.push(new RepairCandidate("CarryPrevious", "ForbiddenAtLineStart", firstIndex, carryPreviousPenalty, false,
                    "carry-would-split-mourning-span", null, carriedIndex));
                repairCandidates.push(new RepairCandidate("LeaveRagged", "ForbiddenAtLineStart", firstIndex, leaveRaggedPenalty, true));
                mutable[i] = new LineCandidate(curr.clusterRange, curr.sourceRange, curr.naturalWidth, curr.adjustedWidth, curr.endReason,
                    RepairOption.LeaveRagged(leaveRaggedPenalty, "ForbiddenAtLineStart:" + firstCluster.text + ":carry-would-split-mourning-span", firstIndex),
                    repairCandidates, curr.hangingClusterIndices);
                i++;
                continue;
            }
            final newPrevRange = new IntRange(prev.clusterRange.start, carriedIndex - 1);
            final newCurrRange = new IntRange(carriedIndex, curr.clusterRange.end);
            final carriedCurrent = LineBreakerLines.rebuildLine(newCurrRange, naturalClusters, adjustedClusters, curr.endReason);
            if (carriedCurrent.adjustedWidth > maxWidth) {
                repairCandidates.push(new RepairCandidate("CarryPrevious", "ForbiddenAtLineStart", firstIndex, carryPreviousPenalty, false, "carry-overflows",
                    null, carriedIndex));
                repairCandidates.push(new RepairCandidate("LeaveRagged", "ForbiddenAtLineStart", firstIndex, leaveRaggedPenalty, true));
                mutable[i] = new LineCandidate(curr.clusterRange, curr.sourceRange, curr.naturalWidth, curr.adjustedWidth, curr.endReason,
                    RepairOption.LeaveRagged(leaveRaggedPenalty, "ForbiddenAtLineStart:" + firstCluster.text + ":carry-overflows", firstIndex),
                    repairCandidates, curr.hangingClusterIndices);
                i++;
                continue;
            }

            repairCandidates.push(new RepairCandidate("CarryPrevious", "ForbiddenAtLineStart", firstIndex, carryPreviousPenalty, true, null, null,
                carriedIndex));
            mutable[i - 1] = LineBreakerLines.rebuildLine(newPrevRange, naturalClusters, adjustedClusters, prev.endReason);
            mutable[i] = new LineCandidate(carriedCurrent.clusterRange, carriedCurrent.sourceRange, carriedCurrent.naturalWidth, carriedCurrent.adjustedWidth,
                carriedCurrent.endReason,
                RepairOption.CarryPrevious(carryPreviousPenalty,
                    "ForbiddenAtLineStart:" + firstCluster.text + ":carried=" + adjustedClusters[carriedIndex].text, firstIndex, carriedIndex),
                repairCandidates, carriedCurrent.hangingClusterIndices);
            i++;
        }

        final totalBadness = mutable.sumOfFloat(line -> line.repair == null ? 0.0 : RepairOptions.penalty(line.repair) * 1.0);
        return new LineSolution(mutable, totalBadness);
    }

    public static function tryPushIn(prev:LineCandidate, curr:LineCandidate, naturalClusters:Array<Cluster>, adjustedClusters:Array<Cluster>, maxWidth:Float,
            shrinkOpportunities:Array<ShrinkOpportunity>, pushInPenalty:Int, ?mergeThroughClusterIndex:Null<Int>, ?reasonCode:Null<String>):PushInResult {
        final code = reasonCode == null ? "ForbiddenAtLineStart" : reasonCode;
        final offenderIndex = mergeThroughClusterIndex == null ? curr.clusterRange.start : mergeThroughClusterIndex;
        if (offenderIndex < curr.clusterRange.start || offenderIndex > curr.clusterRange.end)
            throw new TiqianIllegalArgumentException(Message("PushIn merge-through cluster must belong to the current line."));
        final mergeEndIndex = LineRepair.mandatoryBreakTailEnd(curr, offenderIndex, adjustedClusters);
        final expandedRange = new IntRange(prev.clusterRange.start, mergeEndIndex);
        final expanded = LineBreakerLines.rebuildLine(expandedRange, naturalClusters, adjustedClusters);
        final overflow = expanded.adjustedWidth - maxWidth;

        final inLine:Array<ShrinkOpportunity> = shrinkOpportunities.filter(opp -> opp.clusterIndex >= expandedRange.start
            && opp.clusterIndex <= expandedRange.end
            && opp.capacity > 0
            && (!opp.lineEndOnly || opp.clusterIndex == offenderIndex))
            .map(opp -> {
                if (opp.clusterIndex == offenderIndex
                    && (opp.channel == ShrinkChannel.TrailingGlue || opp.channel == ShrinkChannel.LeadingAndTrailingGlue))
                    return new ShrinkOpportunity(opp.clusterIndex, 1, opp.capacity, opp.channel, opp.lineEndOnly);
                return opp;
            });
        final totalCapacity = inLine.sumOfFloat(opp -> opp.capacity);

        if (overflow > totalCapacity) {
            final required = overflow > 0 ? overflow : 0;
            return new PushInResult(prev, curr,
                new RepairCandidate("PushIn", code, offenderIndex, pushInPenalty, false, "insufficient-capacity", offenderIndex, null, null, required,
                    totalCapacity));
        }

        final shrink = overflow > 0 ? overflow : 0;
        final allocations:Array<PushInAllocation> = shrink > 0 ? LineRepair.distributePushInShrink(inLine, shrink) : [];
        final offender = adjustedClusters[offenderIndex];
        final candidate = new RepairCandidate("PushIn", code, offenderIndex, pushInPenalty, true, null, offenderIndex, null, shrink, shrink, totalCapacity);
        final reasonText = shrink > 0 ? code + ":" + offender.text + ":pushed-in=" + LineRepair.toPortableDebugString(shrink) + "/"
            + LineRepair.toPortableDebugString(totalCapacity) : code
            + ":"
            + offender.text
            + ":fits-no-shrink";
        final candidateList = prev.repairCandidates.copy();
        candidateList.push(candidate);
        final repairedPrevious = new LineCandidate(expanded.clusterRange, expanded.sourceRange, expanded.naturalWidth, expanded.adjustedWidth - shrink,
            mergeEndIndex == curr.clusterRange.end ? curr.endReason : prev.endReason,
            RepairOption.PushIn(pushInPenalty, reasonText, offenderIndex, allocations, shrink, totalCapacity), candidateList, expanded.hangingClusterIndices);
        final repairedCurrent = mergeEndIndex == curr.clusterRange.end ? null : LineBreakerLines.rebuildLine(new IntRange(mergeEndIndex + 1,
            curr.clusterRange.end), naturalClusters, adjustedClusters, curr.endReason);
        return new PushInResult(repairedPrevious, repairedCurrent, candidate);
    }

    static function mandatoryBreakTailEnd(curr:LineCandidate, mergeThroughClusterIndex:Int, adjustedClusters:Array<Cluster>):Int {
        if (curr.endReason != LineEndReason.MandatoryBreak)
            return mergeThroughClusterIndex;
        if (mergeThroughClusterIndex >= curr.clusterRange.end)
            return mergeThroughClusterIndex;
        var tailIsZeroWidthBreak = true;
        var idx = mergeThroughClusterIndex + 1;
        while (idx <= curr.clusterRange.end) {
            if (!(adjustedClusters[idx].displayText.length == 0 && adjustedClusters[idx].advance == 0)) {
                tailIsZeroWidthBreak = false;
                break;
            }
            idx++;
        }
        return tailIsZeroWidthBreak ? curr.clusterRange.end : mergeThroughClusterIndex;
    }

    /**
     * Strict tier order (CLREQ squeeze priority): tier k exhausts before
     * tier k+1; within a tier the shrink is shared proportionally to
     * capacity and the rounding remainder lands on the tier's last entry.
     */
    static function distributePushInShrink(opportunities:Array<ShrinkOpportunity>, totalShrink:Float):Array<PushInAllocation> {
        if (opportunities.length == 0 || totalShrink <= 0)
            return [];
        final allocations:Array<PushInAllocation> = [];
        var remaining = totalShrink;
        final byTier = opportunities.groupBy(function(opp:ShrinkOpportunity):ShrinkTierEntry return {key: opp.tier, value: opp});
        var tierIdx = 0;
        while (tierIdx < byTier.size()) {
            final tierOpps:Array<ShrinkOpportunity> = byTier.valueAt(tierIdx);
            final tierCapacity = tierOpps.sumOfFloat(opp -> opp.capacity);
            if (tierCapacity > 0) {
                final tierShrink = remaining < tierCapacity ? remaining : tierCapacity;
                var tierRemaining = tierShrink;
                final ordered = sortByClusterIndex(tierOpps);
                var i2 = 0;
                while (i2 < ordered.length) {
                    final opp = ordered[i2];
                    final isLast = i2 == tierOpps.length - 1;
                    var share = 0.0;
                    if (isLast) {
                        share = tierRemaining < opp.capacity ? tierRemaining : opp.capacity;
                    } else {
                        final proportional = tierShrink * opp.capacity / tierCapacity;
                        share = proportional < opp.capacity ? proportional : opp.capacity;
                    }
                    if (share > 0) {
                        allocations.push(new PushInAllocation(opp.clusterIndex, share, opp.capacity, opp.channel));
                        tierRemaining -= share;
                    }
                    i2++;
                }
                remaining -= (tierShrink - (tierRemaining > 0 ? tierRemaining : 0));
            }
            tierIdx++;
        }
        return allocations;
    }

    static function sortByClusterIndex(opportunities:Array<ShrinkOpportunity>):Array<ShrinkOpportunity>
        return opportunities.sortedBy(opp -> opp.clusterIndex);

    static function toPortableDebugString(value:Float):String {
        final text = "" + value;
        if (text.indexOf(".") == -1 && text.toLowerCase().indexOf("e") == -1)
            return text + ".0";
        return text;
    }

    static function emptyIntSet():SortedSet<Int> {
        final b = SortedSet.builder();
        return b.build();
    }

    static inline final PROGRESSIVE_TIER_PROMOTION_FILL_EPSILON:Float = 0.001;

    static function isContinuableZeroShrinkFillPushIn(repair:Null<RepairOption>):Bool {
        if (repair == null)
            return false;
        final r:RepairOption = repair;
        return switch (r) {
            case PushIn(_, reason, _, _, totalShrink, _): totalShrink <= 0.001 && StringTools.startsWith(reason, "LineAdjustmentPushIn:");
            case Hang(_, _, _): false;
            case CarryPrevious(_, _, _, _): false;
            case CarryNext(_, _, _): false;
            case LeaveRagged(_, _, _): false;
        };
    }

    public static function fillPushInGroupEnd(curr:LineCandidate, forbiddenLineStartClusters:Null<SortedSet<Int>>, forbiddenLineEndClusters:SortedSet<Int>,
            unbreakableRanges:UnbreakableRanges):Null<Int> {
        var groupEnd = curr.clusterRange.start;
        while (groupEnd <= curr.clusterRange.end) {
            final containing = unbreakableRanges.containingFromClosedStartOrNull(groupEnd);
            if (containing != null) {
                groupEnd = containing.end;
                if (groupEnd > curr.clusterRange.end)
                    return null;
                // containing.last may begin the next contiguous unbreakable range: re-check so the
                // pulled group ends past the WHOLE run, never inside it (closure, matching
                // adjustBreakForUnbreakables). Without this, a per-atom formula's fill pass refills the
                // break back inside the chain (`10^{34}|x^3`).
                continue;
            }
            if (forbiddenLineEndClusters.has(groupEnd)) {
                groupEnd += 1;
                continue;
            }
            final nextHead = groupEnd + 1;
            if (nextHead <= curr.clusterRange.end && forbiddenLineStartClusters != null && forbiddenLineStartClusters.has(nextHead)) {
                groupEnd = nextHead;
                continue;
            }
            return groupEnd;
        }
        return null;
    }

    public static function applyFillPushIn(lines:Array<LineCandidate>, naturalClusters:Array<Cluster>, adjustedClusters:Array<Cluster>, maxWidth:Float,
            shrinkOpportunities:Array<ShrinkOpportunity>, firstLineIndent:Float, compressBias:Float, forbiddenLineStartClusters:Null<SortedSet<Int>>,
            forbiddenLineEndClusters:SortedSet<Int>, unbreakableRanges:UnbreakableRanges, pushInPenalty:Int, ?gapBoundaries:Null<SortedSet<Int>>,
            ?progressiveBreakOpportunities:Null<SortedMap<Int, ProgressiveBreakOpportunity>>):Array<LineCandidate> {
        if (lines.length < 2 || compressBias <= 0)
            return lines;
        final gaps = gapBoundaries == null ? LineBreakerLines.emptyIntSet() : gapBoundaries;
        final progressive = progressiveBreakOpportunities == null ? LineBreakerLines.emptyProgressiveMap() : progressiveBreakOpportunities;
        final out = lines.copy();
        var i = 0;
        while (i < out.length - 1) {
            final prev = out[i];
            final curr = out[i + 1];
            final canExtendZeroShrinkFill = isContinuableZeroShrinkFillPushIn(prev.repair);
            if ((prev.repair != null && !canExtendZeroShrinkFill)
                || prev.hangingClusterIndex != null
                || prev.endReason != LineEndReason.AutoWrap) {
                i += 1;
                continue;
            }
            final limit = ProgressiveBreakDecisions.lineLimit(maxWidth, firstLineIndent, prev.clusterRange.start);
            final deficit = limit - prev.adjustedWidth;
            if (deficit <= 0) {
                i += 1;
                continue;
            }
            final curr0 = curr.clusterRange.start;
            var groupEnd = fillPushInGroupEnd(curr, forbiddenLineStartClusters, forbiddenLineEndClusters, unbreakableRanges);
            if (groupEnd == null) {
                i += 1;
                continue;
            }
            final currentBreak = progressive.get(prev.clusterRange.end + 1);
            var resultingBreak = progressive.get(groupEnd + 1);
            var addedAdvance = 0.0;
            var cIdx = curr0;
            while (cIdx <= groupEnd) {
                addedAdvance += adjustedClusters[cIdx].advance;
                cIdx++;
            }
            var promotesProgressiveTier = currentBreak != null
                && resultingBreak != null
                && currentBreak.spanRange.start == resultingBreak.spanRange.start
                && currentBreak.spanRange.end == resultingBreak.spanRange.end
                && resultingBreak.tier.priority < currentBreak.tier.priority;
            if (promotesProgressiveTier && addedAdvance < deficit - PROGRESSIVE_TIER_PROMOTION_FILL_EPSILON) {
                final activeBreak = currentBreak;
                final searchStart = groupEnd + 2;
                final searchEnd = curr.clusterRange.end + 1;
                var matchingTierBoundary:Null<Int> = null;
                if (searchStart <= searchEnd) {
                    var boundary = searchStart;
                    while (boundary <= searchEnd) {
                        final opp = progressive.get(boundary);
                        if (opp != null
                            && opp.spanRange.start == activeBreak.spanRange.start
                            && opp.spanRange.end == activeBreak.spanRange.end
                            && opp.tier == activeBreak.tier) {
                            matchingTierBoundary = boundary;
                            break;
                        }
                        boundary++;
                    }
                }
                if (matchingTierBoundary != null) {
                    groupEnd = matchingTierBoundary - 1;
                    resultingBreak = progressive.get(matchingTierBoundary);
                    addedAdvance = 0.0;
                    var cIdx2 = curr0;
                    while (cIdx2 <= groupEnd) {
                        addedAdvance += adjustedClusters[cIdx2].advance;
                        cIdx2++;
                    }
                    promotesProgressiveTier = false;
                }
            }
            if (currentBreak != null
                && resultingBreak != null
                && currentBreak.spanRange.start == resultingBreak.spanRange.start
                && currentBreak.spanRange.end == resultingBreak.spanRange.end
                && resultingBreak.tier.priority > currentBreak.tier.priority) {
                i += 1;
                continue;
            }
            final overflow = addedAdvance - deficit;
            if (promotesProgressiveTier && overflow < -PROGRESSIVE_TIER_PROMOTION_FILL_EPSILON) {
                i += 1;
                continue;
            }
            if (overflow >= deficit * compressBias) {
                i += 1;
                continue;
            }
            if (overflow > 0.0 && !promotesProgressiveTier) {
                final prevGaps = LineBreakerLines.lineGapCount(prev.clusterRange, gaps);
                final dStretchCured = prevGaps == 0 ? 0.0 : deficit / prevGaps;
                final groupGaps = LineBreakerLines.lineGapCount(new IntRange(prev.clusterRange.start, groupEnd), gaps);
                final dCompressionIntroduced = overflow / (groupGaps > 1 ? groupGaps : 1);
                if (dCompressionIntroduced > dStretchCured) {
                    i += 1;
                    continue;
                }
            }
            final result = tryPushIn(prev, curr, naturalClusters, adjustedClusters, limit, shrinkOpportunities, pushInPenalty, groupEnd,
                promotesProgressiveTier ? "ProgressiveTechnicalTierPromotion" : "LineAdjustmentPushIn");
            if (result.candidate.accepted) {
                out[i] = result.previous;
                if (result.current == null) {
                    out.splice(i + 1, 1);
                } else {
                    out[i + 1] = result.current;
                }
                if (isContinuableZeroShrinkFillPushIn(result.previous.repair) && result.current != null) {
                    continue;
                }
            }
            i += 1;
        }
        return out;
    }

    /** Gated [applyFillPushIn] over a [LineSolution] — no-op when not [enabled]. */
    public static function withFillPushIn(solution:LineSolution, enabled:Bool, naturalClusters:Array<Cluster>, adjustedClusters:Array<Cluster>,
            maxWidth:Float, shrinkOpportunities:Array<ShrinkOpportunity>, firstLineIndent:Float, compressBias:Float,
            forbiddenLineStartClusters:Null<SortedSet<Int>>, forbiddenLineEndClusters:SortedSet<Int>, unbreakableRanges:UnbreakableRanges, pushInPenalty:Int,
            ?gapBoundaries:Null<SortedSet<Int>>, ?progressiveBreakOpportunities:Null<SortedMap<Int, ProgressiveBreakOpportunity>>):LineSolution {
        if (!enabled) {
            return solution;
        }
        return new LineSolution(applyFillPushIn(solution.lines, naturalClusters, adjustedClusters, maxWidth, shrinkOpportunities, firstLineIndent,
            compressBias, forbiddenLineStartClusters, forbiddenLineEndClusters, unbreakableRanges, pushInPenalty, gapBoundaries, progressiveBreakOpportunities),
            solution.totalBadness);
    }
}
