package org.tiqian.shared.prepared_dom;

/**
 * Failure identity carried by PreparedDomException. The single variant matches
 * the one throw site in renderRun (prepared-dom.ts:558).
 */
enum PreparedDomError {
    UnsupportedOpenTypeFeatures(signature:String);
    InvalidPreparedOverlayGeometry;
    SnapshotRenderFlowMismatch(detail:String);
    ConflictingPreparedRenderTextSpan;
}
