package org.tiqian.shared.prepared_dom;

/** Bopomofo zone plus its plan base range (prepared-dom.ts PlanBopomofoZone). */
typedef PlanBopomofoZone = {
    var text: String;
    var fontWeight: Float;
    var fontFamilies: Array<String>;
    var placements: Array<BopomofoPlacement>;
    var baseRangeEnd: Float;
}
