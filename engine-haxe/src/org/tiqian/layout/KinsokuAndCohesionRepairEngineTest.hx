package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.clreq.*;
import org.tiqian.linebreak.*;
import org.tiqian.test.trace.*;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;

class KinsokuAndCohesionRepairEngineTest {
    @:test public static function bibliographicNumericLocatorExposesStructuralBreaks():Void {
        final t = LineBreakRepairEngineTestSupport.kinsokuStart("bibliographicNumericLocatorExposesStructuralBreaks");
        final text = "中文中文中文44(10):21-38.";
        final result = new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent(text), null,
            new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(224)));
        final decision = result.debug.breakOpportunityDecisions[0];
        TracedAssertions.assertEqualsRendered(Std.string(new TextRange(6, 19)), Std.string(decision.range));
        TracedAssertions.assertEqualsString("44(10):21-38.", decision.sourceText);
        TracedAssertions.assertEqualsIntArray([8, 13], decision.breakOffsets);
        TracedAssertions.assertEqualsString("BibliographicNumericLocatorBreak", decision.reason);
        final lineTexts:Array<String> = [];
        for (i in 0...result.lines.length)
            lineTexts.push(LineBreakRepairEngineTestSupport.lineText(result, i));
        TracedAssertions.assertTrue(StringTools.endsWith(lineTexts[0], "44(10):"),
            "locator should fill the preceding line: " + LineBreakRepairEngineTestSupport.renderStrings(lineTexts));
        TracedAssertions.assertEqualsString("21-38.", lineTexts[lineTexts.length - 1]);
        var noEndOpen = true;
        for (i in 0...lineTexts.length)
            if (StringTools.endsWith(lineTexts[i], "("))
                noEndOpen = false;
        TracedAssertions.assertTrue(noEndOpen, "opening bracket cannot end a line: " + LineBreakRepairEngineTestSupport.renderStrings(lineTexts));
        var noStartClose = true;
        for (i in 0...lineTexts.length)
            if (StringTools.startsWith(lineTexts[i], ")"))
                noStartClose = false;
        TracedAssertions.assertTrue(noStartClose, "closing bracket cannot start a line: " + LineBreakRepairEngineTestSupport.renderStrings(lineTexts));
    }

    @:test public static function hangingPunctuationFillsLineToMeasureAndOverflowsVisual():Void {
        final t = LineBreakRepairEngineTestSupport.kinsokuStart("hangingPunctuationFillsLineToMeasureAndOverflowsVisual");
        final engine = LineBreakRepairEngineTestSupport.fixed(KinsokuLevel.Basic, HangingPunctuationStyle.PauseStops);
        final result = engine.layout(LineBreakRepairEngineTestSupport.input("中文中文，中文。", 64));
        TracedAssertions.assertTrue(result.lines.length >= 2);
        final line0 = result.lines[0];
        TracedAssertions.assertEqualsInt(0, line0.range.start);
        TracedAssertions.assertEqualsInt(5, line0.range.end);
        TracedAssertions.assertEqualsFloat(64, line0.adjustedWidth);
        TracedAssertions.assertTrue(line0.visualWidth > 64, "hung mark must overflow: " + line0.visualWidth);
        TracedAssertions.assertEqualsFloat(line0.visualWidth - line0.adjustedWidth, line0.hangingPunctuationAdvance);
        TracedAssertions.assertEqualsString("Hang", result.debug.lineDecisions[0].repair);
        final plain = LineBreakRepairEngineTestSupport.fixed(KinsokuLevel.Basic, HangingPunctuationStyle.Disabled)
            .layout(LineBreakRepairEngineTestSupport.input("中文中文，中文。", 64));
        var noneOverflow = true;
        for (i in 0...plain.lines.length)
            if (plain.lines[i].visualWidth > 64)
                noneOverflow = false;
        TracedAssertions.assertTrue(noneOverflow);
        var noneHang = true;
        for (i in 0...plain.debug.lineDecisions.length)
            if (plain.debug.lineDecisions[i].repair == "Hang")
                noneHang = false;
        TracedAssertions.assertTrue(noneHang);
    }

    @:test public static function kinsokuCarriesPreviousClusterWhenLineWouldStartWithForbiddenPunctuation():Void {
        final t = LineBreakRepairEngineTestSupport.kinsokuStart("kinsokuCarriesPreviousClusterWhenLineWouldStartWithForbiddenPunctuation");
        final result = LineBreakRepairEngineTestSupport.fixed().layout(LineBreakRepairEngineTestSupport.input("中文中文。", 64));
        TracedAssertions.assertEqualsInt(2, result.lines.length);
        TracedAssertions.assertEqualsInt(0, result.lines[0].range.start);
        TracedAssertions.assertEqualsInt(3, result.lines[0].range.end);
        TracedAssertions.assertEqualsInt(3, result.lines[1].range.start);
        TracedAssertions.assertEqualsInt(5, result.lines[1].range.end);
        TracedAssertions.assertEqualsFloat(48, result.lines[0].adjustedWidth);
        TracedAssertions.assertEqualsFloat(24, result.lines[1].adjustedWidth);
        TracedAssertions.assertEqualsNullableString(null, result.debug.lineDecisions[0].repair);
        TracedAssertions.assertEqualsString("CarryPrevious", result.debug.lineDecisions[1].repair);
        TracedAssertions.assertEqualsInt(10, result.debug.lineDecisions[1].repairPenalty);
        final repairDecision = result.debug.lineDecisions[1].repairDecision;
        TracedAssertions.assertEqualsString("CarryPrevious", repairDecision.kind);
        TracedAssertions.assertEqualsString("ForbiddenAtLineStart", repairDecision.reasonCode);
        TracedAssertions.assertEqualsInt(4, repairDecision.offenderRange.start);
        TracedAssertions.assertEqualsInt(5, repairDecision.offenderRange.end);
        TracedAssertions.assertEqualsInt(3, repairDecision.carriedClusterIndex);
        final repairCandidates = result.debug.lineDecisions[1].repairCandidates;
        TracedAssertions.assertEqualsInt(2, repairCandidates.length);
        TracedAssertions.assertEqualsString("PushIn", repairCandidates[0].kind);
        TracedAssertions.assertEqualsBool(false, repairCandidates[0].accepted);
        TracedAssertions.assertEqualsString("insufficient-capacity", repairCandidates[0].rejectionReason);
        TracedAssertions.assertEqualsString("CarryPrevious", repairCandidates[1].kind);
        TracedAssertions.assertEqualsBool(true, repairCandidates[1].accepted);
        var notesMatch = false;
        final notes = result.debug.lineDecisions[1].notes;
        for (i in 0...notes.length) {
            if (notes[i].indexOf("ForbiddenAtLineStart:。") >= 0 && notes[i].indexOf("carried=文") >= 0) {
                notesMatch = true;
                break;
            }
        }
        TracedAssertions.assertTrue(notesMatch);
    }

    @:test public static function kinsokuFallsBackToLeaveRaggedWhenPreviousLineCannotSpareACluster():Void {
        final t = LineBreakRepairEngineTestSupport.kinsokuStart("kinsokuFallsBackToLeaveRaggedWhenPreviousLineCannotSpareACluster");
        final result = LineBreakRepairEngineTestSupport.fixed().layout(LineBreakRepairEngineTestSupport.input("Coffee。", 96));
        TracedAssertions.assertEqualsInt(2, result.lines.length);
        var coffeeText = "";
        for (i in 0...result.clusters.length)
            if (result.clusters[i].text == "Coffee")
                coffeeText = result.clusters[i].text;
        TracedAssertions.assertEqualsString("Coffee", coffeeText);
        TracedAssertions.assertEqualsString("LeaveRagged", result.debug.lineDecisions[1].repair);
        TracedAssertions.assertEqualsInt(20, result.debug.lineDecisions[1].repairPenalty);
        var notesMatch = false;
        final notes = result.debug.lineDecisions[1].notes;
        for (i in 0...notes.length) {
            if (notes[i].indexOf("ForbiddenAtLineStart:。") >= 0 && notes[i].indexOf("no-room-to-carry") >= 0) {
                notesMatch = true;
                break;
            }
        }
        TracedAssertions.assertTrue(notesMatch);
    }

    @:test public static function kinsokuLeavesGreedyBreakAloneWhenNoForbiddenPunctAtLineStart():Void {
        final t = LineBreakRepairEngineTestSupport.kinsokuStart("kinsokuLeavesGreedyBreakAloneWhenNoForbiddenPunctAtLineStart");
        final result = LineBreakRepairEngineTestSupport.fixed().layout(LineBreakRepairEngineTestSupport.input("中文中文哈哈", 64));
        TracedAssertions.assertEqualsInt(2, result.lines.length);
        TracedAssertions.assertEqualsInt(0, result.lines[0].range.start);
        TracedAssertions.assertEqualsInt(4, result.lines[0].range.end);
        TracedAssertions.assertEqualsInt(4, result.lines[1].range.start);
        TracedAssertions.assertEqualsInt(6, result.lines[1].range.end);
        TracedAssertions.assertEqualsNullableString(null, result.debug.lineDecisions[0].repair);
        TracedAssertions.assertEqualsNullableString(null, result.debug.lineDecisions[1].repair);
    }

    @:test public static function kinsokuLevelNoneLeavesForbiddenMarksAtLineStart():Void {
        final t = LineBreakRepairEngineTestSupport.kinsokuStart("kinsokuLevelNoneLeavesForbiddenMarksAtLineStart");
        final input = LineBreakRepairEngineTestSupport.input("中文中。中", 48);
        final none = LineBreakRepairEngineTestSupport.fixed(KinsokuLevel.None, HangingPunctuationStyle.Disabled).layout(input);
        var allNull = true;
        for (i in 0...none.debug.lineDecisions.length)
            if (none.debug.lineDecisions[i].repair != null)
                allNull = false;
        TracedAssertions.assertTrue(allNull);
        var anyStart3 = false;
        for (i in 0...none.lines.length)
            if (none.lines[i].range.start == 3)
                anyStart3 = true;
        TracedAssertions.assertTrue(anyStart3);
        final basic = LineBreakRepairEngineTestSupport.fixed(KinsokuLevel.Basic, HangingPunctuationStyle.Disabled).layout(input);
        var anyRepair = false;
        for (i in 0...basic.debug.lineDecisions.length)
            if (basic.debug.lineDecisions[i].repair != null)
                anyRepair = true;
        TracedAssertions.assertTrue(anyRepair);
    }

    @:test public static function kinsokuLevelStrictForbidsDashAtLineStart():Void {
        final t = LineBreakRepairEngineTestSupport.kinsokuStart("kinsokuLevelStrictForbidsDashAtLineStart");
        final input = LineBreakRepairEngineTestSupport.input("中文中——文", 48);
        final basic = LineBreakRepairEngineTestSupport.fixed(KinsokuLevel.Basic, HangingPunctuationStyle.Disabled).layout(input);
        var allNull = true;
        for (i in 0...basic.debug.lineDecisions.length)
            if (basic.debug.lineDecisions[i].repair != null)
                allNull = false;
        TracedAssertions.assertTrue(allNull);
        final strict = LineBreakRepairEngineTestSupport.fixed(KinsokuLevel.Strict, HangingPunctuationStyle.Disabled).layout(input);
        var anyRepair = false;
        for (i in 0...strict.debug.lineDecisions.length)
            if (strict.debug.lineDecisions[i].repair != null)
                anyRepair = true;
        TracedAssertions.assertTrue(anyRepair);
    }

    @:test public static function kinsokuPushesLineStartPunctuationIntoPreviousLineWhenTrailingGlueCanShrink():Void {
        final t = LineBreakRepairEngineTestSupport.kinsokuStart("kinsokuPushesLineStartPunctuationIntoPreviousLineWhenTrailingGlueCanShrink");
        final result = new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent("中文中。"), null,
            new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(60)));
        TracedAssertions.assertEqualsInt(1, result.lines.length);
        final line = result.lines[0];
        TracedAssertions.assertEqualsInt(0, line.range.start);
        TracedAssertions.assertEqualsInt(4, line.range.end);
        TracedAssertions.assertEqualsFloat(64, line.naturalWidth);
        TracedAssertions.assertEqualsFloat(56, line.adjustedWidth);
        TracedAssertions.assertEqualsFloat(56, line.visualWidth);
        var cSum = 0.0;
        for (i in 0...result.clusters.length)
            cSum += result.clusters[i].advance;
        TracedAssertions.assertEqualsFloat(56, cSum);
        var gSum = 0.0;
        for (i in 0...result.glyphRuns.length)
            gSum += result.glyphRuns[i].advance;
        TracedAssertions.assertEqualsFloat(56, gSum);
        var stopAdvance = 0.0;
        for (i in 0...result.clusters.length)
            if (result.clusters[i].text == "。")
                stopAdvance = result.clusters[i].advance;
        TracedAssertions.assertEqualsFloat(8, stopAdvance);
        var trailingGlueConsumed = 0.0;
        var resolvedAdvance = 0.0;
        for (i in 0...result.debug.geometryDecisions.length) {
            if (result.debug.geometryDecisions[i].sourceText == "。") {
                trailingGlueConsumed = result.debug.geometryDecisions[i].trailingGlueConsumed;
                resolvedAdvance = result.debug.geometryDecisions[i].resolvedAdvance;
            }
        }
        TracedAssertions.assertEqualsFloat(8, trailingGlueConsumed);
        TracedAssertions.assertEqualsFloat(8, resolvedAdvance);
        TracedAssertions.assertEqualsInt(1, result.debug.lineEdgeTrimDecisions.length);
        TracedAssertions.assertEqualsString("PushIn", result.debug.lineDecisions[0].repair);
        TracedAssertions.assertEqualsInt(2, result.debug.lineDecisions[0].repairPenalty);
        final repairDecision = result.debug.lineDecisions[0].repairDecision;
        TracedAssertions.assertEqualsString("PushIn", repairDecision.kind);
        TracedAssertions.assertEqualsString("ForbiddenAtLineStart", repairDecision.reasonCode);
        TracedAssertions.assertEqualsInt(3, repairDecision.offenderRange.start);
        TracedAssertions.assertEqualsInt(4, repairDecision.offenderRange.end);
        TracedAssertions.assertEqualsInt(3, repairDecision.targetClusterIndex);
        TracedAssertions.assertEqualsFloat(4, repairDecision.shrink);
        TracedAssertions.assertEqualsFloat(8, repairDecision.availableCapacity);
        final repairCandidates = result.debug.lineDecisions[0].repairCandidates;
        TracedAssertions.assertEqualsInt(1, repairCandidates.length);
        TracedAssertions.assertEqualsString("PushIn", repairCandidates[0].kind);
        TracedAssertions.assertEqualsBool(true, repairCandidates[0].accepted);
        TracedAssertions.assertEqualsFloat(4, repairCandidates[0].requiredShrink);
        TracedAssertions.assertEqualsFloat(8, repairCandidates[0].availableCapacity);
        var notesMatch = false;
        final notes = result.debug.lineDecisions[0].notes;
        for (i in 0...notes.length) {
            if (notes[i].indexOf("ForbiddenAtLineStart:。") >= 0 && notes[i].indexOf("pushed-in=4.0") >= 0) {
                notesMatch = true;
                break;
            }
        }
        TracedAssertions.assertTrue(notesMatch);
    }

    @:test public static function lineEndKinsokuMovesDanglingOpenerToNextLine():Void {
        final t = LineBreakRepairEngineTestSupport.kinsokuStart("lineEndKinsokuMovesDanglingOpenerToNextLine");
        final result = LineBreakRepairEngineTestSupport.fixed().layout(LineBreakRepairEngineTestSupport.input("中中中（中中）中", 64));
        for (i in 0...result.lines.length) {
            final line = result.lines[i];
            var lastCluster:Cluster = null;
            for (j in 0...result.clusters.length) {
                if (result.clusters[j].range.end <= line.range.end)
                    lastCluster = result.clusters[j];
            }
            TracedAssertions.assertTrue(lastCluster.text != "（", "line must not end on 开括号: " + LineBreakRepairEngineTestSupport.renderList(result.clusters));
        }
        var anyCarryNext = false;
        for (i in 0...result.debug.lineDecisions.length)
            if (result.debug.lineDecisions[i].repair == "CarryNext")
                anyCarryNext = true;
        TracedAssertions.assertTrue(anyCarryNext);
    }

    @:test public static function longLatinSentenceWrapsAtWordBoundaries():Void {
        final t = LineBreakRepairEngineTestSupport.kinsokuStart("longLatinSentenceWrapsAtWordBoundaries");
        final result = LineBreakRepairEngineTestSupport.layout("The quick brown fox", 160);
        TracedAssertions.assertTrue(result.lines.length > 1, "long Latin must wrap at word boundaries");
        for (i in 0...result.lines.length) {
            final line = result.lines[i];
            final lineClusters:Array<Cluster> = [];
            for (j in 0...result.clusters.length) {
                if (result.clusters[j].range.start >= line.range.start && result.clusters[j].range.end <= line.range.end) {
                    lineClusters.push(result.clusters[j]);
                }
            }
            final first = lineClusters[0];
            final last = lineClusters[lineClusters.length - 1];
            var firstAllSpace = first.text.length > 0;
            for (j in 0...first.text.length)
                if (first.text.charAt(j) != " ")
                    firstAllSpace = false;
            if (firstAllSpace)
                TracedAssertions.assertEqualsFloat(0, first.advance);
            var lastAllSpace = last.text.length > 0;
            for (j in 0...last.text.length)
                if (last.text.charAt(j) != " ")
                    lastAllSpace = false;
            if (lastAllSpace)
                TracedAssertions.assertEqualsFloat(0, last.advance);
        }
    }

    @:test public static function numberWithSuffixSymbolNeverSplitsAcrossLines():Void {
        final t = LineBreakRepairEngineTestSupport.kinsokuStart("numberWithSuffixSymbolNeverSplitsAcrossLines");
        final text = "销量增长了50%呢";
        final result = new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent(text), null,
            new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(120)));
        final lineTexts:Array<String> = [];
        for (i in 0...result.lines.length)
            lineTexts.push(LineBreakRepairEngineTestSupport.lineText(result, i));
        var any50 = false;
        for (i in 0...lineTexts.length)
            if (lineTexts[i].indexOf("50%") >= 0)
                any50 = true;
        TracedAssertions.assertTrue(any50, "50% must stay together: " + LineBreakRepairEngineTestSupport.renderStrings(lineTexts));
        var noneEnd50 = true;
        for (i in 0...lineTexts.length)
            if (StringTools.endsWith(lineTexts[i], "50"))
                noneEnd50 = false;
        TracedAssertions.assertTrue(noneEnd50, "no line may end mid-number: " + LineBreakRepairEngineTestSupport.renderStrings(lineTexts));
    }

    @:test public static function ordinaryNumericFormsDoNotBecomeBibliographicLocators():Void {
        final t = LineBreakRepairEngineTestSupport.kinsokuStart("ordinaryNumericFormsDoNotBecomeBibliographicLocators");
        final tokens = ["3.14", "1,000", "12:34", "2023-08-11"];
        for (i in 0...tokens.length) {
            final token = tokens[i];
            final result = new ExplainableStubParagraphLayoutEngine().layout(new LayoutInput(new TiqianTextContent("中文" + token), null,
                new ParagraphStyle(null, null, null, Ic.Zero, null, null, new LineLengthGrid(false)), new LayoutConstraints(320)));
            TracedAssertions.assertTrue(result.debug.breakOpportunityDecisions.length == 0,
                token + " must keep its existing numeric/token policy: " + LineBreakRepairEngineTestSupport.renderList(result.debug.breakOpportunityDecisions));
        }
    }
}
