package org.tiqian.core;

import std.ReadOnlyArray;

@:dataClass
class JustificationDecisionInfo {
    public final lineRange:TextRange;
    public final deficitBefore:Float;
    public final deficitAfter:Float;
    public final allocations:ReadOnlyArray<JustificationAllocationInfo>;

    public function new(lineRange:TextRange, deficitBefore:Float, deficitAfter:Float, allocations:Array<JustificationAllocationInfo>) {
        this.lineRange = lineRange;
        this.deficitBefore = deficitBefore;
        this.deficitAfter = deficitAfter;
        this.allocations = allocations;
    }
}
