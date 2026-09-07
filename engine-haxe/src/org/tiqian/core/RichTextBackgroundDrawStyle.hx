package org.tiqian.core;

@:sealed
interface RichTextBackgroundDrawStyle {
    function toString():String;
}

class Fill implements RichTextBackgroundDrawStyle {
    public static final instance:Fill = new Fill();

    private function new() {}
}

@:dataClass
// Physical layout-unit stroke kept inside the resolved box by the frontend.
class Border implements RichTextBackgroundDrawStyle {
    public final strokeWidth:Float;

    public function new(strokeWidth:Float) {
        if (!isFinite(strokeWidth) || strokeWidth <= 0.0) {
            throw new TiqianIllegalArgumentException(Message("Failed requirement."));
        }
        this.strokeWidth = strokeWidth;
    }

    private static function isFinite(value:Float):Bool {
        return value == value && value != Math.POSITIVE_INFINITY && value != Math.NEGATIVE_INFINITY;
    }
}
