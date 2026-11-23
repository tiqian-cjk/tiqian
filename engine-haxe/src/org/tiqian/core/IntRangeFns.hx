package org.tiqian.core;

/**
 * Extension form of the empty-cluster-range predicate. The handwritten engine
 * exposed it as `internal fun IntRange.isEmptyClusterRange()`; the port dropped
 * it, so it is restored here with the same receiver shape.
 */
@:keep
class IntRangeFns {
    @:extension
    public static function isEmptyClusterRange(range:IntRange):Bool
        return range.first > range.last;
}
