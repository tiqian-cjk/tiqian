package org.tiqian.core;

@:dataClass
class FontDecisionInfo {
    public final range:TextRange;
    public final sourceText:String;
    public final displayText:String;
    public final role:String;
    public final fontKey:String;
    public final reason:String;
    public final substitutionReason:String;

    public function new(range:TextRange, sourceText:String, displayText:String, role:String, fontKey:String, reason:String, substitutionReason:String) {
        this.range = range;
        this.sourceText = sourceText;
        this.displayText = displayText;
        this.role = role;
        this.fontKey = fontKey;
        this.reason = reason;
        this.substitutionReason = substitutionReason;
    }
}
