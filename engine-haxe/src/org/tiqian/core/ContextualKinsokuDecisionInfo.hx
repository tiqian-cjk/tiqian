package org.tiqian.core;

@:dataClass
class ContextualKinsokuDecisionInfo {
    public final range:TextRange;
    public final sourceText:String;
    public final clusterIndex:Int;
    public final forbiddenPosition:String;
    public final reason:String;
    public final impossibleMeasureFallback:Null<String>;

    public function new(range:TextRange, sourceText:String, clusterIndex:Int, forbiddenPosition:String, reason:String,
            ?impossibleMeasureFallback:Null<String>) {
        this.range = range;
        this.sourceText = sourceText;
        this.clusterIndex = clusterIndex;
        this.forbiddenPosition = forbiddenPosition;
        this.reason = reason;
        this.impossibleMeasureFallback = impossibleMeasureFallback == null ? null : impossibleMeasureFallback;
    }
}
