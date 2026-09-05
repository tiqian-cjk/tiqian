package org.tiqian.core;

@:dataClass
class SpacingDecisionInfo {
    public final range:TextRange;
    public final leftChar:String;
    public final rightChar:String;
    public final naturalInnerGlue:Float;
    public final adjustedInnerGlue:Float;
    public final reduction:Float;
    public final reductionTargetRange:TextRange;
    public final reason:String;

    public function new(range:TextRange, leftChar:String, rightChar:String, naturalInnerGlue:Float, adjustedInnerGlue:Float, reduction:Float,
            reductionTargetRange:TextRange, reason:String) {
        this.range = range;
        this.leftChar = leftChar;
        this.rightChar = rightChar;
        this.naturalInnerGlue = naturalInnerGlue;
        this.adjustedInnerGlue = adjustedInnerGlue;
        this.reduction = reduction;
        this.reductionTargetRange = reductionTargetRange;
        this.reason = reason;
    }
}
