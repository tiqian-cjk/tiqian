package org.tiqian.layout;

import org.tiqian.core.LayoutDebugInfo;
import org.tiqian.core.FontDecisionInfo;
import org.tiqian.core.MetricDecisionInfo;
import org.tiqian.core.PunctuationDecisionInfo;
import org.tiqian.core.SpacingDecisionInfo;
import org.tiqian.core.LineDecisionInfo;
import org.tiqian.core.LineRepairDecisionInfo;
import org.tiqian.core.LineRepairCandidateInfo;
import org.tiqian.core.LineRepairAllocationInfo;
import org.tiqian.core.JustificationDecisionInfo;
import org.tiqian.core.JustificationAllocationInfo;
import org.tiqian.font.FontPolicy.FontDecision;
import org.tiqian.clreq.ClreqPunctuationGlyphSubstitutor;
import org.tiqian.core.TextRange;
import org.tiqian.core.RoleOverrideInfo;
import org.tiqian.core.LineBox;
import org.tiqian.core.Cluster;
import org.tiqian.core.AutoSpaceDecisionInfo;
import org.tiqian.core.LineEdgeTrimDecisionInfo;
import org.tiqian.core.DecorationDecisionInfo;
import org.tiqian.core.DecorationSegmentInfo;
import org.tiqian.core.RubyDecisionInfo;
import org.tiqian.core.BopomofoDecisionInfo;
import org.tiqian.layout.LineOptimization.PushInAllocation;
import org.tiqian.core.MandatoryBreakDecisionInfo;
import org.tiqian.core.MaxLinesDecisionInfo;
import org.tiqian.core.LineSpacingDecisionInfo;
import org.tiqian.core.RubyLineHeightDecisionInfo;
import org.tiqian.core.InlineObjectLineHeightDecisionInfo;
import org.tiqian.core.KinsokuDecisionInfo;
import org.tiqian.core.ContextualKinsokuDecisionInfo;
import org.tiqian.core.LineLengthGridDecisionInfo;
import org.tiqian.core.FirstLineIndentDecisionInfo;
import org.tiqian.core.InlineBoxDecisionInfo;
import org.tiqian.core.InlineObjectDecisionInfo;
import org.tiqian.core.InlineObjectPunctuationAttachmentDecisionInfo;
import org.tiqian.core.ZeroWidthBreakDecisionInfo;
import org.tiqian.core.BreakOpportunityDecisionInfo;
import org.tiqian.core.EmergencyTrackingEligibilityDecisionInfo;
import org.tiqian.core.ShapingDecisionInfo;
import org.tiqian.core.ClusterGeometryDecisionInfo;
import org.tiqian.layout.LineGeometryStage.ClusterMetricDecision;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.PunctuationModel.PunctuationAtom;
import org.tiqian.layout.PunctuationModel.PunctuationSpacingCompressionResult;
import org.tiqian.layout.PunctuationGeometryLedger.AttachedInlinePunctuationBoundaryResult;
import org.tiqian.layout.LineOptimization.LineSolution;
import org.tiqian.layout.LineOptimization.RepairCandidate;
import org.tiqian.layout.LineOptimization.RepairOption;
import org.tiqian.layout.LineOptimization.RepairOptions;
import org.tiqian.layout.Justifier.JustificationPlan;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;

@:dataClass class LayoutDebugStageInput {
    public final text:String;
    public final fontDecisions:Array<FontDecision>;
    public final punctuationGlyphSubstitutor:ClreqPunctuationGlyphSubstitutor;
    public final substitutionRollbacks:std.SortedMap<TextRange, String>;
    public final shapingDecisions:Array<ShapingDecisionInfo>;
    public final metricDecisions:Array<ClusterMetricDecision>;
    public final punctuationAtoms:Array<PunctuationAtom>;
    public final geometryDecisions:Array<ClusterGeometryDecisionInfo>;
    public final spacingPlan:PunctuationSpacingCompressionResult;
    public final attachedPunctuationBoundary:AttachedInlinePunctuationBoundaryResult;
    public final roleOverrideInfos:Array<RoleOverrideInfo>;
    public final laidOutLines:Array<LineBox>;
    public final lineSolution:LineSolution;
    public final clusters:Array<Cluster>;
    public final justificationPlans:Array<Null<JustificationPlan>>;
    public final autoSpaceDecisions:Array<AutoSpaceDecisionInfo>;
    public final edgeTrimDecisions:Array<LineEdgeTrimDecisionInfo>;
    public final decorationDecisions:Array<DecorationDecisionInfo>;
    public final decorationSegments:Array<DecorationSegmentInfo>;
    public final rubyDecisions:Array<RubyDecisionInfo>;
    public final bopomofoDecisions:Array<BopomofoDecisionInfo>;
    public final mandatoryBreakDecisions:Array<MandatoryBreakDecisionInfo>;
    public final maxLinesDecision:Null<MaxLinesDecisionInfo>;
    public final lineSpacingDecision:Null<LineSpacingDecisionInfo>;
    public final rubyLineHeightDecision:Null<RubyLineHeightDecisionInfo>;
    public final inlineObjectLineHeightDecision:Null<InlineObjectLineHeightDecisionInfo>;
    public final kinsokuDecision:KinsokuDecisionInfo;
    public final contextualKinsokuDecisions:Array<ContextualKinsokuDecisionInfo>;
    public final lineLengthGridDecision:LineLengthGridDecisionInfo;
    public final firstLineIndentDecision:FirstLineIndentDecisionInfo;
    public final inlineBoxDecisions:Array<InlineBoxDecisionInfo>;
    public final inlineObjectDecisions:Array<InlineObjectDecisionInfo>;
    public final inlineObjectPunctuationAttachmentDecisions:Array<InlineObjectPunctuationAttachmentDecisionInfo>;
    public final zeroWidthBreakDecisions:Array<ZeroWidthBreakDecisionInfo>;
    public final breakOpportunityDecisions:Array<BreakOpportunityDecisionInfo>;
    public final emergencyTrackingEligibilityDecisions:Array<EmergencyTrackingEligibilityDecisionInfo>;
    public final progressiveBreakOpportunities:std.SortedMap<Int, ProgressiveBreakOpportunity>;

    public function new(text:String, fontDecisions:Array<FontDecision>, punctuationGlyphSubstitutor:ClreqPunctuationGlyphSubstitutor,
            substitutionRollbacks:std.SortedMap<TextRange, String>, shapingDecisions:Array<ShapingDecisionInfo>, metricDecisions:Array<ClusterMetricDecision>,
            punctuationAtoms:Array<PunctuationAtom>, geometryDecisions:Array<ClusterGeometryDecisionInfo>, spacingPlan:PunctuationSpacingCompressionResult,
            attachedPunctuationBoundary:AttachedInlinePunctuationBoundaryResult, roleOverrideInfos:Array<RoleOverrideInfo>, laidOutLines:Array<LineBox>,
            lineSolution:LineSolution, clusters:Array<Cluster>, justificationPlans:Array<Null<JustificationPlan>>,
            autoSpaceDecisions:Array<AutoSpaceDecisionInfo>, edgeTrimDecisions:Array<LineEdgeTrimDecisionInfo>,
            decorationDecisions:Array<DecorationDecisionInfo>, decorationSegments:Array<DecorationSegmentInfo>, rubyDecisions:Array<RubyDecisionInfo>,
            bopomofoDecisions:Array<BopomofoDecisionInfo>, mandatoryBreakDecisions:Array<MandatoryBreakDecisionInfo>,
            maxLinesDecision:Null<MaxLinesDecisionInfo>, lineSpacingDecision:Null<LineSpacingDecisionInfo>,
            rubyLineHeightDecision:Null<RubyLineHeightDecisionInfo>, inlineObjectLineHeightDecision:Null<InlineObjectLineHeightDecisionInfo>,
            kinsokuDecision:KinsokuDecisionInfo, contextualKinsokuDecisions:Array<ContextualKinsokuDecisionInfo>,
            lineLengthGridDecision:LineLengthGridDecisionInfo, firstLineIndentDecision:FirstLineIndentDecisionInfo,
            inlineBoxDecisions:Array<InlineBoxDecisionInfo>, inlineObjectDecisions:Array<InlineObjectDecisionInfo>,
            inlineObjectPunctuationAttachmentDecisions:Array<InlineObjectPunctuationAttachmentDecisionInfo>,
            zeroWidthBreakDecisions:Array<ZeroWidthBreakDecisionInfo>, breakOpportunityDecisions:Array<BreakOpportunityDecisionInfo>,
            emergencyTrackingEligibilityDecisions:Array<EmergencyTrackingEligibilityDecisionInfo>,
            progressiveBreakOpportunities:std.SortedMap<Int, ProgressiveBreakOpportunity>) {
        this.text = text;
        this.fontDecisions = fontDecisions;
        this.punctuationGlyphSubstitutor = punctuationGlyphSubstitutor;
        this.substitutionRollbacks = substitutionRollbacks;
        this.shapingDecisions = shapingDecisions;
        this.metricDecisions = metricDecisions;
        this.punctuationAtoms = punctuationAtoms;
        this.geometryDecisions = geometryDecisions;
        this.spacingPlan = spacingPlan;
        this.attachedPunctuationBoundary = attachedPunctuationBoundary;
        this.roleOverrideInfos = roleOverrideInfos;
        this.laidOutLines = laidOutLines;
        this.lineSolution = lineSolution;
        this.clusters = clusters;
        this.justificationPlans = justificationPlans;
        this.autoSpaceDecisions = autoSpaceDecisions;
        this.edgeTrimDecisions = edgeTrimDecisions;
        this.decorationDecisions = decorationDecisions;
        this.decorationSegments = decorationSegments;
        this.rubyDecisions = rubyDecisions;
        this.bopomofoDecisions = bopomofoDecisions;
        this.mandatoryBreakDecisions = mandatoryBreakDecisions;
        this.maxLinesDecision = maxLinesDecision;
        this.lineSpacingDecision = lineSpacingDecision;
        this.rubyLineHeightDecision = rubyLineHeightDecision;
        this.inlineObjectLineHeightDecision = inlineObjectLineHeightDecision;
        this.kinsokuDecision = kinsokuDecision;
        this.contextualKinsokuDecisions = contextualKinsokuDecisions;
        this.lineLengthGridDecision = lineLengthGridDecision;
        this.firstLineIndentDecision = firstLineIndentDecision;
        this.inlineBoxDecisions = inlineBoxDecisions;
        this.inlineObjectDecisions = inlineObjectDecisions;
        this.inlineObjectPunctuationAttachmentDecisions = inlineObjectPunctuationAttachmentDecisions;
        this.zeroWidthBreakDecisions = zeroWidthBreakDecisions;
        this.breakOpportunityDecisions = breakOpportunityDecisions;
        this.emergencyTrackingEligibilityDecisions = emergencyTrackingEligibilityDecisions;
        this.progressiveBreakOpportunities = progressiveBreakOpportunities;
    }
}

class LayoutDebugAssembly {
    private static function repairCandidateToDecisionInfo(candidate:RepairCandidate, clusters:Array<Cluster>):LineRepairCandidateInfo {
        return new LineRepairCandidateInfo(candidate.kind, candidate.reasonCode, clusters[candidate.offenderClusterIndex].range, candidate.penalty,
            candidate.accepted, candidate.rejectionReason, candidate.targetClusterIndex, candidate.carriedClusterIndex, candidate.shrink,
            candidate.requiredShrink, candidate.availableCapacity);
    }

    private static function toPushInAllocations(allocations:Array<PushInAllocation>, clusters:Array<Cluster>):Array<LineRepairAllocationInfo> {
        final pushInAllocations = new Array<LineRepairAllocationInfo>();
        for (aIdx in 0...allocations.length) {
            final alloc = allocations[aIdx];
            pushInAllocations.push(new LineRepairAllocationInfo(clusters[alloc.clusterIndex].range, alloc.shrink, alloc.availableCapacity));
        }
        return pushInAllocations;
    }

    private static function repairOptionToDecisionInfo(repair:RepairOption, clusters:Array<Cluster>):LineRepairDecisionInfo {
        return switch (repair) {
            case PushIn(penalty, reason, offenderClusterIndex, allocations, totalShrink, totalAvailableCapacity):
                final pushInAllocations = toPushInAllocations(allocations, clusters);
                final colonIdx = reason.indexOf(":");
                final reasonCode = colonIdx >= 0 ? reason.substring(0, colonIdx) : reason;
                new LineRepairDecisionInfo("PushIn", reasonCode, clusters[offenderClusterIndex].range, penalty, offenderClusterIndex, null, totalShrink,
                    totalAvailableCapacity, pushInAllocations);
            case CarryPrevious(penalty, _, offenderClusterIndex, carriedClusterIndex):
                new LineRepairDecisionInfo("CarryPrevious", "ForbiddenAtLineStart", clusters[offenderClusterIndex].range, penalty, null, carriedClusterIndex);
            case LeaveRagged(penalty, _, offenderClusterIndex):
                new LineRepairDecisionInfo("LeaveRagged", "ForbiddenAtLineStart", clusters[offenderClusterIndex].range, penalty);
            case Hang(penalty, _, offenderClusterIndex):
                new LineRepairDecisionInfo("Hang", "ForbiddenAtLineStart", clusters[offenderClusterIndex].range, penalty);
            case CarryNext(penalty, _, movedClusterIndex):
                new LineRepairDecisionInfo("CarryNext", "ForbiddenAtLineEnd", clusters[movedClusterIndex].range, penalty, null, movedClusterIndex);
        };
    }

    private static function repairOptionName(repair:RepairOption):String {
        return switch (repair) {
            case PushIn(_, _, _, _, _, _): "PushIn";
            case Hang(_, _, _): "Hang";
            case CarryPrevious(_, _, _, _): "CarryPrevious";
            case CarryNext(_, _, _): "CarryNext";
            case LeaveRagged(_, _, _): "LeaveRagged";
        };
    }

    private static function progressiveBreakTierName(tier:org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier):String {
        if (tier == org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier.Whitespace)
            return "Whitespace";
        if (tier == org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier.Structural)
            return "Structural";
        if (tier == org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier.Syllable)
            return "Syllable";
        if (tier == org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier.WholeToken)
            return "WholeToken";
        if (tier == org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier.Emergency)
            return "Emergency";
        return "Unknown";
    }

    public static function buildLayoutDebugInfo(engine:ExplainableStubParagraphLayoutEngine, stage:LayoutDebugStageInput):LayoutDebugInfo {
        final fontDecisionsOut = new Array<FontDecisionInfo>();
        for (fIdx in 0...stage.fontDecisions.length) {
            final decision = stage.fontDecisions[fIdx];
            final clusterText = stage.text.substring(decision.range.start, decision.range.end);
            final substitution = org.tiqian.layout.ContextualPunctuationDisplaySubstitution.ContextualPunctuationDisplaySubstitutionFns.substituteForRole(stage.punctuationGlyphSubstitutor,
                clusterText, decision.role);
            var rollbackCause:Null<String> = null;
            for (i in 0...stage.substitutionRollbacks.size()) {
                final k = stage.substitutionRollbacks.keyAt(i);
                if (k.start >= decision.range.start && k.end <= decision.range.end) {
                    rollbackCause = stage.substitutionRollbacks.valueAt(i);
                    break;
                }
            }
            final displayText = rollbackCause != null ? clusterText : substitution.displayText;
            final substitutionReason = rollbackCause != null ? (substitution.reason + ":" + rollbackCause) : substitution.reason;
            fontDecisionsOut.push(new FontDecisionInfo(decision.range, clusterText, displayText, Type.enumConstructor(decision.role), decision.candidate.key,
                decision.reason, substitutionReason));
        }

        final metricDecisionsOut = new Array<MetricDecisionInfo>();
        for (mIdx in 0...stage.metricDecisions.length) {
            final decision = stage.metricDecisions[mIdx];
            metricDecisionsOut.push(new MetricDecisionInfo(decision.range, decision.sourceText, Type.enumConstructor(decision.request.role),
                decision.request.fontKey, decision.rawMetrics.ascent, decision.rawMetrics.descent, decision.rawMetrics.leading,
                Type.enumConstructor(decision.rawMetrics.source), decision.layoutMetrics.ascent, decision.layoutMetrics.descent,
                Type.enumConstructor(decision.layoutMetrics.baselineClass), Type.enumConstructor(decision.layoutMetrics.metricBox),
                Type.enumConstructor(decision.layoutMetrics.source), decision.layoutMetrics.reason));
        }

        final punctuationDecisionsOut = new Array<PunctuationDecisionInfo>();
        for (pIdx in 0...stage.punctuationAtoms.length) {
            final atom = stage.punctuationAtoms[pIdx];
            punctuationDecisionsOut.push(new PunctuationDecisionInfo(atom.range, atom.char, Type.enumConstructor(atom.punctuationClass), atom.advance,
                atom.bodyWidth, atom.leadingGlue.natural, atom.trailingGlue.natural, Type.enumConstructor(atom.anchor), atom.inkBounds, atom.geometrySource,
                atom.policyBodyFloor, atom.inkWidth, atom.inkCenter, atom.inkContainmentBodyFloor, atom.inkContainmentApplied, atom.inkBoundsFallback,
                atom.haltAdvance, atom.haltValidation, atom.advanceExpansion, atom.glyphInlineShift, atom.glyphPlacementReason,
                atom.leadingGlueInitiallyConsumed, atom.trailingGlueInitiallyConsumed));
        }

        final spacingDecisionsOut = new Array<SpacingDecisionInfo>();
        for (sIdx in 0...stage.spacingPlan.adjustments.length) {
            final adjustment = stage.spacingPlan.adjustments[sIdx];
            spacingDecisionsOut.push(new SpacingDecisionInfo(adjustment.range, adjustment.leftChar, adjustment.rightChar, adjustment.naturalInnerGlue,
                adjustment.adjustedInnerGlue, adjustment.reduction, adjustment.reductionTargetRange, adjustment.reason));
        }
        for (apbIdx in 0...stage.attachedPunctuationBoundary.decisions.length) {
            spacingDecisionsOut.push(stage.attachedPunctuationBoundary.decisions[apbIdx]);
        }

        final lineDecisionsOut = new Array<LineDecisionInfo>();
        final minLineCount = stage.laidOutLines.length < stage.lineSolution.lines.length ? stage.laidOutLines.length : stage.lineSolution.lines.length;
        for (lineIndex in 0...minLineCount) {
            final line = stage.laidOutLines[lineIndex];
            final candidate = stage.lineSolution.lines[lineIndex];

            final repairName = candidate.repair != null ? repairOptionName(candidate.repair) : null;
            final repairPenalty = candidate.repair != null ? RepairOptions.penalty(candidate.repair) : 0;
            final repairDecision = candidate.repair != null ? repairOptionToDecisionInfo(candidate.repair, stage.clusters) : null;

            final repairCandidatesOut = new Array<LineRepairCandidateInfo>();
            for (rcIdx in 0...candidate.repairCandidates.length) {
                repairCandidatesOut.push(repairCandidateToDecisionInfo(candidate.repairCandidates[rcIdx], stage.clusters));
            }

            final notes = [
                "index:" + lineIndex,
                "end:" + Std.string(line.endReason),
                "natural:" + line.naturalWidth,
                "adjusted:" + line.adjustedWidth,
                "visual:" + line.visualWidth
            ];
            final nextCluster = candidate.clusterRange.end + 1;
            if (stage.progressiveBreakOpportunities.has(nextCluster)) {
                final opp = stage.progressiveBreakOpportunities.get(nextCluster);
                notes.push("technical-break:" + progressiveBreakTierName(opp.tier));
            }
            if (candidate.repair != null) {
                notes.push("repair-reason:" + RepairOptions.reason(candidate.repair));
            }
            final plan = lineIndex < stage.justificationPlans.length ? stage.justificationPlans[lineIndex] : null;
            if (plan != null && plan.fallbackReason != null) {
                notes.push("justify-fallback:" + plan.fallbackReason);
            }

            lineDecisionsOut.push(new LineDecisionInfo(line.range, engine.lineBreaker.strategyName, repairName, repairPenalty, repairDecision,
                repairCandidatesOut, notes));
        }

        final justificationDecisionsOut = new Array<JustificationDecisionInfo>();
        for (i in 0...stage.lineSolution.lines.length) {
            final candidate = stage.lineSolution.lines[i];
            final plan = i < stage.justificationPlans.length ? stage.justificationPlans[i] : null;
            if (plan != null && (plan.allocations.length > 0 || plan.deficitBefore > 0.0)) {
                final allocationsOut = new Array<JustificationAllocationInfo>();
                for (aIdx in 0...plan.allocations.length) {
                    final alloc = plan.allocations[aIdx];
                    allocationsOut.push(new JustificationAllocationInfo(stage.clusters[alloc.targetClusterIndex].range, Type.enumConstructor(alloc.kind),
                        alloc.priority, alloc.delta, alloc.reason));
                }
                justificationDecisionsOut.push(new JustificationDecisionInfo(candidate.sourceRange, plan.deficitBefore, plan.unfilledDeficit, allocationsOut));
            }
        }

        return new LayoutDebugInfo(stage.maxLinesDecision, metricDecisionsOut, stage.geometryDecisions, stage.autoSpaceDecisions, stage.rubyDecisions,
            stage.bopomofoDecisions, fontDecisionsOut, stage.shapingDecisions, punctuationDecisionsOut, spacingDecisionsOut, stage.roleOverrideInfos,
            lineDecisionsOut, justificationDecisionsOut, stage.edgeTrimDecisions, stage.decorationDecisions, stage.decorationSegments,
            stage.mandatoryBreakDecisions, stage.lineSpacingDecision, stage.rubyLineHeightDecision, stage.inlineObjectLineHeightDecision,
            stage.kinsokuDecision, stage.contextualKinsokuDecisions, stage.lineLengthGridDecision, stage.firstLineIndentDecision, stage.inlineBoxDecisions,
            stage.inlineObjectDecisions, stage.inlineObjectPunctuationAttachmentDecisions, stage.zeroWidthBreakDecisions, stage.breakOpportunityDecisions,
            stage.emergencyTrackingEligibilityDecisions);
    }
}
