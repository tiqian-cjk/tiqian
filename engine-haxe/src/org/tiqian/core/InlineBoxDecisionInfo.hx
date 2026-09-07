package org.tiqian.core;

@:dataClass
class InlineBoxDecisionInfo {
    public final range:TextRange;
    public final inlineStart:Float;
    public final inlineEnd:Float;
    public final outerSpacing:String;
    public final firstClusterIndex:Int;
    public final lastClusterIndex:Int;
    public final reason:String;

    public function new(range:TextRange, inlineStart:Float, inlineEnd:Float, outerSpacing:String, firstClusterIndex:Int, lastClusterIndex:Int,
            ?reason:Null<String>) {
        this.range = range;
        this.inlineStart = inlineStart;
        this.inlineEnd = inlineEnd;
        this.outerSpacing = outerSpacing;
        this.firstClusterIndex = firstClusterIndex;
        this.lastClusterIndex = lastClusterIndex;
        this.reason = reason == null ? "InlineBoxBoundaryAdvance" : reason;
    }
}
