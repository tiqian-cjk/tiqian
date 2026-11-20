package org.tiqian.core;

/**
 * Extension form of the positioned-cluster query. The published Kotlin API
 * exposes `LayoutResult.positionedClusters()`, so the port emits an extension
 * function instead of the static `LayoutQueries.positionedClusters(result)`.
 * The line overload lives in LayoutResultLineFns because Haxe has no
 * overloading and both must emit the same Kotlin name.
 */
@:keep
class LayoutResultFns {
    @:extension
    public static function positionedClusters(result:LayoutResult):Array<PositionedCluster>
        return LayoutQueries.positionedClusters(result);
}
