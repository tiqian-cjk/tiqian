package org.tiqian.core;

@:dataClass
class LineRepairAllocationInfo {
    public final clusterRange:TextRange;
    public final shrink:Float;
    public final availableCapacity:Float;

    public function new(clusterRange:TextRange, shrink:Float, availableCapacity:Float) {
        this.clusterRange = clusterRange;
        this.shrink = shrink;
        this.availableCapacity = availableCapacity;
    }
}
