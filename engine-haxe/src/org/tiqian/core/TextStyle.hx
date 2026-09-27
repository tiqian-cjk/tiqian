package org.tiqian.core;

import std.ReadOnlyArray;

// Slant axis: italic/oblique typeface when the family offers one (ADR 0030 B 档).
// Per-span text color (ARGB) over a SOURCE range — rich-text 颜色 (ADR 0030 A 档).
@:dataClass
class TextStyle {
    public final fontFamilies:ReadOnlyArray<String>;
    public final fontSize:Float;
    public final locale:String;
    public final fontWeight:Int;
    public final italic:Bool;
    public final baselineShift:Float;
    public final inlineAttachment:InlineAttachment;

    public function new(?fontFamilies:Array<String>, ?fontSize:Null<Float>, ?locale:Null<String>, ?fontWeight:Null<Int>, ?italic:Null<Bool>,
            ?baselineShift:Null<Float>, ?inlineAttachment:Null<InlineAttachment>) {
        this.fontFamilies = fontFamilies == null ? [] : fontFamilies;
        this.fontSize = fontSize == null ? 16.0 : fontSize;
        this.locale = locale == null ? "zh-Hans" : locale;
        this.fontWeight = fontWeight == null ? 400 : fontWeight;
        this.italic = italic == null ? false : italic;
        this.baselineShift = baselineShift == null ? 0.0 : baselineShift;
        this.inlineAttachment = inlineAttachment == null ? InlineAttachment.None : inlineAttachment;
    }
}
