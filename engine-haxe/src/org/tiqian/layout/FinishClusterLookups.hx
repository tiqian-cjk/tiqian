package org.tiqian.layout;

import org.tiqian.clreq.PunctuationClass;
import org.tiqian.core.Glyph;
import org.tiqian.core.AccurateSum;
import org.tiqian.core.Cluster;
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
 * from the kinsoku-dependent prep part, so the memo keeps one value per `kinsokuLevelMemoKey`
 * (`WidthIndependentLayoutMemo.finishClusterLookups`).
 *
 * `mappedShapedGlyphs` holds `ParagraphShapingStage.mapToClusterRange(shapedGlyphs[i], cluster)`
 * for every cluster whose shaped glyphs have a positive total advance: that branch reads only the
 * glyphs and the cluster range, which resolved cluster `i` shares with natural cluster `i`. The
 * entry is null when the cluster has no shaped glyphs or their advance is not positive; that
 * branch reads the resolved advance, so `finishParagraphLayout` maps those glyphs per layout.
 */
class FinishClusterLookups {
    public final shapedGlyphs:Array<Null<Array<Glyph>>>;
    public final openTypeFeatures:Array<Null<Array<String>>>;
    public final metricDecisions:Array<Null<ClusterMetricDecision>>;
    public final punctuationClasses:Array<Null<PunctuationClass>>;
    public final mappedShapedGlyphs:Array<Null<Array<Glyph>>>;

    public function new(shapedGlyphs:Array<Null<Array<Glyph>>>, openTypeFeatures:Array<Null<Array<String>>>,
            metricDecisions:Array<Null<ClusterMetricDecision>>, punctuationClasses:Array<Null<PunctuationClass>>,
            mappedShapedGlyphs:Array<Null<Array<Glyph>>>) {
        this.shapedGlyphs = shapedGlyphs;
        this.openTypeFeatures = openTypeFeatures;
        this.metricDecisions = metricDecisions;
        this.punctuationClasses = punctuationClasses;
        this.mappedShapedGlyphs = mappedShapedGlyphs;
    }

    public static function build(prep:ParagraphLayoutPrep, metricDecisionByRange:SortedMap<TextRange, ClusterMetricDecision>):FinishClusterLookups {
        final shapedGlyphs = new Array<Null<Array<Glyph>>>();
        final openTypeFeatures = new Array<Null<Array<String>>>();
        final metricDecisions = new Array<Null<ClusterMetricDecision>>();
        final punctuationClasses = new Array<Null<PunctuationClass>>();
        final mappedShapedGlyphs = new Array<Null<Array<Glyph>>>();
        for (i in 0...prep.naturalClusters.length) {
            final cluster = prep.naturalClusters[i];
            final range = cluster.range;
            final shaped = prep.shapedGlyphsByClusterRange.get(range);
            shapedGlyphs.push(shaped);
            mappedShapedGlyphs.push(shaped == null ? null : mappedWhenAdvancePositive(shaped, cluster));
            openTypeFeatures.push(prep.openTypeFeaturesByClusterRange.get(range));
            metricDecisions.push(metricDecisionByRange.get(range));
            punctuationClasses.push(prep.atomClassByRange.get(range));
        }
        return new FinishClusterLookups(shapedGlyphs, openTypeFeatures, metricDecisions, punctuationClasses, mappedShapedGlyphs);
    }

    /** `mapToClusterRange(glyphs, cluster)` when the glyphs' total advance is positive, else null. */
    static function mappedWhenAdvancePositive(glyphs:Array<Glyph>, cluster:Cluster):Null<Array<Glyph>> {
        final terms:Array<Float> = [];
        for (i in 0...glyphs.length)
            terms.push(glyphs[i].advance);
        return AccurateSum.of(terms) > 0.0 ? ParagraphShapingStage.mapToClusterRange(glyphs, cluster) : null;
    }
}
