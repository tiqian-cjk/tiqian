package org.tiqian.core;

/** Advance of one U+00A0 shaped with the font decision and style of a shaped segment range. */
@:dataClass
class SpacingCarrierAdvanceDecisionInfo {
    public final range:TextRange;
    public final fontKey:String;
    public final advance:Float;
    public final reason:String;

    public function new(range:TextRange, fontKey:String, advance:Float, ?reason:Null<String>) {
        this.range = range;
        this.fontKey = fontKey;
        this.advance = advance;
        this.reason = reason == null ? "SpacingCarrierNoBreakSpaceAdvance" : reason;
    }
}
