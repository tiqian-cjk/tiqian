package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.layout.ClusterRoleResolution.ResolvedClusterRange;
import org.tiqian.layout.ParagraphShapingStage.ParagraphShapingStageResult;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.shaping.TextShaper;
import org.tiqian.shaping.TextShaper.ITextShaper;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ShapingResult;
import org.tiqian.shaping.TextShaper.ExplainableStubTextShaper;
import org.tiqian.linebreak.Hyphenator;
import org.tiqian.font.FontRole;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TestTraceRender;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedMap;
import std.SortedSet;
import org.tiqian.font.FontPolicy.FontCandidate;
import org.tiqian.font.FontPolicy.FontDecision;

class ParagraphEmptyHyphenShaper implements ITextShaper {
    public var delegate:ExplainableStubTextShaper = new ExplainableStubTextShaper();

    public function new() {}

    public function shape(i:ShapingInput):ShapingResult {
        if (i.text == "-" || i.displayText == "-")
            return new ShapingResult([], []);
        return delegate.shape(i);
    }
}

class ParagraphMultiClusterShaper implements ITextShaper {
    public var delegate:ExplainableStubTextShaper = new ExplainableStubTextShaper();
    public var toggle:Bool = false;

    public function new() {}

    public function shape(i:ShapingInput):ShapingResult {
        var r = delegate.shape(i);
        if (i.range.length <= 1)
            return r;
        toggle = !toggle;
        if (!toggle)
            return r;
        var m = Std.int((i.range.start + i.range.end) / 2);
        return new ShapingResult([
            new Cluster(new TextRange(i.range.start, m), "a", "k", 100.0, "a"),
            new Cluster(new TextRange(m, i.range.end), "b", "k", 100.0, "b")
        ], r.glyphRuns, r.decisions);
    }
}

class ParagraphWordShaper implements ITextShaper {
    public var delegate:ExplainableStubTextShaper = new ExplainableStubTextShaper();

    public function new() {}

    public function shape(i:ShapingInput):ShapingResult {
        var r = delegate.shape(i);
        if (i.range.length == 2 && i.text.substring(i.range.start, i.range.end) == "em") {
            return new ShapingResult([
                new Cluster(new TextRange(i.range.start, i.range.start + 1), "e", "k", 10.0, "e"),
                new Cluster(new TextRange(i.range.start + 1, i.range.end), "m", "k", 10.0, "m")
            ], r.glyphRuns, r.decisions);
        }
        return r;
    }
}

class ParagraphEmptyClusterShaper implements ITextShaper {
    public var delegate:ExplainableStubTextShaper = new ExplainableStubTextShaper();

    public function new() {}

    public function shape(i:ShapingInput):ShapingResult {
        var r = delegate.shape(i);
        if (i.text == "singlecluster" || i.displayText == "singlecluster")
            return new ShapingResult([], r.glyphRuns, r.decisions);
        return r;
    }
}

class ParagraphDeficientDashShaper implements ITextShaper {
    public function new() {}

    public function shape(i:ShapingInput):ShapingResult {
        var c = new Cluster(i.range, i.text.substring(i.range.start, i.range.end), "test", 32.0, i.displayText);
        var g = new Glyph(1, i.range, 32.0, 0.0, new Rect(0.0, 0.0, 20.0, 10.0));
        return new ShapingResult([c], [new GlyphRun(i.range, "test", [g], 32.0)]);
    }
}

class ParagraphSufficientDashShaper implements ITextShaper {
    public function new() {}

    public function shape(i:ShapingInput):ShapingResult {
        var c = new Cluster(i.range, i.text.substring(i.range.start, i.range.end), "test", 32.0, i.displayText);
        var g = new Glyph(1, i.range, 32.0, 0.0, new Rect(0.0, 0.0, 30.0, 10.0));
        return new ShapingResult([c], [new GlyphRun(i.range, "test", [g], 32.0)]);
    }
}

class ParagraphRollbackShaper implements ITextShaper {
    public var call:Int = 0;

    public function new() {}

    public function shape(i:ShapingInput):ShapingResult {
        call++;
        var c = new Cluster(i.range, i.text.substring(i.range.start, i.range.end), "test", 16.0, i.displayText);
        var issue = call == 1 ? TextShaper.UNVERIFIED_DISPLAY_SUBSTITUTION_COVERAGE_ISSUE : null;
        var d = new ShapingDecisionInfo(i.range, i.text.substring(i.range.start, i.range.end), i.displayText, "test", 1, 16.0, "Test", "test", null,
            call == 2 ? 1 : 0, null, null, null, null, null, issue);
        return new ShapingResult([c], [new GlyphRun(i.range, "test", [], 16.0)], [d]);
    }
}

class ParagraphMultiGlyphShaper implements ITextShaper {
    public var count:Int = 0;

    public function new() {}

    public function shape(i:ShapingInput):ShapingResult {
        count++;
        var c = new Cluster(i.range, i.text.substring(i.range.start, i.range.end), "test", 32.0, i.displayText);
        var gs:Array<Glyph> = count % 3 == 0 ? [] : (count % 3 == 1 ? [new Glyph(1, i.range, 16.0,
            0.0), new Glyph(2, i.range, 16.0, 16.0)] : [new Glyph(1, i.range, 32.0, 0.0)]);
        return new ShapingResult([c], [new GlyphRun(i.range, "test", gs, 32.0)]);
    }
}

class ParagraphCoverageHyphenator implements Hyphenator {
    public var mode:Int;

    public function new(?mode:Int = 0)
        this.mode = mode;

    public function hyphenate(w:String):std.ReadOnlyArray<Int>
        return mode == 1 && w.indexOf("hyphen") >= 0 ? [2, 4] : (mode == 2 ? [1, 2, 3] : [2]);
}

/** Matches the legacy latinSegmentationAndCutsBranches hyphenator: a word
    * containing "hyphen" breaks at 2 and 4; every other word has no break. */
class ParagraphSegmentationHyphenator implements Hyphenator {
    public function new() {}

    public function hyphenate(w:String):std.ReadOnlyArray<Int>
        return w.indexOf("hyphen") >= 0 ? [2, 4] : [];
}

/** Matches the legacy latinSeparatorCutsExhaustiveBranches hyphenator: only the
    * exact word "hyphenated" breaks, at 3 and 6. */
class ParagraphBiblioHyphenator implements Hyphenator {
    public function new() {}

    public function hyphenate(w:String):std.ReadOnlyArray<Int>
        return w == "hyphenated" ? [3, 6] : [];
}

/** Matches the legacy latinWordCutsLoHiAndEmptyBranches hyphenator: one break
    * offset per known word, none otherwise. */
class ParagraphWordCutsHyphenator implements Hyphenator {
    public function new() {}

    public function hyphenate(w:String):std.ReadOnlyArray<Int> {
        if (w == "abcdef") return [1];
        if (w == "ghijkl") return [2];
        if (w == "mnopqr") return [3];
        if (w == "empty") return [2];
        return [];
    }
}

class ParagraphTierHyphenator implements Hyphenator {
    public function new() {}

    public function hyphenate(w:String):std.ReadOnlyArray<Int>
        return w.indexOf("Machine") >= 0 ? [-1, 0, 3, w.length, w.length + 1] : [2];
}

/** Matches the legacy directShapeParagraphEdgeCases hyphenator
    * (engine/src/commonTest/kotlin/org/tiqian/layout/ParagraphShapingStageCoverageTest.kt:342),
    * whose word list drives the latin cuts of that case and nothing else. */
class ParagraphDirectShapeHyphenator implements Hyphenator {
    public function new() {}

    public function hyphenate(w:String):std.ReadOnlyArray<Int> {
        if (w == "abcdef") return [1];
        if (w == "abcdeg") return [2];
        if (w == "antidisestablishmentarianism") return [];
        if (w == "Machine") return [-1, 0, 2, w.length, w.length + 2];
        return [2];
    }
}

/** Matches the legacy progressiveTechnicalTierPriorityAndFalseBranches
    * hyphenator (ParagraphShapingStageCoverageTest.kt:557): "abcdef" breaks at
    * 2 and 4, every other word reports out-of-range offsets. */
class ParagraphTierPriorityHyphenator implements Hyphenator {
    public function new() {}

    public function hyphenate(w:String):std.ReadOnlyArray<Int>
        return w == "abcdef" ? [2, 4] : [-1, 0, 1, 2, w.length, w.length + 2];
}

/** Matches the legacy progressiveTierLoopRevisitsOffsetsWithLowerPriorityTiers
    * hyphenator (ParagraphShapingStageCoverageTest.kt:650). */
class ParagraphTierLoopHyphenator implements Hyphenator {
    public function new() {}

    public function hyphenate(w:String):std.ReadOnlyArray<Int> {
        if (w == "abcdef") return [2, 4];
        if (w == "cdef") return [1];
        return [];
    }
}

class ParagraphShapingStageCoverageTestSupport {
    public static function input(text:String, width:Float, ?spans:Array<LineBreakSpan>):LayoutInput {
        return new LayoutInput(new TiqianTextContent(text, null, null, spans), null, null, new LayoutConstraints(width));
    }

    public static function begin(n:String):TestTraceRecorder {
        var r = new TestTraceRecorder("ParagraphShapingStageCoverageTest");
        r.section(n);
        return r;
    }

    public static function layout(e:ExplainableStubParagraphLayoutEngine, text:String, width:Float):Void {
        var res = e.layout(new LayoutInput(new TiqianTextContent(text), null, null, new LayoutConstraints(width)));
        TracedAssertions.recordRenderedNotNull(TestTraceRender.cap(res == null ? "null" : Std.string(res)));
    }

    public static function engine(?shaper:ITextShaper, ?hyphenator:Hyphenator):ExplainableStubParagraphLayoutEngine {
        return new ExplainableStubParagraphLayoutEngine(null, null, null, null, null, null, null, null, null, null, shaper, hyphenator);
    }

    public static function candidate(role:FontRole):FontCandidate
        return new FontCandidate("k", "f", role);

    public static function decision(range:TextRange, role:FontRole):FontDecision
        return new FontDecision(range, candidate(role), role, "r");

    public static function paragraph(engine:ExplainableStubParagraphLayoutEngine, input:LayoutInput, text:String, width:Float, role:FontRole,
            ?italic:Bool = false):ParagraphShapingStageResult {
        var range = new TextRange(0, text.length);
        var b = SortedMap.builder();
        b.put(range, decision(range, role));
        var rb = SortedMap.builder();
        var cb = [new ResolvedClusterRange(range, role, false, false)];
        return ParagraphShapingStage.shapeParagraph(engine, input, text, 16.0, width, cb, b.build(), SortedMap.builder().build(),
            new org.tiqian.clreq.ClreqPunctuationGlyphSubstitutor(), function(_:Int) return new TextStyle(null, 16.0), function(_:Int) return italic,
            rb.build());
    }

    public static function paragraphRanges(engine:ExplainableStubParagraphLayoutEngine, input:LayoutInput, text:String, width:Float,
            ranges:Array<ResolvedClusterRange>, decisions:Array<TextRange>):ParagraphShapingStageResult {
        var b = SortedMap.builder();
        for (r in decisions)
            b.put(r, decision(r, FontRole.LatinText));
        var rb = SortedMap.builder();
        return ParagraphShapingStage.shapeParagraph(engine, input, text, 16.0, width, ranges, b.build(), SortedMap.builder().build(),
            new org.tiqian.clreq.ClreqPunctuationGlyphSubstitutor(), function(_:Int) return new TextStyle(null, 16.0), function(_:Int) return false,
            rb.build());
    }

    /** Same direct stage call as paragraphRanges, plus the rejected technical
        * tiers per progressive span that the legacy
        * progressiveTechnicalTierPriorityAndFalseBranches case passes
        * (ParagraphShapingStageCoverageTest.kt:610). Tier values are stored as
        * their ProgressiveBreakTier priorities. */
    public static function paragraphRangesWithRejectedTiers(engine:ExplainableStubParagraphLayoutEngine, input:LayoutInput, text:String, width:Float,
            ranges:Array<ResolvedClusterRange>, decisions:Array<TextRange>, rejectedSpans:Array<TextRange>,
            rejectedTiers:Array<Array<Int>>):ParagraphShapingStageResult {
        var b = SortedMap.builder();
        for (r in decisions)
            b.put(r, decision(r, FontRole.LatinText));
        var rb = SortedMap.builder();
        for (i in 0...rejectedSpans.length) {
            final tiers = SortedSet.builder();
            for (j in 0...rejectedTiers[i].length)
                tiers.put(rejectedTiers[i][j]);
            rb.put(rejectedSpans[i], tiers.build());
        }
        return ParagraphShapingStage.shapeParagraph(engine, input, text, 16.0, width, ranges, b.build(), SortedMap.builder().build(),
            new org.tiqian.clreq.ClreqPunctuationGlyphSubstitutor(), function(_:Int) return new TextStyle(null, 16.0), function(_:Int) return false,
            rb.build());
    }
}
