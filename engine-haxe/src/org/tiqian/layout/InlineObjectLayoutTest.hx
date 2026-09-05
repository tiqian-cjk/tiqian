package org.tiqian.layout;

using std.RecordCopy;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.test.trace.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;
import org.tiqian.layout.LineGeometryStage.LineGeometryStageFns;
import org.tiqian.layout.LineBreaker.GreedyLineBreaker;
import org.tiqian.layout.LineBreaker.LookaheadLineBreaker;
import org.tiqian.layout.ParagraphDpLineBreaker.ParagraphDpLineBreaker;
import org.tiqian.layout.ProgressiveBreakDecisions.UnbreakableRanges;
import org.tiqian.layout.PunctuationModel.GlueKind;

class InlineObjectLayoutTest {
    @:test public static function lineBoundaryClosesOneUlpGapWithoutChangingBaselineDistance() {
        InlineObjectLayoutTestSupport.rec("lineBoundaryClosesOneUlpGapWithoutChangingBaselineDistance");
        TracedAssertions.assertEqualsFloat(84.14, LineGeometryStageFns.resolveInlineObjectLineBoundaryExtent(80, 84.14, 100, 15.86001));
    }

    @:test public static function inlineObjectUsesExistingInterlineSpaceWithoutMovingBaselines() {
        InlineObjectLayoutTestSupport.rec("inlineObjectUsesExistingInterlineSpaceWithoutMovingBaselines");
        final p = InlineObjectLayoutTestSupport.layout("甲乙", 16);
        final o = InlineObjectLayoutTestSupport.layout("甲乙", 16, [new InlineObjectSpan(new TextRange(1, 2), 16, 20, 2)]);
        TracedAssertions.assertEqualsInt(2, o.lines.length);
        TracedAssertions.assertEqualsFloatTolerance(p.lines[1].baseline - p.lines[0].baseline, o.lines[1].baseline - o.lines[0].baseline, .001);
        TracedAssertions.assertEqualsFloatTolerance(24, o.lines[1].baseline - o.lines[0].baseline, .001);
        TracedAssertions.assertEqualsFloatTolerance(p.size.height, o.size.height, .001);
        TracedAssertions.assertEqualsFloatTolerance(o.lines[1].baseline - 20, o.lines[1].top, .001,
            "the existing inter-line gap should be reassigned to the object's own line box");
        final d = o.debug.inlineObjectLineHeightDecision;
        TracedAssertions.assertNotNullRendered(d != null, d == null ? "null" : TestTraceRender.cap(Std.string(d)));
        TracedAssertions.assertEqualsFloatTolerance(1.6, d.minimumClearance, .001);
        TracedAssertions.assertTrue(o.lines[1].baseline - 20 - (o.lines[0].baseline + d.baseFaceDescent) >= d.minimumClearance - .001);
        var extras = true;
        for (i in 0...d.lineExtras.length)
            if (d.lineExtras[i] != 0)
                extras = false;
        TracedAssertions.assertTrue(extras);
        TracedAssertions.assertTrue(d.expandedLineIndices.length == 0);
        TracedAssertions.assertTrue(d.boundaryShiftsAfter.length == 1 && d.boundaryShiftsAfter[0] < 0);
        TracedAssertions.assertEqualsString("ExistingInterlineSpaceFitsInlineObjects", d.reason);
    }

    @:test public static function inlineObjectExpandsBaselineGapOnlyForActualCollision() {
        InlineObjectLayoutTestSupport.rec("inlineObjectExpandsBaselineGapOnlyForActualCollision");
        final a = [
            new InlineObjectSpan(new TextRange(0, 1), 16, 14, 10),
            new InlineObjectSpan(new TextRange(1, 2), 16, 20, 2)
        ];
        final r = InlineObjectLayoutTestSupport.layout("甲乙", 16, a);
        TracedAssertions.assertEqualsFloatTolerance(31.6, r.lines[1].baseline - r.lines[0].baseline, .001);
        TracedAssertions.assertEqualsFloatTolerance(1.6, r.lines[1].baseline - 20 - (r.lines[0].baseline + 10), .001,
            "the measured collision deficit must retain the configured safety clearance");
        final d = r.debug.inlineObjectLineHeightDecision;
        TracedAssertions.assertNotNullRendered(d != null, d == null ? "null" : TestTraceRender.cap(Std.string(d)));
        TracedAssertions.assertEqualsFloatTolerance(0, d.lineExtras[0], .001);
        TracedAssertions.assertEqualsFloatTolerance(7.6, d.lineExtras[1], .001);
        TracedAssertions.assertEqualsIntArray([1], d.expandedLineIndices);
        TracedAssertions.assertEqualsString("InlineObjectInterlineCollision", d.reason);
        final s = InlineObjectLayoutTestSupport.style.copy(inlineObjectMinimumClearanceEm = 0);
        final z = new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent("甲乙"), new TextStyle(16), s,
            new LayoutConstraints(16), null, null, null, null, a));
        TracedAssertions.assertEqualsFloatTolerance(30, z.lines[1].baseline - z.lines[0].baseline, .001);
        final zd = z.debug.inlineObjectLineHeightDecision;
        TracedAssertions.assertNotNullRendered(zd != null, zd == null ? "null" : TestTraceRender.cap(Std.string(zd)));
        TracedAssertions.assertEqualsFloat(0, zd.minimumClearance);
    }

    @:test public static function inlineObjectSkipsFontShapingAndExpandsItsOwnLineMetrics() {
        InlineObjectLayoutTestSupport.rec("inlineObjectSkipsFontShapingAndExpandsItsOwnLineMetrics");
        final r = InlineObjectLayoutTestSupport.layout("中\uFFFC文", 120, [new InlineObjectSpan(new TextRange(1, 2), 20, 30, 4)]);
        final c = InlineObjectLayoutTestSupport.singleCluster(r, new TextRange(1, 2));
        TracedAssertions.assertEqualsFloatTolerance(20, c.advance, .001);
        var noGlyph = true;
        for (i in 0...r.glyphRuns.length)
            for (j in 0...r.glyphRuns[i].glyphs.length)
                if (InlineObjectLayoutTestSupport.sameRange(r.glyphRuns[i].glyphs[j].clusterRange, c.range))
                    noGlyph = false;
        TracedAssertions.assertTrue(noGlyph);
        final shaping = InlineObjectLayoutTestSupport.singleShapingDecision(r, c.range);
        TracedAssertions.assertEqualsInt(0, shaping.glyphCount);
        TracedAssertions.assertEqualsString("MeasurableOpaqueInlineObject:no-font-shaping", shaping.reason);
        TracedAssertions.assertTrue(r.lines[0].baseline - r.lines[0].top >= 30);
        TracedAssertions.assertTrue(r.lines[0].bottom - r.lines[0].baseline >= 4);
        TracedAssertions.assertEqualsInt(0, r.debug.inlineObjectDecisions[0].lineIndex);
        TracedAssertions.assertEqualsString("MeasurableOpaqueInlineObject", r.debug.inlineObjectDecisions[0].reason);
    }

    @:test public static function inlineObjectIsOneIndivisibleBreakCluster() {
        InlineObjectLayoutTestSupport.rec("inlineObjectIsOneIndivisibleBreakCluster");
        final r = InlineObjectLayoutTestSupport.layout("中\uFFFC文", 35, [new InlineObjectSpan(new TextRange(1, 2), 20, 16, 4)]);
        var objectIndex = -1;
        for (i in 0...r.clusters.length)
            if (InlineObjectLayoutTestSupport.sameRange(r.clusters[i].range, new TextRange(1, 2)))
                objectIndex = i;
        var objectLine:LineBox = null;
        for (i in 0...r.lines.length)
            if (objectIndex >= r.lines[i].clusterRange.start && objectIndex <= r.lines[i].clusterRange.end)
                objectLine = r.lines[i];
        TracedAssertions.assertEqualsIntRange(new IntRange(objectIndex, objectIndex), objectLine.clusterRange);
    }

    @:test public static function inlineObjectKeepsAlternateSourceTextWhileSkippingItsGlyphShaping() {
        InlineObjectLayoutTestSupport.rec("inlineObjectKeepsAlternateSourceTextWhileSkippingItsGlyphShaping");
        final r = InlineObjectLayoutTestSupport.layout("中图片文", 120, [new InlineObjectSpan(new TextRange(1, 3), 20, 16, 4)]);
        final c = r.clusters[1];
        TracedAssertions.assertEqualsString("图片", c.text);
        TracedAssertions.assertEqualsString("", c.displayText);
        var noGlyph = true;
        for (i in 0...r.glyphRuns.length)
            for (j in 0...r.glyphRuns[i].glyphs.length)
                if (InlineObjectLayoutTestSupport.sameRange(r.glyphRuns[i].glyphs[j].clusterRange, c.range))
                    noGlyph = false;
        TracedAssertions.assertTrue(noGlyph);
        final shaping = InlineObjectLayoutTestSupport.singleShapingDecision(r, c.range);
        TracedAssertions.assertEqualsString("图片", shaping.sourceText);
        TracedAssertions.assertEqualsString("", shaping.displayText);
    }

    @:test public static function adjustBreakForUnbreakablesRetreatsPastTheWholeContiguousRun() {
        InlineObjectLayoutTestSupport.rec("adjustBreakForUnbreakablesRetreatsPastTheWholeContiguousRun");
        final u = new UnbreakableRanges([new IntRange(1, 2), new IntRange(2, 3), new IntRange(3, 4)]);
        TracedAssertions.assertEqualsInt(1, ProgressiveBreakDecisions.adjustBreakForUnbreakables(4, 0, u));
        TracedAssertions.assertEqualsInt(1, ProgressiveBreakDecisions.adjustBreakForUnbreakables(3, 0, u));
        TracedAssertions.assertEqualsInt(1, ProgressiveBreakDecisions.adjustBreakForUnbreakables(2, 0, u));
        TracedAssertions.assertEqualsInt(5, ProgressiveBreakDecisions.adjustBreakForUnbreakables(5, 0, u));
        TracedAssertions.assertEqualsInt(3,
            ProgressiveBreakDecisions.adjustBreakForUnbreakables(5, 2, new UnbreakableRanges([new IntRange(3, 4), new IntRange(4, 5)])));
        TracedAssertions.assertEqualsInt(4, ProgressiveBreakDecisions.adjustBreakForUnbreakables(4, 1, u));
    }

    @:test public static function perAtomFormulaChainNeverBreaksMidRun() {
        InlineObjectLayoutTestSupport.rec("perAtomFormulaChainNeverBreaksMidRun");
        final a:Array<InlineObjectSpan> = [];
        for (i in 1...5)
            a.push(new InlineObjectSpan(new TextRange(i, i + 1), 12, 16, 4, null,
                i < 4 ? new InlineObjectBoundaryAdjustment(null, null, null, null, true) : new InlineObjectBoundaryAdjustment()));
        final r = InlineObjectLayoutTestSupport.fixedBasicKinsokuEngine(new LookaheadLineBreaker())
            .layout(new LayoutInput(new TiqianTextContent("中一二三四"), new TextStyle(16), InlineObjectLayoutTestSupport.style, new LayoutConstraints(60), null,
                null, null, null, a));
        for (i in 0...r.lines.length) {
            final l = r.lines[i];
            TracedAssertions.assertTrue(l.range.end != 2 && l.range.end != 3 && l.range.end != 4,
                "line ended inside the unbreakable formula chain: " + InlineObjectLayoutTestSupport.renderLineRanges(r));
        }
    }

    @:test public static function formulaBoundaryCompressionPushesAttachedCommaIntoPreviousLine() {
        InlineObjectLayoutTestSupport.rec("formulaBoundaryCompressionPushesAttachedCommaIntoPreviousLine");
        final text = "x+，后";
        final r = InlineObjectLayoutTestSupport.fixedBasicKinsokuEngine()
            .layout(new LayoutInput(new TiqianTextContent(text), new TextStyle(16), InlineObjectLayoutTestSupport.style, new LayoutConstraints(36), null,
                null, null, null, [
                    new InlineObjectSpan(new TextRange(0, 2), 30, 16, 4, null, new InlineObjectBoundaryAdjustment(true, null, 4, null, null))
                ]));
        final ls = InlineObjectLayoutTestSupport.lines(r, text);
        var bad = false;
        for (i in 0...ls.length)
            if (StringTools.startsWith(ls[i], "，"))
                bad = true;
        TracedAssertions.assertTrue(!bad);
        final repair = r.debug.lineDecisions[0].repairDecision;
        TracedAssertions.assertNotNullRendered(repair != null, repair == null ? "null" : TestTraceRender.cap(Std.string(repair)));
        TracedAssertions.assertEqualsString("PushIn", repair.kind);
        var found = false;
        for (i in 0...repair.pushInAllocations.length)
            if (InlineObjectLayoutTestSupport.sameRange(repair.pushInAllocations[i].clusterRange, new TextRange(0, 2))
                && repair.pushInAllocations[i].shrink > 0)
                found = true;
        TracedAssertions.assertTrue(found,
            "formula boundary space must contribute to compression: " + InlineObjectLayoutTestSupport.renderRepairAllocations(repair.pushInAllocations));
    }

    @:test public static function punctuationAttachedToInlineObjectNeverStartsWrappedLine() {
        InlineObjectLayoutTestSupport.rec("punctuationAttachedToInlineObjectNeverStartsWrappedLine");
        for (b in [new GreedyLineBreaker(), new LookaheadLineBreaker(), new ParagraphDpLineBreaker()])
            for (comma in ["\uFF0C", ","])
                for (w in [24, 32, 36, 48, 64]) {
                    final text = "x+" + comma + " 后";
                    final r = InlineObjectLayoutTestSupport.fixedBasicKinsokuEngine(b)
                        .layout(new LayoutInput(new TiqianTextContent(text), new TextStyle(16), InlineObjectLayoutTestSupport.style, new LayoutConstraints(w),
                            null, null, null, null, [new InlineObjectSpan(new TextRange(0, 2), 30, 16, 4)]));
                    final ls = InlineObjectLayoutTestSupport.lines(r, text);
                    var bad = false;
                    for (i in 0...ls.length)
                        if (StringTools.startsWith(ls[i], comma))
                            bad = true;
                    TracedAssertions.assertTrue(!bad,
                        "breaker="
                        + b.strategyName
                        + " width="
                        + w
                        + " comma="
                        + comma
                        + " lines="
                        + InlineObjectLayoutTestSupport.renderStrings(ls));
                    var any = false;
                    for (i in 0...r.debug.contextualKinsokuDecisions.length)
                        if (r.debug.contextualKinsokuDecisions[i].sourceText == comma
                            && r.debug.contextualKinsokuDecisions[i].reason == "InlineObjectAttachedKinsoku")
                            any = true;
                    TracedAssertions.assertTrue(any);
                }
    }

    @:test public static function separatorSpaceBeforePunctuationCollapsesAndStaysWithInlineObject() {
        InlineObjectLayoutTestSupport.rec("separatorSpaceBeforePunctuationCollapsesAndStaysWithInlineObject");
        for (b in [new GreedyLineBreaker(), new LookaheadLineBreaker(), new ParagraphDpLineBreaker()])
            for (w in [32, 40, 48, 56, 64]) {
                final text = "前x ，后文";
                final r = InlineObjectLayoutTestSupport.fixedBasicKinsokuEngine(b)
                    .layout(new LayoutInput(new TiqianTextContent(text), new TextStyle(16), InlineObjectLayoutTestSupport.style, new LayoutConstraints(w),
                        null, null, null, null, [
                            new InlineObjectSpan(new TextRange(1, 2), 24, 16, 4, new InlineObjectBoundaryAdjustment(true),
                                new InlineObjectBoundaryAdjustment(true))
                        ]));
                final space = InlineObjectLayoutTestSupport.singleCluster(r, new TextRange(2, 3));
                TracedAssertions.assertEqualsFloatTolerance(0, space.advance, .001);
                final ls = InlineObjectLayoutTestSupport.lines(r, text);
                var bad = false;
                for (i in 0...ls.length)
                    if (StringTools.startsWith(StringTools.ltrim(ls[i]), "\uFF0C"))
                        bad = true;
                TracedAssertions.assertTrue(!bad, "breaker=" + b.strategyName + " width=" + w + " lines=" + InlineObjectLayoutTestSupport.renderStrings(ls));
                var any = false;
                for (i in 0...r.debug.contextualKinsokuDecisions.length)
                    if (r.debug.contextualKinsokuDecisions[i].sourceText == "\uFF0C"
                        && r.debug.contextualKinsokuDecisions[i].reason == "InlineObjectAttachedKinsokuAcrossCollapsedSeparatorSpace")
                        any = true;
                TracedAssertions.assertTrue(any);
                final att = r.debug.inlineObjectPunctuationAttachmentDecisions[0];
                TracedAssertions.assertEqualsRendered(Std.string(new TextRange(2, 3)), Std.string(att.separatorRange));
                TracedAssertions.assertTrue(att.collapsedAdvance > 0);
                var closed = true;
                for (i in 0...r.debug.justificationDecisions.length)
                    for (j in 0...r.debug.justificationDecisions[i].allocations.length) {
                        final al = r.debug.justificationDecisions[i].allocations[j];
                        if (InlineObjectLayoutTestSupport.sameRange(al.clusterRange, new TextRange(1, 2))
                            && al.kind == Std.string(GlueKind.InlineObjectBoundary))
                            closed = false;
                    }
                TracedAssertions.assertTrue(closed, "the formula edge before attached punctuation must stay closed");
            }
    }

    @:test public static function relationStretchMovesBothFormulaSidesByTheSameFinalGeometry() {
        InlineObjectLayoutTestSupport.rec("relationStretchMovesBothFormulaSidesByTheSameFinalGeometry");
        final naturalRelationGap = 5 / 18 * 16;
        final targetGap = 0.5 * 16;
        final formulaBodyWidth = 10;
        final text = "a=b中";
        final r = InlineObjectLayoutTestSupport.fixedBasicKinsokuEngine()
            .layout(new LayoutInput(new TiqianTextContent(text), new TextStyle(16), InlineObjectLayoutTestSupport.style, new LayoutConstraints(47), null,
                null, null, null, [
                    new InlineObjectSpan(new TextRange(0, 1), formulaBodyWidth + naturalRelationGap, 12, 4, null,
                        new InlineObjectBoundaryAdjustment(true,
                            new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.Relation, naturalRelationGap, targetGap))),
                    new InlineObjectSpan(new TextRange(1, 2), formulaBodyWidth + naturalRelationGap, 12, 4, null,
                        new InlineObjectBoundaryAdjustment(true,
                            new InlineObjectPreferredStretch(InlineObjectPreferredStretchKind.Relation, naturalRelationGap, targetGap), null, null, true)),
                    new InlineObjectSpan(new TextRange(2, 3), formulaBodyWidth, 12, 4)
                ]));
        TracedAssertions.assertTrue(r.lines.length > 1);
        final pc = LayoutQueries.positionedClusters(r);
        final formula:Array<PositionedCluster> = [];
        for (i in 0...pc.length)
            if (pc[i].range.end <= 3)
                formula.push(pc[i]);
        TracedAssertions.assertEqualsInt(3, formula.length);
        TracedAssertions.assertEqualsInt(0, formula[0].lineIndex);
        final beforeEquals = formula[1].drawX - (formula[0].drawX + formulaBodyWidth);
        final afterEquals = formula[2].drawX - (formula[1].drawX + formulaBodyWidth);
        TracedAssertions.assertEqualsFloatTolerance(beforeEquals, afterEquals, .001);
        TracedAssertions.assertTrue(beforeEquals >= targetGap);
        final rel:Array<JustificationAllocationInfo> = [];
        for (i in 0...r.debug.justificationDecisions[0].allocations.length)
            if (r.debug.justificationDecisions[0].allocations[i].kind == Std.string(GlueKind.InlineObjectRelation))
                rel.push(r.debug.justificationDecisions[0].allocations[i]);
        TracedAssertions.assertEqualsInt(2, rel.length);
        TracedAssertions.assertEqualsFloatTolerance(rel[0].delta, rel[1].delta, .001);
    }

    @:test public static function formulaBreakKeepsBaselineOperatorOnPreviousLine() {
        InlineObjectLayoutTestSupport.rec("formulaBreakKeepsBaselineOperatorOnPreviousLine");
        final text = "a+b";
        final objs = [
            new InlineObjectSpan(new TextRange(0, 1), 12, 12, 4),
            new InlineObjectSpan(new TextRange(1, 2), 12, 12, 4, new InlineObjectBoundaryAdjustment(null, null, null, null, true),
                new InlineObjectBoundaryAdjustment(null, null, 4, 4, null)),
            new InlineObjectSpan(new TextRange(2, 3), 12, 12, 4)
        ];
        for (b in [new GreedyLineBreaker(), new LookaheadLineBreaker(), new ParagraphDpLineBreaker()]) {
            final r = InlineObjectLayoutTestSupport.fixedBasicKinsokuEngine(b)
                .layout(new LayoutInput(new TiqianTextContent(text), new TextStyle(16), InlineObjectLayoutTestSupport.style, new LayoutConstraints(24), null,
                    null, null, null, objs));
            final ls = InlineObjectLayoutTestSupport.lines(r, text);
            TracedAssertions.assertTrue(ls.length > 1, "breaker=" + b.strategyName + " lines=" + InlineObjectLayoutTestSupport.renderStrings(ls));
            var starts = false;
            for (i in 1...ls.length)
                if (StringTools.startsWith(ls[i], "+"))
                    starts = true;
            TracedAssertions.assertTrue(!starts,
                "the adjustment-only boundary before the operator must stay closed: breaker="
                + b.strategyName
                + " lines="
                + InlineObjectLayoutTestSupport.renderStrings(ls));
            var ends = false;
            for (i in 0...ls.length - 1)
                if (StringTools.endsWith(ls[i], "+"))
                    ends = true;
            TracedAssertions.assertTrue(ends, "breaker=" + b.strategyName + " lines=" + InlineObjectLayoutTestSupport.renderStrings(ls));
            TracedAssertions.assertEqualsFloatTolerance(8, InlineObjectLayoutTestSupport.singleCluster(r, new TextRange(1, 2)).advance, .001,
                "the operator glyph stays while its post-operator line-end glue disappears");
            TracedAssertions.assertEqualsFloatTolerance(20, r.lines[0].visualWidth, .001, "the discarded glue must not remain in the previous line's width");
            TracedAssertions.assertEqualsFloatTolerance(0,
                InlineObjectLayoutTestSupport.singlePositioned(LayoutQueries.positionedClusters(r), new TextRange(2, 3)).drawX, .001,
                "the following operand must start without inherited formula glue");
            var trim = false;
            for (i in 0...r.debug.lineEdgeTrimDecisions.length) {
                final x = r.debug.lineEdgeTrimDecisions[i];
                if (InlineObjectLayoutTestSupport.sameRange(x.clusterRange, new TextRange(1, 2))
                    && x.reason == "InlineObjectLineEndDiscardableGlue"
                    && x.naturalGlue == 4)
                    trim = true;
            }
            TracedAssertions.assertTrue(trim,
                "breaker="
                + b.strategyName
                + " trims="
                + InlineObjectLayoutTestSupport.renderTrimDecisions(r.debug.lineEdgeTrimDecisions));
            TracedAssertions.assertTrue(InlineObjectLayoutTestSupport.singleInlineObjectDecision(r, new TextRange(1, 2)).leadingPreventsLineBreak);
            TracedAssertions.assertEqualsFloat(4,
                InlineObjectLayoutTestSupport.singleInlineObjectDecision(r, new TextRange(1, 2)).trailingLineEndDiscardableAdvance);
            final u = InlineObjectLayoutTestSupport.fixedBasicKinsokuEngine(b)
                .layout(new LayoutInput(new TiqianTextContent(text), new TextStyle(16), InlineObjectLayoutTestSupport.style, new LayoutConstraints(60), null,
                    null, null, null, objs));
            TracedAssertions.assertEqualsInt(1, u.lines.length);
            TracedAssertions.assertEqualsFloatTolerance(12, InlineObjectLayoutTestSupport.singleCluster(u, new TextRange(1, 2)).advance, .001);
            var no = false;
            for (i in 0...u.debug.lineEdgeTrimDecisions.length)
                if (u.debug.lineEdgeTrimDecisions[i].reason == "InlineObjectLineEndDiscardableGlue")
                    no = true;
            TracedAssertions.assertTrue(!no);
        }
    }
}
