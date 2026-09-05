package org.tiqian.core;

@:dataClass
class DecorationSpan {
    public final range:TextRange;
    public final kind:DecorationKind;

    public function new(range:TextRange, kind:DecorationKind) {
        this.range = range;
        this.kind = kind;
    }
}
