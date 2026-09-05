package org.tiqian.layout;

import org.tiqian.clreq.ClreqProfile;
import org.tiqian.clreq.ClreqProfileResolver;
import org.tiqian.clreq.HangingPunctuationStyle;
import org.tiqian.clreq.KinsokuLevel;
import org.tiqian.clreq.KinsokuMode;
import org.tiqian.core.Ic;
import org.tiqian.core.LayoutConstraints;
import org.tiqian.core.LayoutInput;
import org.tiqian.core.LayoutResult;
import org.tiqian.core.LineLengthGrid;
import org.tiqian.core.ParagraphStyle;
import org.tiqian.core.RubySpan;
import org.tiqian.core.TextSpan;
import org.tiqian.core.TiqianTextContent;
import org.tiqian.layout.LineBreaker.GreedyLineBreaker;
import org.tiqian.layout.LineBreaker.LookaheadLineBreaker;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.linebreak.Hyphenator.NoHyphenator;
import std.ReadOnlyArray;
import org.tiqian.core.Cluster;
import org.tiqian.core.FontDecisionInfo;
import org.tiqian.core.ContextualKinsokuDecisionInfo;
import org.tiqian.core.LineBox;
import org.tiqian.core.LineDecisionInfo;
import org.tiqian.core.TextRange;

typedef BreakerChoice = {label:String, breaker:LineBreaker};

class AsciiPointMarkKinsokuTestSupport {
    public static function renderStrings(a:ReadOnlyArray<String>):String {
        final x:Array<String> = [];
        for (i in 0...a.length)
            x.push(a[i]);
        return "[" + x.join(", ") + "]";
    }

    public static function joinLines(a:Array<String>):String {
        return a.join("\n");
    }

    public static function renderClusters(a:ReadOnlyArray<Cluster>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(Std.string(a[i]));
        return "[" + parts.join(", ") + "]";
    }

    public static function renderFonts(a:ReadOnlyArray<FontDecisionInfo>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(Std.string(a[i]));
        return "[" + parts.join(", ") + "]";
    }

    public static function renderContextual(a:ReadOnlyArray<ContextualKinsokuDecisionInfo>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(Std.string(a[i]));
        return "[" + parts.join(", ") + "]";
    }

    public static function renderLines(a:ReadOnlyArray<LineBox>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(Std.string(a[i]));
        return "[" + parts.join(", ") + "]";
    }

    public static function renderLineDecisions(a:ReadOnlyArray<LineDecisionInfo>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(Std.string(a[i]));
        return "[" + parts.join(", ") + "]";
    }

    public static function hasCluster(r:LayoutResult, s:String):Bool {
        for (i in 0...r.clusters.length)
            if (r.clusters[i].text == s)
                return true;
        return false;
    }

    public static function clustersWithText(r:LayoutResult, s:String):Array<Cluster> {
        final x:Array<Cluster> = [];
        for (i in 0...r.clusters.length)
            if (r.clusters[i].text == s)
                x.push(r.clusters[i]);
        return x;
    }

    public static function sameRange(first:TextRange, second:TextRange):Bool {
        return first.start == second.start && first.end == second.end;
    }

    public static function fontDecision(r:LayoutResult, range:TextRange):FontDecisionInfo {
        for (i in 0...r.debug.fontDecisions.length)
            if (sameRange(r.debug.fontDecisions[i].range, range))
                return r.debug.fontDecisions[i];
        return null;
    }

    public static function hasFontSource(r:LayoutResult, s:String):Bool {
        for (i in 0...r.debug.fontDecisions.length)
            if (r.debug.fontDecisions[i].sourceText == s)
                return true;
        return false;
    }

    public static function fontDecisionByText(r:LayoutResult, s:String):FontDecisionInfo {
        for (i in 0...r.debug.fontDecisions.length)
            if (r.debug.fontDecisions[i].sourceText == s)
                return r.debug.fontDecisions[i];
        return null;
    }

    public static function hasPunctuation(r:LayoutResult, range:TextRange):Bool {
        for (i in 0...r.debug.punctuationDecisions.length)
            if (sameRange(r.debug.punctuationDecisions[i].range, range))
                return true;
        return false;
    }

    public static function contextual(r:LayoutResult, range:Null<TextRange>):ContextualKinsokuDecisionInfo {
        for (i in 0...r.debug.contextualKinsokuDecisions.length)
            if (range == null || sameRange(r.debug.contextualKinsokuDecisions[i].range, range))
                return r.debug.contextualKinsokuDecisions[i];
        return null;
    }

    public static function contextualByText(r:LayoutResult, s:String):ContextualKinsokuDecisionInfo {
        for (i in 0...r.debug.contextualKinsokuDecisions.length)
            if (r.debug.contextualKinsokuDecisions[i].sourceText == s)
                return r.debug.contextualKinsokuDecisions[i];
        return null;
    }

    public static function hasRepair(r:LayoutResult, s:String):Bool {
        for (i in 0...r.debug.lineDecisions.length)
            if (r.debug.lineDecisions[i].repair == s)
                return true;
        return false;
    }

    public static function forbiddenFor(r:LayoutResult, s:String):Array<String> {
        final x:Array<String> = [];
        for (i in 0...r.debug.contextualKinsokuDecisions.length)
            if (r.debug.contextualKinsokuDecisions[i].sourceText == s)
                x.push(r.debug.contextualKinsokuDecisions[i].forbiddenPosition);
        return x;
    }

    public static function nullFallback(r:LayoutResult):String {
        final d = contextual(r, null);
        return d == null || d.impossibleMeasureFallback == null ? "" : d.impossibleMeasureFallback;
    }

    public static function layout(text:String, maxWidth:Float, breaker:LineBreaker, ?level:Null<KinsokuLevel>, ?hanging:Null<HangingPunctuationStyle>,
            ?firstLineIndent:Null<Ic>, ?rubySpans:Array<RubySpan>, ?spans:Array<TextSpan>, ?lineLengthGrid:Null<LineLengthGrid>):LayoutResult {
        final resolvedLevel = level == null ? KinsokuLevel.Basic : level;
        final resolvedHanging = hanging == null ? HangingPunctuationStyle.Disabled : hanging;
        final resolvedIndent = firstLineIndent == null ? Ic.Zero : firstLineIndent;
        final resolvedGrid = lineLengthGrid == null ? new LineLengthGrid() : lineLengthGrid;
        final engine = new ExplainableStubParagraphLayoutEngine(null, null, new AsciiKinsokuFixedResolver(resolvedLevel, resolvedHanging), null, null, null,
            null, null, breaker, null, null, new NoHyphenator(), null);
        return engine.layout(new LayoutInput(new TiqianTextContent(text, spans), null,
            new ParagraphStyle(null, null, null, resolvedIndent, null, null, resolvedGrid), new LayoutConstraints(maxWidth), null, null, rubySpans, null,
            null));
    }

    public static function layoutWithoutExplicitIndent(text:String, maxWidth:Float, breaker:LineBreaker):LayoutResult {
        final engine = new ExplainableStubParagraphLayoutEngine(null, null,
            new AsciiKinsokuFixedResolver(KinsokuLevel.Basic, HangingPunctuationStyle.Disabled), null, null, null, null, null, breaker, null, null,
            new NoHyphenator(), null);
        return engine.layout(new LayoutInput(new TiqianTextContent(text, null), null,
            new ParagraphStyle(null, null, null, null, null, null, new LineLengthGrid()), new LayoutConstraints(maxWidth), null, null, null, null, null));
    }

    public static function lineTexts(result:LayoutResult, source:String):Array<String> {
        final texts = [];
        for (i in 0...result.lines.length) {
            final line = result.lines[i];
            texts.push(source.substring(line.range.start, line.range.end));
        }
        return texts;
    }

    public static function breakers():Array<BreakerChoice> {
        final choices:Array<BreakerChoice> = [
            {label: "greedy", breaker: new GreedyLineBreaker()},
            {label: "lookahead", breaker: new LookaheadLineBreaker()}
        ];
        return choices;
    }

    public static inline var REPORTED_PARAGRAPH:String = "对于你冒犯的断言不敢苟同,你以一种理所当然的语气声明\"明显的已经越过了人际尊重的基本门槛\","
        + "如此注重逻辑推导的作者居然会对论断的前提条件如此宽松以至于不留回旋余地?当然不是,在回复的一开头,"
        + "聪明的作者就已经强调了自己作为被冒犯者有权力定义自己的感受,当然有权力!,但是这种感受是否可以无限扩展到"
        + "\"人际尊重的基本门槛\",还是值得商榷的,逻辑严谨如你岂能放过如此基础的逻辑漏洞?也许我们可以采用更加自洽的解释,"
        + " 这种愤怒来源于作者遭到否定是的第一反应,一篇让你耿耿于怀三年的留言需要你通过反复打磨的语言和极致构思的反讽,"
        + "只为了冷嘲热讽一个逻辑甚至不大通顺的留言.\" 我一定要用最严密的逻辑反驳回去,这是关乎我尊严的网络论战\",也许你心里确实这么想,"
        + " 可是承认这件事情在你的内心是一件丢脸的事情,倘若承认了自己的三年的耿耿于怀, 就等同于认可自己与对方与自己处于同一水平对话,"
        + " “居然要和一个沙文主义在相提并论, 这怎么可以接受”.但事实上,如此自视清高反而令人啼笑皆非,如果你可以大方承认自己的傲慢,"
        + "我大可因为你的心胸宽广\"对你致上最高的敬意\".别急着找我的逻辑漏洞,因为我也会大大方方的承认我就是在玩,"
        + "我乐意这种伪装成思辨的娱乐,这比大部分辩论赛有意思多了 .anyway,你完全有机会在一开始就讲清楚自己愤怒的来源,"
        + "而不是强行带上无所谓的面具却又如此的用力过猛,希望下一次你可以清晰表述,就像你自己提到的那样,"
        + "不要\"把解读的权利拱手让给对方\"";
}

class AsciiKinsokuFixedResolver implements ClreqProfileResolver {
    final level:KinsokuLevel;
    final hanging:HangingPunctuationStyle;

    public function new(level:KinsokuLevel, hanging:HangingPunctuationStyle) {
        this.level = level;
        this.hanging = hanging;
    }

    public function resolve(profileId:org.tiqian.core.LayoutProfileId):ClreqProfile {
        final base = ClreqProfile.MainlandHorizontal;
        return new ClreqProfile(base.id, base.strictness, base.region, base.punctuationGlyphPolicy, null, null, base.gluePlacement, base.adjustment,
            KinsokuMode.Fixed(level, hanging), base.punctuationWidth);
    }
}
