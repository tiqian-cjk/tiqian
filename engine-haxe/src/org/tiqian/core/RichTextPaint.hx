package org.tiqian.core;

import org.tiqian.core.RichTextLinePattern.Solid;
import org.tiqian.core.RichTextLinePattern.Dashed;
import org.tiqian.core.RichTextLinePattern.Dotted;
import org.tiqian.core.RichTextBackgroundDrawStyle.Fill;

@:dataClass
class RichTextPaint {
    public final argb:Null<Int>;
    public final linePattern:RichTextLinePattern;
    public final background:RichTextBackgroundPaint;
    public final adjacentSameStyleClearance:Float;

    public function new(?argb:Null<Int>, ?linePattern:Null<RichTextLinePattern>, background:RichTextBackgroundPaint, ?adjacentSameStyleClearance:Null<Float>) {
        this.argb = argb == null ? null : argb;
        this.linePattern = linePattern == null ? Solid.instance : linePattern;
        this.background = background;
        this.adjacentSameStyleClearance = adjacentSameStyleClearance == null ? 0.0 : adjacentSameStyleClearance;
        if (!isFinite(this.adjacentSameStyleClearance) || this.adjacentSameStyleClearance < 0.0) {
            throw new TiqianIllegalArgumentException(Message("Failed requirement."));
        }
    }

    public static function withBackground(background:RichTextBackgroundPaint):RichTextPaint {
        return new RichTextPaint(null, Solid.instance, background, 0.0);
    }

    public static function withClearance(clearance:Float):RichTextPaint {
        return new RichTextPaint(null, Solid.instance,
            new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), clearance);
    }

    public static function withArgb(value:Int):RichTextPaint {
        return new RichTextPaint(value, Solid.instance,
            new RichTextBackgroundPaint(0.0, 0.0, 0.0, 0.0, RichTextBackgroundMetricPolicy.MarkedFaces, Fill.instance), 0.0);
    }

    public function sameVisibleStyle(other:RichTextPaint):Bool {
        final a = argb;
        final b = other.argb;
        if (a != b)
            return false;
        if (!sameLinePattern(linePattern, other.linePattern))
            return false;
        return RichTextBackgroundPaint.sameValues(background, other.background);
    }

    private static function sameLinePattern(a:RichTextLinePattern, b:RichTextLinePattern):Bool {
        if (Std.isOfType(a, Solid) || Std.isOfType(b, Solid)) {
            return Std.isOfType(a, Solid) && Std.isOfType(b, Solid) && Solid.instance == a && Solid.instance == b;
        }
        if (Std.isOfType(a, Dashed) && Std.isOfType(b, Dashed)) {
            final aa:Dashed = cast(a, Dashed);
            final bb:Dashed = cast(b, Dashed);
            return aa.strokeWidth == bb.strokeWidth && aa.dashLength == bb.dashLength && aa.gapLength == bb.gapLength;
        }
        if (Std.isOfType(a, Dotted) && Std.isOfType(b, Dotted)) {
            final aa:Dotted = cast(a, Dotted);
            final bb:Dotted = cast(b, Dotted);
            return aa.dotDiameter == bb.dotDiameter && aa.gapLength == bb.gapLength;
        }
        return false;
    }

    private static function isFinite(value:Float):Bool {
        return value == value && value != Math.POSITIVE_INFINITY && value != Math.NEGATIVE_INFINITY;
    }
}
