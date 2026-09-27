package org.tiqian.core;

@:dataClass
class MaxLinesDecisionInfo {
    public final laidOutLines:Int;
    public final visibleLines:Int;
    public final reason:String;

    public function new(laidOutLines:Int, visibleLines:Int, ?reason:Null<String>) {
        this.laidOutLines = laidOutLines;
        this.visibleLines = visibleLines;
        this.reason = reason == null ? "MaxLinesLineTruncation" : reason;
    }
}
