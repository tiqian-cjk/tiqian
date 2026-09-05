package org.tiqian.layout;

import org.tiqian.clreq.*;
import org.tiqian.core.*;
import org.tiqian.layout.LineBreaker.LookaheadLineBreaker;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.shaping.TextShaper.ITextShaper;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.shaping.TextShaper.ExplainableStubTextShaper;
import org.tiqian.test.trace.TestTraceRender;
import std.ReadOnlyArray;

typedef JustifiedDashHit = {dash:Cluster, decision:JustificationDecisionInfo};

class DisplayGlyphSubstitutionEngineTestSupport {
    public static function defaultEngine():ExplainableStubParagraphLayoutEngine {
        return new ExplainableStubParagraphLayoutEngine();
    }

    public static function profileEngine(policy:CjkPunctuationGlyphPolicy, ?coalesce:Array<Int>):ExplainableStubParagraphLayoutEngine {
        return new ExplainableStubParagraphLayoutEngine(null, null, new GlyphPolicyResolver(policy, coalesce));
    }

    public static function shaperEngine(shaper:ITextShaper):ExplainableStubParagraphLayoutEngine {
        return new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, shaper);
    }

    public static function lookaheadShaperEngine(shaper:ITextShaper):ExplainableStubParagraphLayoutEngine {
        return new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, new LookaheadLineBreaker(), null, shaper);
    }

    public static function layout320(engine:ExplainableStubParagraphLayoutEngine, text:String):LayoutResult {
        return engine.layout(new LayoutInput(new TiqianTextContent(text), null, new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(320)));
    }

    public static function layout320WithSpans(engine:ExplainableStubParagraphLayoutEngine, text:String, spans:Array<TextSpan>):LayoutResult {
        return engine.layout(new LayoutInput(new TiqianTextContent(text, spans), null, new ParagraphStyle(null, null, null, Ic.Zero),
            new LayoutConstraints(320)));
    }

    public static function layoutWithoutGrid(engine:ExplainableStubParagraphLayoutEngine, text:String, maxWidth:Float):LayoutResult {
        return engine.layout(new LayoutInput(new TiqianTextContent(text), null,
            new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(maxWidth)));
    }

    public static function findJustifiedDashHit(engine:ExplainableStubParagraphLayoutEngine, text:String):JustifiedDashHit {
        var cells = 13;
        while (cells <= 30) {
            final result = layoutWithoutGrid(engine, text, cells * 16 + 7);
            final dash = singleClusterWithText(result, "\u2014\u2014");
            final decision = firstJustificationDecisionCovering(result, dash.range);
            if (decision != null && decision.allocations.length > 0) {
                return {dash: dash, decision: decision};
            }
            cells++;
        }
        throw new IllegalStateException("no width produced a justified line containing the dash");
    }

    public static function firstClusterWithText(r:LayoutResult, s:String):Cluster {
        for (i in 0...r.clusters.length) {
            if (r.clusters[i].text == s) {
                return r.clusters[i];
            }
        }
        throw new IllegalStateException("No cluster with text " + s);
    }

    public static function singleCluster(r:LayoutResult):Cluster {
        if (r.clusters.length != 1) {
            throw new IllegalStateException("Expected a single cluster, found " + r.clusters.length);
        }
        return r.clusters[0];
    }

    public static function singleClusterWithText(r:LayoutResult, s:String):Cluster {
        var found:Cluster = null;
        var count = 0;
        for (i in 0...r.clusters.length) {
            if (r.clusters[i].text == s) {
                found = r.clusters[i];
                count++;
            }
        }
        if (count != 1) {
            throw new IllegalStateException("Expected a single cluster with text " + s + ", found " + count);
        }
        return found;
    }

    public static function singleFontDecisionWithSourceText(r:LayoutResult, s:String):FontDecisionInfo {
        var found:FontDecisionInfo = null;
        var count = 0;
        for (i in 0...r.debug.fontDecisions.length) {
            if (r.debug.fontDecisions[i].sourceText == s) {
                found = r.debug.fontDecisions[i];
                count++;
            }
        }
        if (count != 1) {
            throw new IllegalStateException("Expected a single font decision with source text " + s + ", found " + count);
        }
        return found;
    }

    public static function singlePunctuationDecision(r:LayoutResult):PunctuationDecisionInfo {
        if (r.debug.punctuationDecisions.length != 1) {
            throw new IllegalStateException("Expected a single punctuation decision, found " + r.debug.punctuationDecisions.length);
        }
        return r.debug.punctuationDecisions[0];
    }

    public static function singleGlyphWithClusterRange(r:LayoutResult, range:TextRange):Glyph {
        var found:Glyph = null;
        var count = 0;
        for (ri in 0...r.glyphRuns.length) {
            final glyphs = r.glyphRuns[ri].glyphs;
            for (gi in 0...glyphs.length) {
                if (glyphs[gi].clusterRange.start == range.start && glyphs[gi].clusterRange.end == range.end) {
                    found = glyphs[gi];
                    count++;
                }
            }
        }
        if (count != 1) {
            throw new IllegalStateException("Expected a single glyph for range " + range.toString() + ", found " + count);
        }
        return found;
    }

    public static function firstJustificationDecisionCovering(r:LayoutResult, range:TextRange):JustificationDecisionInfo {
        for (i in 0...r.debug.justificationDecisions.length) {
            final d = r.debug.justificationDecisions[i];
            if (range.start >= d.lineRange.start && range.end <= d.lineRange.end) {
                return d;
            }
        }
        return null;
    }

    public static function renderNullableFloats(a:Array<Null<Float>>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length) {
            parts.push(a[i] == null ? "-" : TestTraceRender.renderFloat(a[i]));
        }
        return "[" + parts.join(", ") + "]";
    }

    public static function renderStringListArray(a:Array<ReadOnlyArray<String>>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length) {
            parts.push(TestTraceRender.renderStringArray(a[i]));
        }
        return "[" + parts.join(", ") + "]";
    }
}

class GlyphPolicyResolver implements ClreqProfileResolver {
    final policy:CjkPunctuationGlyphPolicy;
    final coalesce:Array<Int>;

    public function new(policy:CjkPunctuationGlyphPolicy, ?coalesce:Array<Int>) {
        this.policy = policy;
        this.coalesce = coalesce;
    }

    public function resolve(profileId:LayoutProfileId):ClreqProfile {
        final base = ClreqProfile.MainlandHorizontal;
        return new ClreqProfile(base.id, base.strictness, base.region, policy, coalesce, null, base.gluePlacement, base.adjustment, base.kinsokuMode,
            base.punctuationWidth);
    }
}

class PerGlyphQuoteRunShaper implements ITextShaper {
    final delegate:ExplainableStubTextShaper;

    public function new() {
        delegate = new ExplainableStubTextShaper();
    }

    public function shape(input:ShapingInput):ShapingResult {
        if (input.displayText != "A\u2019B") {
            return delegate.shape(input);
        }
        final clusters:Array<Cluster> = [];
        var index = input.range.start;
        while (index < input.range.end) {
            clusters.push(new Cluster(new TextRange(index, index + 1), input.text.substring(index, index + 1), input.fontDecision.candidate.key, 16,
                input.displayText.substring(index - input.range.start, index + 1 - input.range.start)));
            index++;
        }
        final runs:Array<GlyphRun> = [];
        for (glyphId in 0...clusters.length) {
            final cluster = clusters[glyphId];
            final features:Array<String> = cluster.text == "\u2019" ? ["pwid", "palt"] : [];
            runs.push(new GlyphRun(cluster.range, cluster.fontKey, [new Glyph(glyphId, cluster.range, cluster.advance)], cluster.advance, features));
        }
        return new ShapingResult(clusters, runs);
    }
}

class SingleClusterNoBoundsShaper implements ITextShaper {
    public function new() {}

    public function shape(input:ShapingInput):ShapingResult {
        return new ShapingResult([
            new Cluster(input.range, input.text.substring(input.range.start, input.range.end), input.fontDecision.candidate.key, 16, input.displayText)
        ], [
            new GlyphRun(input.range, input.fontDecision.candidate.key, [new Glyph(0, input.range, 16)], 16)
        ]);
    }
}

class SingleClusterAmbiguousShaper implements ITextShaper {
    public function new() {}

    public function shape(input:ShapingInput):ShapingResult {
        return new ShapingResult([
            new Cluster(input.range, input.text.substring(input.range.start, input.range.end), input.fontDecision.candidate.key, 32, input.displayText)
        ], [
            new GlyphRun(input.range, input.fontDecision.candidate.key, [new Glyph(0, input.range, 32, null, null, null, new Rect(2, -10, 30, -6))], 32)
        ]);
    }
}

class MissingGlyphReportingShaper implements ITextShaper {
    final delegate:ExplainableStubTextShaper;

    public function new() {
        delegate = new ExplainableStubTextShaper();
    }

    public function shape(input:ShapingInput):ShapingResult {
        final res = delegate.shape(input);
        if (input.displayText.indexOf("\u2E3A") < 0) {
            return res;
        }
        final decisions:Array<ShapingDecisionInfo> = [];
        for (i in 0...res.decisions.length) {
            final d = res.decisions[i];
            decisions.push(new ShapingDecisionInfo(d.range, d.sourceText, d.displayText, d.fontKey, d.glyphCount, d.advance, d.source, d.reason,
                d.glyphsWithoutInkBounds, 1, d.resolvedFace, d.script, d.language, d.strategy, d.featureEvidence, d.capabilityIssue));
        }
        return new ShapingResult(res.clusters, res.glyphRuns, decisions);
    }
}

class UnverifiedCoverageReportingShaper implements ITextShaper {
    final delegate:ExplainableStubTextShaper;

    public function new() {
        delegate = new ExplainableStubTextShaper();
    }

    public function shape(input:ShapingInput):ShapingResult {
        final res = delegate.shape(input);
        if (input.displayText.indexOf("\u22EF") < 0) {
            return res;
        }
        final decisions:Array<ShapingDecisionInfo> = [];
        for (i in 0...res.decisions.length) {
            final d = res.decisions[i];
            decisions.push(new ShapingDecisionInfo(d.range, d.sourceText, d.displayText, d.fontKey, d.glyphCount, d.advance, d.source, d.reason,
                d.glyphsWithoutInkBounds, d.missingGlyphs, d.resolvedFace, d.script, d.language, d.strategy, d.featureEvidence,
                "UnverifiedDisplaySubstitutionCoverage"));
        }
        return new ShapingResult(res.clusters, res.glyphRuns, decisions);
    }
}

class DashInkOverrideShaper implements ITextShaper {
    final delegate:ExplainableStubTextShaper;
    final overrideAdvance:Float;
    final ink:Rect;
    final fullOverride:Bool;

    public function new(overrideAdvance:Float, ink:Rect, fullOverride:Bool) {
        delegate = new ExplainableStubTextShaper();
        this.overrideAdvance = overrideAdvance;
        this.ink = ink;
        this.fullOverride = fullOverride;
    }

    public function shape(input:ShapingInput):ShapingResult {
        final res = delegate.shape(input);
        if (input.displayText.indexOf("\u2E3A") < 0) {
            return res;
        }
        if (!fullOverride) {
            return new ShapingResult(res.clusters, overrideRuns(res), res.decisions);
        }
        final clusters:Array<Cluster> = [];
        for (i in 0...res.clusters.length) {
            final c = res.clusters[i];
            clusters.push(new Cluster(c.range, c.text, c.fontKey, overrideAdvance, c.displayText, c.baselineShift, c.leadingLayoutAdvance, c.glyphInlineShift));
        }
        final decisions:Array<ShapingDecisionInfo> = [];
        for (i in 0...res.decisions.length) {
            final d = res.decisions[i];
            decisions.push(new ShapingDecisionInfo(d.range, d.sourceText, d.displayText, d.fontKey, d.glyphCount, overrideAdvance, d.source, d.reason,
                d.glyphsWithoutInkBounds, d.missingGlyphs, d.resolvedFace, d.script, d.language, d.strategy, d.featureEvidence, d.capabilityIssue));
        }
        return new ShapingResult(clusters, overrideRuns(res), decisions);
    }

    function overrideRuns(res:ShapingResult):Array<GlyphRun> {
        final runs:Array<GlyphRun> = [];
        for (ri in 0...res.glyphRuns.length) {
            final run = res.glyphRuns[ri];
            final glyphs:Array<Glyph> = [];
            for (gi in 0...run.glyphs.length) {
                final g = run.glyphs[gi];
                glyphs.push(new Glyph(g.id, g.clusterRange, overrideAdvance, g.x, g.y, g.renderFontKey, ink, g.haltAdvance, g.haltPlacementX));
            }
            runs.push(new GlyphRun(run.range, run.fontKey, glyphs, fullOverride ? overrideAdvance : run.advance, null));
        }
        return runs;
    }
}

class TwoGlyphEllipsisShaper implements ITextShaper {
    final delegate:ExplainableStubTextShaper;

    public function new() {
        delegate = new ExplainableStubTextShaper();
    }

    public function shape(input:ShapingInput):ShapingResult {
        if (input.displayText != "\u22EF\u22EF") {
            return delegate.shape(input);
        }
        return new ShapingResult([
            new Cluster(input.range, input.text.substring(input.range.start, input.range.end), input.fontDecision.candidate.key, 32, input.displayText)
        ], [
            new GlyphRun(input.range, input.fontDecision.candidate.key, [
                new Glyph(1, input.range, 16, 0, null, null, new Rect(1.5, -7, 14.5, -5)),
                new Glyph(2, input.range, 16, 16, null, null, new Rect(1.5, -7, 14.5, -5))
            ], 32)
        ]);
    }
}
