package org.tiqian.core;

import std.ReadOnlyArray;

@:dataClass
class LineBox {
    public final range:TextRange;
    public final clusterRange:IntRange;
    public final baseline:Float;
    public final top:Float;
    public final bottom:Float;
    public final naturalWidth:Float;
    public final adjustedWidth:Float;
    public final visualWidth:Float;
    public final hangingPunctuationAdvance:Float;
    public final indent:Float;
    public final endReason:LineEndReason;
    public final hyphenAdvance:Float;
    public final hyphenGlyphs:ReadOnlyArray<Glyph>;
    public final debug:LineDebugInfo;

    public function new(range:TextRange, clusterRange:IntRange, baseline:Float, top:Float, bottom:Float, naturalWidth:Float, adjustedWidth:Float,
            visualWidth:Float, ?hangingPunctuationAdvance:Null<Float>, ?indent:Null<Float>, ?endReason:Null<LineEndReason>, ?hyphenAdvance:Null<Float>,
            ?hyphenGlyphs:Array<Glyph>, // Kotlin declares debug: LineDebugInfo = LineDebugInfo(), a
            // constructor-call default outside the sanctioned coalescing grammar.
        // The parameter stays mandatory; callers pass LineDebugInfo defaults.
        debug:LineDebugInfo) {
        this.range = range;
        this.clusterRange = clusterRange;
        this.baseline = baseline;
        this.top = top;
        this.bottom = bottom;
        this.naturalWidth = naturalWidth;
        this.adjustedWidth = adjustedWidth;
        this.visualWidth = visualWidth;
        this.hangingPunctuationAdvance = hangingPunctuationAdvance == null ? 0.0 : hangingPunctuationAdvance;
        this.indent = indent == null ? 0.0 : indent;
        this.endReason = endReason == null ? LineEndReason.ParagraphEnd : endReason;
        this.hyphenAdvance = hyphenAdvance == null ? 0.0 : hyphenAdvance;
        this.hyphenGlyphs = hyphenGlyphs == null ? [] : hyphenGlyphs;
        this.debug = debug;
    }
}
