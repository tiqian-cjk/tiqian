package org.tiqian.font;

@:dataClass class RawFontMetrics {
    public final ascent:Float;
    public final descent:Float;
    public final leading:Float;
    public final source:FontMetricSource;
    public final typoAscent:Null<Float>;
    public final typoDescent:Null<Float>;

    public function new(ascent:Float, descent:Float, ?leading:Null<Float>, ?source:Null<FontMetricSource>, ?typoAscent:Null<Float>, ?typoDescent:Null<Float>) {
        this.ascent = ascent;
        this.descent = descent;
        this.leading = leading == null ? 0 : leading;
        this.source = source == null ? FontMetricSource.RawTables : source;
        this.typoAscent = typoAscent;
        this.typoDescent = typoDescent;
    }
}
