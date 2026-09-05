package org.tiqian.core;

@:dataClass
class MeasureAdaptiveFirstLineIndent {
    public final shortBelowEm:Float;
    public final shortEm:Float;
    public final longEm:Float;

    public function new(?shortBelowEm:Null<Float>, ?shortEm:Null<Float>, ?longEm:Null<Float>) {
        this.shortBelowEm = shortBelowEm == null ? 14.0 : shortBelowEm;
        this.shortEm = shortEm == null ? 1.0 : shortEm;
        this.longEm = longEm == null ? 2.0 : longEm;
    }

    public function resolveEm(measureEm:Float):Float {
        return measureEm < shortBelowEm ? shortEm : longEm;
    }
}
