package org.tiqian.layout;

import org.tiqian.clreq.*;
import org.tiqian.core.*;
import org.tiqian.font.FontRole;
import org.tiqian.linebreak.Hyphenator.NoHyphenator;
import org.tiqian.layout.LineBreaker.GreedyLineBreaker;
import org.tiqian.layout.LineBreaker.LookaheadLineBreaker;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.AsciiPointMarkKinsokuTestSupport.BreakerChoice;

class UnicodePunctuationBoundaryTestSupport {
    public static function breakers():Array<BreakerChoice> {
        return [
            {label: "greedy", breaker: new GreedyLineBreaker()},
            {label: "lookahead", breaker: new LookaheadLineBreaker()}
        ];
    }

    public static function setInts(values:Array<Int>):std.SortedSet<Int> {
        final b = std.SortedSet.builder();
        for (i in 0...values.length)
            b.put(values[i]);
        return b.build();
    }

    public static function markClosing(i:Int):String
        return [")", "]", "}", ",", ".", ":", ";", "!", "?"][i];

    public static function markOpening(i:Int):String
        return ["(", "[", "{"][i];

    public static function layout(text:String, width:Float, b:LineBreaker, ?level:Null<KinsokuLevel>):LayoutResult {
        final l = level == null ? KinsokuLevel.Basic : level;
        final resolver = new UnicodePunctuationBoundaryTestResolver(l);
        final boundaries:Array<Int> = [];
        for (i in 0...text.length + 1)
            boundaries.push(i);
        return new ExplainableStubParagraphLayoutEngine(null, null, resolver, null, null, null, null, b, null, null, new NoHyphenator(),
            null).layout(new LayoutInput(new TiqianTextContent(text, null, boundaries), null,
                new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(width)));
    }

    public static function lines(r:LayoutResult, text:String):Array<String> {
        final a:Array<String> = [];
        for (i in 0...r.lines.length) {
            final x = r.lines[i];
            a.push(text.substring(x.range.start, x.range.end));
        }
        return a;
    }

    public static function noneStarts(lines:Array<String>, mark:String):Bool {
        for (i in 0...lines.length)
            if (StringTools.startsWith(lines[i], mark))
                return false;
        return true;
    }

    public static function noneEnds(lines:Array<String>, mark:String):Bool {
        for (i in 0...lines.length)
            if (StringTools.endsWith(lines[i], mark))
                return false;
        return true;
    }

    public static function findReason(r:LayoutResult, text:String, pos:String):String {
        for (i in 0...r.debug.contextualKinsokuDecisions.length) {
            final x = r.debug.contextualKinsokuDecisions[i];
            if (x.sourceText == text && x.forbiddenPosition == pos)
                return x.reason;
        }
        return "";
    }

    public static function clusters(text:String, ?latin:Bool):Array<Cluster> {
        final a:Array<Cluster> = [];
        for (i in 0...text.length)
            a.push(new Cluster(new TextRange(i, i + 1), text.substring(i, i + 1), latin == true ? "latin" : "cjk", 16));
        return a;
    }

    public static function roles(text:String, ?latin:Bool):Array<FontRole> {
        final a:Array<FontRole> = [];
        for (i in 0...text.length)
            a.push(latin == true ? FontRole.LatinText : FontRole.CjkText);
        return a;
    }
}

class UnicodePunctuationBoundaryTestResolver implements ClreqProfileResolver {
    final level:KinsokuLevel;

    public function new(level:KinsokuLevel) {
        this.level = level;
    }

    public function resolve(_:LayoutProfileId):ClreqProfile {
        final b = ClreqProfile.MainlandHorizontal;
        return new ClreqProfile(b.id, b.strictness, b.region, b.punctuationGlyphPolicy, null, null, b.gluePlacement, b.adjustment,
            KinsokuMode.Fixed(level, HangingPunctuationStyle.Disabled), b.punctuationWidth);
    }
}
