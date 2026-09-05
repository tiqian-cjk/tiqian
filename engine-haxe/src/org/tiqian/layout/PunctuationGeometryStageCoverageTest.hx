package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.font.FontRole;
import org.tiqian.layout.PunctuationModel.PunctuationAtom;
import org.tiqian.layout.PunctuationModel.PunctuationAtomBuilder;
import org.tiqian.layout.KinsokuRule.ClreqKinsokuRule;
import org.tiqian.layout.PunctuationGeometryStage.InlineObjectAttachedMark;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TestTraceRender;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedMap;
import std.SortedSet;

class PunctuationGeometryStageCoverageSupport {
    public static function start(n:String):Void {
        new TestTraceRecorder("PunctuationGeometryStageCoverageTest").section(n);
    }

    public static function c(t:String, i:Int, ?a:Float, ?f:String, ?d:String):Cluster
        return new Cluster(new TextRange(i, i + t.length), t, f == null ? "cjk" : f, a == null ? 16 : a, d);

    public static function obj(i:Int):Cluster
        return new Cluster(new TextRange(i, i + 1), "x", "inline-object", 8.0, "");

    public static function g(id:Int, a:Float, ?x:Float, ?b:Rect):Glyph
        return new Glyph(id, new TextRange(0, 1), a, x == null ? 0 : x, 0, null, b);

    public static function e(l:EastAsianSpacingValue, t:EastAsianSpacingValue):EastAsianSpacingEdges
        return new EastAsianSpacingEdges(l, t, l == EastAsianSpacingValue.Wide);

    public static function atoms(c:Cluster, g:Array<Glyph>):Array<PunctuationAtom>
        return PunctuationGeometryStage.punctuationAtoms(c, 16, new PunctuationAtomBuilder(), g, PunctuationGluePlacement.MainlandSimplified,
            new PunctuationWidthPolicy());

    public static function none(n:Int):Array<InlineAttachment> {
        var r = [];
        var i = 0;
        while (i < n) {
            r.push(InlineAttachment.None);
            i++;
        }
        return r;
    }

    public static function setInts(v:Array<Int>):SortedSet<Int> {
        final b = SortedSet.builder();
        var i = 0;
        while (i < v.length) {
            b.put(v[i]);
            i++;
        }
        return b.build();
    }

    public static function floatMap(keys:Array<Int>, values:Array<Float>):SortedMap<Int, Float> {
        final b = SortedMap.builder();
        var i = 0;
        while (i < keys.length) {
            b.put(keys[i], values[i]);
            i++;
        }
        return b.build();
    }

    public static function renderRanges(v:Array<IntRange>):String {
        var b = new StringBuf();
        b.add("[");
        var i = 0;
        while (i < v.length) {
            if (i > 0)
                b.add(", ");
            var r = v[i];
            b.add("[");
            var j = r.start;
            while (j <= r.end) {
                if (j > r.start)
                    b.add(", ");
                b.add(j);
                j++;
            }
            b.add("]");
            i++;
        }
        b.add("]");
        return b.toString();
    }

    public static function renderFloatMap(m:SortedMap<Int, Float>):String {
        var b = new StringBuf();
        b.add("{");
        var i = 0;
        while (i < m.size()) {
            if (i > 0)
                b.add(", ");
            b.add(m.keyAt(i) + "=" + TestTraceRender.renderFloat(m.valueAt(i)));
            i++;
        }
        b.add("}");
        return b.toString();
    }
}

class PunctuationGeometryStageCoverageTest {
    @:test public static function attachedAsciiPointMarkKinsokuProtectsRuns():Void {
        PunctuationGeometryStageCoverageSupport.start("attachedAsciiPointMarkKinsokuProtectsRuns");
        var S = PunctuationGeometryStageCoverageSupport;
        var c = [S.c("\u4E2D", 0), S.c(",", 1, 8, "latin"), S.c(",", 2, 8, "latin")];
        var roles = [FontRole.CjkText, FontRole.LatinText, FontRole.LatinText];
        TracedAssertions.assertFailsWith(null,
            () -> PunctuationGeometryStage.attachedAsciiPointMarkKinsoku(c, roles, [c[1], c[2]], KinsokuLevel.Basic, 100, 100));
        TracedAssertions.assertTrue(PunctuationGeometryStage.attachedAsciiPointMarkKinsoku(c, roles, c, KinsokuLevel.None, 100, 100)
            .unbreakableRanges.length == 0);
        var fits = PunctuationGeometryStage.attachedAsciiPointMarkKinsoku(c, roles, c, KinsokuLevel.Basic, 10, 100);
        TracedAssertions.assertEqualsRendered("[[0, 1, 2]]", S.renderRanges(fits.unbreakableRanges));
        TracedAssertions.assertEqualsIntSet(S.setInts([1, 2]), fits.forbiddenLineStartClusters);
        TracedAssertions.assertEqualsInt(2, fits.decisions.length);
        var allReasons = true;
        var di = 0;
        while (di < fits.decisions.length) {
            if (fits.decisions[di].reason != "AttachedAsciiPointMarkKinsoku")
                allReasons = false;
            di++;
        }
        TracedAssertions.assertTrue(allReasons);
        var hangs = PunctuationGeometryStage.attachedAsciiPointMarkKinsoku(c, roles, c, KinsokuLevel.Basic, 10, 5);
        TracedAssertions.assertEqualsRendered("[[0, 1, 2]]", S.renderRanges(hangs.unbreakableRanges));
        TracedAssertions.assertEqualsIntSet(S.setInts([1, 2]), hangs.impossibleMeasureHangEligibleClusters);
        TracedAssertions.assertEqualsRendered("[[0, 1, 2]]", S.renderRanges(hangs.extendableHangRanges));
        var bounded = [S.c("\u4E2D", 0), S.c(",", 1, 8, "latin"), S.c("a", 2, 8, "latin")];
        var boundedResult = PunctuationGeometryStage.attachedAsciiPointMarkKinsoku(bounded, [FontRole.CjkText, FontRole.LatinText, FontRole.LatinText],
            bounded, KinsokuLevel.Basic, 10, 100);
        TracedAssertions.assertEqualsRendered("[[0, 1]]", S.renderRanges(boundedResult.unbreakableRanges));
        TracedAssertions.assertEqualsInt(1, boundedResult.decisions.length);
        var mid = [S.c("\u4E2D", 0), S.c("\u4E2D", 1), S.c(",", 2, 8, "latin")];
        var midResult = PunctuationGeometryStage.attachedAsciiPointMarkKinsoku(mid, [FontRole.CjkText, FontRole.CjkText, FontRole.LatinText], mid,
            KinsokuLevel.Basic, 100, 5);
        TracedAssertions.assertEqualsRendered("[[1, 2]]", S.renderRanges(midResult.unbreakableRanges));
    }

    @:test public static function attachedAsciiPointMarkKinsokuRejectsDetachedRuns():Void {
        PunctuationGeometryStageCoverageSupport.start("attachedAsciiPointMarkKinsokuRejectsDetachedRuns");
        var S = PunctuationGeometryStageCoverageSupport;
        var afterSpace = [S.c("\u4E2D", 0), S.c(" ", 1), S.c(",", 2, null, "latin")];
        TracedAssertions.assertTrue(PunctuationGeometryStage.attachedAsciiPointMarkKinsoku(afterSpace,
            [FontRole.CjkText, FontRole.LatinText, FontRole.LatinText], afterSpace, KinsokuLevel.Basic, 100, 100)
            .decisions.length == 0);
        var gapped = [S.c("\u4E2D", 0), S.c(",", 2, 8, "latin")];
        TracedAssertions.assertTrue(PunctuationGeometryStage.attachedAsciiPointMarkKinsoku(gapped, [FontRole.CjkText, FontRole.LatinText], gapped,
            KinsokuLevel.Basic, 100, 100)
            .decisions.length == 0);
        var objectBase = [S.obj(0), S.c(",", 1, 8, "latin")];
        TracedAssertions.assertTrue(PunctuationGeometryStage.attachedAsciiPointMarkKinsoku(objectBase, [FontRole.Unknown, FontRole.LatinText], objectBase,
            KinsokuLevel.Basic, 100, 100)
            .decisions.length == 0);
        var plain = [S.c("\u4E2D", 0), S.c("a", 1, 8, "latin")];
        TracedAssertions.assertTrue(PunctuationGeometryStage.attachedAsciiPointMarkKinsoku(plain, [FontRole.CjkText, FontRole.LatinText], plain,
            KinsokuLevel.Basic, 100, 100)
            .decisions.length == 0);
        var cjkMark = [S.c("\u4E2D", 0), S.c("\uFF0C", 1)];
        TracedAssertions.assertTrue(PunctuationGeometryStage.attachedAsciiPointMarkKinsoku(cjkMark, [FontRole.CjkText, FontRole.CjkPunctuation], cjkMark,
            KinsokuLevel.Basic, 100, 100)
            .decisions.length == 0);
    }

    @:test public static function attachedAsciiPointMarksNeedAContiguousNonSpaceBase():Void {
        PunctuationGeometryStageCoverageSupport.start("attachedAsciiPointMarksNeedAContiguousNonSpaceBase");
        var S = PunctuationGeometryStageCoverageSupport;
        var c = [S.c("\u4E2D", 0), S.c(",", 1, 8, "latin")];
        TracedAssertions.assertTrue(PunctuationGeometryStage.isAttachedAsciiPointMarkAt(c, 1));
        TracedAssertions.assertTrue(!PunctuationGeometryStage.isAttachedAsciiPointMarkAt(c, 0));
        var emptyMark = [S.c("\u4E2D", 0), S.c("", 1, 8, "latin")];
        TracedAssertions.assertTrue(!PunctuationGeometryStage.isAttachedAsciiPointMarkAt(emptyMark, 1));
        var plainLetter = [S.c("\u4E2D", 0), S.c("a", 1, 8, "latin")];
        TracedAssertions.assertTrue(!PunctuationGeometryStage.isAttachedAsciiPointMarkAt(plainLetter, 1));
        var afterSpace = [S.c("\u4E2D", 0), S.c(" ", 1, 8, "latin")];
        TracedAssertions.assertTrue(!PunctuationGeometryStage.isAttachedAsciiPointMarkAt(afterSpace, 1));
        var gapped = [S.c("\u4E2D", 0), S.c(",", 2, 8, "latin")];
        TracedAssertions.assertTrue(!PunctuationGeometryStage.isAttachedAsciiPointMarkAt(gapped, 1));
    }

    @:test public static function attachedMarksAcceptAsciiPointMarksAfterObjects():Void {
        PunctuationGeometryStageCoverageSupport.start("attachedMarksAcceptAsciiPointMarksAfterObjects");
        var S = PunctuationGeometryStageCoverageSupport;
        var c = [S.obj(0), S.c(",", 1, null, "latin")];
        var r = PunctuationGeometryStage.inlineObjectAttachedMarks(c, [FontRole.Unknown, FontRole.LatinText], KinsokuLevel.Basic, new ClreqKinsokuRule())[0];
        TracedAssertions.assertEqualsInt(1, r.markClusterIndex);
        TracedAssertions.assertTrue(r.separatorClusterIndices.length == 0);
    }

    @:test public static function attachedMarksCollapseSeparatorSpaceBeforeTheMark():Void {
        PunctuationGeometryStageCoverageSupport.start("attachedMarksCollapseSeparatorSpaceBeforeTheMark");
        var S = PunctuationGeometryStageCoverageSupport;
        var c = [S.obj(0), S.c(" ", 1, null, "latin"), S.c("\uFF0C", 2)];
        var roles = [FontRole.Unknown, FontRole.LatinText, FontRole.CjkPunctuation];
        var rule = new ClreqKinsokuRule();
        var r = PunctuationGeometryStage.inlineObjectAttachedMarks(c, roles, KinsokuLevel.Basic, rule)[0];
        TracedAssertions.assertEqualsInt(0, r.objectClusterIndex);
        TracedAssertions.assertEqualsIntArray([1], r.separatorClusterIndices);
        TracedAssertions.assertEqualsInt(2, r.markClusterIndex);
        TracedAssertions.assertTrue(PunctuationGeometryStage.inlineObjectAttachedMarks(c, roles, KinsokuLevel.None, rule).length == 0);
    }

    @:test public static function attachedMarksRejectMissingObjectsAndGappedRanges():Void {
        PunctuationGeometryStageCoverageSupport.start("attachedMarksRejectMissingObjectsAndGappedRanges");
        var S = PunctuationGeometryStageCoverageSupport;
        var rule = new ClreqKinsokuRule();
        var noObject = [S.c("\u4E2D", 0), S.c("\uFF0C", 1)];
        TracedAssertions.assertTrue(PunctuationGeometryStage.inlineObjectAttachedMarks(noObject, [FontRole.CjkText, FontRole.CjkPunctuation],
            KinsokuLevel.Basic, rule)
            .length == 0);
        var onlySpaces = [S.c(" ", 0, null, "latin"), S.c(" ", 1, null, "latin"), S.c("\uFF0C", 2)];
        TracedAssertions.assertTrue(PunctuationGeometryStage.inlineObjectAttachedMarks(onlySpaces,
            [FontRole.LatinText, FontRole.LatinText, FontRole.CjkPunctuation], KinsokuLevel.Basic, rule)
            .length == 0);
        var gapped = [S.obj(0), S.c("\uFF0C", 2)];
        TracedAssertions.assertTrue(PunctuationGeometryStage.inlineObjectAttachedMarks(gapped, [FontRole.Unknown, FontRole.CjkPunctuation],
            KinsokuLevel.Basic, rule)
            .length == 0);
        var plain = [S.obj(0), S.c("a", 1, 8, "latin")];
        TracedAssertions.assertTrue(PunctuationGeometryStage.inlineObjectAttachedMarks(plain, [FontRole.Unknown, FontRole.LatinText], KinsokuLevel.Basic, rule)
            .length == 0);
    }

    @:test public static function attachedRunsOwnOneVirtualGapAtTheirTrailingEdge():Void {
        PunctuationGeometryStageCoverageSupport.start("attachedRunsOwnOneVirtualGapAtTheirTrailingEdge");
        var S = PunctuationGeometryStageCoverageSupport;
        var c = [S.c("\u4E2D", 0), S.c("ref", 1, 16, "latin"), S.c("a", 2, 8, "latin")];
        var attachments = [InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None];
        var edges = [
            S.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide),
            S.e(EastAsianSpacingValue.Other, EastAsianSpacingValue.Wide),
            S.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var r = PunctuationGeometryStage.applyAutoSpacePolicy(c, edges, attachments, AutoSpacePolicy.Default, 16);
        TracedAssertions.assertEqualsString("trailing", r.decisions[0].side);
        TracedAssertions.assertEqualsString("InlineAttachment.Previous", r.decisions[0].boundaryRole);
        TracedAssertions.assertEqualsString("AttachedInlineVirtualAutoSpace:east-asian-spacing-W-N", r.decisions[0].reason);
        TracedAssertions.assertEqualsFloat(18, r.clusters[1].advance);
        TracedAssertions.assertEqualsFloat(8, r.clusters[2].advance);
    }

    @:test public static function emptyDisplayTextProducesNoAtoms():Void {
        PunctuationGeometryStageCoverageSupport.start("emptyDisplayTextProducesNoAtoms");
        TracedAssertions.assertTrue(PunctuationGeometryStageCoverageSupport.atoms(PunctuationGeometryStageCoverageSupport.c("\n", 0, null, "mandatory-break",
            ""), [])
            .length == 0);
    }

    @:test public static function glyphlessClustersUseThePurePolicyPath():Void {
        PunctuationGeometryStageCoverageSupport.start("glyphlessClustersUseThePurePolicyPath");
        var a = PunctuationGeometryStageCoverageSupport.atoms(PunctuationGeometryStageCoverageSupport.c("\uFF0C", 0), [])[0];
        TracedAssertions.assertEqualsString("ProfileGlueFallbackWithoutFontGeometry", a.geometrySource);
        TracedAssertions.assertEqualsRendered("-", a.inkBoundsFallback == null ? "-" : a.inkBoundsFallback);
        TracedAssertions.assertEqualsFloat(8, a.trailingGlue.natural);
    }

    @:test public static function inlineBoxSpansAddStructuralEdgesAndSkipDegenerateRanges():Void {
        PunctuationGeometryStageCoverageSupport.start("inlineBoxSpansAddStructuralEdgesAndSkipDegenerateRanges");
        var S = PunctuationGeometryStageCoverageSupport;
        var c = [S.c("a", 0, 8, "latin"), S.c("b", 1, 8, "latin"), S.c("c", 2, 8, "latin")];
        var passthrough = PunctuationGeometryStage.applyInlineBoxSpans(c, []);
        TracedAssertions.assertTrue(passthrough.clusters == c);
        var fromEmpty = PunctuationGeometryStage.applyInlineBoxSpans([], [new InlineBoxSpan(new TextRange(0, 1), 2)]);
        TracedAssertions.assertTrue(fromEmpty.clusters.length == 0);
        var skipped = PunctuationGeometryStage.applyInlineBoxSpans(c, [
            new InlineBoxSpan(new TextRange(2, 2), 4),
            new InlineBoxSpan(new TextRange(10, 11), 4)
        ]);
        TracedAssertions.assertTrue(skipped.decisions.length == 0);
        TracedAssertions.assertTrue(skipped.advanceByCluster.size() == 0);
        var applied = PunctuationGeometryStage.applyInlineBoxSpans(c, [
            new InlineBoxSpan(new TextRange(0, 1), 2),
            new InlineBoxSpan(new TextRange(1, 2), null, 3),
            new InlineBoxSpan(new TextRange(0, 2), null, 1.5)
        ]);
        TracedAssertions.assertEqualsInt(3, applied.decisions.length);
        TracedAssertions.assertEqualsRendered(S.renderFloatMap(S.floatMap([0, 1], [2, 4.5])), S.renderFloatMap(applied.advanceByCluster));
        TracedAssertions.assertEqualsFloat(10, applied.clusters[0].advance);
        TracedAssertions.assertEqualsFloat(2, applied.clusters[0].leadingLayoutAdvance);
        TracedAssertions.assertEqualsFloat(12.5, applied.clusters[1].advance);
        TracedAssertions.assertEqualsFloat(8, applied.clusters[2].advance);
        TracedAssertions.assertEqualsFloat(0, applied.clusters[2].leadingLayoutAdvance);
        var clamped = [S.c("a", 0, 2, "latin")];
        var clampedResult = PunctuationGeometryStage.applyInlineBoxSpans(clamped, [new InlineBoxSpan(new TextRange(0, 1), null, -6)]);
        TracedAssertions.assertEqualsFloat(0, clampedResult.clusters[0].advance);
    }

    @:test public static function inlineObjectKinsokuProtectsOrHangsAttachedMarks():Void {
        PunctuationGeometryStageCoverageSupport.start("inlineObjectKinsokuProtectsOrHangsAttachedMarks");
        var S = PunctuationGeometryStageCoverageSupport;
        var c = [S.obj(0), S.c("\uFF0C", 1)];
        var a = [new InlineObjectAttachedMark(0, [], 1)];
        TracedAssertions.assertFailsWith(null, () -> PunctuationGeometryStage.inlineObjectAttachedKinsoku(c, a, [c[1]], KinsokuLevel.Basic, 100, 100));
        var disabled = PunctuationGeometryStage.inlineObjectAttachedKinsoku(c, a, c, KinsokuLevel.None, 100, 100);
        TracedAssertions.assertTrue(disabled.unbreakableRanges.length == 0);
        var fits = PunctuationGeometryStage.inlineObjectAttachedKinsoku(c, a, c, KinsokuLevel.Basic, 100, 100);
        TracedAssertions.assertEqualsRendered("[[0, 1]]", S.renderRanges(fits.unbreakableRanges));
        TracedAssertions.assertEqualsIntSet(S.setInts([1]), fits.forbiddenLineStartClusters);
        TracedAssertions.assertEqualsString("InlineObjectAttachedKinsoku", fits.decisions[0].reason);
        TracedAssertions.assertEqualsInt(1, fits.decisions[0].clusterIndex);
        var hangs = PunctuationGeometryStage.inlineObjectAttachedKinsoku(c, a, c, KinsokuLevel.Basic, 10, 10);
        TracedAssertions.assertTrue(hangs.unbreakableRanges.length == 0);
        TracedAssertions.assertEqualsIntSet(S.setInts([1]), hangs.impossibleMeasureHangEligibleClusters);
        TracedAssertions.assertEqualsRendered("[[0, 1]]", S.renderRanges(hangs.extendableHangRanges));
        var colon = [S.obj(0), S.c("\uFF1A", 1)];
        var colonMarks = [new InlineObjectAttachedMark(0, [], 1)];
        var blocked = PunctuationGeometryStage.inlineObjectAttachedKinsoku(colon, colonMarks, colon, KinsokuLevel.Basic, 10, 10);
        TracedAssertions.assertTrue(blocked.unbreakableRanges.length == 0);
        TracedAssertions.assertTrue(blocked.extendableHangRanges.length == 0);
        TracedAssertions.assertEqualsInt(1, blocked.decisions.length);
        var pair = [S.obj(0), S.c("\uFF0C\u3002", 1, 16, "cjk", "\uFF0C\u3002")];
        var pairMarks = [new InlineObjectAttachedMark(0, [], 1)];
        var noHang = PunctuationGeometryStage.inlineObjectAttachedKinsoku(pair, pairMarks, pair, KinsokuLevel.Basic, 10, 10);
        TracedAssertions.assertTrue(noHang.extendableHangRanges.length == 0);
        var firstLineFits = PunctuationGeometryStage.inlineObjectAttachedKinsoku(c, a, c, KinsokuLevel.Basic, 5, 100);
        TracedAssertions.assertEqualsRendered("[[0, 1]]", S.renderRanges(firstLineFits.unbreakableRanges));
        var withSeparator = [S.obj(0), S.c(" ", 1, null, "latin"), S.c("\uFF0C", 2)];
        var separatorMarks = [new InlineObjectAttachedMark(0, [1], 2)];
        var separated = PunctuationGeometryStage.inlineObjectAttachedKinsoku(withSeparator, separatorMarks, withSeparator, KinsokuLevel.Basic, 100, 100);
        TracedAssertions.assertEqualsIntSet(S.setInts([1, 2]), separated.forbiddenLineStartClusters);
        TracedAssertions.assertEqualsString("InlineObjectAttachedKinsokuAcrossCollapsedSeparatorSpace", separated.decisions[0].reason);
    }

    @:test public static function multipleGlyphsForOneCharacterUnionIntoASingleInkBox():Void {
        PunctuationGeometryStageCoverageSupport.start("multipleGlyphsForOneCharacterUnionIntoASingleInkBox");
        var a = PunctuationGeometryStageCoverageSupport.atoms(PunctuationGeometryStageCoverageSupport.c("\uFF0C", 0), [
            PunctuationGeometryStageCoverageSupport.g(1, 8, 0, new Rect(0, 0, 8, 16)),
            PunctuationGeometryStageCoverageSupport.g(2, 6, 8, new Rect(0, 0, 6, 16))
        ])[0];
        TracedAssertions.assertEqualsFloat(14, a.inkBounds.width);
        TracedAssertions.assertEqualsFloat(16, a.inkBounds.bottom);
        TracedAssertions.assertEqualsFloat(16, a.advance);
        TracedAssertions.assertEqualsRendered("-", a.inkBoundsFallback == null ? "-" : a.inkBoundsFallback);
    }

    @:test public static function narrowInlineBoxesOwnTheirOuterAutoSpace():Void {
        PunctuationGeometryStageCoverageSupport.start("narrowInlineBoxesOwnTheirOuterAutoSpace");
        var S = PunctuationGeometryStageCoverageSupport;
        var c = [S.c("\u4E2D", 0), S.c("a", 1, 8, "latin")];
        var edges = [
            S.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide),
            S.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var r = PunctuationGeometryStage.applyAutoSpacePolicy(c, edges, S.none(2), AutoSpacePolicy.Default, 16, S.setInts([1]));
        TracedAssertions.assertEqualsString("InlineBox.Narrow", r.decisions[0].boundaryRole);
        TracedAssertions.assertEqualsString("InlineBoxOuterAutoSpace:leading-W-N", r.decisions[0].reason);
        var tc = [S.c("a", 0, 8, "latin"), S.c("\u4E2D", 1)];
        var te = [
            S.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            S.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide)
        ];
        var tr = PunctuationGeometryStage.applyAutoSpacePolicy(tc, te, S.none(2), AutoSpacePolicy.Default, 16, null, S.setInts([0]));
        TracedAssertions.assertEqualsString("InlineBox.Narrow", tr.decisions[0].boundaryRole);
        TracedAssertions.assertEqualsString("InlineBoxOuterAutoSpace:trailing-N-W", tr.decisions[0].reason);
    }

    @:test public static function perCharacterInkSubtractsPrecedingGlyphPens():Void {
        PunctuationGeometryStageCoverageSupport.start("perCharacterInkSubtractsPrecedingGlyphPens");
        var a = PunctuationGeometryStageCoverageSupport.atoms(PunctuationGeometryStageCoverageSupport.c("\u3002\uFF0C", 0), [
            PunctuationGeometryStageCoverageSupport.g(1, 16, 0, new Rect(2, 0, 14, 16)),
            PunctuationGeometryStageCoverageSupport.g(2, 16, 16, new Rect(2, 0, 14, 16))
        ]);
        TracedAssertions.assertEqualsInt(2, a.length);
        TracedAssertions.assertEqualsRendered("TextRange(start=0, end=1)", Std.string(a[0].range));
        TracedAssertions.assertEqualsRendered("TextRange(start=1, end=2)", Std.string(a[1].range));
        TracedAssertions.assertEqualsFloat(12, a[0].inkBounds.width);
        TracedAssertions.assertEqualsFloat(12, a[1].inkBounds.width);
        TracedAssertions.assertTrue(a[0].inkBoundsFallback == null && a[1].inkBoundsFallback == null);
    }

    @:test public static function spaceReplacementSkipsDisabledModeNullBoundariesAndExactWidths():Void {
        PunctuationGeometryStageCoverageSupport.start("spaceReplacementSkipsDisabledModeNullBoundariesAndExactWidths");
        var S = PunctuationGeometryStageCoverageSupport;
        var c = [S.c("\u4E2D", 0), S.c(" ", 1, null, "latin"), S.c("a", 2, 8, "latin")];
        var edges = [
            S.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide),
            S.e(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other),
            S.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var disabled = PunctuationGeometryStage.applyAutoSpacePolicy(c, edges, S.none(3), AutoSpacePolicy.Disabled, 16);
        TracedAssertions.assertTrue(disabled.decisions.length == 0);
        TracedAssertions.assertEqualsFloat(16, disabled.clusters[1].advance);
        var replace = new AutoSpacePolicy(AutoSpaceMode.Replace, AutoSpaceMode.Replace);
        var exactWidth = [S.c("\u4E2D", 0), S.c(" ", 1, 2, "latin"), S.c("a", 2, 8, "latin")];
        var exact = PunctuationGeometryStage.applyAutoSpacePolicy(exactWidth, edges, S.none(3), replace, 16);
        TracedAssertions.assertTrue(exact.decisions.length == 0);
        var lone = [S.c(" ", 0, 16, "latin")];
        var loneEdges = [S.e(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other)];
        var loneResult = PunctuationGeometryStage.applyAutoSpacePolicy(lone, loneEdges, S.none(1), replace, 16);
        TracedAssertions.assertTrue(loneResult.decisions.length == 0);
        TracedAssertions.assertFailsWith(null,
            () -> PunctuationGeometryStage.applyAutoSpacePolicy(c, [S.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide)], S.none(3), replace, 16));
        TracedAssertions.assertFailsWith(null, () -> PunctuationGeometryStage.applyAutoSpacePolicy(c, edges, [InlineAttachment.None], replace, 16));
        var emptyC:Array<Cluster> = [];
        var emptyE:Array<EastAsianSpacingEdges> = [];
        var emptyA:Array<InlineAttachment> = [];
        var empty = PunctuationGeometryStage.applyAutoSpacePolicy(emptyC, emptyE, emptyA, replace, 16);
        TracedAssertions.assertTrue(empty.clusters.length == 0);
    }

    @:test public static function spacingBoundariesCountEachWideNarrowGapOnce():Void {
        PunctuationGeometryStageCoverageSupport.start("spacingBoundariesCountEachWideNarrowGapOnce");
        var S = PunctuationGeometryStageCoverageSupport;
        var pairWn = [S.c("\u4E2D", 0), S.c("a", 1, 16, "latin")];
        var pairWnEdges = [
            S.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide),
            S.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        TracedAssertions.assertTrue(PunctuationGeometryStage.isEastAsianSpacingBoundaryAt(1, pairWn, pairWnEdges));
        var pairNw = [S.c("a", 0, 16, "latin"), S.c("\u4E2D", 1)];
        var pairNwEdges = [
            S.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            S.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide)
        ];
        TracedAssertions.assertTrue(PunctuationGeometryStage.isEastAsianSpacingBoundaryAt(1, pairNw, pairNwEdges));
        var spaceRight = [S.c("\u4E2D", 0), S.c(" ", 1, 16, "latin"), S.c("a", 2, 16, "latin")];
        var spaceRightEdges = [
            S.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide),
            S.e(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other),
            S.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        TracedAssertions.assertTrue(PunctuationGeometryStage.isEastAsianSpacingBoundaryAt(1, spaceRight, spaceRightEdges));
        var spaceLeft = [S.c("a", 0, 16, "latin"), S.c(" ", 1, 16, "latin"), S.c("\u4E2D", 2)];
        var spaceLeftEdges = [
            S.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            S.e(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other),
            S.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide)
        ];
        TracedAssertions.assertTrue(PunctuationGeometryStage.isEastAsianSpacingBoundaryAt(2, spaceLeft, spaceLeftEdges));
        var cjkPair = [S.c("\u4E2D", 0), S.c("\u4E2D", 1)];
        var cjkPairEdges = [
            S.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide),
            S.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide)
        ];
        TracedAssertions.assertTrue(!PunctuationGeometryStage.isEastAsianSpacingBoundaryAt(1, cjkPair, cjkPairEdges));
    }

    @:test public static function typedSpaceBetweenWideAndNarrowIsReplacedByTheGap():Void {
        PunctuationGeometryStageCoverageSupport.start("typedSpaceBetweenWideAndNarrowIsReplacedByTheGap");
        var S = PunctuationGeometryStageCoverageSupport;
        var c = [S.c("\u4E2D", 0), S.c(" ", 1, null, "latin"), S.c("a", 2, 8, "latin")];
        var edges = [
            S.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide),
            S.e(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other),
            S.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var r = PunctuationGeometryStage.applyAutoSpacePolicy(c, edges, S.none(3), new AutoSpacePolicy(AutoSpaceMode.Replace, AutoSpaceMode.Replace), 16);
        TracedAssertions.assertEqualsString("gap", r.decisions[0].side);
        TracedAssertions.assertEqualsString("Replace", r.decisions[0].mode);
        TracedAssertions.assertEqualsString("EastAsianSpacing.Wide", r.decisions[0].boundaryRole);
        TracedAssertions.assertEqualsString("TextAutoSpaceReplace:east-asian-spacing-W-space-N", r.decisions[0].reason);
        TracedAssertions.assertEqualsInt(1, r.decisions[0].charactersAffected);
        TracedAssertions.assertEqualsFloat(14, r.decisions[0].reductionPerChar);
        TracedAssertions.assertEqualsFloat(14, r.decisions[0].totalReduction);
        TracedAssertions.assertEqualsFloat(2, r.clusters[1].advance);
    }

    @:test public static function unionWithoutBoundsFallsBackToTheFirstGlyph():Void {
        PunctuationGeometryStageCoverageSupport.start("unionWithoutBoundsFallsBackToTheFirstGlyph");
        var a = PunctuationGeometryStageCoverageSupport.atoms(PunctuationGeometryStageCoverageSupport.c("\uFF0C", 0), [
            PunctuationGeometryStageCoverageSupport.g(1, 8),
            PunctuationGeometryStageCoverageSupport.g(2, 6, 8)
        ])[0];
        TracedAssertions.assertEqualsString("shaper-no-ink-bounds", a.inkBoundsFallback);
        TracedAssertions.assertEqualsFloat(16, a.advance);
        TracedAssertions.assertEqualsFloat(8, a.bodyWidth);
        TracedAssertions.assertEqualsFloat(8, a.trailingGlue.natural);
    }

    @:test public static function unmatchedGlyphCountsRecordTheAmbiguousFallback():Void {
        PunctuationGeometryStageCoverageSupport.start("unmatchedGlyphCountsRecordTheAmbiguousFallback");
        var a = PunctuationGeometryStageCoverageSupport.atoms(PunctuationGeometryStageCoverageSupport.c("\u3002\uFF0C", 0), [
            PunctuationGeometryStageCoverageSupport.g(1, 8),
            PunctuationGeometryStageCoverageSupport.g(2, 8),
            PunctuationGeometryStageCoverageSupport.g(3, 8)
        ]);
        TracedAssertions.assertEqualsInt(2, a.length);
        TracedAssertions.assertTrue(a[0].inkBoundsFallback == "glyph-cluster-mapping-ambiguous"
            && a[1].inkBoundsFallback == "glyph-cluster-mapping-ambiguous");
        TracedAssertions.assertTrue(a[0].inkBounds == null && a[1].inkBounds == null);
        TracedAssertions.assertEqualsFloat(16, a[0].advance);
    }

    @:test public static function virtualGapsRespectNarrowToWideEdgesAndTheirNeighbours():Void {
        PunctuationGeometryStageCoverageSupport.start("virtualGapsRespectNarrowToWideEdgesAndTheirNeighbours");
        var S = PunctuationGeometryStageCoverageSupport;
        var attachments = [InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None];
        var reversed = [S.c("a", 0, 8, "latin"), S.c("ref", 1, 16, "latin"), S.c("\u4E2D", 2)];
        var reversedEdges = [
            S.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            S.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Other),
            S.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide)
        ];
        var reversedResult = PunctuationGeometryStage.applyAutoSpacePolicy(reversed, reversedEdges, attachments, AutoSpacePolicy.Default, 16);
        TracedAssertions.assertEqualsInt(1, reversedResult.decisions.length);
        TracedAssertions.assertEqualsString("AttachedInlineVirtualAutoSpace:east-asian-spacing-W-N", reversedResult.decisions[0].reason);
        var spaceAfter = [S.c("\u4E2D", 0), S.c("ref", 1, 16, "latin"), S.c(" ", 2, 16, "latin")];
        var spaceAfterEdges = [
            S.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide),
            S.e(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other),
            S.e(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other)
        ];
        TracedAssertions.assertTrue(PunctuationGeometryStage.applyAutoSpacePolicy(spaceAfter, spaceAfterEdges, attachments, AutoSpacePolicy.Default, 16)
            .decisions.length == 0);
        var breakAfter = [
            S.c("\u4E2D", 0),
            S.c("ref", 1, 16, "latin"),
            S.c("\n", 2, 16, "mandatory-break", "")
        ];
        TracedAssertions.assertTrue(PunctuationGeometryStage.applyAutoSpacePolicy(breakAfter, spaceAfterEdges, attachments, AutoSpacePolicy.Default, 16)
            .decisions.length == 0);
        var cjkAfter = [S.c("\u4E2D", 0), S.c("ref", 1, 16, "latin"), S.c("\u4E2D", 2)];
        var cjkAfterEdges = [
            S.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide),
            S.e(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other),
            S.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide)
        ];
        TracedAssertions.assertTrue(PunctuationGeometryStage.applyAutoSpacePolicy(cjkAfter, cjkAfterEdges, attachments, AutoSpacePolicy.Default, 16)
            .decisions.length == 0);
    }

    @:test public static function wideToNarrowBoundariesInsertLeadingAndTrailingGaps():Void {
        PunctuationGeometryStageCoverageSupport.start("wideToNarrowBoundariesInsertLeadingAndTrailingGaps");
        var S = PunctuationGeometryStageCoverageSupport;
        var leading = [S.c("\u4E2D", 0), S.c("a", 1, 8, "latin")];
        var leadingEdges = [
            S.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide),
            S.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ];
        var leadingResult = PunctuationGeometryStage.applyAutoSpacePolicy(leading, leadingEdges, S.none(2), AutoSpacePolicy.Default, 16);
        TracedAssertions.assertEqualsString("leading", leadingResult.decisions[0].side);
        TracedAssertions.assertEqualsString("EastAsianSpacing.Wide", leadingResult.decisions[0].boundaryRole);
        TracedAssertions.assertEqualsString("TextAutoSpaceInsert:east-asian-spacing-W-N", leadingResult.decisions[0].reason);
        TracedAssertions.assertEqualsFloat(-2, leadingResult.decisions[0].totalReduction);
        TracedAssertions.assertEqualsFloat(10, leadingResult.clusters[1].advance);
        var trailing = [S.c("a", 0, 8, "latin"), S.c("\u4E2D", 1)];
        var trailingEdges = [
            S.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            S.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide)
        ];
        var trailingResult = PunctuationGeometryStage.applyAutoSpacePolicy(trailing, trailingEdges, S.none(2), AutoSpacePolicy.Default, 16);
        TracedAssertions.assertEqualsString("trailing", trailingResult.decisions[0].side);
        TracedAssertions.assertEqualsFloat(10, trailingResult.clusters[0].advance);
    }
}
