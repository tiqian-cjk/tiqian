package org.tiqian.core;

import std.ReadOnlyArray;

@:dataClass
class PositionedCluster {
    public final lineIndex:Int;
    public final clusterIndex:Int;
    public final range:TextRange;
    public final left:Float;
    public final top:Float;
    public final right:Float;
    public final bottom:Float;
    public final baseline:Float;
    public final drawX:Float;
    public final sourceStops:Null<ReadOnlyArray<Float>>;

    public function new(lineIndex:Int, clusterIndex:Int, range:TextRange, left:Float, top:Float, right:Float, bottom:Float, baseline:Float, drawX:Float,
            sourceStops:Null<Array<Float>>) {
        this.lineIndex = lineIndex;
        this.clusterIndex = clusterIndex;
        this.range = range;
        this.left = left;
        this.top = top;
        this.right = right;
        this.bottom = bottom;
        this.baseline = baseline;
        this.drawX = drawX;
        this.sourceStops = sourceStops;
    }

    public var width(get, never):Float;

    public function get_width():Float {
        return right - left;
    }

    public var height(get, never):Float;

    public function get_height():Float {
        return bottom - top;
    }

    public var rect(get, never):Rect;

    public function get_rect():Rect {
        return new Rect(left, top, right, bottom);
    }
}
