package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.shaping.TextShaper.ITextShaper;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.shaping.TextShaper.ExplainableStubTextShaper;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;

class R3GeometryTailCoverageTestSupport {
    public static function layout(text:String, ?maxWidth:Float, ?maxLines:Int, ?spans:Array<TextSpan>, ?rubySpans:Array<RubySpan>,
            ?shaper:ITextShaper):LayoutResult {
        final width = maxWidth == null ? 320.0 : maxWidth;
        final lines = maxLines == null ? 2147483647 : maxLines;
        final ss = spans == null ? [] : spans;
        final rr = rubySpans == null ? [] : rubySpans;
        final engine = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, shaper);
        return engine.layout(new LayoutInput(new TiqianTextContent(text, ss), null, null, new LayoutConstraints(width, null, lines), null, null, rr));
    }

    public static function centeredInkShaper():ITextShaper
        return new CenteredInkShaper();
}

class CenteredInkShaper implements ITextShaper {
    public function new() {}

    public function shape(input:ShapingInput):ShapingResult {
        final res = new ExplainableStubTextShaper().shape(input);
        final runs:Array<GlyphRun> = [];
        for (i in 0...res.glyphRuns.length) {
            final run = res.glyphRuns[i];
            final glyphs:Array<Glyph> = [];
            for (j in 0...run.glyphs.length) {
                final g = run.glyphs[j];
                glyphs.push(new Glyph(g.id, g.clusterRange, g.advance, g.x, g.y, g.renderFontKey, new Rect(4.0, 2.0, 12.0, 10.0), g.haltAdvance,
                    g.haltPlacementX));
            }
            runs.push(new GlyphRun(run.range, run.fontKey, glyphs, run.advance, null));
        }
        return new ShapingResult(res.clusters, runs, res.decisions);
    }
}
