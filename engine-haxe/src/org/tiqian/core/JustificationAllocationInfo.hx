package org.tiqian.core;

@:dataClass
class JustificationAllocationInfo {
    public final clusterRange:TextRange;
    public final kind:String;
    public final priority:Int;
    public final delta:Float;
    public final reason:String;

    public function new(clusterRange:TextRange, kind:String, priority:Int, delta:Float, reason:String) {
        this.clusterRange = clusterRange;
        this.kind = kind;
        this.priority = priority;
        this.delta = delta;
        this.reason = reason;
    }
}
