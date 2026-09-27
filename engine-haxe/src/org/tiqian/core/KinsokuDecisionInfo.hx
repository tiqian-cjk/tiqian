package org.tiqian.core;

@:dataClass
class KinsokuDecisionInfo {
    public final measureEm:Float;
    public final level:String;
    public final hanging:String;
    public final reason:String;

    public function new(measureEm:Float, level:String, hanging:String, reason:String) {
        this.measureEm = measureEm;
        this.level = level;
        this.hanging = hanging;
        this.reason = reason;
    }
}
