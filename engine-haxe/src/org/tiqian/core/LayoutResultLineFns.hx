package org.tiqian.core;

/** Line overload of the positioned-cluster extension; see LayoutResultFns. */
@:keep
class LayoutResultLineFns {
    @:extension
    public static function positionedClusters(result:LayoutResult, line:LineBox):Array<PositionedCluster>
        return LayoutQueries.positionedClustersForLine(result, line);
}
