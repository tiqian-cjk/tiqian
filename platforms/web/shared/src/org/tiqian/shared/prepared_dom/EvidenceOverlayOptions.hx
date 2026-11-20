package org.tiqian.shared.prepared_dom;

/**
 * Overlay options of appendEvidenceOverlays. The TS oracle types
 * emphasisDotColor as (clusterRangeStart) => string | null and falls back to
 * currentColor for both null and the empty string; boring puts the
 * nullability of Null<(Float)->String> on the emitted return type, so the
 * Haxe side receives the empty string for "no color" and tests it against
 * "" (the TS truthiness test is byte-equivalent).
 */
typedef EvidenceOverlayOptions = {
    var emphasisDotColor: Null<EmphasisDotColorResolver>;
}
