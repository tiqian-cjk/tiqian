package org.tiqian.core;

import std.ReadOnlyArray;

// The Kotlin original declares every constructor parameter with a default
// (empty list or null) and orders the list fields before the nullable
// decisions. The port keeps maxLinesDecision as the mandatory first
// parameter because the ported tests construct positionally; callers that
// interoperate with the handwritten Kotlin use named arguments, so the
// parameter order carries no interop meaning.
@:dataClass
class LayoutDebugInfo {
    public final maxLinesDecision:Null<MaxLinesDecisionInfo>;
    public final metricDecisions:ReadOnlyArray<MetricDecisionInfo>;
    public final geometryDecisions:ReadOnlyArray<ClusterGeometryDecisionInfo>;
    public final autoSpaceDecisions:ReadOnlyArray<AutoSpaceDecisionInfo>;
    public final rubyDecisions:ReadOnlyArray<RubyDecisionInfo>;
    public final bopomofoDecisions:ReadOnlyArray<BopomofoDecisionInfo>;
    public final fontDecisions:ReadOnlyArray<FontDecisionInfo>;
    public final shapingDecisions:ReadOnlyArray<ShapingDecisionInfo>;
    public final punctuationDecisions:ReadOnlyArray<PunctuationDecisionInfo>;
    public final spacingDecisions:ReadOnlyArray<SpacingDecisionInfo>;
    public final roleOverrides:ReadOnlyArray<RoleOverrideInfo>;
    public final lineDecisions:ReadOnlyArray<LineDecisionInfo>;
    public final justificationDecisions:ReadOnlyArray<JustificationDecisionInfo>;
    public final lineEdgeTrimDecisions:ReadOnlyArray<LineEdgeTrimDecisionInfo>;
    public final decorationDecisions:ReadOnlyArray<DecorationDecisionInfo>;
    public final decorationSegments:ReadOnlyArray<DecorationSegmentInfo>;
    public final mandatoryBreakDecisions:ReadOnlyArray<MandatoryBreakDecisionInfo>;
    public final lineSpacingDecision:Null<LineSpacingDecisionInfo>;
    public final rubyLineHeightDecision:Null<RubyLineHeightDecisionInfo>;
    public final inlineObjectLineHeightDecision:Null<InlineObjectLineHeightDecisionInfo>;
    public final kinsokuDecision:Null<KinsokuDecisionInfo>;
    public final contextualKinsokuDecisions:ReadOnlyArray<ContextualKinsokuDecisionInfo>;
    public final lineLengthGridDecision:Null<LineLengthGridDecisionInfo>;
    public final firstLineIndentDecision:Null<FirstLineIndentDecisionInfo>;
    public final inlineBoxDecisions:ReadOnlyArray<InlineBoxDecisionInfo>;
    public final inlineObjectDecisions:ReadOnlyArray<InlineObjectDecisionInfo>;
    public final inlineObjectPunctuationAttachmentDecisions:ReadOnlyArray<InlineObjectPunctuationAttachmentDecisionInfo>;
    public final zeroWidthBreakDecisions:ReadOnlyArray<ZeroWidthBreakDecisionInfo>;
    public final breakOpportunityDecisions:ReadOnlyArray<BreakOpportunityDecisionInfo>;
    public final emergencyTrackingEligibilityDecisions:ReadOnlyArray<EmergencyTrackingEligibilityDecisionInfo>;

    public function new(maxLinesDecision:Null<MaxLinesDecisionInfo>, ?metricDecisions:Array<MetricDecisionInfo>,
            ?geometryDecisions:Array<ClusterGeometryDecisionInfo>, ?autoSpaceDecisions:Array<AutoSpaceDecisionInfo>, ?rubyDecisions:Array<RubyDecisionInfo>,
            ?bopomofoDecisions:Array<BopomofoDecisionInfo>, ?fontDecisions:Array<FontDecisionInfo>, ?shapingDecisions:Array<ShapingDecisionInfo>,
            ?punctuationDecisions:Array<PunctuationDecisionInfo>, ?spacingDecisions:Array<SpacingDecisionInfo>, ?roleOverrides:Array<RoleOverrideInfo>,
            ?lineDecisions:Array<LineDecisionInfo>, ?justificationDecisions:Array<JustificationDecisionInfo>,
            ?lineEdgeTrimDecisions:Array<LineEdgeTrimDecisionInfo>, ?decorationDecisions:Array<DecorationDecisionInfo>,
            ?decorationSegments:Array<DecorationSegmentInfo>, ?mandatoryBreakDecisions:Array<MandatoryBreakDecisionInfo>,
            ?lineSpacingDecision:Null<LineSpacingDecisionInfo>, ?rubyLineHeightDecision:Null<RubyLineHeightDecisionInfo>,
            ?inlineObjectLineHeightDecision:Null<InlineObjectLineHeightDecisionInfo>, ?kinsokuDecision:Null<KinsokuDecisionInfo>,
            ?contextualKinsokuDecisions:Array<ContextualKinsokuDecisionInfo>, ?lineLengthGridDecision:Null<LineLengthGridDecisionInfo>,
            ?firstLineIndentDecision:Null<FirstLineIndentDecisionInfo>, ?inlineBoxDecisions:Array<InlineBoxDecisionInfo>,
            ?inlineObjectDecisions:Array<InlineObjectDecisionInfo>,
            ?inlineObjectPunctuationAttachmentDecisions:Array<InlineObjectPunctuationAttachmentDecisionInfo>,
            ?zeroWidthBreakDecisions:Array<ZeroWidthBreakDecisionInfo>, ?breakOpportunityDecisions:Array<BreakOpportunityDecisionInfo>,
            ?emergencyTrackingEligibilityDecisions:Array<EmergencyTrackingEligibilityDecisionInfo>) {
        this.maxLinesDecision = maxLinesDecision;
        this.metricDecisions = metricDecisions == null ? [] : metricDecisions;
        this.geometryDecisions = geometryDecisions == null ? [] : geometryDecisions;
        this.autoSpaceDecisions = autoSpaceDecisions == null ? [] : autoSpaceDecisions;
        this.rubyDecisions = rubyDecisions == null ? [] : rubyDecisions;
        this.bopomofoDecisions = bopomofoDecisions == null ? [] : bopomofoDecisions;
        this.fontDecisions = fontDecisions == null ? [] : fontDecisions;
        this.shapingDecisions = shapingDecisions == null ? [] : shapingDecisions;
        this.punctuationDecisions = punctuationDecisions == null ? [] : punctuationDecisions;
        this.spacingDecisions = spacingDecisions == null ? [] : spacingDecisions;
        this.roleOverrides = roleOverrides == null ? [] : roleOverrides;
        this.lineDecisions = lineDecisions == null ? [] : lineDecisions;
        this.justificationDecisions = justificationDecisions == null ? [] : justificationDecisions;
        this.lineEdgeTrimDecisions = lineEdgeTrimDecisions == null ? [] : lineEdgeTrimDecisions;
        this.decorationDecisions = decorationDecisions == null ? [] : decorationDecisions;
        this.decorationSegments = decorationSegments == null ? [] : decorationSegments;
        this.mandatoryBreakDecisions = mandatoryBreakDecisions == null ? [] : mandatoryBreakDecisions;
        this.lineSpacingDecision = lineSpacingDecision;
        this.rubyLineHeightDecision = rubyLineHeightDecision;
        this.inlineObjectLineHeightDecision = inlineObjectLineHeightDecision;
        this.kinsokuDecision = kinsokuDecision;
        this.contextualKinsokuDecisions = contextualKinsokuDecisions == null ? [] : contextualKinsokuDecisions;
        this.lineLengthGridDecision = lineLengthGridDecision;
        this.firstLineIndentDecision = firstLineIndentDecision;
        this.inlineBoxDecisions = inlineBoxDecisions == null ? [] : inlineBoxDecisions;
        this.inlineObjectDecisions = inlineObjectDecisions == null ? [] : inlineObjectDecisions;
        this.inlineObjectPunctuationAttachmentDecisions = inlineObjectPunctuationAttachmentDecisions == null ? [] : inlineObjectPunctuationAttachmentDecisions;
        this.zeroWidthBreakDecisions = zeroWidthBreakDecisions == null ? [] : zeroWidthBreakDecisions;
        this.breakOpportunityDecisions = breakOpportunityDecisions == null ? [] : breakOpportunityDecisions;
        this.emergencyTrackingEligibilityDecisions = emergencyTrackingEligibilityDecisions == null ? [] : emergencyTrackingEligibilityDecisions;
    }

    public static function withMetricDecisions(values:Array<MetricDecisionInfo>):LayoutDebugInfo {
        return new LayoutDebugInfo(null, values);
    }

    public static function withGeometryDecisions(values:Array<ClusterGeometryDecisionInfo>):LayoutDebugInfo {
        return new LayoutDebugInfo(null, [], values);
    }

    public static function withAutoSpaceDecisions(values:Array<AutoSpaceDecisionInfo>):LayoutDebugInfo {
        return new LayoutDebugInfo(null, [], [], values);
    }

    public static function withRubyDecisions(values:Array<RubyDecisionInfo>):LayoutDebugInfo {
        return new LayoutDebugInfo(null, [], [], [], values);
    }

    public static function withBopomofoDecisions(values:Array<BopomofoDecisionInfo>):LayoutDebugInfo {
        return new LayoutDebugInfo(null, [], [], [], [], values);
    }
}
