package org.tiqian.shared.prepared_dom;

/**
 * Ruby annotation plus its plan base range (prepared-dom.ts
 * PlanRubyAnnotation). The fields mirror RubyAnnotation; the typedef is
 * repeated instead of extended because reflaxe emits no structure extension.
 */
typedef PlanRubyAnnotation = {
    var fontSize: Float;
    var ascent: Float;
    var fontFamilies: Array<String>;
    var text: String;
    var fontWeight: Float;
    var centerX: Float;
    var baselineY: Float;
    var baseRangeEnd: Float;
}
