package org.tiqian.layout;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import org.tiqian.test.trace.TestTraceRender;
import org.tiqian.clreq.GlueSide;
import org.tiqian.clreq.InteriorPunctuationStyle;
import org.tiqian.clreq.PunctuationGluePlacement;
import org.tiqian.clreq.PunctuationWidthPolicy;
import org.tiqian.clreq.PunctuationClass;
import org.tiqian.core.Rect;
import org.tiqian.core.TextRange;
import org.tiqian.layout.PunctuationModel.Glue;
import org.tiqian.layout.PunctuationModel.PunctuationAtom;
import org.tiqian.layout.PunctuationModel.PunctuationInkInput;
import org.tiqian.layout.PunctuationModel.PunctuationAtomBuilder;
import org.tiqian.layout.PunctuationModel.PunctuationSpacingCompressor;
import org.tiqian.layout.PunctuationModel.PunctuationSpacingCompressionResult;
import org.tiqian.layout.PunctuationModel.PunctuationSpacingAdjustment;
import org.tiqian.layout.PunctuationModel.AdjustmentOpportunity;
import org.tiqian.layout.PunctuationModel.PunctuationAnchor;
import org.tiqian.layout.PunctuationModel.GlueKind;
import org.tiqian.clreq.PunctuationGluePlacements;

using std.RecordCopy;

class PunctuationModelCoverageTest {
    @:test public static function glueRejectsInvertedBounds():Void {
        PunctuationModelCoverageSupport.start("glueRejectsInvertedBounds");
        TracedAssertions.assertFailsWith(null, function() new Glue(PunctuationTrailing, 2, 1, 3, 0, 0));
        TracedAssertions.assertFailsWith(null, function() new Glue(PunctuationTrailing, 0, 3, 1, 0, 0));
    }

    @:test public static function adjustmentOpportunityCarriesRangeAndGlue():Void {
        PunctuationModelCoverageSupport.start("adjustmentOpportunityCarriesRangeAndGlue");
        final o = new AdjustmentOpportunity(new TextRange(1, 2), PunctuationModelCoverageSupport.glue(4));
        PunctuationModelCoverageSupport.eqr(Std.string(new TextRange(1, 2)), Std.string(o.range));
        PunctuationModelCoverageSupport.eqf(4, o.glue.natural);
    }

    @:test public static function compressionResultSumsAdjustmentReductions():Void {
        PunctuationModelCoverageSupport.start("compressionResultSumsAdjustmentReductions");
        final r = new PunctuationSpacingCompressionResult([
            new PunctuationSpacingAdjustment(new TextRange(0, 2), new TextRange(0, 1), "。", "「", 16, 8, 8, "test-a"),
            new PunctuationSpacingAdjustment(new TextRange(2, 4), new TextRange(2, 3), "，", "「", 8, 4, 4, "test-b")
        ]);
        PunctuationModelCoverageSupport.eqf(12, r.totalReduction);
        PunctuationModelCoverageSupport.eqf(0, new PunctuationSpacingCompressionResult([]).totalReduction);
    }

    @:test public static function adjacentPunctuationInnerGlueCollapsesByHalfEm():Void {
        PunctuationModelCoverageSupport.start("adjacentPunctuationInnerGlueCollapsesByHalfEm");
        final stop = PunctuationModelCoverageSupport.atom("。", 0), opening = PunctuationModelCoverageSupport.atom("「", 1);
        final r = new PunctuationSpacingCompressor().compress([stop, opening], PunctuationModelCoverageSupport.em);
        TracedAssertions.assertEqualsInt(1, r.adjustments.length);
        final a = r.adjustments[0];
        PunctuationModelCoverageSupport.eqf(16, a.naturalInnerGlue);
        PunctuationModelCoverageSupport.eqf(8, a.adjustedInnerGlue);
        PunctuationModelCoverageSupport.eqf(8, a.reduction);
        PunctuationModelCoverageSupport.eqr(Std.string(stop.range), Std.string(a.reductionTargetRange));
        PunctuationModelCoverageSupport.eqs("。", a.leftChar);
        PunctuationModelCoverageSupport.eqs("「", a.rightChar);
        PunctuationModelCoverageSupport.eqs("collapse-adjacent-punctuation-inner-glue", a.reason);
        PunctuationModelCoverageSupport.eqr(Std.string(new TextRange(0, 2)), Std.string(a.range));
    }

    @:test public static function adjacentPunctuationTargetsTheWiderSide():Void {
        PunctuationModelCoverageSupport.start("adjacentPunctuationTargetsTheWiderSide");
        final stop = PunctuationModelCoverageSupport.atom("。", 0).copy(trailingGlueInitiallyConsumed = 8);
        final opening = PunctuationModelCoverageSupport.atom("「", 1);
        final r = new PunctuationSpacingCompressor().compress([stop, opening], PunctuationModelCoverageSupport.em);
        PunctuationModelCoverageSupport.eqr(Std.string(opening.range), Std.string(r.adjustments[0].reductionTargetRange));
    }

    @:test public static function adjacentPunctuationSkipsNonAdjacentZeroGlueAndZeroEm():Void {
        PunctuationModelCoverageSupport.start("adjacentPunctuationSkipsNonAdjacentZeroGlueAndZeroEm");
        final stop = PunctuationModelCoverageSupport.atom("。", 0), opening = PunctuationModelCoverageSupport.atom("「", 2);
        TracedAssertions.assertTrue(new PunctuationSpacingCompressor().compress([stop, opening], PunctuationModelCoverageSupport.em).adjustments.length == 0);
        final c = stop.copy(trailingGlueInitiallyConsumed = 8), ao = PunctuationModelCoverageSupport.atom("「", 1).copy(leadingGlueInitiallyConsumed = 8);
        TracedAssertions.assertTrue(new PunctuationSpacingCompressor().compress([c, ao], PunctuationModelCoverageSupport.em).adjustments.length == 0);
        TracedAssertions.assertTrue(new PunctuationSpacingCompressor().compress([stop], PunctuationModelCoverageSupport.em).adjustments.length == 0);
        TracedAssertions.assertTrue(new PunctuationSpacingCompressor().compress([
            PunctuationModelCoverageSupport.atom("。", 0),
            PunctuationModelCoverageSupport.atom("「", 1)
        ], 0).adjustments.length == 0);
    }

    @:test public static function cjkClosingBeforeAsciiPointMarkCollapsesTrailingGlue():Void {
        PunctuationModelCoverageSupport.start("cjkClosingBeforeAsciiPointMarkCollapsesTrailingGlue");
        final c = PunctuationModelCoverageSupport.atom("」", 0);
        final a = new PunctuationSpacingCompressor().compressCjkClosingBeforeAsciiPointMark([c], "」, rest", PunctuationModelCoverageSupport.em).adjustments[0];
        PunctuationModelCoverageSupport.eqr(Std.string(new TextRange(0, 2)), Std.string(a.range));
        PunctuationModelCoverageSupport.eqr(Std.string(c.range), Std.string(a.reductionTargetRange));
        PunctuationModelCoverageSupport.eqf(8, a.naturalInnerGlue);
        PunctuationModelCoverageSupport.eqf(0, a.adjustedInnerGlue);
        PunctuationModelCoverageSupport.eqs("」", a.leftChar);
        PunctuationModelCoverageSupport.eqs(",", a.rightChar);
        PunctuationModelCoverageSupport.eqs("collapse-cjk-closing-before-ascii-point-mark", a.reason);
    }

    @:test public static function cjkClosingCompressionRejectsNonMatchingNeighbours():Void {
        PunctuationModelCoverageSupport.start("cjkClosingCompressionRejectsNonMatchingNeighbours");
        final x = new PunctuationSpacingCompressor(), o = PunctuationModelCoverageSupport.atom("「", 0), c = PunctuationModelCoverageSupport.atom("」", 0);
        TracedAssertions.assertTrue(x.compressCjkClosingBeforeAsciiPointMark([o], "「, x", PunctuationModelCoverageSupport.em).adjustments.length == 0);
        TracedAssertions.assertTrue(x.compressCjkClosingBeforeAsciiPointMark([c], "」", PunctuationModelCoverageSupport.em).adjustments.length == 0);
        TracedAssertions.assertTrue(x.compressCjkClosingBeforeAsciiPointMark([c], "」中", PunctuationModelCoverageSupport.em).adjustments.length == 0);
        TracedAssertions.assertTrue(x.compressCjkClosingBeforeAsciiPointMark([c.copy(trailingGlueInitiallyConsumed = 8)], "」,x",
            PunctuationModelCoverageSupport.em)
            .adjustments.length == 0);
        TracedAssertions.assertTrue(x.compressCjkClosingBeforeAsciiPointMark([c], "」,x", 0).adjustments.length == 0);
    }

    @:test public static function indexedBuildRejectsOutOfRangeIndex():Void {
        PunctuationModelCoverageSupport.start("indexedBuildRejectsOutOfRangeIndex");
        PunctuationModelCoverageSupport.nul(PunctuationModelCoverageSupport.builder.buildAtIndex("，", 5, PunctuationModelCoverageSupport.em));
        final a = PunctuationModelCoverageSupport.builder.buildAtIndex("，", 0, PunctuationModelCoverageSupport.em);
        PunctuationModelCoverageSupport.nn(a);
        PunctuationModelCoverageSupport.eqr(Std.string(new TextRange(0, 1)), Std.string(a.range));
        PunctuationModelCoverageSupport.eqs("，", a.char);
    }

    @:test public static function nonPunctuationCharactersProduceNoAtom():Void {
        PunctuationModelCoverageSupport.start("nonPunctuationCharactersProduceNoAtom");
        PunctuationModelCoverageSupport.nul(PunctuationModelCoverageSupport.atom("中"));
        PunctuationModelCoverageSupport.nul(PunctuationModelCoverageSupport.atom("a"));
    }

    @:test public static function policyFallbackSplitsGlueByClassSide():Void {
        PunctuationModelCoverageSupport.start("policyFallbackSplitsGlueByClassSide");
        final s = PunctuationModelCoverageSupport.atom("，");
        PunctuationModelCoverageSupport.eqf(0, s.leadingGlue.natural);
        PunctuationModelCoverageSupport.eqf(8, s.trailingGlue.natural);
        PunctuationModelCoverageSupport.eqr(Std.string(PunctuationAnchor.Leading), Std.string(s.anchor));
        PunctuationModelCoverageSupport.eqf(8, s.bodyWidth);
        PunctuationModelCoverageSupport.eqs("ProfileGlueFallbackWithoutFontGeometry", s.geometrySource);
        PunctuationModelCoverageSupport.nul(s.haltAdvance);
        PunctuationModelCoverageSupport.nul(s.inkContainmentBodyFloor);
        TracedAssertions.assertFalse(s.inkContainmentApplied);
        PunctuationModelCoverageSupport.nul(s.inkBoundsFallback);
        PunctuationModelCoverageSupport.nul(s.haltValidation);
        final o = PunctuationModelCoverageSupport.atom("「");
        PunctuationModelCoverageSupport.eqf(8, o.leadingGlue.natural);
        PunctuationModelCoverageSupport.eqf(0, o.trailingGlue.natural);
        PunctuationModelCoverageSupport.eqr(Std.string(PunctuationAnchor.Trailing), Std.string(o.anchor));
        final t = PunctuationModelCoverageSupport.builder.build("，", new TextRange(0, 1), PunctuationModelCoverageSupport.em, null,
            PunctuationGluePlacement.Traditional);
        PunctuationModelCoverageSupport.eqf(4, t.leadingGlue.natural);
        PunctuationModelCoverageSupport.eqf(4, t.trailingGlue.natural);
        PunctuationModelCoverageSupport.eqr(Std.string(PunctuationAnchor.Center), Std.string(t.anchor));
    }

    @:test public static function underwidthGlyphsExpandIntoFullWidthCellByClassSide():Void {
        PunctuationModelCoverageSupport.start("underwidthGlyphsExpandIntoFullWidthCellByClassSide");
        final o = PunctuationModelCoverageSupport.atom("「", 0, new PunctuationInkInput(8));
        PunctuationModelCoverageSupport.eqf(8, o.glyphInlineShift);
        PunctuationModelCoverageSupport.eqs("UnderwidthPunctuationFullWidthBoxPlacement", o.glyphPlacementReason);
        PunctuationModelCoverageSupport.eqf(8, o.advanceExpansion);
        PunctuationModelCoverageSupport.eqf(16, o.advance);
        final m = PunctuationModelCoverageSupport.atom("·", 0, new PunctuationInkInput(8));
        PunctuationModelCoverageSupport.eqf(4, m.glyphInlineShift);
        PunctuationModelCoverageSupport.eqf(8, m.advanceExpansion);
        final c = PunctuationModelCoverageSupport.atom("」", 0, new PunctuationInkInput(8));
        PunctuationModelCoverageSupport.eqf(0, c.glyphInlineShift);
        PunctuationModelCoverageSupport.nul(c.glyphPlacementReason);
        PunctuationModelCoverageSupport.eqf(8, c.advanceExpansion);
        final e = PunctuationModelCoverageSupport.atom("「", 0, new PunctuationInkInput(16));
        PunctuationModelCoverageSupport.eqf(0, e.glyphInlineShift);
        PunctuationModelCoverageSupport.nul(e.glyphPlacementReason);
        PunctuationModelCoverageSupport.eqf(0, e.advanceExpansion);
    }

    @:test public static function haltFittedCompressionUsesFontMeasurements():Void {
        PunctuationModelCoverageSupport.start("haltFittedCompressionUsesFontMeasurements");
        final a = PunctuationModelCoverageSupport.atom("·", 0, new PunctuationInkInput(16, new Rect(2, 4, 10, 12), 8, -2));
        PunctuationModelCoverageSupport.eqs("FontHaltFittedBodyCompression", a.geometrySource);
        PunctuationModelCoverageSupport.eqf(2, a.leadingGlue.natural);
        PunctuationModelCoverageSupport.eqf(6, a.trailingGlue.natural);
        PunctuationModelCoverageSupport.eqf(8, a.bodyWidth);
        PunctuationModelCoverageSupport.eqr(Std.string(PunctuationAnchor.Center), Std.string(a.anchor));
        PunctuationModelCoverageSupport.eqf(8, a.haltAdvance);
        PunctuationModelCoverageSupport.nul(a.haltValidation);
        TracedAssertions.assertFalse(a.inkContainmentApplied);
        TracedAssertions.assertNotNullRendered(a.inkContainmentBodyFloor != null, TestTraceRender.cap(Std.string(a.inkContainmentBodyFloor)));
    }

    @:test public static function haltTrimIsLimitedByInkBoundsAndRecordsWhy():Void {
        PunctuationModelCoverageSupport.start("haltTrimIsLimitedByInkBoundsAndRecordsWhy");
        final a = PunctuationModelCoverageSupport.atom("·", 0, new PunctuationInkInput(16, new Rect(2, 4, 14, 12), 8, -2));
        PunctuationModelCoverageSupport.eqf(2, a.leadingGlue.natural);
        PunctuationModelCoverageSupport.eqf(2, a.trailingGlue.natural);
        TracedAssertions.assertTrue(a.inkContainmentApplied);
        PunctuationModelCoverageSupport.eqs("halt-trim-limited-by-default-ink-bounds", a.haltValidation);
    }

    @:test public static function haltAdvanceWithoutPlacementFallsBackToFittedInkOrProfile():Void {
        PunctuationModelCoverageSupport.start("haltAdvanceWithoutPlacementFallsBackToFittedInkOrProfile");
        final i = PunctuationModelCoverageSupport.atom("·", 0, new PunctuationInkInput(16, new Rect(8, 4, 16, 12), 8));
        PunctuationModelCoverageSupport.eqs("FontHaltAdvanceWithInkBoundsFittedPlacement", i.geometrySource);
        final p = PunctuationModelCoverageSupport.atom("，", 0, new PunctuationInkInput(16, null, 8));
        PunctuationModelCoverageSupport.eqs("FontHaltAdvanceWithProfileFallback", p.geometrySource);
        PunctuationModelCoverageSupport.eqf(0, p.leadingGlue.natural);
        PunctuationModelCoverageSupport.eqf(8, p.trailingGlue.natural);
    }

    @:test public static function haltFromProportionalGlyphIsRejected():Void {
        PunctuationModelCoverageSupport.start("haltFromProportionalGlyphIsRejected");
        final a = PunctuationModelCoverageSupport.atom("「", 0, new PunctuationInkInput(8, null, 4, -2));
        PunctuationModelCoverageSupport.nul(a.haltAdvance);
        PunctuationModelCoverageSupport.eqf(8, a.glyphInlineShift);
        PunctuationModelCoverageSupport.eqs("UnderwidthPunctuationFullWidthBoxPlacement", a.glyphPlacementReason);
    }

    @:test public static function inkBoundsFittedFramePicksTheNarrowestContainingAnchor():Void {
        PunctuationModelCoverageSupport.start("inkBoundsFittedFramePicksTheNarrowestContainingAnchor");
        final r = PunctuationModelCoverageSupport.atom("」", 0, new PunctuationInkInput(16, new Rect(8, 4, 16, 12)));
        PunctuationModelCoverageSupport.eqr(Std.string(PunctuationAnchor.Trailing), Std.string(r.anchor));
        PunctuationModelCoverageSupport.eqf(8, r.leadingGlue.natural);
        PunctuationModelCoverageSupport.eqf(0, r.trailingGlue.natural);
        PunctuationModelCoverageSupport.eqs("InkBoundsFittedBodyCompression", r.geometrySource);
        TracedAssertions.assertFalse(r.inkContainmentApplied);
        final l = PunctuationModelCoverageSupport.atom("「", 0, new PunctuationInkInput(16, new Rect(0, 4, 8, 12)));
        PunctuationModelCoverageSupport.eqr(Std.string(PunctuationAnchor.Leading), Std.string(l.anchor));
        PunctuationModelCoverageSupport.eqf(0, l.leadingGlue.natural);
        PunctuationModelCoverageSupport.eqf(8, l.trailingGlue.natural);
        final w = PunctuationModelCoverageSupport.atom("」", 0, new PunctuationInkInput(16, new Rect(1, 4, 15, 12)));
        TracedAssertions.assertTrue(w.inkContainmentApplied);
        PunctuationModelCoverageSupport.eqf(14, w.inkContainmentBodyFloor);
    }

    @:test public static function forcedHalfWidthConnectorsConsumeGlueUpFront():Void {
        PunctuationModelCoverageSupport.start("forcedHalfWidthConnectorsConsumeGlueUpFront");
        final h = PunctuationModelCoverageSupport.atom("-");
        PunctuationModelCoverageSupport.eqf(8, h.advance);
        PunctuationModelCoverageSupport.eqf(8, h.bodyWidth);
        TracedAssertions.assertTrue(StringTools.endsWith(h.geometrySource, "FixedHalfWidth"));
        PunctuationModelCoverageSupport.eqf(0, h.leadingGlueInitiallyConsumed);
        PunctuationModelCoverageSupport.eqf(0, h.trailingGlueInitiallyConsumed);
        final d = PunctuationModelCoverageSupport.builder.build("·", new TextRange(0, 1), PunctuationModelCoverageSupport.em, null, null,
            new PunctuationWidthPolicy(null, true));
        TracedAssertions.assertTrue(StringTools.endsWith(d.geometrySource, "FixedHalfWidth"));
        PunctuationModelCoverageSupport.eqf(4, d.leadingGlueInitiallyConsumed);
        PunctuationModelCoverageSupport.eqf(4, d.trailingGlueInitiallyConsumed);
        final k = PunctuationModelCoverageSupport.builder.build("，", new TextRange(0, 1), PunctuationModelCoverageSupport.em, null, null,
            new PunctuationWidthPolicy(Kaiming));
        TracedAssertions.assertTrue(StringTools.endsWith(k.geometrySource, "FixedHalfWidth"));
        PunctuationModelCoverageSupport.eqf(8, k.trailingGlueInitiallyConsumed);
        final ks = PunctuationModelCoverageSupport.builder.build("。", new TextRange(0, 1), PunctuationModelCoverageSupport.em, null, null,
            new PunctuationWidthPolicy(Kaiming));
        TracedAssertions.assertFalse(StringTools.endsWith(ks.geometrySource, "FixedHalfWidth"));
    }

    @:test public static function inkInputRecordsWhyBoundsAreMissing():Void {
        PunctuationModelCoverageSupport.start("inkInputRecordsWhyBoundsAreMissing");
        final a = PunctuationModelCoverageSupport.atom("，", 0, new PunctuationInkInput(16, null, null, null, "shaper-no-ink-bounds"));
        PunctuationModelCoverageSupport.eqs("shaper-no-ink-bounds", a.inkBoundsFallback);
        PunctuationModelCoverageSupport.nul(a.inkBounds);
        final b = PunctuationModelCoverageSupport.atom("，", 0, new PunctuationInkInput(0, null, null, null, "glyph-cluster-mapping-ambiguous"));
        PunctuationModelCoverageSupport.eqs("glyph-cluster-mapping-ambiguous", b.inkBoundsFallback);
        PunctuationModelCoverageSupport.eqf(16, b.advance);
    }

    @:test public static function glueSideForMainlandSimplifiedMapsClassesToSides():Void {
        PunctuationModelCoverageSupport.start("glueSideForMainlandSimplifiedMapsClassesToSides");
        PunctuationModelCoverageSupport.eqr(Std.string(LeadingOnly), Std.string(PunctuationGluePlacements.glueSideFor(MainlandSimplified, Opening)));
        PunctuationModelCoverageSupport.eqr(Std.string(TrailingOnly), Std.string(PunctuationGluePlacements.glueSideFor(MainlandSimplified, Closing)));
        PunctuationModelCoverageSupport.eqr(Std.string(TrailingOnly), Std.string(PunctuationGluePlacements.glueSideFor(MainlandSimplified, PauseOrStop)));
        PunctuationModelCoverageSupport.eqr(Std.string(BothSides), Std.string(PunctuationGluePlacements.glueSideFor(MainlandSimplified, MiddleDot)));
        PunctuationModelCoverageSupport.eqr(Std.string(BothSides), Std.string(PunctuationGluePlacements.glueSideFor(Traditional, Opening)));
    }
}

/** Shared fixtures and traced-assertion helpers for PunctuationModelCoverageTest; the Kotlin test-class lowering admits test functions only. */
class PunctuationModelCoverageSupport {
    public static final em:Float = 16.0;
    public static final builder = new PunctuationAtomBuilder();

    public static function start(n:String):Void
        new TestTraceRecorder("PunctuationModelCoverageTest").section(n);

    public static function glue(n:Float):Glue
        return new Glue(PunctuationTrailing, 0, n, n, 0, 0);

    public static function atom(c:String, ?s:Int, ?ink:PunctuationInkInput):PunctuationAtom {
        final i = s == null ? 0 : s;
        return builder.build(c, new TextRange(i, i + 1), em, ink);
    }

    public static function nul<T>(v:Null<T>):Void
        TracedAssertions.assertNullRendered(v == null, "-");

    public static function nn(v:Null<PunctuationAtom>):Void
        TracedAssertions.assertNotNullRendered(v != null, v == null ? "-" : TestTraceRender.cap(Std.string(v)));

    public static function eqf(e:Float, a:Float):Void
        TracedAssertions.assertEqualsFloat(e, a);

    public static function eqs(e:String, a:String):Void
        TracedAssertions.assertEqualsString(e, a);

    public static function eqr(e:String, a:String):Void
        TracedAssertions.assertEqualsRendered(e, a);
}
