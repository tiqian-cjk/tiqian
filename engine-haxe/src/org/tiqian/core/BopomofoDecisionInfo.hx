package org.tiqian.core;

import std.ReadOnlyArray;

@:dataClass
class BopomofoDecisionInfo {
    public final baseRange:TextRange;
    public final text:String;
    public final lineIndex:Int;
    public final placements:ReadOnlyArray<BopomofoGlyphPlacement>;
    public final fontFamilies:ReadOnlyArray<String>;
    public final fontWeight:Int;
    public final locale:String;

    public function new(baseRange:TextRange, text:String, lineIndex:Int, placements:Array<BopomofoGlyphPlacement>, ?fontFamilies:Array<String>,
            ?fontWeight:Null<Int>, ?locale:Null<String>) {
        this.baseRange = baseRange;
        this.text = text;
        this.lineIndex = lineIndex;
        this.placements = placements;
        this.fontFamilies = fontFamilies == null ? [] : fontFamilies;
        this.fontWeight = fontWeight == null ? 400 : fontWeight;
        this.locale = locale == null ? "zh-Hans" : locale;
    }
}
