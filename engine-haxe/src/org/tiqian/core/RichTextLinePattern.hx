package org.tiqian.core;

@:sealed
interface RichTextLinePattern {
    function toString():String;
}

class Solid implements RichTextLinePattern {
    public static final instance:Solid = new Solid();

    private function new() {}
}

@:dataClass
// Physical layout-unit dash geometry supplied by the frontend.
class Dashed implements RichTextLinePattern {
    public final strokeWidth:Float;
    public final dashLength:Float;
    public final gapLength:Float;

    public function new(strokeWidth:Float, dashLength:Float, gapLength:Float) {
        if (!isFinite(strokeWidth) || strokeWidth <= 0.0 || !isFinite(dashLength) || dashLength <= 0.0 || !isFinite(gapLength) || gapLength <= 0.0)
            throw new TiqianIllegalArgumentException(Message("Failed requirement."));
        this.strokeWidth = strokeWidth;
        this.dashLength = dashLength;
        this.gapLength = gapLength;
    }

    private static function isFinite(value:Float):Bool
        return value == value && value != Math.POSITIVE_INFINITY && value != Math.NEGATIVE_INFINITY;
}

@:dataClass
// Round dots with frontend-supplied diameter and visible edge-to-edge gap.
class Dotted implements RichTextLinePattern {
    public final dotDiameter:Float;
    public final gapLength:Float;

    public function new(dotDiameter:Float, gapLength:Float) {
        if (!isFinite(dotDiameter) || dotDiameter <= 0.0 || !isFinite(gapLength) || gapLength <= 0.0)
            throw new TiqianIllegalArgumentException(Message("Failed requirement."));
        this.dotDiameter = dotDiameter;
        this.gapLength = gapLength;
    }

    private static function isFinite(value:Float):Bool
        return value == value && value != Math.POSITIVE_INFINITY && value != Math.NEGATIVE_INFINITY;
}
