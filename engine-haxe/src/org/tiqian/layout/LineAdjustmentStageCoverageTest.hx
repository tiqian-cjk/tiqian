package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.TestHelpers;
import org.tiqian.test.trace.*;
import org.tiqian.layout.LineAdjustmentStageCoverageTestSupport.ZeroSpaceShaper;

class LineAdjustmentStageCoverageTest {
    @:test public static function attachedFootnoteTrailingGlueTrimsWhenTheLineEndsAtTheRun():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("attachedFootnoteTrailingGlueTrimsWhenTheLineEndsAtTheRun");
        final text = "\u6B63\u6587\uFF1A\u201C\u5185\u5BB9\u3002\u201D[1]\u540E\u6587";
        final r = LineAdjustmentStageCoverageTestSupport.layout(text, 164.0, [
            new TextSpan(new TextRange(8, 11), new TextStyle(null, null, null, null, null, null, InlineAttachment.Previous))
        ]);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 8), r.lines[0].clusterRange, LineAdjustmentStageCoverageTestSupport.renderLines(r.lines));
        final trim = LineAdjustmentStageCoverageTestSupport.trimByReason(r, "AttachedInlineVirtualBoundaryLineEndTrim");
        TracedAssertions.assertEqualsRendered(new TextRange(8, 11).toString(), trim.clusterRange.toString());
        TracedAssertions.assertEqualsFloat(8.0, trim.trimAmount);
        TracedAssertions.assertEqualsString("trailing", trim.side);
    }

    @:test public static function attachedObjectMarkHangsInsteadOfLeavingTheSeparatorAtAnEdge():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("attachedObjectMarkHangsInsteadOfLeavingTheSeparatorAtAnEdge");
        final text = "\u4E2D" + InlineObjectSpan.INLINE_OBJECT_REPLACEMENT_CHAR + " \uFF0C\u4E2D";
        final r = LineAdjustmentStageCoverageTestSupport.layout(text, 48.0, null, [new InlineObjectSpan(new TextRange(1, 2), 100.0, 12.0, 12.0)]);
        var hung = r.lines[0];
        for (i in 0...r.lines.length)
            if (r.lines[i].hangingPunctuationAdvance > 0.0) {
                hung = r.lines[i];
                break;
            }
        TracedAssertions.assertEqualsIntRange(new IntRange(1, 3), hung.clusterRange, LineAdjustmentStageCoverageTestSupport.renderLines(r.lines));
        var noneCollapse = true;
        for (i in 0...r.debug.lineEdgeTrimDecisions.length)
            if (r.debug.lineEdgeTrimDecisions[i].reason == "LineEdgeWordSpaceCollapse") {
                noneCollapse = false;
                break;
            }
        TracedAssertions.assertTrue(noneCollapse, LineAdjustmentStageCoverageTestSupport.renderTrims(r.debug.lineEdgeTrimDecisions));
    }

    @:test public static function baselineShiftSpanRaisesTheFinalClusterShift():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("baselineShiftSpanRaisesTheFinalClusterShift");
        final r = LineAdjustmentStageCoverageTestSupport.layout("\u4E2D\u6587\u6B63\u6587", 200.0, [
            new TextSpan(new TextRange(0, 2), new TextStyle(null, null, null, null, null, 4.0))
        ]);
        TracedAssertions.assertEqualsFloat(4.0, r.clusters[0].baselineShift);
        TracedAssertions.assertEqualsFloat(4.0, r.clusters[1].baselineShift);
        TracedAssertions.assertEqualsFloat(0.0, r.clusters[2].baselineShift);
    }

    @:test public static function blankMiddleLineSkipsEveryEdgePass():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("blankMiddleLineSkipsEveryEdgePass");
        final r = LineAdjustmentStageCoverageTestSupport.layout("\u4E2D\u6587\n\n\u4E2D\u6587", 80.0);
        TracedAssertions.assertEquals(3, r.lines.length, LineAdjustmentStageCoverageTestSupport.renderLines(r.lines));
        TracedAssertions.assertEqualsIntRange(new IntRange(3, 3), r.lines[1].clusterRange, LineAdjustmentStageCoverageTestSupport.renderLines(r.lines));
        TracedAssertions.assertEqualsFloat(0.0, r.lines[1].naturalWidth);
        var noneJust = true;
        for (i in 0...r.debug.justificationDecisions.length) {
            final d = r.debug.justificationDecisions[i];
            if (d.lineRange.start == r.lines[1].range.start && d.lineRange.end == r.lines[1].range.end) {
                noneJust = false;
                break;
            }
        }
        TracedAssertions.assertTrue(noneJust, LineAdjustmentStageCoverageTestSupport.renderJustifications(r.debug.justificationDecisions));
    }

    @:test public static function dashRunWithoutInkBoundsKeepsSyntheticGlyphs():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("dashRunWithoutInkBoundsKeepsSyntheticGlyphs");
        final r = LineAdjustmentStageCoverageTestSupport.layout("\u4E2D\u2014\u2014\u4E2D", 200.0);
        TracedAssertions.assertEquals(1, r.lines.length, LineAdjustmentStageCoverageTestSupport.renderLines(r.lines));
        TracedAssertions.assertEquals(1, r.glyphRuns.length);
        TracedAssertions.assertEquals(3, r.glyphRuns[0].glyphs.length);
        var allNull = true;
        for (i in 0...r.glyphRuns[0].glyphs.length)
            if (r.glyphRuns[0].glyphs[i].bounds != null) {
                allNull = false;
                break;
            }
        TracedAssertions.assertTrue(allNull, LineAdjustmentStageCoverageTestSupport.renderGlyphs(r.glyphRuns[0].glyphs));
        TracedAssertions.assertEqualsFloat(64.0, r.glyphRuns[0].advance);
    }

    @:test public static function emergencySelectedBreakOpensThePreferredTrackingSpan():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("emergencySelectedBreakOpensThePreferredTrackingSpan");
        final text = "deadbeefcafebabefeedfaceabcdefabcdef";
        final r = LineAdjustmentStageCoverageTestSupport.layout(text, 101.0, null, null, [
            new LineBreakSpan(new TextRange(0, LineAdjustmentStageCoverageTestSupport.textLength(text)), LineBreakPolicy.ProgressiveTechnical)
        ]);
        TracedAssertions.assertTrue(r.lines.length > 1, LineAdjustmentStageCoverageTestSupport.renderLines(r.lines));
        final tracking = LineAdjustmentStageCoverageTestSupport.allocationDeltas(r, "EmergencyGraphemeTracking");
        TracedAssertions.assertTrue(tracking.length > 0, LineAdjustmentStageCoverageTestSupport.renderJustifications(r.debug.justificationDecisions));
    }

    @:test public static function emptyTextYieldsZeroHeightWithoutLines():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("emptyTextYieldsZeroHeightWithoutLines");
        final r = LineAdjustmentStageCoverageTestSupport.layout("", 100.0);
        TracedAssertions.assertTrue(r.lines.length == 0, LineAdjustmentStageCoverageTestSupport.renderLines(r.lines));
        TracedAssertions.assertEqualsFloat(0.0, r.size.height);
        TracedAssertions.assertEqualsFloat(0.0, r.size.width);
    }

    @:test public static function formulaLineEndDiscardsTheTrailingBoundaryAdvance():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("formulaLineEndDiscardsTheTrailingBoundaryAdvance");
        final text = "\u7532" + InlineObjectSpan.INLINE_OBJECT_REPLACEMENT_CHAR + "\u4E59\u4E19\u4E01\u620A";
        final r = LineAdjustmentStageCoverageTestSupport.layout(text, 48.0, null, [
            new InlineObjectSpan(new TextRange(1, 2), 24.0, 12.0, 12.0, null, new InlineObjectBoundaryAdjustment(null, null, null, 6.0))
        ]);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 1), r.lines[0].clusterRange, LineAdjustmentStageCoverageTestSupport.renderLines(r.lines));
        final discard = LineAdjustmentStageCoverageTestSupport.trimByReason(r, "InlineObjectLineEndDiscardableGlue");
        TracedAssertions.assertEqualsFloat(6.0, discard.trimAmount);
        TracedAssertions.assertEqualsFloat(0.0, discard.consumedBefore);
        TracedAssertions.assertEqualsString("trailing", discard.side);
    }

    @:test public static function formulaObjectWithoutBoundaryDiscardsNothingAtLineEnd():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("formulaObjectWithoutBoundaryDiscardsNothingAtLineEnd");
        final text = "\u7532" + InlineObjectSpan.INLINE_OBJECT_REPLACEMENT_CHAR + "\u4E59\u4E19\u4E01\u620A";
        final r = LineAdjustmentStageCoverageTestSupport.layout(text, 48.0, null, [new InlineObjectSpan(new TextRange(1, 2), 24.0, 12.0, 12.0)]);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 1), r.lines[0].clusterRange, LineAdjustmentStageCoverageTestSupport.renderLines(r.lines));
        var noneDiscard = true;
        for (i in 0...r.debug.lineEdgeTrimDecisions.length)
            if (r.debug.lineEdgeTrimDecisions[i].reason == "InlineObjectLineEndDiscardableGlue") {
                noneDiscard = false;
                break;
            }
        TracedAssertions.assertTrue(noneDiscard, LineAdjustmentStageCoverageTestSupport.renderTrims(r.debug.lineEdgeTrimDecisions));
    }

    @:test public static function hyphenSqueezeConsumesOpeningAndClosingBracketGlueChannels():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("hyphenSqueezeConsumesOpeningAndClosingBracketGlueChannels");
        final r = LineAdjustmentStageCoverageTestSupport.layout("\uFF08\u4E2D\u00B7\u6587\uFF0Cinternationalization", 112.0, null, null, null, true);
        final opening = LineAdjustmentStageCoverageTestSupport.clusterByText(r, "\uFF08");
        final comma = LineAdjustmentStageCoverageTestSupport.clusterByText(r, "\uFF0C");
        TracedAssertions.assertEqualsFloat(8.0, opening.advance, LineAdjustmentStageCoverageTestSupport.renderClusterTextAdvance(r.clusters));
        TracedAssertions.assertEqualsFloat(8.0, comma.advance, LineAdjustmentStageCoverageTestSupport.renderClusterTextAdvance(r.clusters));
    }

    @:test public static function hyphenSqueezeConsumesTheInterpunctPairedChannel():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("hyphenSqueezeConsumesTheInterpunctPairedChannel");
        final r = LineAdjustmentStageCoverageTestSupport.layout("\u4E2D\u6587\uFF0C\u6587internationalization", 112.0, null, null, null, true);
        final comma = LineAdjustmentStageCoverageTestSupport.clusterByText(r, "\uFF0C");
        TracedAssertions.assertEqualsFloat(14.0, comma.advance, LineAdjustmentStageCoverageTestSupport.renderClusterTextAdvance(r.clusters));
    }

    @:test public static function hyphenSqueezeConsumesTheWordSpaceRawAdvanceChannel():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("hyphenSqueezeConsumesTheWordSpaceRawAdvanceChannel");
        final r = LineAdjustmentStageCoverageTestSupport.layout("\u4E2D\u6587aa internationalization", 118.0, null, null, null, true);
        var space = r.clusters[0];
        for (i in 0...r.clusters.length)
            if (r.clusters[i].text == " ") {
                space = r.clusters[i];
                break;
            }
        TracedAssertions.assertEqualsFloat(4.0, space.advance, LineAdjustmentStageCoverageTestSupport.renderClusterTextAdvance(r.clusters));
        final first = r.lines[0];
        TracedAssertions.assertEqualsFloat(16.0, first.hyphenAdvance);
        TracedAssertions.assertEqualsFloatTolerance(118.0, first.adjustedWidth + first.hyphenAdvance, 1e-9);
    }

    @:test public static function hyphenSqueezeFallsBackToZeroUsedGlueWhenTheLineAlreadyFits():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("hyphenSqueezeFallsBackToZeroUsedGlueWhenTheLineAlreadyFits");
        final comma = LineAdjustmentStageCoverageTestSupport.layout("\u4E2D\u6587\uFF0Cinternationalization", 88.0, null, null, null, true);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 3), comma.lines[0].clusterRange, LineAdjustmentStageCoverageTestSupport.renderLines(comma.lines));
        TracedAssertions.assertEqualsFloat(16.0, comma.lines[0].hyphenAdvance);
        TracedAssertions.assertEqualsFloat(8.0, comma.clusters[2].advance, LineAdjustmentStageCoverageTestSupport.renderAdvances(comma.clusters));
        final bracket = LineAdjustmentStageCoverageTestSupport.layout("\uFF08\u4E2D\u6587internationalization", 84.0, null, null, null, true);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 3), bracket.lines[0].clusterRange,
            LineAdjustmentStageCoverageTestSupport.renderLines(bracket.lines));
        TracedAssertions.assertEqualsFloat(16.0, bracket.lines[0].hyphenAdvance);
        TracedAssertions.assertTrue(bracket.clusters[0].advance <= 16.0, LineAdjustmentStageCoverageTestSupport.renderAdvances(bracket.clusters));
    }

    @:test public static function loneLatinClusterMergesBothAutoSpaceEdgeTrimsIntoOneKey():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("loneLatinClusterMergesBothAutoSpaceEdgeTrimsIntoOneKey");
        final r = LineAdjustmentStageCoverageTestSupport.layout("\u4E2DA\u4E2D", 24.0);
        TracedAssertions.assertEqualsIntRange(new IntRange(1, 1), r.lines[1].clusterRange, LineAdjustmentStageCoverageTestSupport.renderLines(r.lines));
        final trims = LineAdjustmentStageCoverageTestSupport.trimsByReason(r, "TextAutoSpaceLineEdgeTrim");
        final sides:Array<String> = [];
        for (i in 0...trims.length)
            sides.push(trims[i].side);
        TracedAssertions.assertEqualsStringArray(["trailing", "leading"], sides);
        var allMatch = true;
        for (i in 0...trims.length) {
            final d = trims[i];
            if (!(d.clusterRange.start == 1 && d.clusterRange.end == 2 && d.trimAmount == 2.0)) {
                allMatch = false;
                break;
            }
        }
        TracedAssertions.assertTrue(allMatch, LineAdjustmentStageCoverageTestSupport.renderTrims(trims));
        TracedAssertions.assertEqualsFloat(16.0, r.lines[1].adjustedWidth);
    }

    @:test public static function loneMandatoryBreakEmitsTwoZeroWidthLines():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("loneMandatoryBreakEmitsTwoZeroWidthLines");
        final r = LineAdjustmentStageCoverageTestSupport.layout("\n", 100.0);
        TracedAssertions.assertEquals(2, r.lines.length, LineAdjustmentStageCoverageTestSupport.renderLines(r.lines));
        var allZero = true;
        for (i in 0...r.lines.length)
            if (!(r.lines[i].naturalWidth == 0.0 && r.lines[i].visualWidth == 0.0)) {
                allZero = false;
                break;
            }
        TracedAssertions.assertTrue(allZero);
        TracedAssertions.assertTrue(r.size.height > 0.0, Std.string(r.size.height));
    }

    @:test public static function mandatoryBreakMiddleLineSkipsItsJustificationPlan():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("mandatoryBreakMiddleLineSkipsItsJustificationPlan");
        final r = LineAdjustmentStageCoverageTestSupport.layout("\u4E2D\u6587\u4E2D\u6587\n\u4E2D\u6587\u4E2D\u6587", 80.0);
        TracedAssertions.assertEquals(2, r.lines.length, LineAdjustmentStageCoverageTestSupport.renderLines(r.lines));
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 4), r.lines[0].clusterRange);
        TracedAssertions.assertEqualsIntRange(new IntRange(5, 8), r.lines[1].clusterRange);
        var allAdjusted = true;
        for (i in 0...r.lines.length)
            if (!(r.lines[i].adjustedWidth == r.lines[i].naturalWidth)) {
                allAdjusted = false;
                break;
            }
        TracedAssertions.assertTrue(allAdjusted, LineAdjustmentStageCoverageTestSupport.lineRangeWidths(r.lines));
        TracedAssertions.assertTrue(r.debug.justificationDecisions.length == 0);
    }

    @:test public static function technicalLineBodyStretchRejectsTheCleanTierAndReplays():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("technicalLineBodyStretchRejectsTheCleanTierAndReplays");
        final text = "\u4E2D\u6587\u4E2D aa bb \u4E2D\u6587\u4E2D\u6587\u4E2D\u6587\u4E2D\u6587\u4E2D\u6587\u4E2D\u6587";
        final r = LineAdjustmentStageCoverageTestSupport.layout(text, 96.0, null, null, [
            new LineBreakSpan(new TextRange(0, LineAdjustmentStageCoverageTestSupport.textLength(text)), LineBreakPolicy.ProgressiveTechnical)
        ]);
        TracedAssertions.assertTrue(r.lines.length > 1, LineAdjustmentStageCoverageTestSupport.renderLines(r.lines));
        final reasons = LineAdjustmentStageCoverageTestSupport.emergencyReasons(r);
        var hasRejection = false;
        for (i in 0...reasons.length)
            if (StringTools.startsWith(reasons[i], "CurrentLineTechnicalTierRejection:")) {
                hasRejection = true;
                break;
            }
        TracedAssertions.assertTrue(hasRejection, LineAdjustmentStageCoverageTestSupport.renderStrings(reasons));
        final bReasons = LineAdjustmentStageCoverageTestSupport.breakReasons(r);
        var hasEmergency = false;
        for (i in 0...bReasons.length)
            if (bReasons[i] == "CurrentLineTechnicalEmergencyBreak") {
                hasEmergency = true;
                break;
            }
        TracedAssertions.assertTrue(hasEmergency, LineAdjustmentStageCoverageTestSupport.renderStrings(bReasons));
    }

    @:test public static function tinyTechnicalTrackingStaysBelowTheRejectionThreshold():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("tinyTechnicalTrackingStaysBelowTheRejectionThreshold");
        final text = "\u4E2D\u4E2D\u4E2D\u4E2D\u4E2D\u4E2D aaaa";
        final span = [
            new LineBreakSpan(new TextRange(0, LineAdjustmentStageCoverageTestSupport.textLength(text)), LineBreakPolicy.ProgressiveTechnical)
        ];
        final tiny = LineAdjustmentStageCoverageTestSupport.layout(text, TestHelpers.f32Literal(96.004), null, null, span);
        TracedAssertions.assertEqualsIntRange(new IntRange(0, 5), tiny.lines[0].clusterRange, LineAdjustmentStageCoverageTestSupport.renderLines(tiny.lines));
        final deltas = LineAdjustmentStageCoverageTestSupport.allocationDeltas(tiny, "CjkInterChar");
        TracedAssertions.assertTrue(deltas.length > 0, LineAdjustmentStageCoverageTestSupport.renderJustifications(tiny.debug.justificationDecisions));
        var allSmall = true;
        for (i in 0...deltas.length)
            if (!(deltas[i] <= 0.001)) {
                allSmall = false;
                break;
            }
        TracedAssertions.assertTrue(allSmall, LineAdjustmentStageCoverageTestSupport.renderFloats(deltas));
        final tinyReasons = LineAdjustmentStageCoverageTestSupport.emergencyReasons(tiny);
        var noneRejection = true;
        for (i in 0...tinyReasons.length)
            if (StringTools.startsWith(tinyReasons[i], "CurrentLineTechnicalTierRejection:")) {
                noneRejection = false;
                break;
            }
        TracedAssertions.assertTrue(noneRejection, LineAdjustmentStageCoverageTestSupport.renderStrings(tinyReasons));
        final rejected = LineAdjustmentStageCoverageTestSupport.layout(text, 96.4, null, null, span);
        final rejReasons = LineAdjustmentStageCoverageTestSupport.emergencyReasons(rejected);
        var hasWholeToken = false;
        for (i in 0...rejReasons.length)
            if (rejReasons[i] == "CurrentLineTechnicalTierRejection:WholeToken") {
                hasWholeToken = true;
                break;
            }
        TracedAssertions.assertTrue(hasWholeToken, LineAdjustmentStageCoverageTestSupport.renderStrings(rejReasons));
    }

    @:test public static function trailingMandatoryBreakEmitsTerminalEmptyLineWithoutHyphen():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("trailingMandatoryBreakEmitsTerminalEmptyLineWithoutHyphen");
        final r = LineAdjustmentStageCoverageTestSupport.layout("\u4E2D\u6587aa internationalization\n", 118.0, null, null, null, true);
        final last = r.lines[r.lines.length - 1];
        TracedAssertions.assertTrue(last.clusterRange.isEmpty, LineAdjustmentStageCoverageTestSupport.renderLines(r.lines));
        TracedAssertions.assertEqualsFloat(0.0, last.hyphenAdvance);
        final before = r.lines[r.lines.length - 2];
        TracedAssertions.assertEqualsFloat(0.0, before.hyphenAdvance, LineAdjustmentStageCoverageTestSupport.renderLines(r.lines));
        TracedAssertions.assertTrue(before.hyphenGlyphs.length == 0);
    }

    @:test public static function zeroAdvanceEdgeSpaceIsNeverCollapsed():Void {
        final t = new TestTraceRecorder("LineAdjustmentStageCoverageTest");
        t.section("zeroAdvanceEdgeSpaceIsNeverCollapsed");
        final r = LineAdjustmentStageCoverageTestSupport.layout("\u4E2D\u4E2D\u4E2D\u4E2D aaa bbb", 114.0, null, null, null, null, new ZeroSpaceShaper());
        final first = r.lines[0];
        final edge = r.clusters[first.clusterRange.end];
        TracedAssertions.assertTrue(LineAdjustmentStageCoverageTestSupport.isAllSpaces(edge.text),
            LineAdjustmentStageCoverageTestSupport.renderClusterTexts(r.clusters));
        TracedAssertions.assertEqualsFloat(0.0, edge.advance);
        var noneCollapse = true;
        for (i in 0...r.debug.lineEdgeTrimDecisions.length)
            if (r.debug.lineEdgeTrimDecisions[i].reason == "LineEdgeWordSpaceCollapse") {
                noneCollapse = false;
                break;
            }
        TracedAssertions.assertTrue(noneCollapse, LineAdjustmentStageCoverageTestSupport.renderTrims(r.debug.lineEdgeTrimDecisions));
    }
}
