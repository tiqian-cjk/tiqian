package org.tiqian.core;

import org.tiqian.core.RichTextBackgroundDrawStyle.Fill;
import org.tiqian.core.RichTextBackgroundDrawStyle.Border;

@:dataClass
class RichTextBackgroundPaint {
    public final horizontalPadding:Float;
    public final verticalPadding:Float;
    public final cornerRadius:Float;
    public final continuationCornerRadius:Float;
    public final metricPolicy:RichTextBackgroundMetricPolicy;
    public final drawStyle:RichTextBackgroundDrawStyle;

    public function new(?horizontalPadding:Null<Float>, ?verticalPadding:Null<Float>, ?cornerRadius:Null<Float>, ?continuationCornerRadius:Null<Float>,
            ?metricPolicy:Null<RichTextBackgroundMetricPolicy>, ?drawStyle:Null<RichTextBackgroundDrawStyle>) {
        this.horizontalPadding = horizontalPadding == null ? 0.0 : horizontalPadding;
        this.verticalPadding = verticalPadding == null ? 0.0 : verticalPadding;
        this.cornerRadius = cornerRadius == null ? 0.0 : cornerRadius;
        this.continuationCornerRadius = continuationCornerRadius == null ? cornerRadius : continuationCornerRadius;
        this.metricPolicy = metricPolicy == null ? RichTextBackgroundMetricPolicy.MarkedFaces : metricPolicy;
        this.drawStyle = drawStyle == null ? Fill.instance : drawStyle;
        if (!isFinite(this.horizontalPadding)
            || this.horizontalPadding < 0.0
            || !isFinite(this.verticalPadding)
            || this.verticalPadding < 0.0
            || !isFinite(this.cornerRadius)
            || this.cornerRadius < 0.0
            || !isFinite(this.continuationCornerRadius)
            || this.continuationCornerRadius < 0.0) {
            throw new TiqianIllegalArgumentException(Message("Failed requirement."));
        }
    }

    public static function withHorizontalPadding(value:Float):RichTextBackgroundPaint {
        return new RichTextBackgroundPaint(value, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance);
    }

    public static function withMetricPolicy(value:RichTextBackgroundMetricPolicy):RichTextBackgroundPaint {
        return new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, value, Fill.instance);
    }

    public static function withCornerRadius(corner:Float, continuation:Null<Float>):RichTextBackgroundPaint {
        return new RichTextBackgroundPaint(0.0, 0.0, corner, continuation, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance);
    }

    @:allow(org.tiqian.core.RichTextPaint)
    private static function sameValues(a:RichTextBackgroundPaint, b:RichTextBackgroundPaint):Bool {
        return a.horizontalPadding == b.horizontalPadding
            && a.verticalPadding == b.verticalPadding
            && a.cornerRadius == b.cornerRadius
            && a.continuationCornerRadius == b.continuationCornerRadius
            && a.metricPolicy == b.metricPolicy
            && sameDrawStyle(a.drawStyle, b.drawStyle);
    }

    private static function sameDrawStyle(a:RichTextBackgroundDrawStyle, b:RichTextBackgroundDrawStyle):Bool {
        if (Std.isOfType(a, Fill) || Std.isOfType(b, Fill)) {
            return Std.isOfType(a, Fill) && Std.isOfType(b, Fill) && Fill.instance == a && Fill.instance == b;
        }
        if (Std.isOfType(a, Border) && Std.isOfType(b, Border)) {
            return (cast(a, Border)).strokeWidth == (cast(b, Border)).strokeWidth;
        }
        return false;
    }

    private static function isFinite(value:Float):Bool {
        return value == value && value != Math.POSITIVE_INFINITY && value != Math.NEGATIVE_INFINITY;
    }
}
