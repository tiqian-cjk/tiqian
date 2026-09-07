package org.tiqian.core;

@:dataClass
class LineEdgeTrimDecisionInfo {
    public final lineRange:TextRange;
    public final clusterRange:TextRange;
    public final side:String;
    public final trimAmount:Float;
    public final consumedBefore:Float;
    public final naturalGlue:Float;
    public final reason:String;

    public function new(lineRange:TextRange, clusterRange:TextRange, side:String, trimAmount:Float, consumedBefore:Float, naturalGlue:Float, reason:String) {
        this.lineRange = lineRange;
        this.clusterRange = clusterRange;
        this.side = side;
        this.trimAmount = trimAmount;
        this.consumedBefore = consumedBefore;
        this.naturalGlue = naturalGlue;
        this.reason = reason;
    }
}
