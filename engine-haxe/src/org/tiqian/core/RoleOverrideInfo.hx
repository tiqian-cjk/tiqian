package org.tiqian.core;

@:dataClass
class RoleOverrideInfo {
    public final range:TextRange;
    public final sourceText:String;
    public final originalRole:String;
    public final overriddenRole:String;
    public final source:String;
    public final reason:String;

    public function new(range:TextRange, sourceText:String, originalRole:String, overriddenRole:String, source:String, reason:String) {
        this.range = range;
        this.sourceText = sourceText;
        this.originalRole = originalRole;
        this.overriddenRole = overriddenRole;
        this.source = source;
        this.reason = reason;
    }
}
