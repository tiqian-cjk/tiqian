package org.tiqian.shared.prepared_dom;

/**
 * Emphasis-dot colour resolver as an interface, per the D1 ruling. The empty
 * string means "no colour"; the lowering folds it to currentColor, which is
 * byte-equivalent to the TS resolver returning null.
 */
interface EmphasisDotColorResolver {
    public function resolve(clusterRangeStart:Float):String;
}
