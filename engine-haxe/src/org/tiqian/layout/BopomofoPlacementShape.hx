package org.tiqian.layout;

import org.tiqian.core.Glyph;
import org.tiqian.core.Rect;

/**
 * `BopomofoPlacementShape`: the shaping of one bopomofo placement that
 * `AnnotationGeometryStage.computeBopomofoDecisions` reads: the font size the placement is
 * replayed at, its glyphs, its advance (the `AccurateSum` of the shaped cluster advances) and its
 * ink bounds (`bopomofoInkBounds`, null without ink).
 */
class BopomofoPlacementShape {
    public final replayFontSize:Float;
    public final glyphs:Array<Glyph>;
    public final advance:Float;
    public final ink:Null<Rect>;

    public function new(replayFontSize:Float, glyphs:Array<Glyph>, advance:Float, ink:Null<Rect>) {
        this.replayFontSize = replayFontSize;
        this.glyphs = glyphs;
        this.advance = advance;
        this.ink = ink;
    }
}
