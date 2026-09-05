package org.tiqian.core;

@:dataClass
class RichTextCornerRadii {
    public final topLeft:Float;
    public final topRight:Float;
    public final bottomRight:Float;
    public final bottomLeft:Float;

    public function new(topLeft:Float, topRight:Float, bottomRight:Float, bottomLeft:Float) {
        this.topLeft = topLeft;
        this.topRight = topRight;
        this.bottomRight = bottomRight;
        this.bottomLeft = bottomLeft;
    }

    public var isSquare(get, never):Bool;

    public function get_isSquare():Bool {
        return topLeft == 0.0 && topRight == 0.0 && bottomRight == 0.0 && bottomLeft == 0.0;
    }

    public var isUniform(get, never):Bool;

    public function get_isUniform():Bool {
        return topLeft == topRight && topRight == bottomRight && bottomRight == bottomLeft;
    }
}
