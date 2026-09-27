package org.tiqian.core;

import std.ReadOnlyArray;

@:dataClass
class LineRepairDecisionInfo {
    public final kind:String;
    public final reasonCode:String;
    public final offenderRange:TextRange;
    public final penalty:Int;
    public final targetClusterIndex:Null<Int>;
    public final carriedClusterIndex:Null<Int>;
    public final shrink:Float;
    public final availableCapacity:Float;
    public final pushInAllocations:ReadOnlyArray<LineRepairAllocationInfo>;

    public function new(kind:String, reasonCode:String, offenderRange:TextRange, penalty:Int, ?targetClusterIndex:Null<Int>, ?carriedClusterIndex:Null<Int>,
            ?shrink:Null<Float>, ?availableCapacity:Null<Float>, ?pushInAllocations:Array<LineRepairAllocationInfo>) {
        this.kind = kind;
        this.reasonCode = reasonCode;
        this.offenderRange = offenderRange;
        this.penalty = penalty;
        this.targetClusterIndex = targetClusterIndex == null ? null : targetClusterIndex;
        this.carriedClusterIndex = carriedClusterIndex == null ? null : carriedClusterIndex;
        this.shrink = shrink == null ? 0.0 : shrink;
        this.availableCapacity = availableCapacity == null ? 0.0 : availableCapacity;
        this.pushInAllocations = pushInAllocations == null ? [] : pushInAllocations;
    }
}
