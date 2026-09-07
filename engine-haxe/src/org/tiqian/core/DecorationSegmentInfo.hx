package org.tiqian.core;

@:dataClass
class DecorationSegmentInfo {
    public final sourceRange:TextRange;
    public final kind:String;
    public final lineIndex:Int;
    public final left:Float;
    public final top:Float;
    public final right:Float;
    public final bottom:Float;
    public final openStart:Bool;
    public final openEnd:Bool;
    public final reason:String;

    public function new(sourceRange:TextRange, kind:String, lineIndex:Int, left:Float, top:Float, right:Float, bottom:Float, openStart:Bool, openEnd:Bool,
            reason:String) {
        this.sourceRange = sourceRange;
        this.kind = kind;
        this.lineIndex = lineIndex;
        this.left = left;
        this.top = top;
        this.right = right;
        this.bottom = bottom;
        this.openStart = openStart;
        this.openEnd = openEnd;
        this.reason = reason;
    }
}
