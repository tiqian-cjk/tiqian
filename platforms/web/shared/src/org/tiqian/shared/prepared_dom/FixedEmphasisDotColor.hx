package org.tiqian.shared.prepared_dom;

/** Emphasis-dot resolver stand-in: the corpus fixed colour for every cluster. */
class FixedEmphasisDotColor implements EmphasisDotColorResolver {
    public function new() {}

    public function resolve(clusterRangeStart:Float):String {
        return "rgb(17, 34, 51)";
    }
}
