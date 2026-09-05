package org.tiqian.core;

@:dataClass
class InlineObjectDecisionInfo {
    public final range:TextRange;
    public final advance:Float;
    public final ascent:Float;
    public final descent:Float;
    public final clusterIndex:Int;
    public final lineIndex:Int;
    public final leadingUniformStretch:Bool;
    public final leadingPreferredStretchKind:Null<String>;
    public final leadingPreferredStretchNaturalWidth:Float;
    public final leadingPreferredStretchTargetWidth:Float;
    public final leadingPreferredStretchCapacity:Float;
    public final leadingPreventsLineBreak:Bool;
    public final leadingShrinkCapacity:Float;
    public final leadingLineEndDiscardableAdvance:Float;
    public final trailingUniformStretch:Bool;
    public final trailingPreferredStretchKind:Null<String>;
    public final trailingPreferredStretchNaturalWidth:Float;
    public final trailingPreferredStretchTargetWidth:Float;
    public final trailingPreferredStretchCapacity:Float;
    public final trailingPreventsLineBreak:Bool;
    public final trailingShrinkCapacity:Float;
    public final trailingLineEndDiscardableAdvance:Float;
    public final reason:String;

    public function new(range:TextRange, advance:Float, ascent:Float, descent:Float, clusterIndex:Int, lineIndex:Int, ?leadingUniformStretch:Null<Bool>,
            ?leadingPreferredStretchKind:Null<String>, ?leadingPreferredStretchNaturalWidth:Null<Float>, ?leadingPreferredStretchTargetWidth:Null<Float>,
            ?leadingPreferredStretchCapacity:Null<Float>, ?leadingPreventsLineBreak:Null<Bool>, ?leadingShrinkCapacity:Null<Float>,
            ?leadingLineEndDiscardableAdvance:Null<Float>, ?trailingUniformStretch:Null<Bool>, ?trailingPreferredStretchKind:Null<String>,
            ?trailingPreferredStretchNaturalWidth:Null<Float>, ?trailingPreferredStretchTargetWidth:Null<Float>,
            ?trailingPreferredStretchCapacity:Null<Float>, ?trailingPreventsLineBreak:Null<Bool>, ?trailingShrinkCapacity:Null<Float>,
            ?trailingLineEndDiscardableAdvance:Null<Float>, ?reason:Null<String>) {
        this.range = range;
        this.advance = advance;
        this.ascent = ascent;
        this.descent = descent;
        this.clusterIndex = clusterIndex;
        this.lineIndex = lineIndex;
        this.leadingUniformStretch = leadingUniformStretch == null ? false : leadingUniformStretch;
        this.leadingPreferredStretchKind = leadingPreferredStretchKind == null ? null : leadingPreferredStretchKind;
        this.leadingPreferredStretchNaturalWidth = leadingPreferredStretchNaturalWidth == null ? 0.0 : leadingPreferredStretchNaturalWidth;
        this.leadingPreferredStretchTargetWidth = leadingPreferredStretchTargetWidth == null ? 0.0 : leadingPreferredStretchTargetWidth;
        this.leadingPreferredStretchCapacity = leadingPreferredStretchCapacity == null ? 0.0 : leadingPreferredStretchCapacity;
        this.leadingPreventsLineBreak = leadingPreventsLineBreak == null ? false : leadingPreventsLineBreak;
        this.leadingShrinkCapacity = leadingShrinkCapacity == null ? 0.0 : leadingShrinkCapacity;
        this.leadingLineEndDiscardableAdvance = leadingLineEndDiscardableAdvance == null ? 0.0 : leadingLineEndDiscardableAdvance;
        this.trailingUniformStretch = trailingUniformStretch == null ? false : trailingUniformStretch;
        this.trailingPreferredStretchKind = trailingPreferredStretchKind == null ? null : trailingPreferredStretchKind;
        this.trailingPreferredStretchNaturalWidth = trailingPreferredStretchNaturalWidth == null ? 0.0 : trailingPreferredStretchNaturalWidth;
        this.trailingPreferredStretchTargetWidth = trailingPreferredStretchTargetWidth == null ? 0.0 : trailingPreferredStretchTargetWidth;
        this.trailingPreferredStretchCapacity = trailingPreferredStretchCapacity == null ? 0.0 : trailingPreferredStretchCapacity;
        this.trailingPreventsLineBreak = trailingPreventsLineBreak == null ? false : trailingPreventsLineBreak;
        this.trailingShrinkCapacity = trailingShrinkCapacity == null ? 0.0 : trailingShrinkCapacity;
        this.trailingLineEndDiscardableAdvance = trailingLineEndDiscardableAdvance == null ? 0.0 : trailingLineEndDiscardableAdvance;
        this.reason = reason == null ? "MeasurableOpaqueInlineObject" : reason;
    }
}
