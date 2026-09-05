package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.font.FontRole;
import org.tiqian.layout.PunctuationModel.PunctuationAtom;
import org.tiqian.layout.PunctuationModel.PunctuationAtomBuilder;
import org.tiqian.layout.PunctuationModel.PunctuationInkInput;
import org.tiqian.layout.PunctuationModel.PunctuationSpacingAdjustment;
import org.tiqian.layout.PunctuationModel.Glue;
import org.tiqian.layout.PunctuationModel.PunctuationSpacingAdjustment;
import org.tiqian.layout.PunctuationModel.Glue;
import org.tiqian.layout.PunctuationModel.PunctuationSpacingCompressionResult;
import org.tiqian.layout.PunctuationGeometryStage.InlineObjectAttachedMark;

using org.tiqian.layout.PunctuationGeometryStage;

import org.tiqian.test.trace.*;
import org.tiqian.layout.KinsokuRule.ClreqKinsokuRule;

using std.RecordCopy;

@:test class PunctuationGeometryBranchArmsCoverageTest {
    @:test public static function haltAdvanceIsRejectedAtZeroAndAtFullWidth():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("haltAdvanceIsRejectedAtZeroAndAtFullWidth");
        var b = new PunctuationAtomBuilder();
        var z = b.build('，', new TextRange(0, 1), PunctuationGeometryBranchArmsCoverageTestSupport.E, new PunctuationInkInput(16, null, 0));
        TracedAssertions.assertEqualsNullableFloat(null, z.haltAdvance);
        TracedAssertions.assertEqualsString("ProfileGlueFallbackWithoutFontGeometry", z.geometrySource);
        var f = b.build('，', new TextRange(0, 1), PunctuationGeometryBranchArmsCoverageTestSupport.E, new PunctuationInkInput(16, null, 16));
        TracedAssertions.assertEqualsNullableFloat(null, f.haltAdvance);
        TracedAssertions.assertEqualsString("ProfileGlueFallbackWithoutFontGeometry", f.geometrySource);
    }

    @:test public static function nonFiniteHaltPlacementIsIgnored():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("nonFiniteHaltPlacementIsIgnored");
        var b = new PunctuationAtomBuilder();
        var a = b.build('·', new TextRange(0, 1), PunctuationGeometryBranchArmsCoverageTestSupport.E,
            new PunctuationInkInput(16, new Rect(8, 4, 16, 12), 8, Math.NaN));
        TracedAssertions.assertEqualsString("FontHaltAdvanceWithInkBoundsFittedPlacement", a.geometrySource);
        var x = b.build('，', new TextRange(0, 1), PunctuationGeometryBranchArmsCoverageTestSupport.E, new PunctuationInkInput(16, null, 8, Math.NaN));
        TracedAssertions.assertEqualsString("FontHaltAdvanceWithProfileFallback", x.geometrySource);
        TracedAssertions.assertEqualsFloat(8, x.trailingGlue.natural);
    }

    @:test public static function unionIgnoresGlyphsWithoutBounds():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("unionIgnoresGlyphsWithoutBounds");
        var c = new Cluster(new TextRange(0, 1), "，", "cjk", 16, "，");
        var gs = [
            new Glyph(1, new TextRange(0, 1), 8, 0, 0, null, new Rect(0, 0, 8, 16)),
            new Glyph(2, new TextRange(0, 1), 6, 8, 0, null, null)
        ];
        var a = PunctuationGeometryStage.punctuationAtoms(c, 16, new PunctuationAtomBuilder(), gs, PunctuationGluePlacement.MainlandSimplified,
            new PunctuationWidthPolicy())[0];
        TracedAssertions.assertEqualsFloat(8, a.inkBounds.width);
        TracedAssertions.assertEqualsFloat(16, a.advance);
    }

    @:test public static function attachedMarkWalkStopsMidRunAtAGap():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("attachedMarkWalkStopsMidRunAtAGap");
        var r = new ClreqKinsokuRule();
        var g = [
            PunctuationGeometryBranchArmsCoverageTestSupport.o(0),
            PunctuationGeometryBranchArmsCoverageTestSupport.c(" ", 1, 16, "latin"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c(" ", 2, 16, "latin"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("，", 4)
        ];
        TracedAssertions.assertTrue(g.inlineObjectAttachedMarks([
            FontRole.Unknown,
            FontRole.LatinText,
            FontRole.LatinText,
            FontRole.CjkPunctuation
        ], KinsokuLevel.Basic, r).length == 0);
        var q = [
            PunctuationGeometryBranchArmsCoverageTestSupport.o(0),
            PunctuationGeometryBranchArmsCoverageTestSupport.c(" ", 1, 16, "latin"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c(" ", 2, 16, "latin"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("，", 3)
        ];
        var m = q.inlineObjectAttachedMarks([
            FontRole.Unknown,
            FontRole.LatinText,
            FontRole.LatinText,
            FontRole.CjkPunctuation
        ], KinsokuLevel.Basic, r)[0];
        TracedAssertions.assertEqualsIntArray([1, 2], m.separatorClusterIndices);
        TracedAssertions.assertEqualsInt(3, m.markClusterIndex);
    }

    @:test public static function emptyTextClustersCannotBeAttachedMarks():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("emptyTextClustersCannotBeAttachedMarks");
        var cs = [
            PunctuationGeometryBranchArmsCoverageTestSupport.o(0),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("", 1, null, "latin")
        ];
        var r = new ClreqKinsokuRule();
        TracedAssertions.assertTrue(cs.inlineObjectAttachedMarks([FontRole.Unknown, FontRole.LatinText], KinsokuLevel.Basic, r).length == 0);
        var x = cs.inlineObjectAttachedKinsoku([new InlineObjectAttachedMark(0, [], 1)], cs, KinsokuLevel.Basic, 10, 10);
        TracedAssertions.assertTrue(x.extendableHangRanges.length == 0);
        TracedAssertions.assertTrue(x.impossibleMeasureHangEligibleClusters.size() == 0);
        TracedAssertions.assertEqualsInt(1, x.decisions.length);
    }

    @:test public static function asciiPointMarkKinsokuSkipsEmptyTextClusters():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("asciiPointMarkKinsokuSkipsEmptyTextClusters");
        var r = new ClreqKinsokuRule();
        var a = [
            PunctuationGeometryBranchArmsCoverageTestSupport.c("中", 0),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("", 1, "latin", "x")
        ];
        TracedAssertions.assertTrue(a.attachedAsciiPointMarkKinsoku([FontRole.CjkText, FontRole.LatinText], a, KinsokuLevel.Basic, 100, 100)
            .decisions.length == 0);
        var b = [
            PunctuationGeometryBranchArmsCoverageTestSupport.c("", 0, null, "latin", "x"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c(",", 0, null, "latin")
        ];
        TracedAssertions.assertTrue(b.attachedAsciiPointMarkKinsoku([FontRole.LatinText, FontRole.LatinText], b, KinsokuLevel.Basic, 100, 100)
            .decisions.length == 0);
        var d = [
            PunctuationGeometryBranchArmsCoverageTestSupport.c("中", 0),
            PunctuationGeometryBranchArmsCoverageTestSupport.c(",", 1, 8, "latin"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("", 2, null, "latin", "x")
        ];
        var dr = d.attachedAsciiPointMarkKinsoku([FontRole.CjkText, FontRole.LatinText, FontRole.LatinText], d, KinsokuLevel.Basic, 100, 100);
        TracedAssertions.assertEqualsRendered("[[0, 1]]", PunctuationGeometryBranchArmsCoverageTestSupport.render(dr.unbreakableRanges));
        TracedAssertions.assertEqualsInt(1, dr.decisions.length);
        var e = [
            PunctuationGeometryBranchArmsCoverageTestSupport.c("中", 0),
            PunctuationGeometryBranchArmsCoverageTestSupport.c(",", 1, 8, "latin"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c(",", 3, 8, "latin")
        ];
        var er = e.attachedAsciiPointMarkKinsoku([FontRole.CjkText, FontRole.LatinText, FontRole.LatinText], e, KinsokuLevel.Basic, 100, 100);
        TracedAssertions.assertEqualsRendered("[[0, 1]]", PunctuationGeometryBranchArmsCoverageTestSupport.render(er.unbreakableRanges));
        TracedAssertions.assertEqualsInt(1, er.decisions.length);
    }

    @:test public static function spaceRunRequiresNonEmptyAllSpaceText():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("spaceRunRequiresNonEmptyAllSpaceText");
        TracedAssertions.assertTrue(PunctuationGeometryBranchArmsCoverageTestSupport.c(" ", 0, 16, "latin").isSpaceRun());
        TracedAssertions.assertTrue(PunctuationGeometryBranchArmsCoverageTestSupport.c("  ", 0, 16, "latin").isSpaceRun());
        TracedAssertions.assertFalse(PunctuationGeometryBranchArmsCoverageTestSupport.c("", 0, "latin", " ").isSpaceRun());
        TracedAssertions.assertFalse(PunctuationGeometryBranchArmsCoverageTestSupport.c("a b", 0, 16, "latin").isSpaceRun());
        TracedAssertions.assertFalse(PunctuationGeometryBranchArmsCoverageTestSupport.c("中", 0).isSpaceRun());
    }

    @:test public static function attachedRunAtParagraphEndEmitsNoAutoSpace():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("attachedRunAtParagraphEndEmitsNoAutoSpace");
        var x = [
            PunctuationGeometryBranchArmsCoverageTestSupport.c("中", 0),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("r", 1, 16, "latin")
        ];
        var r = x.applyAutoSpacePolicy([
            PunctuationGeometryBranchArmsCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide),
            PunctuationGeometryBranchArmsCoverageTestSupport.e(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other)
        ], [InlineAttachment.None, InlineAttachment.Previous], AutoSpacePolicy.Default,
            16);
        TracedAssertions.assertTrue(r.decisions.length == 0);
        TracedAssertions.assertEqualsFloat(16, r.clusters[1].advance);
    }

    @:test public static function virtualGapWithEmptyPreviousTextHasNoNarrowCharacter():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("virtualGapWithEmptyPreviousTextHasNoNarrowCharacter");
        var x = [
            PunctuationGeometryBranchArmsCoverageTestSupport.c("", 0, "latin", "y"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("r", 1, 16, "latin"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("中", 2)
        ];
        var a = [
            PunctuationGeometryBranchArmsCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            PunctuationGeometryBranchArmsCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Other),
            PunctuationGeometryBranchArmsCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide)
        ];
        var r = x.applyAutoSpacePolicy(a, [InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None], AutoSpacePolicy.Default, 16);
        TracedAssertions.assertTrue(r.decisions.length == 0);
        TracedAssertions.assertTrue(r.decisions.length == 0);
    }

    @:test public static function typedSpaceWithEmptyTextNeighboursKeepsItsWidth():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("typedSpaceWithEmptyTextNeighboursKeepsItsWidth");
        var x = [
            PunctuationGeometryBranchArmsCoverageTestSupport.c("中", 0),
            PunctuationGeometryBranchArmsCoverageTestSupport.c(" ", 1, 16, "latin"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("", 2, null, "latin", "y")
        ];
        var r = x.applyAutoSpacePolicy([
            PunctuationGeometryBranchArmsCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide),
            PunctuationGeometryBranchArmsCoverageTestSupport.e(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other),
            PunctuationGeometryBranchArmsCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow)
        ],
            [InlineAttachment.None, InlineAttachment.None, InlineAttachment.None], AutoSpacePolicy.Default, 16);
        TracedAssertions.assertTrue(r.decisions.length == 0);
        TracedAssertions.assertEqualsFloat(16, r.clusters[1].advance);
        var y = [
            PunctuationGeometryBranchArmsCoverageTestSupport.c("", 0, 16, "latin", "y"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c(" ", 1, 16, "latin"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("中", 2)
        ];
        var z = y.applyAutoSpacePolicy([
            PunctuationGeometryBranchArmsCoverageTestSupport.e(EastAsianSpacingValue.Narrow, EastAsianSpacingValue.Narrow),
            PunctuationGeometryBranchArmsCoverageTestSupport.e(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other),
            PunctuationGeometryBranchArmsCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide)
        ],
            [InlineAttachment.None, InlineAttachment.None, InlineAttachment.None], AutoSpacePolicy.Default, 16);
        TracedAssertions.assertTrue(z.decisions.length == 0);
        var w = [
            PunctuationGeometryBranchArmsCoverageTestSupport.c("中", 0),
            PunctuationGeometryBranchArmsCoverageTestSupport.c(" ", 1, 16, "latin"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("中", 2)
        ];
        var wr = w.applyAutoSpacePolicy([
            PunctuationGeometryBranchArmsCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide),
            PunctuationGeometryBranchArmsCoverageTestSupport.e(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other),
            PunctuationGeometryBranchArmsCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide)
        ],
            [InlineAttachment.None, InlineAttachment.None, InlineAttachment.None], AutoSpacePolicy.Default, 16);
        TracedAssertions.assertTrue(wr.decisions.length == 0);
        TracedAssertions.assertEqualsFloat(16, wr.clusters[1].advance);
    }

    @:test public static function spacingBoundariesAtListEdgesAreFalse():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("spacingBoundariesAtListEdgesAreFalse");
        TracedAssertions.assertFalse(PunctuationGeometryStage.isEastAsianSpacingBoundaryAt(1, [
            PunctuationGeometryBranchArmsCoverageTestSupport.c("中", 0),
            PunctuationGeometryBranchArmsCoverageTestSupport.c(" ", 1, 16, "latin")
        ], [
            PunctuationGeometryBranchArmsCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide),
            PunctuationGeometryBranchArmsCoverageTestSupport.e(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other)
        ]));
        TracedAssertions.assertFalse(PunctuationGeometryStage.isEastAsianSpacingBoundaryAt(1, [
            PunctuationGeometryBranchArmsCoverageTestSupport.c(" ", 0, 16, "latin"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("中", 1)
        ], [
            PunctuationGeometryBranchArmsCoverageTestSupport.e(EastAsianSpacingValue.Other, EastAsianSpacingValue.Other),
            PunctuationGeometryBranchArmsCoverageTestSupport.e(EastAsianSpacingValue.Wide, EastAsianSpacingValue.Wide)
        ]));
    }

    @:test public static function attachedAsciiPointMarkCheckSkipsEmptyPreviousText():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("attachedAsciiPointMarkCheckSkipsEmptyPreviousText");
        TracedAssertions.assertFalse([
            PunctuationGeometryBranchArmsCoverageTestSupport.c("", 0, null, "latin", "x"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c(",", 0, null, "latin")
        ].isAttachedAsciiPointMarkAt(1));
    }

    @:test public static function inlineBoxSpanWithZeroNetStructuralEdgeStillAppliesLeading():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("inlineBoxSpanWithZeroNetStructuralEdgeStillAppliesLeading");
        var r = [PunctuationGeometryBranchArmsCoverageTestSupport.c("a", 0, 8, "latin")].applyInlineBoxSpans([
            new InlineBoxSpan(new TextRange(0, 1), 2),
            new InlineBoxSpan(new TextRange(0, 1), 0, -2)
        ]);
        TracedAssertions.assertEqualsFloat(8, r.clusters[0].advance);
        TracedAssertions.assertEqualsFloat(2, r.clusters[0].leadingLayoutAdvance);
        TracedAssertions.assertTrue(r.advanceByCluster.size() == 0);
        TracedAssertions.assertEqualsInt(2, r.decisions.length);
    }

    @:test public static function resolveClustersAppliesGlyphShiftWithUnchangedAdvance():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("resolveClustersAppliesGlyphShiftWithUnchangedAdvance");
        var cs = [PunctuationGeometryBranchArmsCoverageTestSupport.c("「", 0, 16, "cjk")];
        var aa = PunctuationGeometryStage.punctuationAtoms(cs[0], 16, new PunctuationAtomBuilder(),
            [new Glyph(1, new TextRange(0, 1), 8, 0, 0, null, new Rect(0, 0, 8, 16))], PunctuationGluePlacement.MainlandSimplified,
            new PunctuationWidthPolicy());
        var r = PunctuationGeometryLedger.from(cs, aa, new PunctuationSpacingCompressionResult([])).resolveClusters();
        TracedAssertions.assertEqualsFloat(16, r[0].advance);
        TracedAssertions.assertEqualsFloat(8, r[0].glyphInlineShift);
    }

    @:test public static function glueCapacitiesMarkCentredFramesAsPaired():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("glueCapacitiesMarkCentredFramesAsPaired");
        var cs = [PunctuationGeometryBranchArmsCoverageTestSupport.c("，", 0)];
        var aa = PunctuationGeometryStage.punctuationAtoms(cs[0], 16, new PunctuationAtomBuilder(), [], PunctuationGluePlacement.Traditional,
            new PunctuationWidthPolicy());
        var cap = PunctuationGeometryLedger.from(cs, aa, new PunctuationSpacingCompressionResult([])).glueCapacities().get(0);
        TracedAssertions.assertTrue(cap.paired);
        TracedAssertions.assertEqualsFloat(4, cap.leading);
        TracedAssertions.assertEqualsFloat(4, cap.trailing);
    }

    @:test public static function attachedBoundaryWithPlainPreviousClusterKeepsTheRightBudget():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("attachedBoundaryWithPlainPreviousClusterKeepsTheRightBudget");
        var cs = [
            PunctuationGeometryBranchArmsCoverageTestSupport.c("中", 0),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("r", 1, 16, "latin"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("「", 2, 16, "cjk")
        ];
        var aa = PunctuationGeometryBranchArmsCoverageTestSupport.atoms(cs);
        var r = PunctuationGeometryLedger.from(cs, aa, new PunctuationSpacingCompressionResult([]))
            .resolveAttachedInlinePunctuationBoundaries([InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None], aa, 16);
        TracedAssertions.assertTrue(r.decisions.length == 0);
        TracedAssertions.assertTrue(r.trailingGlueByCluster.size() == 0);
        TracedAssertions.assertEqualsFloat(16, r.geometry.resolveClusters()[2].advance);
    }

    @:test public static function attachedBoundaryRecordsNullCharactersForEmptyTextClusters():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("attachedBoundaryRecordsNullCharactersForEmptyTextClusters");
        var cs = [
            PunctuationGeometryBranchArmsCoverageTestSupport.c("」", 0),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("r", 1, 16, "latin"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("", 4, 16, "latin", "a")
        ];
        var aa = PunctuationGeometryBranchArmsCoverageTestSupport.atoms(cs);
        var r = PunctuationGeometryLedger.from(cs, aa, new PunctuationSpacingCompressionResult([]))
            .resolveAttachedInlinePunctuationBoundaries([InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None], aa, 16);
        TracedAssertions.assertEqualsString("\u0000", r.decisions[0].rightChar);
        TracedAssertions.assertEqualsString("AttachedInlineVirtualPunctuationBoundary:natural", r.decisions[0].reason);
        TracedAssertions.assertEqualsFloat(8, r.trailingGlueByCluster.get(1));
        var ps = [
            PunctuationGeometryBranchArmsCoverageTestSupport.c("", 0, 16, "latin", "」"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("r", 1, 16, "latin"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("「", 4)
        ];
        var pr = PunctuationGeometryLedger.from(ps, PunctuationGeometryBranchArmsCoverageTestSupport.atoms(ps), new PunctuationSpacingCompressionResult([]))
            .resolveAttachedInlinePunctuationBoundaries([InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None],
                PunctuationGeometryBranchArmsCoverageTestSupport.atoms(ps), 16);
        TracedAssertions.assertEqualsString("\u0000", pr.decisions[0].leftChar);
        TracedAssertions.assertEqualsString("AttachedInlineVirtualPunctuationBoundary:adjacent-punctuation", pr.decisions[0].reason);
    }

    @:test public static function attachedTrailingGlueWidensABudgetedEndCluster():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("attachedTrailingGlueWidensABudgetedEndCluster");
        var cs = [
            PunctuationGeometryBranchArmsCoverageTestSupport.c("」", 0),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("」", 1),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("「", 2, 16, "cjk")
        ];
        var aa = PunctuationGeometryBranchArmsCoverageTestSupport.atoms(cs);
        var widened = aa.copy();
        widened[0] = widened[0].copy(trailingGlue = widened[0].trailingGlue.copy(natural = 12, max = 12));
        var r = PunctuationGeometryLedger.from(cs, widened, new PunctuationSpacingCompressionResult([]))
            .resolveAttachedInlinePunctuationBoundaries([InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None], widened, 16);
        TracedAssertions.assertEqualsFloat(4, r.trailingGlueByCluster.get(1));
        TracedAssertions.assertEqualsFloat(20, r.geometry.resolveClusters()[1].advance);
    }

    @:test public static function spacingPlanIgnoresTargetsOutsideTheBudgets():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("spacingPlanIgnoresTargetsOutsideTheBudgets");
        var cs = [
            PunctuationGeometryBranchArmsCoverageTestSupport.c("中", 0),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("。", 1)
        ];
        var aa = PunctuationGeometryBranchArmsCoverageTestSupport.atoms(cs);
        var s = [
            new PunctuationSpacingAdjustment(new TextRange(0, 2), new TextRange(0, 1), '中', '。', 8, 0, 8, "test-stray")
        ];
        var m = PunctuationGeometryLedger.from(cs, aa, new PunctuationSpacingCompressionResult(s)).glueCapacities();
        TracedAssertions.assertFalse(m.has(0));
        TracedAssertions.assertEqualsFloat(8, m.get(1).trailing);
    }

    @:test public static function centredAdjacencyConsumesBothSidesEqually():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("centredAdjacencyConsumesBothSidesEqually");
        var cs = [
            PunctuationGeometryBranchArmsCoverageTestSupport.c("，", 0),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("，", 1)
        ];
        var aa:Array<PunctuationAtom> = [];
        for (x in cs)
            for (a in PunctuationGeometryStage.punctuationAtoms(x, 16, new PunctuationAtomBuilder(), [], PunctuationGluePlacement.Traditional,
                new PunctuationWidthPolicy()))
                aa.push(a);
        var m = PunctuationGeometryLedger.from(cs, aa, new PunctuationModel.PunctuationSpacingCompressor().compress(aa, 16)).glueCapacities();
        TracedAssertions.assertTrue(!m.has(0));
        TracedAssertions.assertEqualsFloat(4, m.get(1).leading);
        var r = PunctuationGeometryLedger.from(cs, aa, new PunctuationModel.PunctuationSpacingCompressor().compress(aa, 16)).resolveClusters();
        TracedAssertions.assertEqualsFloat(8, r[0].advance);
        TracedAssertions.assertEqualsFloat(16, r[1].advance);
    }

    @:test public static function attachedBoundaryReasonFallsBackToNaturalWithoutLeftAtom():Void {
        PunctuationGeometryBranchArmsCoverageTestSupport.t("attachedBoundaryReasonFallsBackToNaturalWithoutLeftAtom");
        var cs = [
            PunctuationGeometryBranchArmsCoverageTestSupport.c("」", 0),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("r", 1, 16, "latin"),
            PunctuationGeometryBranchArmsCoverageTestSupport.c("「", 2, 16, "cjk")
        ];
        var aa = PunctuationGeometryBranchArmsCoverageTestSupport.atoms(cs);
        var r = PunctuationGeometryLedger.from(cs, aa, new PunctuationSpacingCompressionResult([]))
            .resolveAttachedInlinePunctuationBoundaries([InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None], [], 16);
        TracedAssertions.assertEqualsString("AttachedInlineVirtualPunctuationBoundary:natural", r.decisions[0].reason);
        TracedAssertions.assertEqualsString("」", r.decisions[0].leftChar);
        TracedAssertions.assertEqualsFloat(8, r.trailingGlueByCluster.get(1));
    }
}

class PunctuationGeometryBranchArmsCoverageTestSupport {
    public static function t(n:String):Void
        new TestTraceRecorder("PunctuationGeometryBranchArmsCoverageTest").section(n);

    public static inline var E:Float = 16;

    public static function c(s:String, i:Int, ?advance:Float = 16, ?font:String = "cjk", ?display:String = null):Cluster
        return new Cluster(new TextRange(i, i + s.length), s, font, advance, display == null ? s : display);

    public static function o(i:Int):Cluster
        return c("x", i, 8, "inline-object", "");

    public static function e(a:EastAsianSpacingValue, b:EastAsianSpacingValue):EastAsianSpacingEdges
        return new EastAsianSpacingEdges(a, b, a == EastAsianSpacingValue.Wide);

    public static function atoms(cs:Array<Cluster>):Array<PunctuationAtom> {
        var r:Array<PunctuationAtom> = [];
        for (x in cs)
            for (a in PunctuationGeometryStage.punctuationAtoms(x, 16, new PunctuationAtomBuilder(), [], PunctuationGluePlacement.MainlandSimplified,
                new PunctuationWidthPolicy()))
                r.push(a);
        return r;
    }

    public static function render(rs:Array<IntRange>):String {
        var s = "[";
        for (i in 0...rs.length) {
            if (i > 0)
                s += ", ";
            s += "[" + rs[i].start + ", " + rs[i].end + "]";
        }
        return s + "]";
    }
}
