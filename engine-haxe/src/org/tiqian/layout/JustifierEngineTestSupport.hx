package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.test.trace.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ITextShaper;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.linebreak.Hyphenator.NoHyphenator;

using std.RecordCopy;

class JustifierEngineTestSupport {
    public static function start(n:String):TestTraceRecorder {
        var t = new TestTraceRecorder("JustifierEngineTest");
        t.section(n);
        return t;
    }

    public static function engine():ExplainableStubParagraphLayoutEngine {
        var p = ClreqProfile.MainlandHorizontal;
        var r:ClreqProfileResolver = new Fixed(p.copy(adjustment = p.adjustment.copy(lineAdjustment = LineAdjustmentStrategy.PushOutOnly)));
        return new ExplainableStubParagraphLayoutEngine(null, null, r);
    }

    public static function positioned():ExplainableStubParagraphLayoutEngine
        return new ExplainableStubParagraphLayoutEngine(null, null,
            new Fixed(ClreqProfile.MainlandHorizontal.copy(adjustment = ClreqProfile.MainlandHorizontal.adjustment.copy(lineAdjustment = LineAdjustmentStrategy.PushOutOnly))),
            null, null, null, null, null, null, null, new PositionedPairShaper(), new NoHyphenator());

    public static function layout(text:String, width:Float):LayoutResult
        return engine().layout(new LayoutInput(new TiqianTextContent(text), null, new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(width)));

    public static function allocationsText(list:std.ReadOnlyArray<JustificationAllocationInfo>):String {
        var out:Array<String> = [];
        for (i in 0...list.length)
            out.push(Std.string(list[i]));
        return "[" + out.join(", ") + "]";
    }
}

class Fixed implements ClreqProfileResolver {
    var p:ClreqProfile;

    public function new(p:ClreqProfile)
        this.p = p;

    public function resolve(id:LayoutProfileId):ClreqProfile
        return p;
}

class PositionedPairShaper implements ITextShaper {
    public function new() {}

    public function shape(input:ShapingInput):ShapingResult {
        var text = input.text.substring(input.range.start, input.range.end);
        var advance = text == "AV" ? 10 : text.length * 16;
        var gs:Array<Glyph> = [];
        if (text == "AV") {
            gs.push(new Glyph(1, input.range, 5, 0, 0, null));
            gs.push(new Glyph(2, input.range, 5, 5, 0, null));
        } else
            gs.push(new Glyph(3, input.range, advance, 0, 0, null));
        return new ShapingResult([
            new Cluster(input.range, text, input.fontDecision.candidate.key, advance, input.displayText)
        ], [new GlyphRun(input.range, input.fontDecision.candidate.key, gs, advance)]);
    }
}
