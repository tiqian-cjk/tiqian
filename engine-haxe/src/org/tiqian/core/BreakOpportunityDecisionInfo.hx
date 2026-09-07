package org.tiqian.core;

import std.ReadOnlyArray;

@:dataClass
class BreakOpportunityDecisionInfo {
    public final range:TextRange;
    public final sourceText:String;
    public final breakOffsets:ReadOnlyArray<Int>;
    public final reason:String;
    public final tier:Null<String>;

    public function new(range:TextRange, sourceText:String, breakOffsets:Array<Int>, reason:String, ?tier:Null<String>) {
        this.range = range;
        this.sourceText = sourceText;
        this.breakOffsets = breakOffsets;
        this.reason = reason;
        this.tier = tier == null ? null : tier;
    }
}
