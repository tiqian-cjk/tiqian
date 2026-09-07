package org.tiqian.core;

@:dataClass
class MandatoryBreakDecisionInfo {
    public final range:TextRange;
    public final sourceText:String;
    public final breakAfterClusterIndex:Int;
    public final reason:String;

    public function new(range:TextRange, sourceText:String, breakAfterClusterIndex:Int, reason:String) {
        this.range = range;
        this.sourceText = sourceText;
        this.breakAfterClusterIndex = breakAfterClusterIndex;
        this.reason = reason;
    }
}
