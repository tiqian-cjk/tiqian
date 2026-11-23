package org.tiqian.shared.prepared_dom;

/**
 * The PreparedRun fields renderRun reads (prepared-dom.ts:215-243 subset).
 * Field optionality matches the TS oracle exactly: openTypeFeatures is
 * optional (folds to empty signature), renderFontFamilies is always present,
 * and the remaining shaping/punctuation/evidence fields are nullable.
 */
typedef PreparedRunRenderInput = {
    var source: String;
    var display: String;
    var drawX: Float;
    var naturalWidth: Float;
    var shapingBoundary: Bool;
    var openTypeFeatures: Null<Array<String>>;
    var renderFontFamilies: Array<String>;
    var trailingGap: Float;
    var spacing: PreparedSpacingResult;
    var styleDelta: Null<StyleDelta>;
    var italicEffect: Bool;
    var dashStrategy: Null<String>;
    var shapingLanguage: Null<String>;
    var resolvedFace: Null<String>;
    var glyphIds: Null<String>;
    var shapingEvidence: Null<String>;
    var punctuationInkFloor: Null<Float>;
    var punctuationBodyWidth: Null<Float>;
    var evidenceRenderFontFamily: Null<String>;
}
