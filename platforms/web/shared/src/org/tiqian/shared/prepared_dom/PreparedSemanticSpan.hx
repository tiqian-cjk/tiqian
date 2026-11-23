package org.tiqian.shared.prepared_dom;

/**
 * One normalized semantic span, the union of the snapshot and live shapes
 * (snapshot-source.ts SnapshotSemanticSpan / LiveSemanticSpan), plus the two
 * fields the typed lowering needs:
 *
 * index — position in the normalized list; the lowering compares semantic
 * paths by this value, which is the identity comparison the TS oracle
 * performs on the span objects.
 * signature — JSON.stringify of the normalized span object, computed by the
 * glue; the merge pass compares it, so the oracle's serialization order is
 * preserved without a JSON writer in the generated module.
 */
typedef PreparedSemanticSpan = {
    var index: Int;
    var start: Float;
    var end: Float;
    var tagName: String;
    var sourceIndex: Float;
    var attributes: Array<AttributeEntry>;
    var signature: String;
}
