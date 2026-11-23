package org.tiqian.shared.prepared_dom;

/**
 * Overlay geometry input of appendEvidenceOverlays (prepared-dom-evidence.ts
 * EvidenceOverlayPlan). The TS oracle folds a missing segment/dot list to the
 * empty array, so both lists are nullable here.
 */
typedef EvidenceOverlayPlan = {
    var decorationSegments: Null<Array<EvidenceDecorationSegment>>;
    var emphasisDots: Null<Array<EvidenceEmphasisDot>>;
    var fontSize: Float;
    var overlayWidth: Float;
    var height: Float;
}
