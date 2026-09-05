package org.tiqian.layout;

using std.RecordCopy;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.layout.LineBreaker.GreedyLineBreaker;
import std.ReadOnlyArray;

class InlineObjectLayoutTestSupport {
    public static function rec(n:String):TestTraceRecorder {
        final t = new TestTraceRecorder("InlineObjectLayoutTest");
        t.section(n);
        return t;
    }

    public static final style = new ParagraphStyle(null, null, 24, Ic.Zero, null, null, new LineLengthGrid(false));

    public static function resolver(p:ClreqProfile):ClreqProfileResolver
        return new Resolver(p);

    public static function fixed(?b:LineBreaker):ExplainableStubParagraphLayoutEngine
        return new ExplainableStubParagraphLayoutEngine(null, null, resolver(ClreqProfile.MainlandHorizontal), null, null, null, null, null,
            b == null ? new GreedyLineBreaker() : b);

    public static function layout(text:String, width:Float, ?objects:Array<InlineObjectSpan>, ?b:LineBreaker):LayoutResult
        return fixed(b).layout(new LayoutInput(new TiqianTextContent(text), new TextStyle(16), style, new LayoutConstraints(width), null, null, null, null,
            objects));

    public static function fixedBasicKinsokuEngine(?b:LineBreaker):ExplainableStubParagraphLayoutEngine {
        final base = ClreqProfile.MainlandHorizontal;
        final p = new ClreqProfile(base.id, base.strictness, base.region, base.punctuationGlyphPolicy, null, base.autoSpace, base.gluePlacement,
            base.adjustment, KinsokuMode.Fixed(KinsokuLevel.Basic, HangingPunctuationStyle.Disabled), base.punctuationWidth);
        return new ExplainableStubParagraphLayoutEngine(null, null, resolver(p), null, null, null, null, null, b == null ? new GreedyLineBreaker() : b);
    }

    public static function lines(r:LayoutResult, text:String):Array<String> {
        var a:Array<String> = [];
        for (i in 0...r.lines.length)
            a.push(text.substring(r.lines[i].range.start, r.lines[i].range.end));
        return a;
    }

    public static function renderStrings(a:Array<String>):String
        return "[" + a.join(", ") + "]";

    public static function sameRange(first:TextRange, second:TextRange):Bool
        return first.start == second.start && first.end == second.end;

    public static function singleCluster(r:LayoutResult, range:TextRange):Cluster {
        var f:Cluster = null;
        var n = 0;
        for (i in 0...r.clusters.length)
            if (sameRange(r.clusters[i].range, range)) {
                f = r.clusters[i];
                n++;
            }
        return n == 1 ? f : null;
    }

    public static function singlePositioned(cs:Array<PositionedCluster>, range:TextRange):PositionedCluster {
        var f:PositionedCluster = null;
        var n = 0;
        for (i in 0...cs.length)
            if (sameRange(cs[i].range, range)) {
                f = cs[i];
                n++;
            }
        return n == 1 ? f : null;
    }

    public static function singleInlineObjectDecision(r:LayoutResult, range:TextRange):InlineObjectDecisionInfo {
        var f:InlineObjectDecisionInfo = null;
        var n = 0;
        for (i in 0...r.debug.inlineObjectDecisions.length)
            if (sameRange(r.debug.inlineObjectDecisions[i].range, range)) {
                f = r.debug.inlineObjectDecisions[i];
                n++;
            }
        return n == 1 ? f : null;
    }

    public static function singleShapingDecision(r:LayoutResult, range:TextRange):ShapingDecisionInfo {
        var f:ShapingDecisionInfo = null;
        var n = 0;
        for (i in 0...r.debug.shapingDecisions.length)
            if (sameRange(r.debug.shapingDecisions[i].range, range)) {
                f = r.debug.shapingDecisions[i];
                n++;
            }
        return n == 1 ? f : null;
    }

    public static function renderRepairAllocations(a:ReadOnlyArray<LineRepairAllocationInfo>):String {
        final x:Array<String> = [];
        for (i in 0...a.length)
            x.push(Std.string(a[i]));
        return "[" + x.join(", ") + "]";
    }

    public static function renderTrimDecisions(a:ReadOnlyArray<LineEdgeTrimDecisionInfo>):String {
        final x:Array<String> = [];
        for (i in 0...a.length)
            x.push(Std.string(a[i]));
        return "[" + x.join(", ") + "]";
    }

    public static function renderLineRanges(r:LayoutResult):String {
        final x:Array<String> = [];
        for (i in 0...r.lines.length)
            x.push(Std.string(r.lines[i].range));
        return "[" + x.join(", ") + "]";
    }
}

class Resolver implements ClreqProfileResolver {
    final p:ClreqProfile;

    public function new(p)
        this.p = p;

    public function resolve(id:LayoutProfileId):ClreqProfile
        return p;
}
