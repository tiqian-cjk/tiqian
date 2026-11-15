package org.tiqian.shared.prepared_dom;

/** One prepared plan line, typed (prepared-dom.ts PreparedLayoutPlanLine). */
typedef PreparedPlanLine = {
    var cells: Array<PreparedPlanCell>;
    var top: Float;
    var bottom: Float;
    var baseline: Float;
    var indent: Float;
    var visualWidth: Float;
    var hyphenAdvance: Float;
    var endReason: String;
    var rangeStart: Float;
    var rangeEnd: Float;
}
