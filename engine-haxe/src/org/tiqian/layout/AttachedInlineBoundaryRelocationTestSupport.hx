package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.layout.LineBreaker.GreedyLineBreaker;
import org.tiqian.layout.LineBreaker.LookaheadLineBreaker;
import org.tiqian.layout.ParagraphDpLineBreaker;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.AsciiPointMarkKinsokuTestSupport.BreakerChoice;
import org.tiqian.layout.UnicodePunctuationBoundaryResolver.AttachedInlineVirtualBoundary;
import std.ReadOnlyArray;

class AttachedInlineBoundaryRelocationTestSupport {
    public static function resolve(a:Array<InlineAttachment>):Array<AttachedInlineVirtualBoundary> {
        return UnicodePunctuationBoundaryResolver.resolveAttachedInlineVirtualBoundaries(a);
    }

    public static function layoutAttachedReference(text:String):LayoutResult {
        var idx = text.indexOf("[1]");
        var spans = [
            new TextSpan(new TextRange(idx, idx + 3), new TextStyle(null, null, null, null, null, null, InlineAttachment.Previous))
        ];
        return new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent(text, spans), null,
            new ParagraphStyle(null, null, null, Ic.Zero), new LayoutConstraints(320.0)));
    }

    public static function layoutWithBreaker(text:String, breaker:LineBreaker):LayoutResult {
        var spans = [
            new TextSpan(new TextRange(2, 3), new TextStyle(null, null, null, null, null, null, InlineAttachment.Previous))
        ];
        var engine = new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, breaker);
        return engine.layout(new LayoutInput(new TiqianTextContent(text, spans), null, new ParagraphStyle(null, null, null, Ic.Zero),
            new LayoutConstraints(32.0)));
    }

    public static function breakers():Array<BreakerChoice> {
        return [
            {label: "greedy", breaker: new GreedyLineBreaker()},
            {label: "lookahead", breaker: new LookaheadLineBreaker()},
            {label: "paragraph-dp", breaker: new ParagraphDpLineBreaker()}
        ];
    }

    public static function virtualBoundary(r:LayoutResult):SpacingDecisionInfo {
        var hit:SpacingDecisionInfo = null;
        for (i in 0...r.debug.spacingDecisions.length) {
            if (StringTools.startsWith(r.debug.spacingDecisions[i].reason, "AttachedInlineVirtualPunctuationBoundary")) {
                hit = r.debug.spacingDecisions[i];
                break;
            }
        }
        return hit;
    }

    public static function renderLines(a:ReadOnlyArray<LineBox>):String {
        var parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(Std.string(a[i]));
        return "[" + parts.join(", ") + "]";
    }

    public static function renderRanges(a:ReadOnlyArray<LineBox>):String {
        var parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(Std.string(a[i].range));
        return "[" + parts.join(", ") + "]";
    }
}
