package org.tiqian.shared.prepared_dom;

/**
 * Record typedef for the PreparedRun fields the merge pass touches
 * (prepared-dom.ts:215-243 subset). Record typedef is one of the three kinds
 * the boring TS target lowers faithfully (class / variant enum / record
 * typedef), so the merge decision replays byte-for-byte. The full PreparedRun
 * adds drawX / semanticPath / styleDelta / shaping detail; it is a structural
 * superset assignable to this width.
 */
typedef PreparedRunSignature = {
    var rangeStart: Float;
    var rangeEnd: Float;
    var source: String;
    var display: String;
    var naturalWidth: Float;
    var trailingGap: Float;
    var shapingBoundary: Bool;
    var openTypeFeatures: Null<Array<String>>;
    var renderFontFamilies: Array<String>;
    var spacing: PreparedSpacingResult;
    var italicEffect: Bool;
    var dashStrategy: Null<String>;
    var evidenceRenderFontFamily: Null<String>;
    var styleSignature: String;
    var punctuationSignature: String;
    var semanticSignature: Null<String>;
}
