package org.tiqian.shared.prepared_dom;

/**
 * Ruby annotation input of rubyAnnotationSpan (prepared-dom-evidence.ts
 * RubyAnnotation). fontFamilies is always present in the TS oracle, which
 * folds a missing list to the empty array.
 */
typedef RubyAnnotation = {
    var fontSize: Float;
    var ascent: Float;
    var fontFamilies: Array<String>;
    var text: String;
    var fontWeight: Float;
    var centerX: Float;
    var baselineY: Float;
}
