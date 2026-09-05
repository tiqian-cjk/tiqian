package org.tiqian.core;

@:dataClass
class InlineBoxSpan {
    public final range:TextRange;
    public final inlineStart:Float;
    public final inlineEnd:Float;
    public final outerSpacing:InlineBoxOuterSpacing;

    public function new(range:TextRange, ?inlineStart:Null<Float>, ?inlineEnd:Null<Float>, ?outerSpacing:Null<InlineBoxOuterSpacing>) {
        this.range = range;
        this.inlineStart = inlineStart == null ? 0.0 : inlineStart;
        this.inlineEnd = inlineEnd == null ? 0.0 : inlineEnd;
        this.outerSpacing = outerSpacing == null ? InlineBoxOuterSpacing.Narrow : outerSpacing;
    }
}
