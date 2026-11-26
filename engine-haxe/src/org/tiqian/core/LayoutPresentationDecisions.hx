package org.tiqian.core;

import std.ReadOnlyArray;

/**
 * `LayoutPresentationDecisions`: the decision records of one layout that presentation code reads.
 * Renderers draw ruby, bopomofo and decoration marks and pick display fonts from them;
 * `PlanLowering` and `PreparedParagraph` build paint plans from them; `LayoutQueries`,
 * `RichTextLayoutQueries`, `LayoutPaintBounds` and `LayoutResultReplayIndex` compute selection
 * geometry, paint bounds and replay lookups from them.
 *
 * `LayoutResult.presentation` always carries these records. `LayoutResult.debug` carries the full
 * explanation record (`LayoutDebugInfo`, which repeats the same lists) only when the engine
 * records debug information, so presentation code never reads `LayoutResult.debug`.
 *
 * The constructor takes the lists in the order `LayoutDebugInfo` declares its leading
 * parameters (metric, geometry, auto-space, ruby, bopomofo, font, shaping, punctuation), then
 * the decoration, zero-width break and line spacing records.
 */
@:dataClass
class LayoutPresentationDecisions {
    public final metricDecisions:ReadOnlyArray<MetricDecisionInfo>;
    public final geometryDecisions:ReadOnlyArray<ClusterGeometryDecisionInfo>;
    public final autoSpaceDecisions:ReadOnlyArray<AutoSpaceDecisionInfo>;
    public final rubyDecisions:ReadOnlyArray<RubyDecisionInfo>;
    public final bopomofoDecisions:ReadOnlyArray<BopomofoDecisionInfo>;
    public final fontDecisions:ReadOnlyArray<FontDecisionInfo>;
    public final shapingDecisions:ReadOnlyArray<ShapingDecisionInfo>;
    public final punctuationDecisions:ReadOnlyArray<PunctuationDecisionInfo>;
    public final decorationDecisions:ReadOnlyArray<DecorationDecisionInfo>;
    public final decorationSegments:ReadOnlyArray<DecorationSegmentInfo>;
    public final zeroWidthBreakDecisions:ReadOnlyArray<ZeroWidthBreakDecisionInfo>;
    public final lineSpacingDecision:Null<LineSpacingDecisionInfo>;

    /** The published no-argument default, used by LayoutResult's presentation parameter. */
    public static final Default:LayoutPresentationDecisions = new LayoutPresentationDecisions();

    public function new(?metricDecisions:Array<MetricDecisionInfo>, ?geometryDecisions:Array<ClusterGeometryDecisionInfo>,
            ?autoSpaceDecisions:Array<AutoSpaceDecisionInfo>, ?rubyDecisions:Array<RubyDecisionInfo>, ?bopomofoDecisions:Array<BopomofoDecisionInfo>,
            ?fontDecisions:Array<FontDecisionInfo>, ?shapingDecisions:Array<ShapingDecisionInfo>, ?punctuationDecisions:Array<PunctuationDecisionInfo>,
            ?decorationDecisions:Array<DecorationDecisionInfo>, ?decorationSegments:Array<DecorationSegmentInfo>,
            ?zeroWidthBreakDecisions:Array<ZeroWidthBreakDecisionInfo>, ?lineSpacingDecision:Null<LineSpacingDecisionInfo>) {
        this.metricDecisions = metricDecisions == null ? [] : metricDecisions;
        this.geometryDecisions = geometryDecisions == null ? [] : geometryDecisions;
        this.autoSpaceDecisions = autoSpaceDecisions == null ? [] : autoSpaceDecisions;
        this.rubyDecisions = rubyDecisions == null ? [] : rubyDecisions;
        this.bopomofoDecisions = bopomofoDecisions == null ? [] : bopomofoDecisions;
        this.fontDecisions = fontDecisions == null ? [] : fontDecisions;
        this.shapingDecisions = shapingDecisions == null ? [] : shapingDecisions;
        this.punctuationDecisions = punctuationDecisions == null ? [] : punctuationDecisions;
        this.decorationDecisions = decorationDecisions == null ? [] : decorationDecisions;
        this.decorationSegments = decorationSegments == null ? [] : decorationSegments;
        this.zeroWidthBreakDecisions = zeroWidthBreakDecisions == null ? [] : zeroWidthBreakDecisions;
        this.lineSpacingDecision = lineSpacingDecision;
    }
}
