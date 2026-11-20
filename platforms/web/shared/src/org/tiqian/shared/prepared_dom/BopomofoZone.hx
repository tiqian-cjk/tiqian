package org.tiqian.shared.prepared_dom;

/** Bopomofo annotation zone input (prepared-dom-evidence.ts BopomofoZone). */
typedef BopomofoZone = {
    var text: String;
    var fontWeight: Float;
    var fontFamilies: Array<String>;
    var placements: Array<BopomofoPlacement>;
}
