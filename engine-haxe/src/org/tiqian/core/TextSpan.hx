package org.tiqian.core;

@:dataClass
class TextSpan {
    public final range:TextRange;
    public final style:TextStyle;

    public function new(range:TextRange, style:TextStyle) {
        this.range = range;
        this.style = style;
    }
}
