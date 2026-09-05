package org.tiqian.layout;

import org.tiqian.clreq.*;
import org.tiqian.core.*;
import org.tiqian.shaping.TextShaper.ITextShaper;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.shaping.TextShaper.ExplainableStubTextShaper;
import org.tiqian.shaping.TextShaper;
import org.tiqian.linebreak.EnglishHyphenation;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;

class LineAdjustmentStageJfTestSupport {
    public static function resolver(p:ClreqProfile):ClreqProfileResolver
        return new FixedClreqResolver(p);

    public static function engine(?shaper:ITextShaper, hyphenate:Bool, p:Null<ClreqProfile>):ExplainableStubParagraphLayoutEngine {
        final r = p == null ? null : resolver(p);
        return shaper != null ? new ExplainableStubParagraphLayoutEngine(null, null, r, null, null, null, null, null, null, null,
            shaper) : hyphenate ? new ExplainableStubParagraphLayoutEngine(null, null, r, null, null, null, null, null, null, null, null,
                EnglishHyphenation.enUs()) : new ExplainableStubParagraphLayoutEngine(null, null, r);
    }

    public static function layout(text:String, width:Float, ?objects:Array<InlineObjectSpan>, ?hyphenate:Bool = false, ?shaper:ITextShaper,
            ?profile:ClreqProfile):LayoutResult {
        final e = LineAdjustmentStageJfTestSupport.engine(shaper, hyphenate, profile);
        return e.layout(new LayoutInput(new TiqianTextContent(text), null, new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(width), null,
            null, null, null, objects));
    }
}

class FixedClreqResolver implements ClreqProfileResolver {
    final profile:ClreqProfile;

    public function new(p:ClreqProfile)
        profile = p;

    public function resolve(id:LayoutProfileId):ClreqProfile
        return profile;
}

class DashBoundsShaper implements ITextShaper {
    final delegate:ExplainableStubTextShaper;
    final wide:Bool;

    public function new(wide:Bool) {
        delegate = new ExplainableStubTextShaper();
        this.wide = wide;
    }

    public function shape(input:ShapingInput):ShapingResult {
        final r = delegate.shape(input);
        var runs:Array<GlyphRun> = [];
        for (ri in 0...r.glyphRuns.length) {
            final run = r.glyphRuns[ri];
            var gs:Array<Glyph> = [];
            for (gi in 0...run.glyphs.length) {
                final g = run.glyphs[gi];
                gs.push(input.displayText.indexOf("⸺") >= 0 ? new Glyph(g.id, g.clusterRange, g.advance, g.x, g.y, g.renderFontKey,
                    new Rect(wide ? 0.0 : 1.0, 0, wide ? 31.5 : 29, 16), g.haltAdvance, g.haltPlacementX) : g);
            }
            runs.push(new GlyphRun(run.range, run.fontKey, gs, run.advance));
        }
        return new ShapingResult(r.clusters, runs, r.decisions);
    }
}
