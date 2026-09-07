package org.tiqian.core;

@:dataClass
class LineLengthGridDecisionInfo {
    public final enabled:Bool;
    public final containerWidth:Float;
    public final fontSize:Float;
    public final cells:Int;
    public final measure:Float;
    public final slack:Float;
    public final bodyAlignment:String;
    public final bodyOffset:Float;
    public final reason:String;

    public function new(enabled:Bool, containerWidth:Float, fontSize:Float, cells:Int, measure:Float, slack:Float, bodyAlignment:String, bodyOffset:Float,
            reason:String) {
        this.enabled = enabled;
        this.containerWidth = containerWidth;
        this.fontSize = fontSize;
        this.cells = cells;
        this.measure = measure;
        this.slack = slack;
        this.bodyAlignment = bodyAlignment;
        this.bodyOffset = bodyOffset;
        this.reason = reason;
    }
}
