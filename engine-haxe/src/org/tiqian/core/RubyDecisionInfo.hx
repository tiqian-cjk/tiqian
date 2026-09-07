package org.tiqian.core;

import std.ReadOnlyArray;

@:dataClass
class RubyDecisionInfo {
    public final baseRange:TextRange;
    public final text:String;
    public final lineIndex:Int;
    public final centerX:Float;
    public final baselineY:Float;
    public final fontSize:Float;
    public final overhang:Float;
    public final ascent:Float;
    public final descent:Float;
    public final width:Float;
    public final fontFamilies:ReadOnlyArray<String>;
    public final fontWeight:Int;
    public final locale:String;
    public final glyphs:ReadOnlyArray<Glyph>;

    public function new(baseRange:TextRange, text:String, lineIndex:Int, centerX:Float, baselineY:Float, fontSize:Float, overhang:Float, ?ascent:Null<Float>,
            ?descent:Null<Float>, ?width:Null<Float>, ?fontFamilies:Array<String>, ?fontWeight:Null<Int>, ?locale:Null<String>, ?glyphs:Array<Glyph>) {
        this.baseRange = baseRange;
        this.text = text;
        this.lineIndex = lineIndex;
        this.centerX = centerX;
        this.baselineY = baselineY;
        this.fontSize = fontSize;
        this.overhang = overhang;
        this.ascent = ascent == null ? 0.0 : ascent;
        this.descent = descent == null ? 0.0 : descent;
        this.width = width == null ? 0.0 : width;
        this.fontFamilies = fontFamilies == null ? [] : fontFamilies;
        this.fontWeight = fontWeight == null ? 400 : fontWeight;
        this.locale = locale == null ? "zh-Hans" : locale;
        this.glyphs = glyphs == null ? [] : glyphs;
    }
}
