package org.tiqian.core;

@:dataClass
class InlineObjectBoundaryAdjustment {
    public final participatesInUniformStretch:Bool;
    public final preferredStretch:Null<InlineObjectPreferredStretch>;
    public final shrinkCapacity:Float;
    public final lineEndDiscardableAdvance:Float;
    public final preventsLineBreak:Bool;

    public function new(?participatesInUniformStretch:Null<Bool>, ?preferredStretch:Null<InlineObjectPreferredStretch>, ?shrinkCapacity:Null<Float>,
            ?lineEndDiscardableAdvance:Null<Float>, ?preventsLineBreak:Null<Bool>) {
        this.participatesInUniformStretch = participatesInUniformStretch == null ? false : participatesInUniformStretch;
        this.preferredStretch = preferredStretch == null ? null : preferredStretch;
        this.shrinkCapacity = shrinkCapacity == null ? 0.0 : shrinkCapacity;
        this.lineEndDiscardableAdvance = lineEndDiscardableAdvance == null ? 0.0 : lineEndDiscardableAdvance;
        this.preventsLineBreak = preventsLineBreak == null ? false : preventsLineBreak;
        if (!isFinite(this.shrinkCapacity) || this.shrinkCapacity < 0.0) {
            throw new TiqianIllegalArgumentException(Message("Inline-object boundary shrink capacity must be finite and non-negative"));
        }
        if (!isFinite(this.lineEndDiscardableAdvance) || this.lineEndDiscardableAdvance < 0.0) {
            throw new TiqianIllegalArgumentException(Message("Inline-object line-end discardable advance must be finite and non-negative"));
        }
    }

    public static function fixed():InlineObjectBoundaryAdjustment {
        return new InlineObjectBoundaryAdjustment();
    }

    private static function isFinite(value:Float):Bool {
        return value == value && value != Math.POSITIVE_INFINITY && value != Math.NEGATIVE_INFINITY;
    }
}
