package org.tiqian.shared.prepared_dom;

/** Test resolver: colours cluster 3 and reports no colour for every other cluster. */
class ClusterThreeDotColor implements EmphasisDotColorResolver {
    public function new() {}

    public function resolve(clusterRangeStart:Float):String {
        return clusterRangeStart == 3 ? "rgb(17, 34, 51)" : "";
    }
}
