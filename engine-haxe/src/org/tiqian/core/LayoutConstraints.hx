package org.tiqian.core;

@:dataClass
class LayoutConstraints {
    public final maxWidth:Float;
    public final maxHeight:Float;
    public final maxLines:Int;

    public function new(maxWidth:Float, ?maxHeight:Null<Float>, ?maxLines:Null<Int>) {
        this.maxWidth = maxWidth;
        this.maxHeight = maxHeight == null ? Math.POSITIVE_INFINITY : maxHeight;
        this.maxLines = maxLines == null ? 2147483647 : maxLines;
        if (!(this.maxWidth > 0.0)) {
            throw new TiqianIllegalArgumentException(Message("maxWidth must be positive."));
        }
        if (!(this.maxHeight > 0.0)) {
            throw new TiqianIllegalArgumentException(Message("maxHeight must be positive."));
        }
        if (this.maxLines <= 0) {
            throw new TiqianIllegalArgumentException(Message("maxLines must be positive."));
        }
    }
}
