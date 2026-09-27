package org.tiqian.core;

@:dataClass
class AutoSpaceDecisionInfo {
    public final clusterRange:TextRange;
    public final side:String;
    public final boundaryRole:String;
    public final mode:String;
    public final charactersAffected:Int;
    public final reductionPerChar:Float;
    public final totalReduction:Float;
    public final reason:String;

    public function new(clusterRange:TextRange, side:String, boundaryRole:String, mode:String, charactersAffected:Int, reductionPerChar:Float,
            totalReduction:Float, reason:String) {
        this.clusterRange = clusterRange;
        this.side = side;
        this.boundaryRole = boundaryRole;
        this.mode = mode;
        this.charactersAffected = charactersAffected;
        this.reductionPerChar = reductionPerChar;
        this.totalReduction = totalReduction;
        this.reason = reason;
    }
}
