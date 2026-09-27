package org.tiqian.layout;

import org.tiqian.clreq.*;
import org.tiqian.core.*;
import org.tiqian.linebreak.*;
import org.tiqian.linebreak.Hyphenator.NoHyphenator;
import org.tiqian.linebreak.Hyphenator.TailHyphenator;
import org.tiqian.linebreak.Hyphenator.SyllableHyphenator;
import org.tiqian.layout.LineBreaker.LookaheadLineBreaker;
import org.tiqian.test.trace.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;

class LineBreakRepairEngineTestSupport {
    public static function input(text:String, width:Float, ?spans:Array<LineBreakSpan>):LayoutInput
        return new LayoutInput(new TiqianTextContent(text, spans == null ? [] : spans), null, new ParagraphStyle(null, null, null, Ic.Zero),
            new LayoutConstraints(width));

    public static function layout(text:String, width:Float, ?breaker:LineBreaker, ?hyphenator:Hyphenator, ?spans:Array<LineBreakSpan>):LayoutResult {
        return new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, breaker, null, null, hyphenator,
            null).layout(input(text, width, spans));
    }

    public static function layoutWithGrid(text:String, width:Float, gridEnabled:Bool, ?breaker:LineBreaker, ?hyphenator:Hyphenator,
            ?spans:Array<LineBreakSpan>):LayoutResult {
        return new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, breaker, null, null, hyphenator,
            null).layout(new LayoutInput(new TiqianTextContent(text, spans == null ? [] : spans), null,
                new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(gridEnabled)), new LayoutConstraints(width)));
    }

    public static function lineText(r:LayoutResult, n:Int):String {
        final l = r.lines[n];
        var s = "";
        for (i in l.clusterRange.start...l.clusterRange.end + 1)
            s += r.clusters[i].text;
        return s;
    }

    public static function hasText(r:LayoutResult, s:String):Bool {
        for (i in 0...r.clusters.length)
            if (r.clusters[i].text == s)
                return true;
        return false;
    }

    public static function noHyphen(r:LayoutResult):Bool {
        for (i in 0...r.lines.length)
            if (r.lines[i].hyphenAdvance != 0)
                return false;
        return true;
    }

    public static function fixed(?level:KinsokuLevel, ?hanging:HangingPunctuationStyle):ExplainableStubParagraphLayoutEngine {
        return new ExplainableStubParagraphLayoutEngine(null, null, new FixedProfileResolver(level, hanging), null, null, null, null, null, null, null, null,
            new NoHyphenator(), null);
    }

    public static function renderStrings(a:std.ReadOnlyArray<String>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(a[i]);
        return "[" + parts.join(", ") + "]";
    }

    public static function renderList<T>(a:std.ReadOnlyArray<T>):String {
        final parts:Array<String> = [];
        for (i in 0...a.length)
            parts.push(Std.string(a[i]));
        return "[" + parts.join(", ") + "]";
    }

    public static function blobTestTail(t:TestTraceRecorder):Void {
        final p = "为什么历史是 ";
        final s = StringTools.lpad("", "s", 40) + "herstory";
        final r = LineBreakRepairEngineTestSupport.layout(p + s, 160, new LookaheadLineBreaker(), new TailHyphenator());
        final x = LineBreakRepairEngineTestSupport.lineText(r, 0);
        TracedAssertions.assertTrue(x.length > 7, "first line should carry part of the opaque letter blob: " + x);
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.noHyphen(r));
        TracedAssertions.assertTrue(!LineBreakRepairEngineTestSupport.hasText(r, s));
    }

    public static function blobTestFitsAlone(t:TestTraceRecorder):Void {
        final p = "为什么历史是 ";
        final s = StringTools.lpad("", "s", 40) + "herstory";
        final r = LineBreakRepairEngineTestSupport.layout(p + s, 800, new LookaheadLineBreaker(), new TailHyphenator());
        final x = LineBreakRepairEngineTestSupport.lineText(r, 0);
        TracedAssertions.assertTrue(x.length > 7, "first line should carry part of the long opaque token instead of stretching only '" + p + "': " + x);
        TracedAssertions.assertTrue(!LineBreakRepairEngineTestSupport.hasText(r, s));
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.noHyphen(r));
    }

    public static function blobTestNonLexical(t:TestTraceRecorder):Void {
        final p = "为什么历史是 ";
        final s = StringTools.lpad("", "s", 40) + "herstory";
        final r = LineBreakRepairEngineTestSupport.layout(p + s, 160, new LookaheadLineBreaker(), new NoHyphenator());
        final x = LineBreakRepairEngineTestSupport.lineText(r, 0);
        TracedAssertions.assertTrue(x.length > 7, "first line should carry part of the non-lexical letter run: " + x);
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.noHyphen(r));
    }

    public static function blobTest(t:TestTraceRecorder, w:Float, ignored:Bool):Void {
        final p = "为什么历史是 ", s = StringTools.lpad("", "s", 40) + "herstory";
        final r = LineBreakRepairEngineTestSupport.layout(p + s, w, new LookaheadLineBreaker(), new NoHyphenator());
        var x = LineBreakRepairEngineTestSupport.lineText(r, 0);
        TracedAssertions.assertTrue(x.length > 7, "first line should carry part of the long opaque token instead of stretching only '" + p + "': " + x);
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.noHyphen(r));
        TracedAssertions.assertTrue(!LineBreakRepairEngineTestSupport.hasText(r, s));
    }

    public static function kinsokuStart(n:String):TestTraceRecorder {
        final t = new TestTraceRecorder("KinsokuAndCohesionRepairEngineTest");
        t.section(n);
        return t;
    }
}

class FixedProfileResolver implements ClreqProfileResolver {
    public final level:KinsokuLevel;
    public final hanging:HangingPunctuationStyle;

    public function new(?level:KinsokuLevel, ?hanging:HangingPunctuationStyle) {
        this.level = level == null ? KinsokuLevel.Basic : level;
        this.hanging = hanging == null ? HangingPunctuationStyle.Disabled : hanging;
    }

    public function resolve(id:LayoutProfileId):ClreqProfile {
        final b = ClreqProfile.MainlandHorizontal;
        return new ClreqProfile(b.id, b.strictness, b.region, b.punctuationGlyphPolicy, null, b.autoSpace, b.gluePlacement, b.adjustment,
            KinsokuMode.Fixed(level, hanging), b.punctuationWidth);
    }
}
