package org.tiqian.shared.prepared_dom;

/**
 * Style delta from the prepared layout plan cell (prepared-dom.ts:54
 * StyleDelta). Every field is optional in the TS oracle; a null field leaves
 * that axis unchanged.
 */
typedef StyleDelta = {
    var fontSize: Null<Float>;
    var fontWeight: Null<Float>;
    var italic: Null<Bool>;
}
