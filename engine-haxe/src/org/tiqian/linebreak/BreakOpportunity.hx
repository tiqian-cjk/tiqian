package org.tiqian.linebreak;

import org.tiqian.core.TextRange;

@:dataClass
class BreakOpportunity {
    public final index:Int;
    public final kind:BreakKind;
    public final penalty:Int;
    public final reason:String;

    public function new(index:Int, kind:BreakKind, reason:String, ?penalty:Null<Int>) {
        this.index = index;
        this.kind = kind;
        this.penalty = penalty == null ? 0 : penalty;
        this.reason = reason;
    }
}

@:dataClass
class ForbiddenBreak {
    public final range:TextRange;
    public final reason:String;

    public function new(range:TextRange, reason:String) {
        this.range = range;
        this.reason = reason;
    }
}
