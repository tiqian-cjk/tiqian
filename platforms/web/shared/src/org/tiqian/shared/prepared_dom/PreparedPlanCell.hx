package org.tiqian.shared.prepared_dom;

/**
 * One prepared plan cell, typed (prepared-dom.ts PreparedLayoutPlanCell).
 *
 * The three signature fields are computed by the glue from the wire object
 * because the TS oracle uses JSON.stringify over the parsed object: rendering
 * order and undefined-key folding of JSON.stringify cannot be reproduced after
 * the wire object has been turned into a typed record. They participate only
 * in merge decisions, never in the emitted bytes.
 *
 * leadingLayoutAdvance keeps the TS arithmetic: the glue maps a missing field
 * to NaN so drawX - leadingLayoutAdvance is NaN, which the flow gate treats
 * as inside tolerance exactly like TS.
 */
typedef PreparedPlanCell = {
    var rangeStart: Float;
    var rangeEnd: Float;
    var source: String;
    var display: String;
    var drawX: Float;
    var naturalWidth: Float;
    var leadingLayoutAdvance: Float;
    var advance: Null<Float>;
    var shapingBoundary: Bool;
    var openTypeFeatures: Null<Array<String>>;
    var style: Null<StyleDelta>;
    var styleSignature: String;
    var punctuationSignature: String;
    var latin: Bool;
    var dashStrategy: Null<String>;
    var shapingLanguage: Null<String>;
    var resolvedFace: Null<String>;
    var glyphIds: Null<String>;
    var shapingEvidence: Null<String>;
    var punctuationInkFloor: Null<Float>;
    var punctuationBodyWidth: Null<Float>;
    var renderFontFamily: Null<String>;
    var inlineObject: Null<Float>;
}
