package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.shaping.TextShaper.ExplainableStubTextShaper;
import org.tiqian.shaping.TextShaper.ITextShaper;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.test.trace.TracedAssertions;
import std.ReadOnlyArray;

class RubyLayoutTestSupport {
    public static function engine():ExplainableStubParagraphLayoutEngine {
        return new ExplainableStubParagraphLayoutEngine();
    }

    public static function input(ruby:Array<RubySpan>):LayoutInput {
        return new LayoutInput(new TiqianTextContent("\u4E2D\u6587\u6392\u7248"), null, new ParagraphStyle(null, null, null, new Ic(0)),
            new LayoutConstraints(400.0), null, null, ruby);
    }

    public static function layout(ruby:Array<RubySpan>):LayoutResult {
        return engine().layout(input(ruby));
    }

    public static function layoutEight(ruby:Array<RubySpan>):LayoutResult {
        return engine().layout(new LayoutInput(new TiqianTextContent("\u7532\u4E59\u4E19\u4E01\u620A\u5DF1\u5E9A\u8F9B"), null,
            new ParagraphStyle(null, null, null, new Ic(0)), new LayoutConstraints(64.0), null, null, ruby));
    }

    public static function layoutTwelve(ruby:Array<RubySpan>):LayoutResult {
        return engine().layout(new LayoutInput(new TiqianTextContent("\u7532\u4E59\u4E19\u4E01\u620A\u5DF1\u5E9A\u8F9B\u58EC\u7678\u5B50\u4E11"), null,
            new ParagraphStyle(null, null, 18.0, new Ic(0)), new LayoutConstraints(64.0), null, null, ruby));
    }

    public static function layoutUniform(ruby:Array<RubySpan>):LayoutResult {
        return engine().layout(new LayoutInput(new TiqianTextContent("\u7532\u4E59\u4E19\u4E01\u620A\u5DF1\u5E9A\u8F9B\u58EC\u7678\u5B50\u4E11"), null,
            new ParagraphStyle(null, null, 18.0, new Ic(0), null, null, null, RubyLineHeightMode.UniformParagraph), new LayoutConstraints(64.0), null, null,
            ruby));
    }

    public static function layoutContradictory(reading:String):LayoutResult {
        final e = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, new ContradictoryInkShaper());
        return e.layout(new LayoutInput(new TiqianTextContent("\u7532\u4E59\u4E19\u4E01"), null, new ParagraphStyle(null, null, 18.0, new Ic(0)),
            new LayoutConstraints(64.0), null, null, [new RubySpan(new TextRange(0, 1), reading)]));
    }

    public static function totalWidth(texts:Array<String>):Float {
        final spans:Array<RubySpan> = [];
        for (i in 0...texts.length)
            spans.push(new RubySpan(new TextRange(i, i + 1), texts[i]));
        final r = engine().layout(new LayoutInput(new TiqianTextContent("\u4E2D\u6587\u6392\u7248"), null, new ParagraphStyle(null, null, null, new Ic(0)),
            new LayoutConstraints(4000.0), null, null, spans));
        var total = 0.0;
        for (i in 0...r.clusters.length)
            total += r.clusters[i].advance;
        return total;
    }

    public static function assertFloatListEquals(expected:Array<Float>, actual:ReadOnlyArray<Float>):Void {
        final e:Array<Int> = [];
        for (i in 0...expected.length)
            e.push(Std.int(expected[i]));
        final a:Array<Int> = [];
        for (i in 0...actual.length)
            a.push(Std.int(actual[i]));
        TracedAssertions.assertEqualsIntArray(e, a);
    }
}

class ContradictoryInkShaper implements ITextShaper {
    final delegate:ExplainableStubTextShaper;

    public function new() {
        delegate = new ExplainableStubTextShaper();
    }

    public function shape(input:ShapingInput):ShapingResult {
        final r = delegate.shape(input);
        final bounds = input.displayText == "pg" ? new Rect(0.0, -100.0, 16.0, 100.0) : new Rect(0.0, -1.0, 16.0, 1.0);
        final runs:Array<GlyphRun> = [];
        for (i in 0...r.glyphRuns.length) {
            final run = r.glyphRuns[i];
            final gs:Array<Glyph> = [];
            for (j in 0...run.glyphs.length) {
                final g = run.glyphs[j];
                gs.push(new Glyph(g.id, g.clusterRange, g.advance, g.x, g.y, g.renderFontKey, bounds, g.haltAdvance, g.haltPlacementX));
            }
            runs.push(new GlyphRun(run.range, run.fontKey, gs, run.advance, null));
        }
        final ds:Array<ShapingDecisionInfo> = [];
        for (i in 0...r.decisions.length) {
            final d = r.decisions[i];
            ds.push(new ShapingDecisionInfo(d.range, d.sourceText, d.displayText, d.fontKey, d.glyphCount, d.advance, d.source, d.reason, 0, d.missingGlyphs,
                d.resolvedFace, d.script, d.language, d.strategy, d.featureEvidence, d.capabilityIssue));
        }
        return new ShapingResult(r.clusters, runs, ds);
    }
}
