package org.tiqian.core;

import std.ReadOnlyArray;

@:dataClass
class RubyLineHeightDecisionInfo {
    public final mode:String;
    public final baseLineHeight:Float;
    public final baseFaceHeight:Float;
    public final rubyExtent:Float;
    public final availableInterlineSpace:Float;
    public final maxExtra:Float;
    public final lineExtras:ReadOnlyArray<Float>;
    public final expandedLineIndices:ReadOnlyArray<Int>;
    public final reason:String;

    public function new(mode:String, baseLineHeight:Float, baseFaceHeight:Float, rubyExtent:Float, availableInterlineSpace:Float, maxExtra:Float,
            lineExtras:Array<Float>, expandedLineIndices:Array<Int>, reason:String) {
        this.mode = mode;
        this.baseLineHeight = baseLineHeight;
        this.baseFaceHeight = baseFaceHeight;
        this.rubyExtent = rubyExtent;
        this.availableInterlineSpace = availableInterlineSpace;
        this.maxExtra = maxExtra;
        this.lineExtras = lineExtras;
        this.expandedLineIndices = expandedLineIndices;
        this.reason = reason;
    }
}
