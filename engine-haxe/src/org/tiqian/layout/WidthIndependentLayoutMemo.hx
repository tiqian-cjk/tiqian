package org.tiqian.layout;

import org.tiqian.core.FontDecisionInfo;
import org.tiqian.core.TextRange;
import org.tiqian.layout.LineGeometryStage.ClusterMetricDecision;
import org.tiqian.layout.ParagraphPrepParts.KinsokuDependentPrep;
import org.tiqian.layout.ParagraphPrepParts.ShapedParagraphBase;
import org.tiqian.layout.UnicodePunctuationBoundaryResolver.UnicodePunctuationBoundaries;
import org.tiqian.layout.cache.LayoutMemoSlot;
import org.tiqian.layout.cache.LayoutMemoSlot.IntKeyedLayoutMemoSlot;
import std.SortedMap;
import std.SortedSet;

/**
 * `WidthIndependentLayoutMemo`: the memo slots of one paragraph. Paragraph preparation,
 * line-break planning and the debug assembly each read a slot, compute the value when the slot is
 * empty and write it back, so a relayout at another width reuses values that do not depend on the
 * measure.
 *
 * Every slot holds a pure function of fields that the annotation cache key already fixes (source
 * text, styles, font decisions, the base shaping stage's clusters, roles, quote pairs and
 * substitution rollbacks) plus the engine's font-metrics resolver and normalizer. None depends on
 * the measure; `kinsokuDependent` also depends on the measure-adaptive kinsoku level and is keyed
 * by it.
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
    public final kinsokuDependent:IntKeyedLayoutMemoSlot<KinsokuDependentPrep>;

    /** Raw and normalized font metrics per font decision (`LineBreakPlanningStage.planParagraphLines`). */
    public final metricDecisions:LayoutMemoSlot<Array<ClusterMetricDecision>>;

    /** The metric decision containing each natural cluster, keyed by cluster range. */
    public final metricDecisionByRange:LayoutMemoSlot<SortedMap<TextRange, ClusterMetricDecision>>;

    /** Contextual kinsoku boundaries from `UnicodePunctuationBoundaryResolver.resolveUnicodePunctuationBoundaries`. */
    public final unicodePunctuationBoundaries:LayoutMemoSlot<UnicodePunctuationBoundaries>;

    /** Western bracket and CJK inter-character boundaries after each cluster. */
    public final westernBracketBoundaries:LayoutMemoSlot<SortedSet<Int>>;

    /** The debug record of each font decision with its display substitution (`LayoutDebugAssembly.buildLayoutDebugInfo`). */
    public final fontDecisionInfos:LayoutMemoSlot<Array<FontDecisionInfo>>;

    public function new() {
        this.shapedBase = new LayoutMemoSlot<ShapedParagraphBase>();
        this.kinsokuDependent = new IntKeyedLayoutMemoSlot<KinsokuDependentPrep>();
        this.metricDecisions = new LayoutMemoSlot<Array<ClusterMetricDecision>>();
        this.metricDecisionByRange = new LayoutMemoSlot<SortedMap<TextRange, ClusterMetricDecision>>();
        this.unicodePunctuationBoundaries = new LayoutMemoSlot<UnicodePunctuationBoundaries>();
        this.westernBracketBoundaries = new LayoutMemoSlot<SortedSet<Int>>();
        this.fontDecisionInfos = new LayoutMemoSlot<Array<FontDecisionInfo>>();
    }
}
