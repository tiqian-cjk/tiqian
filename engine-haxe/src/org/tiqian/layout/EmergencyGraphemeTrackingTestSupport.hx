package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.linebreak.EnglishHyphenation;
import std.ReadOnlyArray;
import org.tiqian.shaping.TextShaper.ITextShaper;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.test.trace.TestTrace;
import org.tiqian.test.trace.TestTraceRender;
import org.tiqian.test.trace.TracedAssertions;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;

class EmergencyGraphemeTrackingTestSupport {
    public static final noIndent:ParagraphStyle = new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false));

    public static function engine(?textShaper:ITextShaper, ?hyphenator:org.tiqian.linebreak.Hyphenator):ExplainableStubParagraphLayoutEngine {
        return new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, textShaper, hyphenator);
    }

    public static function renderInts(a:Array<Int>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(Std.string(a[i]));
        return "[" + parts.join(", ") + "]";
    }

    public static function renderClusters(a:ReadOnlyArray<Cluster>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(Std.string(a[i]));
        return "[" + parts.join(", ") + "]";
    }

    public static function joinTextRanges(a:Array<TextRange>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(Std.string(a[i]));
        return parts.join(", ");
    }

    public static function renderAllocations(a:Array<JustificationAllocationInfo>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(Std.string(a[i]));
        return "[" + parts.join(", ") + "]";
    }

    public static function layout(text:String, maxWidth:Float, ?lineBreakSpans:Array<LineBreakSpan>):LayoutResult {
        return engine(null,
            EnglishHyphenation.enUs()).layout(new LayoutInput(new TiqianTextContent(text, null, null, lineBreakSpans), null, noIndent,
            new LayoutConstraints(maxWidth)));
    }

    public static function layoutWithShaper(text:String, maxWidth:Float, textShaper:ITextShaper, ?lineBreakSpans:Array<LineBreakSpan>):LayoutResult {
        return engine(textShaper,
            EnglishHyphenation.enUs()).layout(new LayoutInput(new TiqianTextContent(text, null, null, lineBreakSpans), null, noIndent,
            new LayoutConstraints(maxWidth)));
    }

    public static function layoutWithObjects(text:String, maxWidth:Float, objects:Array<InlineObjectSpan>, ?lineBreakSpans:Array<LineBreakSpan>):LayoutResult {
        return new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent(text, null, null, lineBreakSpans), null, noIndent,
            new LayoutConstraints(maxWidth), null, null, null, null, objects));
    }

    public static function breakOffsetsForTier(decisions:ReadOnlyArray<BreakOpportunityDecisionInfo>, tier:String):Array<Int> {
        final result:Array<Int> = [];
        for (i in 0...decisions.length) {
            if (decisions[i].tier == tier) {
                for (j in 0...decisions[i].breakOffsets.length)
                    result.push(decisions[i].breakOffsets[j]);
            }
        }
        return result;
    }

    public static function allocationsForKind(decisions:ReadOnlyArray<JustificationDecisionInfo>, kind:String):Array<JustificationAllocationInfo> {
        final result:Array<JustificationAllocationInfo> = [];
        for (i in 0...decisions.length) {
            for (j in 0...decisions[i].allocations.length) {
                if (decisions[i].allocations[j].kind == kind)
                    result.push(decisions[i].allocations[j]);
            }
        }
        return result;
    }

    public static function assertEqualsTextRange(expected:TextRange, actual:TextRange):Void {
        final e = TestTraceRender.canonicalNumbers(Std.string(expected));
        final a = TestTraceRender.canonicalNumbers(Std.string(actual));
        final recorder = TestTrace.currentRecorder();
        if (recorder != null)
            recorder.record("eq expected=" + e + " actual=" + a);
        if (expected.start != actual.start || expected.end != actual.end)
            TracedAssertions.fail("TextRange mismatch");
    }
}

class UniformAdvanceShaper implements ITextShaper {
    public function new() {}

    public function shape(input:ShapingInput):ShapingResult {
        final source = input.text.substring(input.range.start, input.range.end);
        return new ShapingResult([
            new Cluster(input.range, source, input.fontDecision.candidate.key, source.length * 10.0, input.displayText)
        ], []);
    }
}
