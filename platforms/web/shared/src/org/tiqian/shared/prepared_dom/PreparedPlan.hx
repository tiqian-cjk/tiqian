package org.tiqian.shared.prepared_dom;

/**
 * The typed prepared layout plan the artifact lowering consumes (prepared-dom.ts
 * PreparedLayoutPlan). Parsing the wire JSON, checking schema/layoutRevision
 * and folding missing arrays to empty ones happen in the glue.
 */
typedef PreparedPlan = {
    var height: Float;
    var lines: Array<PreparedPlanLine>;
    var emphasisRanges: Array<PreparedEmphasisRange>;
    var rubyDecisions: Array<PlanRubyAnnotation>;
    var bopomofoDecisions: Array<PlanBopomofoZone>;
    var inlineEdges: Array<InlineEdgeEntry>;
    var decorationSegments: Null<Array<EvidenceDecorationSegment>>;
    var emphasisDots: Null<Array<EvidenceEmphasisDot>>;
    var fontSize: Float;
    var overlayWidth: Float;
}
