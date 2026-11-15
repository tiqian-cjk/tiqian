package org.tiqian.shared.prepared_dom;

/** One bopomofo glyph placement inside a zone (prepared-dom-evidence.ts). */
typedef BopomofoPlacement = {
    var text: String;
    var role: String;
    var left: Float;
    var top: Float;
    var width: Float;
    var height: Float;
}
