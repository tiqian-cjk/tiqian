package org.tiqian.core;

@:dataClass
class EmergencyTrackingEligibilityDecisionInfo {
    public final range:TextRange;
    public final sourceText:String;
    public final reason:String;

    public function new(range:TextRange, sourceText:String, reason:String) {
        this.range = range;
        this.sourceText = sourceText;
        this.reason = reason;
    }
}
