package org.tiqian.shared.prepared_dom;

/** Advance of the U+00A0 spacing carrier for cells inside [rangeStart, rangeEnd) (plan spacingCarrierAdvances). */
typedef PreparedSpacingCarrierAdvance = {
    var rangeStart: Float;
    var rangeEnd: Float;
    var advance: Float;
}
