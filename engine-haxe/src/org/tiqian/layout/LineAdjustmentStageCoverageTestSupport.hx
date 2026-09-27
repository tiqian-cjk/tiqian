package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.shaping.TextShaper.ITextShaper;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.shaping.TextShaper.ExplainableStubTextShaper;
import org.tiqian.linebreak.EnglishHyphenation;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import std.ReadOnlyArray;

class LineAdjustmentStageCoverageTestSupport {
    public static function engine(?shaper:ITextShaper, hyphenate:Bool):ExplainableStubParagraphLayoutEngine {
        if (shaper != null)
            return new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, shaper);
        if (hyphenate)
            return new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, null, EnglishHyphenation.enUs());
        return new ExplainableStubParagraphLayoutEngine();
    }

    public static function layout(text:String, width:Float, ?spans:Array<TextSpan>, ?inlineObjects:Array<InlineObjectSpan>,
            ?lineBreakSpans:Array<LineBreakSpan>, ?hyphenate:Bool, ?shaper:ITextShaper):LayoutResult {
        final resolvedSpans = spans == null ? [] : spans;
        final resolvedObjects = inlineObjects == null ? [] : inlineObjects;
        final resolvedBreaks = lineBreakSpans == null ? [] : lineBreakSpans;
        final e = LineAdjustmentStageCoverageTestSupport.engine(shaper, hyphenate == true);
        return e.layout(new LayoutInput(new TiqianTextContent(text, resolvedSpans, null, resolvedBreaks), null,
            new ParagraphStyle(null, null, null, new Ic(0.0), null, null, new LineLengthGrid(false)), new LayoutConstraints(width), null, null, null, null,
            resolvedObjects));
    }

    public static function renderLines(a:ReadOnlyArray<LineBox>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(Std.string(a[i]));
        return "[" + parts.join(", ") + "]";
    }

    public static function renderTrims(a:ReadOnlyArray<LineEdgeTrimDecisionInfo>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(Std.string(a[i]));
        return "[" + parts.join(", ") + "]";
    }

    public static function renderJustifications(a:ReadOnlyArray<JustificationDecisionInfo>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(Std.string(a[i]));
        return "[" + parts.join(", ") + "]";
    }

    public static function renderGlyphs(a:ReadOnlyArray<Glyph>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(Std.string(a[i]));
        return "[" + parts.join(", ") + "]";
    }

    public static function renderStrings(a:ReadOnlyArray<String>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(a[i]);
        return "[" + parts.join(", ") + "]";
    }

    public static function renderFloats(a:Array<Float>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(Std.string(a[i]));
        return "[" + parts.join(", ") + "]";
    }

    public static function renderClusterTextAdvance(a:ReadOnlyArray<Cluster>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(a[i].text + "@" + Std.string(a[i].advance));
        return parts.join(",");
    }

    public static function renderAdvances(a:ReadOnlyArray<Cluster>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(Std.string(a[i].advance));
        return parts.join(",");
    }

    public static function renderClusterTexts(a:ReadOnlyArray<Cluster>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(a[i].text);
        return parts.join(",");
    }

    public static function lineRangeWidths(a:ReadOnlyArray<LineBox>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(a[i].clusterRange.toString() + ":" + Std.string(a[i].naturalWidth) + "/" + Std.string(a[i].adjustedWidth));
        return "[" + parts.join(", ") + "]";
    }

    public static function clusterByText(r:LayoutResult, text:String):Cluster {
        for (i in 0...r.clusters.length)
            if (r.clusters[i].text == text)
                return r.clusters[i];
        throw new TiqianNoSuchElementException(NoSuchElementError.Message("missing cluster " + text));
    }

    public static function trimByReason(r:LayoutResult, reason:String):LineEdgeTrimDecisionInfo {
        for (i in 0...r.debug.lineEdgeTrimDecisions.length)
            if (r.debug.lineEdgeTrimDecisions[i].reason == reason)
                return r.debug.lineEdgeTrimDecisions[i];
        throw new TiqianNoSuchElementException(NoSuchElementError.Message("missing trim " + reason));
    }

    public static function trimsByReason(r:LayoutResult, reason:String):Array<LineEdgeTrimDecisionInfo> {
        final out:Array<LineEdgeTrimDecisionInfo> = [];
        for (i in 0...r.debug.lineEdgeTrimDecisions.length)
            if (r.debug.lineEdgeTrimDecisions[i].reason == reason)
                out.push(r.debug.lineEdgeTrimDecisions[i]);
        return out;
    }

    public static function allocationDeltas(r:LayoutResult, kind:String):Array<Float> {
        final out:Array<Float> = [];
        for (i in 0...r.debug.justificationDecisions.length) {
            final allocs = r.debug.justificationDecisions[i].allocations;
            for (j in 0...allocs.length)
                if (allocs[j].kind == kind)
                    out.push(allocs[j].delta);
        }
        return out;
    }

    public static function emergencyReasons(r:LayoutResult):Array<String> {
        final out:Array<String> = [];
        for (i in 0...r.debug.emergencyTrackingEligibilityDecisions.length)
            out.push(r.debug.emergencyTrackingEligibilityDecisions[i].reason);
        return out;
    }

    public static function breakReasons(r:LayoutResult):Array<String> {
        final out:Array<String> = [];
        for (i in 0...r.debug.breakOpportunityDecisions.length)
            out.push(r.debug.breakOpportunityDecisions[i].reason);
        return out;
    }

    public static function isAllSpaces(s:String):Bool {
        if (s.length == 0)
            return false;
        for (i in 0...s.length)
            if (s.charAt(i) != " ")
                return false;
        return true;
    }

    public static function textLength(s:String):Int {
        return s.length;
    }
}

class ZeroSpaceShaper implements ITextShaper {
    final delegate:ExplainableStubTextShaper;

    public function new() {
        delegate = new ExplainableStubTextShaper();
    }

    public function shape(input:ShapingInput):ShapingResult {
        final shaped = delegate.shape(input);
        final clusters:Array<Cluster> = [];
        for (i in 0...shaped.clusters.length) {
            final c = shaped.clusters[i];
            clusters.push(LineAdjustmentStageCoverageTestSupport.isAllSpaces(c.text) ? new Cluster(c.range, c.text, c.fontKey, 0.0, c.displayText,
                c.baselineShift, c.leadingLayoutAdvance, c.glyphInlineShift) : c);
        }
        return new ShapingResult(clusters, shaped.glyphRuns, shaped.decisions);
    }
}
