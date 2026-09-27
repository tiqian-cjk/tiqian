package org.tiqian.core;

@:dataClass
class LineSpacingDecisionInfo {
    public final naturalHeight:Float;
    public final requestedLineHeight:Null<Float>;
    public final resolvedHeight:Float;
    public final spacingFloor:Float;
    public final floorApplied:Bool;
    public final reason:String;

    public function new(naturalHeight:Float, requestedLineHeight:Null<Float>, resolvedHeight:Float, spacingFloor:Float, floorApplied:Bool, reason:String) {
        this.naturalHeight = naturalHeight;
        this.requestedLineHeight = requestedLineHeight;
        this.resolvedHeight = resolvedHeight;
        this.spacingFloor = spacingFloor;
        this.floorApplied = floorApplied;
        this.reason = reason;
    }
}
