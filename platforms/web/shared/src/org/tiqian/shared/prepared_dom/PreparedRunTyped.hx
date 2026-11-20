package org.tiqian.shared.prepared_dom;

/**
 * The run record the artifact lowering builds per plan cell (prepared-dom.ts
 * PreparedRun). It is a structural superset of both PreparedRunSignature (the
 * merge pass) and PreparedRunRenderInput (renderRun), so it is passed to those
 * functions unchanged.
 */
typedef PreparedRunTyped = {
    var rangeStart: Float;
    var rangeEnd: Float;
    var source: String;
    var display: String;
    var drawX: Float;
    var naturalWidth: Float;
    var shapingBoundary: Bool;
    var openTypeFeatures: Null<Array<String>>;
    var renderFontFamilies: Array<String>;
    var trailingGap: Float;
    var spacing: PreparedSpacingResult;
    var semanticPath: Array<PreparedSemanticSpan>;
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
    var inlineObjectAdvance: Null<Float>;
    var bopomofoAdvanceWidth: Float;
    var styleSignature: String;
    var punctuationSignature: String;
    var semanticSignature: Null<String>;
}
