package org.tiqian.core;

@:dataClass
class InlineObjectSpan {
    public static final INLINE_OBJECT_REPLACEMENT_CHAR:String = "\uFFFC";

    public final range:TextRange;
    public final advance:Float;
    public final ascent:Float;
    public final descent:Float;
    public final leadingBoundary:InlineObjectBoundaryAdjustment;
    public final trailingBoundary:InlineObjectBoundaryAdjustment;

    public function new(range:TextRange, advance:Float, ascent:Float, descent:Float, ?leadingBoundary:Null<InlineObjectBoundaryAdjustment>,
            ?trailingBoundary:Null<InlineObjectBoundaryAdjustment>) {
        this.range = range;
        this.advance = advance;
        this.ascent = ascent;
        this.descent = descent;
        this.leadingBoundary = leadingBoundary == null ? InlineObjectBoundaryAdjustment.fixed() : leadingBoundary;
        this.trailingBoundary = trailingBoundary == null ? InlineObjectBoundaryAdjustment.fixed() : trailingBoundary;
    }
}
