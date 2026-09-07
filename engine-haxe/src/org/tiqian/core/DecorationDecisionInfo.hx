package org.tiqian.core;

@:dataClass
class DecorationDecisionInfo {
    public final clusterRange:TextRange;
    public final sourceText:String;
    public final kind:String;
    public final applied:Bool;
    public final reason:String;
    public final anchorX:Float;
    public final anchorY:Float;
    public final dotDiameter:Float;

    public function new(clusterRange:TextRange, sourceText:String, kind:String, applied:Bool, reason:String, ?anchorX:Null<Float>, ?anchorY:Null<Float>,
            ?dotDiameter:Null<Float>) {
        this.clusterRange = clusterRange;
        this.sourceText = sourceText;
        this.kind = kind;
        this.applied = applied;
        this.reason = reason;
        this.anchorX = anchorX == null ? 0.0 : anchorX;
        this.anchorY = anchorY == null ? 0.0 : anchorY;
        this.dotDiameter = dotDiameter == null ? 0.0 : dotDiameter;
    }
}
