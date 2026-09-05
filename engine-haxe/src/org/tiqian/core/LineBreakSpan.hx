package org.tiqian.core;

@:dataClass
class LineBreakSpan {
    public final range:TextRange;
    public final policy:LineBreakPolicy;

    public function new(range:TextRange, policy:LineBreakPolicy) {
        this.range = range;
        this.policy = policy;
    }
}
