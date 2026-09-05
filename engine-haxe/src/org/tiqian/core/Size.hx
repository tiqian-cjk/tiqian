package org.tiqian.core;

@:dataClass
class Size {
    public final width:Float;
    public final height:Float;

    public function new(width:Float, height:Float) {
        this.width = width;
        this.height = height;
    }
}
