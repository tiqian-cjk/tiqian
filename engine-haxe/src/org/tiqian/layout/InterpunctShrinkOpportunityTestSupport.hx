package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.shaping.TextShaper.ITextShaper;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.shaping.TextShaper.ExplainableStubTextShaper;

class InterpunctShrinkOpportunityTestSupport {
    public static function haltInkShaper():ITextShaper
        return new InterpunctHaltShaper();

    public static function preserveResolver():ClreqProfileResolver
        return new InterpunctPreserveResolver();
}

class InterpunctPreserveResolver implements ClreqProfileResolver {
    public function new() {}

    public function resolve(profileId:org.tiqian.core.LayoutProfileId):ClreqProfile {
        return new ClreqProfile(ClreqProfile.MainlandHorizontal.id, ClreqStrictness.Normal, ClreqRegion.Mainland, CjkPunctuationGlyphPolicy.PreserveInput,
            null, null, null, new AdjustmentStylePolicy(), KinsokuMode.MeasureAdaptive(14.0, 24.0, 32.0), new PunctuationWidthPolicy());
    }
}

class InterpunctHaltShaper implements ITextShaper {
    final delegate:ExplainableStubTextShaper;

    public function new()
        delegate = new ExplainableStubTextShaper();

    public function shape(input:ShapingInput):ShapingResult {
        final res = delegate.shape(input);
        final source = input.text.substring(input.range.start, input.range.end);
        final inter = source == "·" || source == "・";
        final ellipsis = source == "…";
        final runs:Array<GlyphRun> = [];
        for (ri in 0...res.glyphRuns.length) {
            final run = res.glyphRuns[ri];
            final glyphs:Array<Glyph> = [];
            for (gi in 0...run.glyphs.length) {
                final g = run.glyphs[gi];
                final bounds = new Rect(ellipsis ? 2.0 : 4.0, 2.0, ellipsis ? 10.0 : 12.0, 10.0);
                glyphs.push(new Glyph(g.id, g.clusterRange, g.advance, g.x, g.y, g.renderFontKey, bounds, (inter || ellipsis) ? 8.0 : g.haltAdvance,
                    inter ? -4.0 : ellipsis ? 0.0 : g.haltPlacementX));
            }
            runs.push(new GlyphRun(run.range, run.fontKey, glyphs, run.advance, null));
        }
        return new ShapingResult(res.clusters, runs, res.decisions);
    }
}
