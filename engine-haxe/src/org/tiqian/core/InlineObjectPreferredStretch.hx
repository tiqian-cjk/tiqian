package org.tiqian.core;

@:dataClass
class InlineObjectPreferredStretch {
    public final kind:InlineObjectPreferredStretchKind;
    public final naturalWidth:Float;
    public final targetWidth:Float;

    public function new(kind:InlineObjectPreferredStretchKind, naturalWidth:Float, targetWidth:Float) {
        if (!isFinite(naturalWidth) || naturalWidth < 0.0) {
            throw new TiqianIllegalArgumentException(Message("Inline-object preferred stretch natural width must be finite and non-negative"));
        }
        if (!isFinite(targetWidth) || targetWidth <= naturalWidth) {
            throw new TiqianIllegalArgumentException(Message("Inline-object preferred stretch target must be finite and exceed its natural width"));
        }
        this.kind = kind;
        this.naturalWidth = naturalWidth;
        this.targetWidth = targetWidth;
    }

    public var capacity(get, never):Float;

    public function get_capacity():Float {
        return targetWidth - naturalWidth;
    }

    private static function isFinite(value:Float):Bool {
        return value == value && value != Math.POSITIVE_INFINITY && value != Math.NEGATIVE_INFINITY;
    }
}
