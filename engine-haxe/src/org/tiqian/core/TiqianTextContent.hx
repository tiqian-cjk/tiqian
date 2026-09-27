package org.tiqian.core;

import std.ReadOnlyArray;

@:dataClass
class TiqianTextContent {
    public final text:String;
    public final spans:ReadOnlyArray<TextSpan>;
    public final sourceBoundaries:ReadOnlyArray<Int>;
    public final lineBreakSpans:ReadOnlyArray<LineBreakSpan>;
    public final autoSpaceSuppressedRanges:ReadOnlyArray<TextRange>;

    public function new(text:String, ?spans:Array<TextSpan>, ?sourceBoundaries:Array<Int>, ?lineBreakSpans:Array<LineBreakSpan>,
            ?autoSpaceSuppressedRanges:Array<TextRange>) {
        this.text = text;
        this.spans = spans == null ? [] : spans;
        this.sourceBoundaries = sourceBoundaries == null ? [] : sourceBoundaries;
        this.lineBreakSpans = lineBreakSpans == null ? [] : lineBreakSpans;
        this.autoSpaceSuppressedRanges = autoSpaceSuppressedRanges == null ? [] : autoSpaceSuppressedRanges;
    }
}
