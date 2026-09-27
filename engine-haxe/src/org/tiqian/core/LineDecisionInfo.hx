package org.tiqian.core;

import std.ReadOnlyArray;

@:dataClass
class LineDecisionInfo {
    public final range:TextRange;
    public final kind:String;
    public final repair:Null<String>;
    public final repairPenalty:Int;
    public final repairDecision:Null<LineRepairDecisionInfo>;
    public final repairCandidates:ReadOnlyArray<LineRepairCandidateInfo>;
    public final notes:ReadOnlyArray<String>;

    public function new(range:TextRange, kind:String, ?repair:Null<String>, ?repairPenalty:Null<Int>, ?repairDecision:Null<LineRepairDecisionInfo>,
            ?repairCandidates:Array<LineRepairCandidateInfo>, ?notes:Array<String>) {
        this.range = range;
        this.kind = kind;
        this.repair = repair == null ? null : repair;
        this.repairPenalty = repairPenalty == null ? 0 : repairPenalty;
        this.repairDecision = repairDecision == null ? null : repairDecision;
        this.repairCandidates = repairCandidates == null ? [] : repairCandidates;
        this.notes = notes == null ? [] : notes;
    }
}
