package org.tiqian.layout;

import org.tiqian.clreq.PunctuationClass;
import org.tiqian.core.AutoSpaceDecisionInfo;
import org.tiqian.core.Cluster;
import org.tiqian.core.EastAsianSpacingEdges;
import org.tiqian.core.Glyph;
import org.tiqian.core.InlineAttachment;
import org.tiqian.core.InlineObjectPreferredStretch;
import org.tiqian.core.InlineObjectPunctuationAttachmentDecisionInfo;
import org.tiqian.core.InlineObjectSpan;
import org.tiqian.core.IntRange;
import org.tiqian.core.MandatoryBreakDecisionInfo;
import org.tiqian.core.ShapingDecisionInfo;
import org.tiqian.core.TextRange;
import org.tiqian.core.ZeroWidthBreakDecisionInfo;
import org.tiqian.font.FontRole;
import org.tiqian.layout.ProgressiveBreakDecisions.ShrinkOpportunity;
import org.tiqian.layout.PunctuationGeometryLedger.AttachedInlinePunctuationBoundaryResult;
import org.tiqian.layout.PunctuationGeometryStage.InlineBoxApplicationResult;
import org.tiqian.layout.PunctuationGeometryStage.InlineObjectAttachedMark;
import org.tiqian.layout.PunctuationModel.PunctuationAtom;
import org.tiqian.layout.PunctuationModel.PunctuationSpacingCompressionResult;
import std.SortedMap;
import std.SortedSet;

/**
 * `ShapedParagraphBase`: the part of a `ParagraphLayoutPrep` that depends only on one shaping
 * stage, the paragraph input and its width-independent annotation: natural clusters after
 * auto-space and inline boxes, cluster roles, inline-object boundaries, mandatory and zero-width
 * breaks, punctuation atoms with their spacing compression, and the ruby spread. Neither the
 * measure nor the kinsoku level enters it, so a prep built on the base shaping stage reuses one
 * base at every width (`WidthIndependentLayoutMemo.shapedBase`).
 */
class ShapedParagraphBase {
    public final shapedGlyphsByClusterRange:SortedMap<TextRange, Array<Glyph>>;
    public final openTypeFeaturesByClusterRange:SortedMap<TextRange, Array<String>>;
    public final eastAsianSpacingEdges:Array<EastAsianSpacingEdges>;
    public final autoSpaceDecisions:Array<AutoSpaceDecisionInfo>;
    public final inlineBoxResult:InlineBoxApplicationResult;
    public final naturalClusters:Array<Cluster>;
    public final inlineObjectByClusterIndex:SortedMap<Int, InlineObjectSpan>;
    public final uniformInlineObjectBoundaryAfterClusters:SortedSet<Int>;
    public final preferredInlineObjectBoundaryAfterClusters:SortedMap<Int, InlineObjectPreferredStretch>;
    public final inlineObjectBoundaryUnbreakableRanges:Array<IntRange>;
    public final clusterRoles:Array<FontRole>;
    public final mandatoryBreakClusters:SortedSet<Int>;
    public final zeroWidthBreakClusters:SortedSet<Int>;
    public final mandatoryBreakDecisions:Array<MandatoryBreakDecisionInfo>;
    public final zeroWidthBreakDecisions:Array<ZeroWidthBreakDecisionInfo>;
    public final punctuationAtoms:Array<PunctuationAtom>;
    public final spacingPlan:PunctuationSpacingCompressionResult;
    public final rubyAndBopomofoSpread:SortedMap<Int, Float>;
    public final shapingDecisions:Array<ShapingDecisionInfo>;

    public function new(shapedGlyphsByClusterRange:SortedMap<TextRange, Array<Glyph>>,
            openTypeFeaturesByClusterRange:SortedMap<TextRange, Array<String>>, eastAsianSpacingEdges:Array<EastAsianSpacingEdges>,
            autoSpaceDecisions:Array<AutoSpaceDecisionInfo>, inlineBoxResult:InlineBoxApplicationResult, naturalClusters:Array<Cluster>,
            inlineObjectByClusterIndex:SortedMap<Int, InlineObjectSpan>, uniformInlineObjectBoundaryAfterClusters:SortedSet<Int>,
            preferredInlineObjectBoundaryAfterClusters:SortedMap<Int, InlineObjectPreferredStretch>,
            inlineObjectBoundaryUnbreakableRanges:Array<IntRange>, clusterRoles:Array<FontRole>, mandatoryBreakClusters:SortedSet<Int>,
            zeroWidthBreakClusters:SortedSet<Int>, mandatoryBreakDecisions:Array<MandatoryBreakDecisionInfo>,
            zeroWidthBreakDecisions:Array<ZeroWidthBreakDecisionInfo>, punctuationAtoms:Array<PunctuationAtom>,
            spacingPlan:PunctuationSpacingCompressionResult, rubyAndBopomofoSpread:SortedMap<Int, Float>, shapingDecisions:Array<ShapingDecisionInfo>) {
        this.shapedGlyphsByClusterRange = shapedGlyphsByClusterRange;
        this.openTypeFeaturesByClusterRange = openTypeFeaturesByClusterRange;
        this.eastAsianSpacingEdges = eastAsianSpacingEdges;
        this.autoSpaceDecisions = autoSpaceDecisions;
        this.inlineBoxResult = inlineBoxResult;
        this.naturalClusters = naturalClusters;
        this.inlineObjectByClusterIndex = inlineObjectByClusterIndex;
        this.uniformInlineObjectBoundaryAfterClusters = uniformInlineObjectBoundaryAfterClusters;
        this.preferredInlineObjectBoundaryAfterClusters = preferredInlineObjectBoundaryAfterClusters;
        this.inlineObjectBoundaryUnbreakableRanges = inlineObjectBoundaryUnbreakableRanges;
        this.clusterRoles = clusterRoles;
        this.mandatoryBreakClusters = mandatoryBreakClusters;
        this.zeroWidthBreakClusters = zeroWidthBreakClusters;
        this.mandatoryBreakDecisions = mandatoryBreakDecisions;
        this.zeroWidthBreakDecisions = zeroWidthBreakDecisions;
        this.punctuationAtoms = punctuationAtoms;
        this.spacingPlan = spacingPlan;
        this.rubyAndBopomofoSpread = rubyAndBopomofoSpread;
        this.shapingDecisions = shapingDecisions;
    }
}

/**
 * `KinsokuDependentPrep`: the part of a `ParagraphLayoutPrep` that depends on a
 * `ShapedParagraphBase` and the resolved kinsoku level, and on nothing else that varies with the
 * measure: punctuation attached to inline objects (which follows the kinsoku rule), the
 * punctuation geometry ledger that consumes those attachments, the resolved clusters and the shrink
 * opportunities. Natural inline attachments and atom classes do not depend on the level; they are
 * built here because the ledger and the shrink opportunities consume them. `WidthIndependentLayoutMemo`
 * keeps one part per kinsoku level, so relayouts at widths that resolve to a level seen before reuse
 * that level's part.
 */
class KinsokuDependentPrep {
    public final inlineObjectAttachedMarks:Array<InlineObjectAttachedMark>;
    public final inlineObjectSeparatorSpaceTrims:SortedMap<Int, Float>;
    public final inlineObjectAttachmentNoStretchBoundaries:SortedSet<Int>;
    public final inlineObjectPunctuationAttachmentDecisions:Array<InlineObjectPunctuationAttachmentDecisionInfo>;
    public final naturalInlineAttachments:Array<InlineAttachment>;
    public final attachedPunctuationBoundary:AttachedInlinePunctuationBoundaryResult;
    public final baseGeometry:PunctuationGeometryLedger;
    public final attachedPunctuationTrailingGlueByCluster:SortedMap<Int, Float>;
    public final clusters:Array<Cluster>;
    public final atomClassByRange:SortedMap<TextRange, PunctuationClass>;
    public final shrinkOpportunities:Array<ShrinkOpportunity>;

    public function new(inlineObjectAttachedMarks:Array<InlineObjectAttachedMark>, inlineObjectSeparatorSpaceTrims:SortedMap<Int, Float>,
            inlineObjectAttachmentNoStretchBoundaries:SortedSet<Int>,
            inlineObjectPunctuationAttachmentDecisions:Array<InlineObjectPunctuationAttachmentDecisionInfo>,
            naturalInlineAttachments:Array<InlineAttachment>, attachedPunctuationBoundary:AttachedInlinePunctuationBoundaryResult,
            baseGeometry:PunctuationGeometryLedger, attachedPunctuationTrailingGlueByCluster:SortedMap<Int, Float>, clusters:Array<Cluster>,
            atomClassByRange:SortedMap<TextRange, PunctuationClass>, shrinkOpportunities:Array<ShrinkOpportunity>) {
        this.inlineObjectAttachedMarks = inlineObjectAttachedMarks;
        this.inlineObjectSeparatorSpaceTrims = inlineObjectSeparatorSpaceTrims;
        this.inlineObjectAttachmentNoStretchBoundaries = inlineObjectAttachmentNoStretchBoundaries;
        this.inlineObjectPunctuationAttachmentDecisions = inlineObjectPunctuationAttachmentDecisions;
        this.naturalInlineAttachments = naturalInlineAttachments;
        this.attachedPunctuationBoundary = attachedPunctuationBoundary;
        this.baseGeometry = baseGeometry;
        this.attachedPunctuationTrailingGlueByCluster = attachedPunctuationTrailingGlueByCluster;
        this.clusters = clusters;
        this.atomClassByRange = atomClassByRange;
        this.shrinkOpportunities = shrinkOpportunities;
    }
}
