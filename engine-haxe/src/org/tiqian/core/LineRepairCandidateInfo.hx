package org.tiqian.core;

@:dataClass
class LineRepairCandidateInfo {
    public final kind:String;
    public final reasonCode:String;
    public final offenderRange:TextRange;
    public final penalty:Int;
    public final accepted:Bool;
    public final rejectionReason:Null<String>;
    public final targetClusterIndex:Null<Int>;
    public final carriedClusterIndex:Null<Int>;
    public final shrink:Float;
    public final requiredShrink:Float;
    public final availableCapacity:Float;

    public function new(kind:String, reasonCode:String, offenderRange:TextRange, penalty:Int, accepted:Bool, ?rejectionReason:Null<String>,
            ?targetClusterIndex:Null<Int>, ?carriedClusterIndex:Null<Int>, ?shrink:Null<Float>, ?requiredShrink:Null<Float>, ?availableCapacity:Null<Float>) {
        this.kind = kind;
        this.reasonCode = reasonCode;
        this.offenderRange = offenderRange;
        this.penalty = penalty;
        this.accepted = accepted;
        this.rejectionReason = rejectionReason == null ? null : rejectionReason;
        this.targetClusterIndex = targetClusterIndex == null ? null : targetClusterIndex;
        this.carriedClusterIndex = carriedClusterIndex == null ? null : carriedClusterIndex;
        this.shrink = shrink == null ? 0.0 : shrink;
        this.requiredShrink = requiredShrink == null ? 0.0 : requiredShrink;
        this.availableCapacity = availableCapacity == null ? 0.0 : availableCapacity;
    }
}
