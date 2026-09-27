package org.tiqian.core;

// Per-line rectangle segment of a box-style decoration (示亡号, ADR 0018).
// Vertical bounds hug the CJK character face (字面) on the real baseline —
// `openStart`/`openEnd` mark segments that continue from/onto another line —
// 着重号 dot diameter (px), for the renderer to draw a filled circle of the
@:dataClass
class RichTextLineSegment {
    public final span:RichTextSpan;
    public final lineIndex:Int;
    public final range:TextRange;
    public final left:Float;
    public final top:Float;
    public final right:Float;
    public final bottom:Float;
    public final baseline:Float;

    public function new(span:RichTextSpan, lineIndex:Int, range:TextRange, left:Float, top:Float, right:Float, bottom:Float, baseline:Float) {
        this.span = span;
        this.lineIndex = lineIndex;
        this.range = range;
        this.left = left;
        this.top = top;
        this.right = right;
        this.bottom = bottom;
        this.baseline = baseline;
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

    public var continuesFromPreviousLine(get, never):Bool;

    public function get_continuesFromPreviousLine():Bool {
        return range.start > span.range.start;
    }

    public var continuesOnNextLine(get, never):Bool;

    public function get_continuesOnNextLine():Bool {
        return range.end < span.range.end;
    }
}
