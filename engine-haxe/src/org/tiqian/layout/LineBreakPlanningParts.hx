package org.tiqian.layout;

import org.tiqian.core.IntRange;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakOpportunity;
import org.tiqian.layout.ProgressiveBreakDecisions.ProgressiveBreakTier;
import org.tiqian.layout.UnicodePunctuationBoundaryResolver.AttachedInlineInterCharBoundaries;
import std.SortedMap;
import std.SortedSet;

/**
 * `LineBreakPlanningBase`: the break-planning sets of `LineBreakPlanningStage.planParagraphLines`
 * that depend only on a `ShapedParagraphBase` and the paragraph input fields that the annotation
 * cache key fixes (source text, line-break spans, decorations, ruby spans, text style). Neither the
 * measure nor the kinsoku level enters them, so a relayout at another width reuses one value
 * (`WidthIndependentLayoutMemo.planningBase`).
 *
 * `leadingUnbreakableRanges` holds the mourning-decoration, ruby-base and attached-inline
 * unbreakable ranges, in that order; planning appends the measure-dependent ranges after them so
 * the combined list keeps the order it had when every range was collected per layout.
 */
class LineBreakPlanningBase {
    public final attachedInlineInterCharBoundaries:AttachedInlineInterCharBoundaries;
    public final attachedInlineForbiddenLineStartClusters:SortedSet<Int>;
    public final hyphenBreakClusters:SortedSet<Int>;
    public final progressiveBreakOpportunities:SortedMap<Int, ProgressiveBreakOpportunity>;
    public final numberSymbolClusterRanges:Array<IntRange>;
    public final noStretchBoundaryClusters:SortedSet<Int>;
    public final technicalBoundaryAfterClusters:SortedMap<Int, ProgressiveBreakTier>;
    public final emergencyTrackingBoundaryAfterClusters:SortedMap<Int, String>;
    public final leadingUnbreakableRanges:Array<IntRange>;

    public function new(attachedInlineInterCharBoundaries:AttachedInlineInterCharBoundaries, attachedInlineForbiddenLineStartClusters:SortedSet<Int>,
            hyphenBreakClusters:SortedSet<Int>, progressiveBreakOpportunities:SortedMap<Int, ProgressiveBreakOpportunity>,
            numberSymbolClusterRanges:Array<IntRange>, noStretchBoundaryClusters:SortedSet<Int>,
            technicalBoundaryAfterClusters:SortedMap<Int, ProgressiveBreakTier>, emergencyTrackingBoundaryAfterClusters:SortedMap<Int, String>,
            leadingUnbreakableRanges:Array<IntRange>) {
        this.attachedInlineInterCharBoundaries = attachedInlineInterCharBoundaries;
        this.attachedInlineForbiddenLineStartClusters = attachedInlineForbiddenLineStartClusters;
        this.hyphenBreakClusters = hyphenBreakClusters;
        this.progressiveBreakOpportunities = progressiveBreakOpportunities;
        this.numberSymbolClusterRanges = numberSymbolClusterRanges;
        this.noStretchBoundaryClusters = noStretchBoundaryClusters;
        this.technicalBoundaryAfterClusters = technicalBoundaryAfterClusters;
        this.emergencyTrackingBoundaryAfterClusters = emergencyTrackingBoundaryAfterClusters;
        this.leadingUnbreakableRanges = leadingUnbreakableRanges;
    }
}

/**
 * `KinsokuDependentPlanning`: the break-planning sets that also depend on the resolved kinsoku
 * level, through the prep's kinsoku rule and `KinsokuDependentPrep.inlineObjectAttachmentNoStretchBoundaries`,
 * and on nothing that varies with the measure. `forbiddenLineStartCoreClusters` holds every
 * forbidden line start except the ones the measure-dependent contextual kinsoku adds
 * (`PunctuationGeometryStage.attachedAsciiPointMarkKinsoku` and `inlineObjectAttachedKinsoku`);
 * planning merges those per layout. `WidthIndependentLayoutMemo.planningKinsokuPart` keeps one
 * value per kinsoku level.
 */
class KinsokuDependentPlanning {
    public final forbiddenLineStartCoreClusters:SortedSet<Int>;
    public final forbiddenLineEndClusters:SortedSet<Int>;
    public final noStretchBoundaryAfterClusters:SortedSet<Int>;
    public final cjkInterCharBoundaries:SortedSet<Int>;
    public final sinoWesternBoundaries:SortedSet<Int>;

    /** `LineBreakerLines.unionLineGapBoundaries(cjkInterCharBoundaries, sinoWesternBoundaries)`, passed to the line breaker. */
    public final lineGapBoundaries:SortedSet<Int>;

    public function new(forbiddenLineStartCoreClusters:SortedSet<Int>, forbiddenLineEndClusters:SortedSet<Int>,
            noStretchBoundaryAfterClusters:SortedSet<Int>, cjkInterCharBoundaries:SortedSet<Int>, sinoWesternBoundaries:SortedSet<Int>,
            lineGapBoundaries:SortedSet<Int>) {
        this.forbiddenLineStartCoreClusters = forbiddenLineStartCoreClusters;
        this.forbiddenLineEndClusters = forbiddenLineEndClusters;
        this.noStretchBoundaryAfterClusters = noStretchBoundaryAfterClusters;
        this.cjkInterCharBoundaries = cjkInterCharBoundaries;
        this.sinoWesternBoundaries = sinoWesternBoundaries;
        this.lineGapBoundaries = lineGapBoundaries;
    }
}
