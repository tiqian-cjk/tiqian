package org.tiqian.layout;

import org.tiqian.core.FontDecisionInfo;
import org.tiqian.core.MetricDecisionInfo;
import org.tiqian.core.PunctuationDecisionInfo;
import org.tiqian.core.TextRange;
import org.tiqian.layout.LineBreakPlanningParts.KinsokuDependentPlanning;
import org.tiqian.layout.LineBreakPlanningParts.LineBreakPlanningBase;
import org.tiqian.layout.LineGeometryStage.ClusterMetricDecision;
import org.tiqian.layout.ParagraphPrepParts.KinsokuDependentPrep;
import org.tiqian.layout.ParagraphPrepParts.ShapedParagraphBase;
import org.tiqian.layout.UnicodePunctuationBoundaryResolver.UnicodePunctuationBoundaries;
import org.tiqian.layout.cache.LayoutMemoSlot;
import std.SortedMap;

/**
 * `WidthIndependentLayoutMemo`: the memo slots of one paragraph. Paragraph preparation,
 * line-break planning and the debug assembly each read a slot, compute the value when the slot is
 * empty and write it back, so a relayout at another width reuses values that do not depend on the
 * measure.
 *
 * Every slot holds a pure function of fields that the annotation cache key already fixes (source
 * text, styles, line-break spans, decorations, ruby spans, font decisions, the base shaping
 * stage's clusters, roles, quote pairs and substitution rollbacks) plus engine components (the
 * font-metrics resolver and normalizer, and the justifier's progressive technical stretch
 * capacity). None depends on the measure or on the paragraph style; `kinsokuDependent`,
 * `planningKinsokuPart` and `finishClusterLookups` also depend on the measure-adaptive kinsoku
 * level, so each is an array of slots indexed by `kinsokuLevelMemoKey`, one slot per
 * `KinsokuLevel`: a relayout whose measure moves the paragraph back to a level it had before reuses
 * that level's values. The arrays hold `LayoutMemoSlot` values directly; a generic slot container
 * class did not compile in boring's Rust target, which emits no `PartialEq` for a generic class
 * whose array field fails its Clone check (`classDecl` in `RustDecl.hx`), while this class derives
 * `PartialEq` over its fields.
 *
 * Each `WidthIndependentParagraphAnnotation` owns one memo that lives as long as the annotation.
 * A prep built from a dynamic shaping stage, which depends on the measure, receives a new memo of
 * its own instead, so its values are computed for that layout only. Stored values are shared by
 * every `LayoutResult` built from the annotation, and no stage mutates them after construction.
 * Like the annotation cache that owns it, the memo serves the thread that uses its engine.
 */
class WidthIndependentLayoutMemo {
    /** The prep part derived from the base shaping stage alone (`buildParagraphLayoutPrep`). */
    public final shapedBase:LayoutMemoSlot<ShapedParagraphBase>;

    /** The prep part that also depends on the kinsoku level, keyed by `kinsokuLevelMemoKey`. */
    public final kinsokuDependent:Array<LayoutMemoSlot<KinsokuDependentPrep>>;

    /** Raw and normalized font metrics per font decision (`LineBreakPlanningStage.planParagraphLines`). */
    public final metricDecisions:LayoutMemoSlot<Array<ClusterMetricDecision>>;

    /** The metric decision containing each natural cluster, keyed by cluster range. */
    public final metricDecisionByRange:LayoutMemoSlot<SortedMap<TextRange, ClusterMetricDecision>>;

    /** Contextual kinsoku boundaries from `UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries`. */
    public final unicodePunctuationBoundaries:LayoutMemoSlot<UnicodePunctuationBoundaries>;

    /** The break-planning sets that depend on neither the measure nor the kinsoku level. */
    public final planningBase:LayoutMemoSlot<LineBreakPlanningBase>;

    /** The break-planning sets that also depend on the kinsoku level, keyed by `kinsokuLevelMemoKey`. */
    public final planningKinsokuPart:Array<LayoutMemoSlot<KinsokuDependentPlanning>>;

    /** The debug record of each font decision with its display substitution (`LayoutDebugAssembly.buildLayoutDebugInfo`). */
    public final fontDecisionInfos:LayoutMemoSlot<Array<FontDecisionInfo>>;

    /** The debug record of each entry of `metricDecisions` (`LayoutDebugAssembly.buildLayoutDebugInfo`). */
    public final metricDecisionInfos:LayoutMemoSlot<Array<MetricDecisionInfo>>;

    /** The debug record of each punctuation atom of `shapedBase` (`LayoutDebugAssembly.buildLayoutDebugInfo`). */
    public final punctuationDecisionInfos:LayoutMemoSlot<Array<PunctuationDecisionInfo>>;

    /** The per-cluster lookups of `LineAdjustmentStage.finishParagraphLayout`, keyed by `kinsokuLevelMemoKey`. */
    public final finishClusterLookups:Array<LayoutMemoSlot<FinishClusterLookups>>;

    public function new() {
        this.shapedBase = new LayoutMemoSlot<ShapedParagraphBase>();
        this.kinsokuDependent = [new LayoutMemoSlot<KinsokuDependentPrep>(), new LayoutMemoSlot<KinsokuDependentPrep>(), new LayoutMemoSlot<KinsokuDependentPrep>(), new LayoutMemoSlot<KinsokuDependentPrep>()];
        this.metricDecisions = new LayoutMemoSlot<Array<ClusterMetricDecision>>();
        this.metricDecisionByRange = new LayoutMemoSlot<SortedMap<TextRange, ClusterMetricDecision>>();
        this.unicodePunctuationBoundaries = new LayoutMemoSlot<UnicodePunctuationBoundaries>();
        this.planningBase = new LayoutMemoSlot<LineBreakPlanningBase>();
        this.planningKinsokuPart = [new LayoutMemoSlot<KinsokuDependentPlanning>(), new LayoutMemoSlot<KinsokuDependentPlanning>(), new LayoutMemoSlot<KinsokuDependentPlanning>(), new LayoutMemoSlot<KinsokuDependentPlanning>()];
        this.fontDecisionInfos = new LayoutMemoSlot<Array<FontDecisionInfo>>();
        this.metricDecisionInfos = new LayoutMemoSlot<Array<MetricDecisionInfo>>();
        this.punctuationDecisionInfos = new LayoutMemoSlot<Array<PunctuationDecisionInfo>>();
        this.finishClusterLookups = [new LayoutMemoSlot<FinishClusterLookups>(), new LayoutMemoSlot<FinishClusterLookups>(), new LayoutMemoSlot<FinishClusterLookups>(), new LayoutMemoSlot<FinishClusterLookups>()];
    }
}
