package org.tiqian.core;

@:dataClass
class ZeroWidthBreakDecisionInfo {
    public final range:TextRange;
    public final sourceText:String;
    public final clusterIndex:Int;
    public final reason:String;

    public function new(range:TextRange, sourceText:String, clusterIndex:Int, ?reason:Null<String>) {
        this.range = range;
        this.sourceText = sourceText;
        this.clusterIndex = clusterIndex;
        this.reason = reason == null ? "ZeroWidthSpaceSoftBreakNoShape" : reason;
    }
}
