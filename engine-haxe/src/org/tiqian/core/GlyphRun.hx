package org.tiqian.core;

import std.ReadOnlyArray;

@:dataClass
class GlyphRun {
    public final range:TextRange;
    public final fontKey:String;
    public final glyphs:ReadOnlyArray<Glyph>;
    public final advance:Float;
    public final openTypeFeatures:ReadOnlyArray<String>;

    public function new(range:TextRange, fontKey:String, glyphs:Array<Glyph>, advance:Float, ?openTypeFeatures:Array<String>) {
        this.range = range;
        this.fontKey = fontKey;
        this.glyphs = glyphs;
        this.advance = advance;
        this.openTypeFeatures = openTypeFeatures == null ? [] : openTypeFeatures;
    }
}
