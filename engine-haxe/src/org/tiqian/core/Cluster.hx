package org.tiqian.core;

import std.ReadOnlyArray;

@:dataClass
class Cluster {
    public final range:TextRange;
    public final text:String;
    public final displayText:String;
    public final fontKey:String;
    public final advance:Float;
    public final baselineShift:Float;
    public final leadingLayoutAdvance:Float;
    public final glyphInlineShift:Float;

    public function new(range:TextRange, text:String, fontKey:String, advance:Float, ?displayText:Null<String>, ?baselineShift:Null<Float>,
            ?leadingLayoutAdvance:Null<Float>, ?glyphInlineShift:Null<Float>) {
        this.range = range;
        this.text = text;
        this.displayText = displayText == null ? text : displayText;
        this.fontKey = fontKey;
        this.advance = advance;
        this.baselineShift = baselineShift == null ? 0.0 : baselineShift;
        this.leadingLayoutAdvance = leadingLayoutAdvance == null ? 0.0 : leadingLayoutAdvance;
        this.glyphInlineShift = glyphInlineShift == null ? 0.0 : glyphInlineShift;
    }
}
