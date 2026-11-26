package org.tiqian.layout;

import org.tiqian.clreq.PunctuationClass;
import org.tiqian.core.Glyph;
import org.tiqian.core.TextRange;
import org.tiqian.layout.LineBreakPlanningStage.ParagraphLayoutPrep;
import org.tiqian.layout.LineGeometryStage.ClusterMetricDecision;
import std.SortedMap;

/**
 * `FinishClusterLookups`: the per-cluster values that `LineAdjustmentStage.finishParagraphLayout`
 * reads for every cluster of every layout, stored by natural cluster index. Entry `i` of each
 * array is the value that the prep's range-keyed map returns for `prep.naturalClusters[i].range`
 * (null when the map has no entry), so reading entry `i` returns what the map lookup returned.
 *
 * `finishParagraphLayout` reads them through the clusters of `PunctuationGeometryLedger.resolveClusters`:
 * the ledger is built from the same `naturalClusters` array as the prep and keeps it, and entry
 * `i` of the resolved clusters keeps the range of natural cluster `i`.
 *
 * The shaped glyphs, OpenType features and metric decisions depend on fields that
 * `WidthIndependentLayoutMemo` already treats as width-independent; the punctuation class comes
 * from the kinsoku-dependent prep part, so the memo keeps the value in a slot keyed by
 * `kinsokuLevelMemoKey` (`WidthIndependentLayoutMemo.finishClusterLookups`).
 */
class FinishClusterLookups {
    public final shapedGlyphs:Array<Null<Array<Glyph>>>;
    public final openTypeFeatures:Array<Null<Array<String>>>;
    public final metricDecisions:Array<Null<ClusterMetricDecision>>;
    public final punctuationClasses:Array<Null<PunctuationClass>>;

    public function new(shapedGlyphs:Array<Null<Array<Glyph>>>, openTypeFeatures:Array<Null<Array<String>>>,
            metricDecisions:Array<Null<ClusterMetricDecision>>, punctuationClasses:Array<Null<PunctuationClass>>) {
        this.shapedGlyphs = shapedGlyphs;
        this.openTypeFeatures = openTypeFeatures;
        this.metricDecisions = metricDecisions;
        this.punctuationClasses = punctuationClasses;
    }

    public static function build(prep:ParagraphLayoutPrep, metricDecisionByRange:SortedMap<TextRange, ClusterMetricDecision>):FinishClusterLookups {
        final shapedGlyphs = new Array<Null<Array<Glyph>>>();
        final openTypeFeatures = new Array<Null<Array<String>>>();
        final metricDecisions = new Array<Null<ClusterMetricDecision>>();
        final punctuationClasses = new Array<Null<PunctuationClass>>();
        for (i in 0...prep.naturalClusters.length) {
            final range = prep.naturalClusters[i].range;
            shapedGlyphs.push(prep.shapedGlyphsByClusterRange.get(range));
            openTypeFeatures.push(prep.openTypeFeaturesByClusterRange.get(range));
            metricDecisions.push(metricDecisionByRange.get(range));
            punctuationClasses.push(prep.atomClassByRange.get(range));
        }
        return new FinishClusterLookups(shapedGlyphs, openTypeFeatures, metricDecisions, punctuationClasses);
    }
}
