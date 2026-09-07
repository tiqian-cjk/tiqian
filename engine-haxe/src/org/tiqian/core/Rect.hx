package org.tiqian.core;

@:dataClass
class Rect {
    public final left:Float;
    public final top:Float;
    public final right:Float;
    public final bottom:Float;

    public function new(left:Float, top:Float, right:Float, bottom:Float) {
        this.left = left;
        this.top = top;
        this.right = right;
        this.bottom = bottom;
    }

    public var width(get, never):Float;

    public function get_width():Float {
        return right - left;
    }

    public var height(get, never):Float;

    public function get_height():Float {
        return bottom - top;
    }

    public function toString():String {
        return "Rect(left=" + left + ", top=" + top + ", right=" + right + ", bottom=" + bottom + ")";
    }
}
