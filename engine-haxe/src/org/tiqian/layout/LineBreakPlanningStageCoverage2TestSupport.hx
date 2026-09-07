package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.font.FontRole;
import org.tiqian.clreq.PunctuationClass;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.font.FontPolicy.FontDecision;
import org.tiqian.layout.LineBreakPlanningStage.ParagraphLayoutPrep;
import org.tiqian.layout.LineBreakPlanningStage.LineBreakPlanningStageResult;
import org.tiqian.layout.WidthIndependentAnnotationCache.WidthIndependentAnnotationCacheFns;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedMap;
import std.SortedSet;

class LineBreakPlanningStageCoverage2TestSupport {
    public static function engine():ExplainableStubParagraphLayoutEngine
        return new ExplainableStubParagraphLayoutEngine();

    public static function layout(text:String, width:Float = 200, ?objects:Array<InlineObjectSpan>):LayoutResult {
        final e = engine();
        return e.layout(new LayoutInput(new TiqianTextContent(text), null, new ParagraphStyle(), new LayoutConstraints(width), null, null, null, null,
            objects));
    }

    public static function input(text:String):LayoutInput
        return new LayoutInput(new TiqianTextContent(text), null, new ParagraphStyle(), new LayoutConstraints(200), null, null, null, null, null);

    public static function prep(text:String):ParagraphLayoutPrep {
        final e = engine();
        final i = input(text);
        final z:SortedMap<TextRange, SortedSet<Int>> = SortedMap.builder().build();
        final a = WidthIndependentAnnotationCacheFns.prepareWidthIndependentAnnotation(e, i, z);
        return WidthIndependentAnnotationCacheFns.buildParagraphLayoutPrep(e, i, a, z);
    }

    public static function withPrep(p:ParagraphLayoutPrep, ?natural:Array<Cluster>, ?clusters:Array<Cluster>, ?fonts:Array<FontDecision>,
            ?offsets:SortedMap<Int, ProgressiveBreakOpportunity>, ?elig:Array<EmergencyTrackingEligibilityDecisionInfo>, ?uniform:SortedSet<Int>,
            ?atoms:SortedMap<TextRange, PunctuationClass>):ParagraphLayoutPrep {
        final nc = natural == null ? p.naturalClusters : natural;
        final cr = clusters == null ? p.clusters : clusters;
        var roles:Array<FontRole> = p.clusterRoles;
        var edges:Array<EastAsianSpacingEdges> = p.eastAsianSpacingEdges;
        var attachments:Array<InlineAttachment> = p.naturalInlineAttachments;
        if (natural != null && nc.length != p.naturalClusters.length) {
            roles = [];
            edges = [];
            attachments = [];
            for (i in 0...nc.length) {
                roles.push(FontRole.LatinText);
                edges.push(new EastAsianSpacingEdges(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other, false));
                attachments.push(InlineAttachment.None);
            }
        }
        return new ParagraphLayoutPrep(p.input, p.rejectedTechnicalTiersBySpan, p.text, p.fontSize, p.styleAt, p.fontSizeAt, p.bopomofoFontWeightAt,
            p.rubyFontSize, p.rubyStackGap, p.rubyFontWeight, p.pinyinSpans, p.clreqProfile, p.punctuationGlyphSubstitutor, p.measure, p.measureEm,
            p.gridBodyOffset, p.lineLengthGridDecision, p.quotePairs, p.roleOverrideInfos, fonts == null ? p.fontDecisions : fonts, p.hyphenOffsets,
            p.hyphenAdvance, p.hyphenGlyphs, p.substitutionRollbacks, p.breakOpportunityDecisions,
            elig == null ? p.emergencyTrackingEligibilityDecisions : elig, offsets == null ? p.progressiveBreakOffsets : offsets,
            p.shapedGlyphsByClusterRange, p.openTypeFeaturesByClusterRange, p.shapingDecisions, edges, p.autoSpaceDecisions, p.inlineBoxResult, nc,
            p.inlineObjectByClusterIndex, uniform == null ? p.uniformInlineObjectBoundaryAfterClusters : uniform,
            p.preferredInlineObjectBoundaryAfterClusters, p.inlineObjectBoundaryUnbreakableRanges, roles, p.resolvedKinsoku, p.kinsokuRule,
            p.inlineObjectAttachedMarks, p.inlineObjectSeparatorSpaceTrims, p.inlineObjectAttachmentNoStretchBoundaries,
            p.inlineObjectPunctuationAttachmentDecisions, p.mandatoryBreakClusters, p.zeroWidthBreakClusters, p.mandatoryBreakDecisions,
            p.zeroWidthBreakDecisions, p.punctuationAtoms, p.spacingPlan, p.rubyFontGeometryBySpan, p.rubyAndBopomofoSpread, attachments,
            p.attachedPunctuationBoundary, p.baseGeometry, p.attachedPunctuationTrailingGlueByCluster, cr, p.adjustmentStyle,
            atoms == null ? p.atomClassByRange : atoms, p.shrinkOpportunities);
    }

    public static function plan(p:ParagraphLayoutPrep):LineBreakPlanningStageResult
        return LineBreakPlanningStage.planParagraphLines(engine(), p);

    public static function mapOpp():SortedMap<Int, ProgressiveBreakOpportunity> {
        final b = SortedMap.builder();
        b.put(999, new ProgressiveBreakOpportunity(ProgressiveBreakTier.Whitespace, new TextRange(0, 3)));
        return b.build();
    }

    public static function mapAtom():SortedMap<TextRange, PunctuationClass> {
        final b = SortedMap.builder();
        b.put(new TextRange(0, 1), PunctuationClass.Dash);
        b.put(new TextRange(2, 3), PunctuationClass.Connector);
        return b.build();
    }

    public static function setUniform():SortedSet<Int> {
        final b:std.SortedSetBuilder<Int> = SortedSet.builder();
        b.put(0);
        b.put(1);
        b.put(3);
        return b.build();
    }
}
