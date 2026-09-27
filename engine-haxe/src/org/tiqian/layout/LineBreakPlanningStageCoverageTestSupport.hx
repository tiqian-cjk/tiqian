package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.font.*;
import org.tiqian.font.FontPolicy.FontDecision;
import org.tiqian.test.trace.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.LineBreaker.LookaheadLineBreaker;

class LineBreakPlanningStageCoverageTestSupport {
    public static function engine(?lookahead:Bool = false):ExplainableStubParagraphLayoutEngine
        return new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, lookahead ? new LookaheadLineBreaker() : null);

    public static function layout(text:String, width:Float, ?strategy:LineAdjustmentStrategy, ?height:Float, ?spans:Array<LineBreakSpan>,
            ?objects:Array<InlineObjectSpan>, ?lookahead:Bool = false):LayoutResult {
        final ps = new ParagraphStyle(null, null, height, Ic.Zero, null, null, new LineLengthGrid(false));
        var resolver:Null<ClreqProfileResolver> = null;
        if (strategy != null)
            resolver = new FixedResolver(strategy);
        final e = new ExplainableStubParagraphLayoutEngine(null, null, resolver, null, null, null, null, null, lookahead ? new LookaheadLineBreaker() : null);
        return e.layout(new LayoutInput(new TiqianTextContent(text, null, null, spans), null, ps, new LayoutConstraints(width), null, null, null, null,
            objects));
    }

    // Mirrors Kotlin layoutWith in LineBreakPlanningStageCoverageTest.kt: the
    // real-paragraph-1 fixture is laid out with a DEFAULT ParagraphStyle (null
    // firstLineIndent, so MeasureAdaptiveFirstLineIndent applies) instead of the
    // explicit-zero style used by layout() above.
    public static function layoutWithDefaultStyle(text:String, width:Float, strategy:LineAdjustmentStrategy):LayoutResult {
        final e = new ExplainableStubParagraphLayoutEngine(null, null, new FixedResolver(strategy), null, null, null, null, null, new LookaheadLineBreaker());
        return e.layout(new LayoutInput(new TiqianTextContent(text), null, null, new LayoutConstraints(width), null, null, null, null, null));
    }

    public static function fillPushInCount(r:LayoutResult):Int {
        var n = 0;
        for (d in r.debug.lineDecisions)
            if (d.repairDecision != null && d.repairDecision.reasonCode == "LineAdjustmentPushIn")
                n++;
        return n;
    }

    public static function renderDecisions(r:LayoutResult):String {
        final x:Array<String> = [];
        for (i in 0...r.debug.lineDecisions.length)
            x.push(Std.string(r.debug.lineDecisions[i]));
        return "[" + x.join(", ") + "]";
    }

    public static function renderLines(a:std.ReadOnlyArray<LineBox>):String {
        final x:Array<String> = [];
        for (i in 0...a.length)
            x.push(Std.string(a[i]));
        return "[" + x.join(", ") + "]";
    }

    public static function renderJustification(a:std.ReadOnlyArray<JustificationDecisionInfo>):String {
        final x:Array<String> = [];
        for (i in 0...a.length)
            x.push(Std.string(a[i]));
        return "[" + x.join(", ") + "]";
    }
}

class FixedResolver implements ClreqProfileResolver {
    final strategy:LineAdjustmentStrategy;

    public function new(s:LineAdjustmentStrategy)
        strategy = s;

    public function resolve(id:LayoutProfileId):ClreqProfile
        return new ClreqProfile(ClreqProfile.MainlandHorizontal.id, ClreqProfile.MainlandHorizontal.strictness, ClreqProfile.MainlandHorizontal.region,
            ClreqProfile.MainlandHorizontal.punctuationGlyphPolicy, null, null, null, new AdjustmentStylePolicy(null, null, null, strategy),
            ClreqProfile.MainlandHorizontal.kinsokuMode, ClreqProfile.MainlandHorizontal.punctuationWidth);
}
