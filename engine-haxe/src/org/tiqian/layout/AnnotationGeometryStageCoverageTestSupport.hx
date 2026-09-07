package org.tiqian.layout;

import org.tiqian.core.Cluster;
import org.tiqian.core.Glyph;
import org.tiqian.core.GlyphRun;
import org.tiqian.core.Rect;
import org.tiqian.shaping.TextShaper.ExplainableStubTextShaper;
import org.tiqian.shaping.TextShaper.ITextShaper;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingResult;

class InkBoundsTextShaper implements ITextShaper {
    final delegate:ExplainableStubTextShaper;

    public function new(?delegate:ExplainableStubTextShaper) {
        this.delegate = delegate == null ? new ExplainableStubTextShaper() : delegate;
    }

    public function shape(input:ShapingInput):ShapingResult {
        final res = delegate.shape(input);
        final runs:Array<GlyphRun> = [];
        for (i in 0...res.glyphRuns.length) {
            final run = res.glyphRuns[i];
            final gs:Array<Glyph> = [];
            for (j in 0...run.glyphs.length) {
                final g = run.glyphs[j];
                gs.push(new Glyph(g.id, g.clusterRange, g.advance, g.x, g.y, g.renderFontKey, new Rect(1.0, 2.0, 9.0, 10.0), g.haltAdvance, g.haltPlacementX));
            }
            final features:Array<String> = [];
            for (k in 0...run.openTypeFeatures.length)
                features.push(run.openTypeFeatures[k]);
            runs.push(new GlyphRun(run.range, run.fontKey, gs, run.advance, features));
        }
        return new ShapingResult(res.clusters, runs, res.decisions);
    }
}

class MultiGlyphMinMaxShaper implements ITextShaper {
    final delegate:ExplainableStubTextShaper;

    public function new() {
        delegate = new ExplainableStubTextShaper();
    }

    public function shape(input:ShapingInput):ShapingResult {
        final res = delegate.shape(input);
        final runs:Array<GlyphRun> = [];
        for (i in 0...res.glyphRuns.length) {
            final run = res.glyphRuns[i];
            final g1 = new Glyph(1, input.range, 4.0, 0.0, null, null, new Rect(5.0, 5.0, 5.0, 5.0));
            final g2 = new Glyph(2, input.range, 4.0, 4.0, null, null, new Rect(0.0, 0.0, 10.0, 10.0));
            final g3 = new Glyph(3, input.range, 4.0, 8.0, null, null, new Rect(10.0, 10.0, 0.0, 0.0));
            runs.push(new GlyphRun(run.range, run.fontKey, [g1, g2, g3], run.advance, null));
        }
        return new ShapingResult(res.clusters, runs, res.decisions);
    }
}

class MultiGlyphBoundsShaper implements ITextShaper {
    public var callCount:Int;

    public function new() {
        callCount = 0;
    }

    public function shape(input:ShapingInput):ShapingResult {
        callCount += 1;
        final cluster = new Cluster(input.range, input.text.substring(input.range.start, input.range.end), "test", 16.0, input.displayText);
        final glyphs:Array<Glyph> = [];
        if (callCount % 2 == 0) {
            glyphs.push(new Glyph(1, input.range, 5.0, 0.0, null, null, new Rect(10.0, 10.0, 20.0, 20.0)));
            glyphs.push(new Glyph(2, input.range, 5.0, 5.0, null, null, new Rect(5.0, 5.0, 25.0, 25.0)));
            glyphs.push(new Glyph(3, input.range, 6.0, 10.0, null, null, new Rect(15.0, 15.0, 15.0, 15.0)));
        }
        return new ShapingResult([cluster], [new GlyphRun(input.range, "test", glyphs, 16.0)], null);
    }
}
