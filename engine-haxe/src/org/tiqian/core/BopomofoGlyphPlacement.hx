package org.tiqian.core;

import std.ReadOnlyArray;

@:dataClass
class BopomofoGlyphPlacement {
    public final text:String;
    public final left:Float;
    public final top:Float;
    public final width:Float;
    public final height:Float;
    public final role:BopomofoGlyphRole;
    public final glyphs:ReadOnlyArray<Glyph>;
    public final drawX:Float;
    public final baselineY:Float;
    public final fontSize:Float;

    // Kotlin declares drawX: Float = left, baselineY: Float = top + height
    // and fontSize: Float = height, parameter-reading defaults (boring gap 4).
    // The three parameters stay mandatory until that lowering lands.
    public function new(text:String, left:Float, top:Float, width:Float, height:Float, role:BopomofoGlyphRole, ?glyphs:Array<Glyph>, drawX:Float,
            baselineY:Float, fontSize:Float) {
        this.text = text;
        this.left = left;
        this.top = top;
        this.width = width;
        this.height = height;
        this.role = role;
        this.glyphs = glyphs == null ? [] : glyphs;
        this.drawX = drawX;
        this.baselineY = baselineY;
        this.fontSize = fontSize;
    }
}
