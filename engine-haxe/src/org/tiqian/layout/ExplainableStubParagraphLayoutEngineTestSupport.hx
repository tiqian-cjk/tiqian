package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.linebreak.Hyphenator.NoHyphenator;
import org.tiqian.shaping.TextShaper;
import org.tiqian.shaping.TextShaper.ITextShaper;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.font.FontRole;
import org.tiqian.test.trace.TestTraceRecorder;

class ExplainableStubParagraphLayoutEngineTestSupport {
    public static function start(name:String):TestTraceRecorder {
        var t = new TestTraceRecorder("ExplainableStubParagraphLayoutEngineTest");
        t.section(name);
        return t;
    }

    public static function textLength(s:String):Int
        return s.length;

    public static function graphemeBoundaries(s:String):Array<Int>
        return SourceInteractionBoundaries.sourceGraphemeBoundaries(s, new TextRange(0, s.length));

    public static function renderRanges(a:Array<TextRange>):String {
        var s = "[";
        for (i in 0...a.length) {
            if (i > 0)
                s += ", ";
            s += Std.string(a[i]);
        }
        return s + "]";
    }

    public static function renderPairs(a:Array<String>, b:Array<String>):String {
        var s = "[";
        for (i in 0...a.length) {
            if (i > 0)
                s += ", ";
            s += "(" + a[i] + ", " + b[i] + ")";
        }
        return s + "]";
    }

    public static function input(text:String, width:Float, ?style:ParagraphStyle, ?shaper:ITextShaper, ?textStyle:TextStyle):LayoutInput {
        return new LayoutInput(new TiqianTextContent(text), textStyle, style == null ? new ParagraphStyle(null, null, null, Ic.Zero) : style,
            new LayoutConstraints(width));
    }

    public static function engine(?shaper:ITextShaper, ?breaker:LineBreaker):ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine {
        return new ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, breaker, null, shaper,
            new NoHyphenator());
    }

    public static function renderStrings(a:Array<String>):String {
        var s = "[";
        for (i in 0...a.length) {
            if (i > 0)
                s += ", ";
            s += "'" + a[i] + "'";
        }
        return s + "]";
    }
}

class EmptyTextShaper implements ITextShaper {
    public function new() {}

    public function shape(input:ShapingInput):ShapingResult
        return new ShapingResult([], []);
}

class FixedBoundsTextShaper implements ITextShaper {
    public function new() {}

    public function shape(input:ShapingInput):ShapingResult {
        var text = input.text.substring(input.range.start, input.range.end);
        var c = new Cluster(input.range, text, input.fontDecision.candidate.key, input.range.end - input.range.start == 0 ? 0 : 20, input.displayText);
        var g = new Glyph(42, input.range, 20, null, null, null, new Rect(1, -10, 12, 2));
        return new ShapingResult([c], [new GlyphRun(input.range, input.fontDecision.candidate.key, [g], 20)]);
    }
}
