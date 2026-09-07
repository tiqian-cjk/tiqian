package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.layout.PunctuationModel.PunctuationAtomBuilder;
import org.tiqian.layout.PunctuationModel.PunctuationAtom;
import org.tiqian.layout.PunctuationModel.Glue;
import org.tiqian.clreq.PunctuationGluePlacement;
import org.tiqian.clreq.PunctuationWidthPolicy;
import org.tiqian.layout.PunctuationModel.PunctuationSpacingCompressor;
import org.tiqian.layout.PunctuationModel.PunctuationSpacingAdjustment;
import org.tiqian.layout.PunctuationModel.PunctuationSpacingCompressionResult;
import org.tiqian.layout.PunctuationModel.PunctuationInkInput;
import org.tiqian.test.trace.*;
import std.SortedMap;
import std.SortedSet;

using std.RecordCopy;

@:test class PunctuationGeometryLedgerCoverageTest {
    @:test public static function budgetsResolveAdvancesThroughRemainingGlue():Void {
        PunctuationGeometryLedgerCoverageSupport.start("budgetsResolveAdvancesThroughRemainingGlue");
        var x = PunctuationGeometryLedgerCoverageSupport.ledger(["。", "「", "中"]);
        var resolved = x.resolveClusters();
        TracedAssertions.assertEqualsFloat(8, resolved[0].advance);
        TracedAssertions.assertEqualsFloat(16, resolved[1].advance);
        TracedAssertions.assertEqualsFloat(16, resolved[2].advance);
        TracedAssertions.assertTrue(resolved[2] == x.resolveClusters()[2]);
    }

    @:test public static function glueCapacitiesReportSidesAndPairing():Void {
        PunctuationGeometryLedgerCoverageSupport.start("glueCapacitiesReportSidesAndPairing");
        var m = PunctuationGeometryLedgerCoverageSupport.ledger(["。", "「"]).glueCapacities();
        var ek = SortedSet.builder();
        ek.put(1);
        var ak = SortedSet.builder();
        for (i in 0...m.size())
            ak.put(m.keyAt(i));
        TracedAssertions.assertEqualsIntSet(ek.build(), ak.build());
        TracedAssertions.assertEqualsFloat(8, m.get(1).leading);
        TracedAssertions.assertEqualsFloat(0, m.get(1).trailing);
        TracedAssertions.assertEqualsRendered("false", m.get(1).paired ? "true" : "false");
    }

    @:test public static function sideConsumptionIsCappedAndSkipsNonPositiveAmounts():Void {
        PunctuationGeometryLedgerCoverageSupport.start("sideConsumptionIsCappedAndSkipsNonPositiveAmounts");
        var x = PunctuationGeometryLedgerCoverageSupport.ledger(["。", "「"])
            .consumeLeadingByCluster(PunctuationGeometryLedgerCoverageSupport.budgetAt([1], 4.0))
            .consumeLeadingByCluster(PunctuationGeometryLedgerCoverageSupport.budgetAt([1], 0.0))
            .consumeTrailingByCluster(PunctuationGeometryLedgerCoverageSupport.budgetAt([1], -1.0))
            .consumeLeadingByCluster(PunctuationGeometryLedgerCoverageSupport.budgetAt([99], 8.0))
            .glueCapacities();
        TracedAssertions.assertEqualsFloat(4, x.get(1).leading);
        var y = PunctuationGeometryLedgerCoverageSupport.ledger(["。", "「"])
            .consumeLeadingByCluster(PunctuationGeometryLedgerCoverageSupport.budgetAt([1], 100.0));
        TracedAssertions.assertTrue(!y.glueCapacities().has(1));
    }

    @:test public static function justificationDeltasAndStructuralChannelsFeedResolvedAdvance():Void {
        PunctuationGeometryLedgerCoverageSupport.start("justificationDeltasAndStructuralChannelsFeedResolvedAdvance");
        var base = PunctuationGeometryLedgerCoverageSupport.ledger(["「", "中"]);
        TracedAssertions.assertEqualsFloat(16, base.resolveClusters()[0].advance);
        var b = SortedMap.builder();
        b.put(0, 1.5);
        var justified = base.addJustificationDeltas(b.build());
        TracedAssertions.assertEqualsFloat(17.5, justified.resolveClusters()[0].advance);
        TracedAssertions.assertEqualsFloat(1.5, justified.toDecisionInfo()[0].justificationDelta);
        TracedAssertions.assertEqualsFloat(0, base.toDecisionInfo()[0].justificationDelta);
        var s = SortedMap.builder();
        s.put(0, 2.0);
        var spread = base.withRubySpread(s.build());
        TracedAssertions.assertEqualsFloat(18, spread.resolveClusters()[0].advance);
        TracedAssertions.assertEqualsFloat(2, spread.toDecisionInfo()[0].rubySpread);
        var r = SortedMap.builder();
        r.put(0, 3.0);
        var trimmed = base.withRawEdgeTrims(r.build());
        TracedAssertions.assertEqualsFloat(13, trimmed.resolveClusters()[0].advance);
        var r2 = SortedMap.builder();
        r2.put(0, 20.0);
        var trimmedTwice = trimmed.withRawEdgeTrims(r2.build());
        TracedAssertions.assertEqualsFloat(0, trimmedTwice.resolveClusters()[0].advance);
        var empty = SortedMap.builder().build();
        TracedAssertions.assertTrue(base.withRubySpread(empty) == base);
        TracedAssertions.assertTrue(base.withRawEdgeTrims(empty) == base);
        TracedAssertions.assertTrue(base.withInlineBoxAdvances(empty) == base);
        var box = SortedMap.builder();
        box.put(0, 4.0);
        var boxed = base.withInlineBoxAdvances(box.build());
        TracedAssertions.assertEqualsFloat(20, boxed.resolveClusters()[0].advance);
    }

    @:test public static function geometryWithoutBudgetFallsBackToBodyWidth():Void {
        PunctuationGeometryLedgerCoverageSupport.start("geometryWithoutBudgetFallsBackToBodyWidth");
        var x = PunctuationGeometryLedgerCoverageSupport.ledger(["「", "中"]);
        var e = SortedMap.builder().build();
        var y = new PunctuationGeometryLedger(x.naturalClusters, x.geometries, e);
        TracedAssertions.assertEqualsFloat(8, y.resolveClusters()[0].advance);
        var d = y.addJustificationDeltas(PunctuationGeometryLedgerCoverageSupport.budgetAt([0], 1))
            .withRubySpread(PunctuationGeometryLedgerCoverageSupport.budgetAt([0], 2))
            .withRawEdgeTrims(PunctuationGeometryLedgerCoverageSupport.budgetAt([0], 1));
        TracedAssertions.assertEqualsFloat(10, d.resolveClusters()[0].advance);
    }

    @:test public static function decisionInfoListsEveryGeometryWithBudgets():Void {
        PunctuationGeometryLedgerCoverageSupport.start("decisionInfoListsEveryGeometryWithBudgets");
        var i = PunctuationGeometryLedgerCoverageSupport.ledger(["。", "中"]).toDecisionInfo()[0];
        TracedAssertions.assertEqualsInt(1, PunctuationGeometryLedgerCoverageSupport.ledger(["。", "中"]).toDecisionInfo().length);
        TracedAssertions.assertEqualsRendered("TextRange(start=0, end=1)", i.range.toString());
        TracedAssertions.assertEqualsString("。", i.sourceText);
        TracedAssertions.assertEqualsFloat(16, i.baseAdvance);
        TracedAssertions.assertEqualsFloat(8, i.bodyWidth);
        TracedAssertions.assertEqualsFloat(0, i.leadingGlueNatural);
        TracedAssertions.assertEqualsFloat(8, i.trailingGlueNatural);
        TracedAssertions.assertEqualsFloat(16, i.resolvedAdvance);
        TracedAssertions.assertEqualsString("PunctuationGeometryLedger", i.source);
    }

    @:test public static function spacingPlanAdjustmentsConsumeByTargetAndAnchor():Void {
        PunctuationGeometryLedgerCoverageSupport.start("spacingPlanAdjustmentsConsumeByTargetAndAnchor");
        var cs = [
            PunctuationGeometryLedgerCoverageSupport.c("「", 0),
            PunctuationGeometryLedgerCoverageSupport.c("「", 1)
        ];
        var aa:Array<PunctuationAtom> = [];
        for (q in cs)
            for (atom in PunctuationGeometryStage.punctuationAtoms(q, PunctuationGeometryLedgerCoverageSupport.em,
                PunctuationGeometryLedgerCoverageSupport.builder, [], PunctuationGluePlacement.MainlandSimplified, new PunctuationWidthPolicy()))
                aa.push(atom);
        var stray = new PunctuationSpacingAdjustment(new TextRange(90, 91), new TextRange(90, 91), "。", "「", 8, 0, 8, "stray");
        var ek = SortedSet.builder();
        ek.put(0);
        ek.put(1);
        var ak = SortedSet.builder();
        var sm = PunctuationGeometryLedger.from(cs, aa, new PunctuationSpacingCompressionResult([stray])).glueCapacities();
        for (i in 0...sm.size())
            ak.put(sm.keyAt(i));
        TracedAssertions.assertEqualsIntSet(ek.build(), ak.build());
        var a = new PunctuationSpacingAdjustment(new TextRange(0, 1), new TextRange(0, 1), "「", "「", 8, 4, 4, "leading-side");
        var y = PunctuationGeometryLedger.from(cs, aa, new PunctuationSpacingCompressionResult([a]));
        TracedAssertions.assertEqualsFloat(4, y.glueCapacities().get(0).leading);
        TracedAssertions.assertEqualsFloat(8, y.glueCapacities().get(1).leading);
        var atom = PunctuationGeometryLedgerCoverageSupport.builder.build('·', new TextRange(0, 1), PunctuationGeometryLedgerCoverageSupport.em,
            new PunctuationInkInput(16, new Rect(2, 4, 10, 12), 8, -2));
        var ca = [
            PunctuationGeometryLedgerCoverageSupport.c("·", 0),
            PunctuationGeometryLedgerCoverageSupport.c("中", 1)
        ];
        var ct = new PunctuationSpacingAdjustment(new TextRange(0, 1), new TextRange(0, 1), "·", "中", 8, 2, 6, "centred");
        var cy = PunctuationGeometryLedger.from(ca, [atom], new PunctuationSpacingCompressionResult([ct]));
        var cap = cy.glueCapacities().get(0);
        TracedAssertions.assertTrue(cap.paired);
        TracedAssertions.assertEqualsFloat(0, cap.leading);
        TracedAssertions.assertEqualsFloat(4, cap.trailing);
    }

    @:test public static function attachedInlineBoundariesRequireAlignmentAndRunOnlyWithAttachments():Void {
        PunctuationGeometryLedgerCoverageSupport.start("attachedInlineBoundariesRequireAlignmentAndRunOnlyWithAttachments");
        var x = PunctuationGeometryLedgerCoverageSupport.ledger(["。", "中"]);
        TracedAssertions.assertFailsWith(null,
            function() x.resolveAttachedInlinePunctuationBoundaries([InlineAttachment.None], [], PunctuationGeometryLedgerCoverageSupport.em));
        var r = x.resolveAttachedInlinePunctuationBoundaries([InlineAttachment.None, InlineAttachment.None], [], PunctuationGeometryLedgerCoverageSupport.em);
        TracedAssertions.assertTrue(r.decisions.length == 0);
        TracedAssertions.assertTrue(r.trailingGlueByCluster.size() == 0);
        var p = PunctuationGeometryLedgerCoverageSupport.ledger(["中", "中"])
            .resolveAttachedInlinePunctuationBoundaries([InlineAttachment.None, InlineAttachment.Previous], [], PunctuationGeometryLedgerCoverageSupport.em);
        TracedAssertions.assertTrue(p.decisions.length == 0);
    }

    @:test public static function attachedInlineBoundaryAtLineEndConsumesTrailingGlue():Void {
        PunctuationGeometryLedgerCoverageSupport.start("attachedInlineBoundaryAtLineEndConsumesTrailingGlue");
        var x = PunctuationGeometryLedgerCoverageSupport.ledger(["」", "ref"]);
        var r = x.resolveAttachedInlinePunctuationBoundaries([InlineAttachment.None, InlineAttachment.Previous], [],
            PunctuationGeometryLedgerCoverageSupport.em);
        TracedAssertions.assertEqualsRendered("TextRange(start=0, end=4)", r.decisions[0].range.toString());
        TracedAssertions.assertEqualsString("」", r.decisions[0].leftChar);
        TracedAssertions.assertEqualsString("\u0000", r.decisions[0].rightChar);
        TracedAssertions.assertEqualsString("AttachedInlineVirtualPunctuationBoundary:line-end", r.decisions[0].reason);
        TracedAssertions.assertEqualsFloat(8, r.decisions[0].reduction);
        TracedAssertions.assertEqualsFloat(8, r.geometry.resolveClusters()[0].advance);
        TracedAssertions.assertTrue(r.trailingGlueByCluster.size() == 0);
    }

    @:test public static function attachedInlineBoundaryAdjacentPunctuationHalvesTheVirtualGlue():Void {
        PunctuationGeometryLedgerCoverageSupport.start("attachedInlineBoundaryAdjacentPunctuationHalvesTheVirtualGlue");
        var cs = [
            PunctuationGeometryLedgerCoverageSupport.c("」", 0),
            PunctuationGeometryLedgerCoverageSupport.c("ref", 1),
            PunctuationGeometryLedgerCoverageSupport.c("「", 4)
        ];
        var atoms:Array<PunctuationAtom> = [];
        for (q in cs)
            for (a in PunctuationGeometryStage.punctuationAtoms(q, PunctuationGeometryLedgerCoverageSupport.em,
                PunctuationGeometryLedgerCoverageSupport.builder, [], PunctuationGluePlacement.MainlandSimplified, new PunctuationWidthPolicy()))
                atoms.push(a);
        var r = PunctuationGeometryLedger.from(cs, atoms, new PunctuationSpacingCompressionResult([]))
            .resolveAttachedInlinePunctuationBoundaries([InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None], atoms,
                PunctuationGeometryLedgerCoverageSupport.em);
        TracedAssertions.assertEqualsString("AttachedInlineVirtualPunctuationBoundary:adjacent-punctuation", r.decisions[0].reason);
        TracedAssertions.assertEqualsFloat(16, r.decisions[0].naturalInnerGlue);
        TracedAssertions.assertEqualsFloat(8, r.decisions[0].adjustedInnerGlue);
        TracedAssertions.assertEqualsFloat(8, r.decisions[0].reduction);
        TracedAssertions.assertEqualsRendered("TextRange(start=0, end=5)", r.decisions[0].range.toString());
        var pre = PunctuationGeometryLedger.from(cs, atoms, new PunctuationSpacingCompressionResult([]))
            .consumeTrailingByCluster(PunctuationGeometryLedgerCoverageSupport.budgetAt([0], 4));
        var b = pre.resolveAttachedInlinePunctuationBoundaries([InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None], atoms,
            PunctuationGeometryLedgerCoverageSupport.em);
        TracedAssertions.assertEqualsFloat(12, b.decisions[0].naturalInnerGlue);
        TracedAssertions.assertEqualsFloat(4, b.decisions[0].adjustedInnerGlue);
        TracedAssertions.assertTrue(b.trailingGlueByCluster.size() == 0);
        TracedAssertions.assertEqualsFloat(4, b.geometry.glueCapacities().get(2).leading);
    }

    @:test public static function attachedInlineBoundaryBeforeAsciiPointMarkCollapsesLikeAdjacent():Void {
        PunctuationGeometryLedgerCoverageSupport.start("attachedInlineBoundaryBeforeAsciiPointMarkCollapsesLikeAdjacent");
        var cs = [
            PunctuationGeometryLedgerCoverageSupport.c("」", 0),
            PunctuationGeometryLedgerCoverageSupport.c("ref", 1),
            PunctuationGeometryLedgerCoverageSupport.c(",", 4)
        ];
        var atoms:Array<PunctuationAtom> = PunctuationGeometryStage.punctuationAtoms(cs[0], PunctuationGeometryLedgerCoverageSupport.em,
            PunctuationGeometryLedgerCoverageSupport.builder, [], PunctuationGluePlacement.MainlandSimplified, new PunctuationWidthPolicy());
        var r = PunctuationGeometryLedger.from(cs, atoms, new PunctuationSpacingCompressionResult([]))
            .resolveAttachedInlinePunctuationBoundaries([InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None], atoms,
                PunctuationGeometryLedgerCoverageSupport.em);
        TracedAssertions.assertEqualsString("AttachedInlineVirtualPunctuationBoundary:ascii-point-mark", r.decisions[0].reason);
        TracedAssertions.assertEqualsFloat(8, r.decisions[0].naturalInnerGlue);
        TracedAssertions.assertEqualsFloat(0, r.decisions[0].adjustedInnerGlue);
        TracedAssertions.assertEqualsString(",", r.decisions[0].rightChar);
    }

    @:test public static function attachedInlineBoundarySkipsMandatoryBreakNeighbour():Void {
        PunctuationGeometryLedgerCoverageSupport.start("attachedInlineBoundarySkipsMandatoryBreakNeighbour");
        var cs:Array<Cluster> = [
            PunctuationGeometryLedgerCoverageSupport.c("」", 0),
            PunctuationGeometryLedgerCoverageSupport.c("ref", 1, 16, "latin"),
            new Cluster(new TextRange(3, 4), "\n", "mandatory-break", 0, "")
        ];
        var atoms:Array<PunctuationAtom> = PunctuationGeometryStage.punctuationAtoms(cs[0], PunctuationGeometryLedgerCoverageSupport.em,
            PunctuationGeometryLedgerCoverageSupport.builder, [], PunctuationGluePlacement.MainlandSimplified, new PunctuationWidthPolicy());
        var x = PunctuationGeometryLedger.from(cs, atoms, new PunctuationSpacingCompressionResult([]));
        var r = x.resolveAttachedInlinePunctuationBoundaries([InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None], atoms,
            PunctuationGeometryLedgerCoverageSupport.em);
        TracedAssertions.assertEqualsString("AttachedInlineVirtualPunctuationBoundary:line-end", r.decisions[0].reason);
    }

    @:test public static function attachedInlineBoundaryWithoutGlueEmitsNoDecision():Void {
        PunctuationGeometryLedgerCoverageSupport.start("attachedInlineBoundaryWithoutGlueEmitsNoDecision");
        var cs = [
            PunctuationGeometryLedgerCoverageSupport.c("「", 0),
            PunctuationGeometryLedgerCoverageSupport.c("ref", 1, 16, "latin"),
            PunctuationGeometryLedgerCoverageSupport.c("中", 2)
        ];
        var aa:Array<PunctuationAtom> = [];
        for (q in cs)
            for (atom in PunctuationGeometryStage.punctuationAtoms(q, PunctuationGeometryLedgerCoverageSupport.em,
                PunctuationGeometryLedgerCoverageSupport.builder, [], PunctuationGluePlacement.MainlandSimplified, new PunctuationWidthPolicy()))
                aa.push(atom);
        var r = PunctuationGeometryLedger.from(cs, aa, new PunctuationSpacingCompressionResult([]))
            .resolveAttachedInlinePunctuationBoundaries([InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None], aa,
                PunctuationGeometryLedgerCoverageSupport.em);
        TracedAssertions.assertTrue(r.decisions.length == 0);
        var ccs = [
            PunctuationGeometryLedgerCoverageSupport.c("」", 0),
            PunctuationGeometryLedgerCoverageSupport.c("ref", 1, 16, "latin"),
            PunctuationGeometryLedgerCoverageSupport.c("中", 2)
        ];
        var caa:Array<PunctuationAtom> = [];
        for (q in ccs)
            for (atom in PunctuationGeometryStage.punctuationAtoms(q, PunctuationGeometryLedgerCoverageSupport.em,
                PunctuationGeometryLedgerCoverageSupport.builder, [], PunctuationGluePlacement.MainlandSimplified, new PunctuationWidthPolicy()))
                caa.push(atom);
        var n = PunctuationGeometryLedger.from(ccs, caa, new PunctuationSpacingCompressionResult([]))
            .resolveAttachedInlinePunctuationBoundaries([InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None], caa,
                PunctuationGeometryLedgerCoverageSupport.em);
        TracedAssertions.assertEqualsString("AttachedInlineVirtualPunctuationBoundary:natural", n.decisions[0].reason);
        TracedAssertions.assertEqualsFloat(8, n.decisions[0].naturalInnerGlue);
        TracedAssertions.assertEqualsFloat(8, n.decisions[0].adjustedInnerGlue);
        var wide:Array<PunctuationAtom> = [];
        for (atom in caa)
            wide.push(atom.char == "」" ? atom.copy(trailingGlue = atom.trailingGlue.copy(natural = 12, max = 12)) : atom);
        var w = PunctuationGeometryLedger.from(ccs, wide, new PunctuationSpacingCompressionResult([]))
            .resolveAttachedInlinePunctuationBoundaries([InlineAttachment.None, InlineAttachment.Previous, InlineAttachment.None], wide,
                PunctuationGeometryLedgerCoverageSupport.em);
        TracedAssertions.assertEqualsRendered("{1=12}", PunctuationGeometryLedgerCoverageSupport.floatMapText(w.trailingGlueByCluster));
        TracedAssertions.assertEqualsFloat(28, w.geometry.resolveClusters()[1].advance);
    }

    @:test public static function lineEdgeTrimConsumesHalfWidthAtEdgesAndSkipsEmptyInputs():Void {
        PunctuationGeometryLedgerCoverageSupport.start("lineEdgeTrimConsumesHalfWidthAtEdgesAndSkipsEmptyInputs");
        var x = PunctuationGeometryLedgerCoverageSupport.ledger(["」", "中"]);
        TracedAssertions.assertTrue(x.consumeLineEdgeGlue([]).decisions.length == 0);
        var plain = PunctuationGeometryLedgerCoverageSupport.ledger(["中", "中"]);
        TracedAssertions.assertTrue(plain.consumeLineEdgeGlue([PunctuationGeometryLedgerCoverageSupport.line(0, 1)]).decisions.length == 0);
        TracedAssertions.assertTrue(x.consumeLineEdgeGlue([PunctuationGeometryLedgerCoverageSupport.line(1, 0)]).decisions.length == 0);
        var r = x.consumeLineEdgeGlue([PunctuationGeometryLedgerCoverageSupport.line(0, 0)]);
        TracedAssertions.assertEqualsString("trailing", r.decisions[0].side);
        TracedAssertions.assertEqualsFloat(8, r.decisions[0].trimAmount);
        TracedAssertions.assertEqualsFloat(8, r.decisions[0].naturalGlue);
        TracedAssertions.assertEqualsString("LineEndHalfWidthPunctuation", r.decisions[0].reason);
        TracedAssertions.assertEqualsRendered("TextRange(start=0, end=1)", r.decisions[0].clusterRange.toString());
        TracedAssertions.assertEqualsFloat(8, r.geometry.resolveClusters()[0].advance);
        var relaxed = x.consumeLineEdgeGlue([PunctuationGeometryLedgerCoverageSupport.line(0, 0)], false);
        TracedAssertions.assertTrue(relaxed.decisions.length == 0);
        TracedAssertions.assertEqualsFloat(16, relaxed.geometry.resolveClusters()[0].advance);
    }

    @:test public static function lineEdgeTrimConsumesCentredPunctuationOncePerLine():Void {
        PunctuationGeometryLedgerCoverageSupport.start("lineEdgeTrimConsumesCentredPunctuationOncePerLine");
        var atom:PunctuationAtom = PunctuationGeometryLedgerCoverageSupport.builder.build('·', new TextRange(0, 1),
            PunctuationGeometryLedgerCoverageSupport.em, new PunctuationInkInput(16, new Rect(2, 4, 10, 12), 8, -2));
        var x = PunctuationGeometryLedger.from([PunctuationGeometryLedgerCoverageSupport.c("·", 0)], [atom], new PunctuationSpacingCompressionResult([]));
        var r = x.consumeLineEdgeGlue([PunctuationGeometryLedgerCoverageSupport.line(0, 0)]);
        TracedAssertions.assertEqualsString("both", r.decisions[0].side);
        TracedAssertions.assertEqualsFloat(4, r.decisions[0].trimAmount);
        TracedAssertions.assertEqualsFloat(8, r.decisions[0].naturalGlue);
        TracedAssertions.assertEqualsString("LineEndCenteredPunctuationPairedCompression", r.decisions[0].reason);
        var cap = r.geometry.glueCapacities().get(0);
        TracedAssertions.assertEqualsFloat(0, cap.leading);
        TracedAssertions.assertEqualsFloat(4, cap.trailing);
    }

    @:test public static function clusterIndexRangeFindCoveredClusters():Void {
        PunctuationGeometryLedgerCoverageSupport.start("clusterIndexRangeFindCoveredClusters");
        var cs = [
            PunctuationGeometryLedgerCoverageSupport.c("中", 0),
            PunctuationGeometryLedgerCoverageSupport.c("中", 1),
            PunctuationGeometryLedgerCoverageSupport.c("中", 2)
        ];
        TracedAssertions.assertTrue(PunctuationGeometryLedger.clusterIndexRangeFor([], new TextRange(0, 3)) == null);
        var a = PunctuationGeometryLedger.clusterIndexRangeFor(cs, new TextRange(0, 3));
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 2), a);
        var b = PunctuationGeometryLedger.clusterIndexRangeFor(cs, new TextRange(1, 2));
        TracedAssertions.assertEqualsIntRange(new IntRange(1, 1), b);
        var nil = PunctuationGeometryLedger.clusterIndexRangeFor(cs, new TextRange(5, 6));
        TracedAssertions.assertEqualsRendered("-", nil == null ? "-" : PunctuationGeometryLedgerCoverageSupport.intRangeText(nil));
        var d = PunctuationGeometryLedger.clusterIndexRangeFor(cs, new TextRange(0, 1));
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 0), d);
    }
}

/** Shared fixtures and cluster builders for PunctuationGeometryLedgerCoverageTest; the Kotlin test-class lowering admits test functions only. */
class PunctuationGeometryLedgerCoverageSupport {
    public static final em:Float = 16;
    public static final builder = new PunctuationAtomBuilder();

    public static function start(n:String):Void
        new TestTraceRecorder("PunctuationGeometryLedgerCoverageTest").section(n);

    public static function c(text:String, start:Int, ?advance:Float = 16, ?font:String = "cjk"):Cluster
        return new Cluster(new TextRange(start, start + text.length), text, font, advance, text);

    public static function ledger(texts:Array<String>):PunctuationGeometryLedger {
        var cs:Array<Cluster> = [];
        var atoms:Array<PunctuationAtom> = [];
        var i = 0;
        var pos = 0;
        while (i < texts.length) {
            var x = c(texts[i], pos);
            cs.push(x);
            var aa = PunctuationGeometryStage.punctuationAtoms(x, em, builder, [], PunctuationGluePlacement.MainlandSimplified, new PunctuationWidthPolicy());
            for (a in aa)
                atoms.push(a);
            pos += texts[i].length;
            i++;
        }
        return PunctuationGeometryLedger.from(cs, atoms, new PunctuationSpacingCompressor().compress(atoms, em));
    }

    public static function floatMapText(m:SortedMap<Int, Float>):String {
        var s = "{";
        for (i in 0...m.size()) {
            if (i > 0)
                s += ", ";
            s += m.keyAt(i) + "=" + m.get(m.keyAt(i));
        }
        return s + "}";
    }

    public static function intRangeText(r:IntRange):String {
        var s = "[";
        var i = r.start;
        while (i <= r.end) {
            if (i > r.start)
                s += ", ";
            s += i;
            i++;
        }
        return s + "]";
    }

    public static function budgetAt(entries:Array<Int>, value:Float):SortedMap<Int, Float> {
        var b = SortedMap.builder();
        for (k in entries)
            b.put(k, value);
        return b.build();
    }

    public static function line(s:Int, e:Int):LineOptimization.LineCandidate
        return new LineOptimization.LineCandidate(new IntRange(s, e), new TextRange(s, e + 1), 32, 32);
}
