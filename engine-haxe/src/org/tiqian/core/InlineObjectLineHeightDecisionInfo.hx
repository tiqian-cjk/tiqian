package org.tiqian.core;

import std.ReadOnlyArray;

@:dataClass
class InlineObjectLineHeightDecisionInfo {
    public final baseLineHeight:Float;
    public final baseFaceAscent:Float;
    public final baseFaceDescent:Float;
    public final availableInterlineSpace:Float;
    public final minimumClearance:Float;
    public final lineAscents:ReadOnlyArray<Float>;
    public final lineDescents:ReadOnlyArray<Float>;
    public final lineExtras:ReadOnlyArray<Float>;
    public final boundaryShiftsAfter:ReadOnlyArray<Float>;
    public final trailingExtra:Float;
    public final expandedLineIndices:ReadOnlyArray<Int>;
    public final reason:String;

    public function new(baseLineHeight:Float, baseFaceAscent:Float, baseFaceDescent:Float, availableInterlineSpace:Float, minimumClearance:Float,
            lineAscents:Array<Float>, lineDescents:Array<Float>, lineExtras:Array<Float>, boundaryShiftsAfter:Array<Float>, trailingExtra:Float,
            expandedLineIndices:Array<Int>, reason:String) {
        this.baseLineHeight = baseLineHeight;
        this.baseFaceAscent = baseFaceAscent;
        this.baseFaceDescent = baseFaceDescent;
        this.availableInterlineSpace = availableInterlineSpace;
        this.minimumClearance = minimumClearance;
        this.lineAscents = lineAscents;
        this.lineDescents = lineDescents;
        this.lineExtras = lineExtras;
        this.boundaryShiftsAfter = boundaryShiftsAfter;
        this.trailingExtra = trailingExtra;
        this.expandedLineIndices = expandedLineIndices;
        this.reason = reason;
    }
}
