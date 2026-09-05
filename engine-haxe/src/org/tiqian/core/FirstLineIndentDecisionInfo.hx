package org.tiqian.core;

@:dataClass
class FirstLineIndentDecisionInfo {
    public final source:String;
    public final measureEm:Float;
    public final thresholdEm:Float;
    public final resolvedEm:Float;

    public function new(source:String, measureEm:Float, thresholdEm:Float, resolvedEm:Float) {
        this.source = source;
        this.measureEm = measureEm;
        this.thresholdEm = thresholdEm;
        this.resolvedEm = resolvedEm;
    }
}
