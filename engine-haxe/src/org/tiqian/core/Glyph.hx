package org.tiqian.core;

@:dataClass
class Glyph {
    public final id:Int;
    public final clusterRange:TextRange;
    public final advance:Float;
    public final x:Float;
    public final y:Float;
    public final renderFontKey:Null<String>;
    public final bounds:Null<Rect>;
    public final haltAdvance:Null<Float>;
    public final haltPlacementX:Null<Float>;

    public function new(id:Int, clusterRange:TextRange, advance:Float, ?x:Null<Float>, ?y:Null<Float>, ?renderFontKey:Null<String>, ?bounds:Null<Rect>,
            ?haltAdvance:Null<Float>, ?haltPlacementX:Null<Float>) {
        this.id = id;
        this.clusterRange = clusterRange;
        this.advance = advance;
        this.x = x == null ? 0.0 : x;
        this.y = y == null ? 0.0 : y;
        this.renderFontKey = renderFontKey == null ? null : renderFontKey;
        this.bounds = bounds == null ? null : bounds;
        this.haltAdvance = haltAdvance == null ? null : haltAdvance;
        this.haltPlacementX = haltPlacementX == null ? null : haltPlacementX;
    }
}
