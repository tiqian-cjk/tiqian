package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.linebreak.*;
import org.tiqian.linebreak.Hyphenator.NoHyphenator;
import org.tiqian.linebreak.Hyphenator.TailHyphenator;
import org.tiqian.linebreak.Hyphenator.SyllableHyphenator;
import org.tiqian.test.trace.*;
import org.tiqian.layout.LineBreaker.*;
import org.tiqian.layout.LineBreaker.LookaheadLineBreaker;
import org.tiqian.layout.LineBreaker.GreedyLineBreaker;
import org.tiqian.layout.ParagraphDpLineBreaker;

class LineBreakRepairEngineTest {
    @:test public static function allCapsAbbreviationIsNeverBroken():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("allCapsAbbreviationIsNeverBroken");
        final r = LineBreakRepairEngineTestSupport.layout("INTERNATIONALIZATION中", 128);
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.hasText(r, "INTERNATIONALIZATION"));
    }

    @:test public static function camelCaseTokenBreaksAtTheHumpWithoutAHyphen():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("camelCaseTokenBreaksAtTheHumpWithoutAHyphen");
        final r = LineBreakRepairEngineTestSupport.layout("PowerPoint", 128);
        TracedAssertions.assertEqualsInt(2, r.lines.length);
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.noHyphen(r));
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.hasText(r, "Power"));
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.hasText(r, "Point"));
    }

    @:test public static function greedyBreakerProducesMultipleLinesWhenWidthOverflows():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("greedyBreakerProducesMultipleLinesWhenWidthOverflows");
        final r = LineBreakRepairEngineTestSupport.layout("中文排版引擎测试", 64);
        TracedAssertions.assertEqualsInt(2, r.lines.length);
        TracedAssertions.assertEqualsInt(8, r.clusters.length);
        final a = r.lines[0];
        final b = r.lines[1];
        TracedAssertions.assertEqualsInt(0, a.range.start);
        TracedAssertions.assertEqualsInt(4, a.range.end);
        TracedAssertions.assertEqualsFloat(64, a.adjustedWidth);
        TracedAssertions.assertEqualsFloat(0, a.top);
        TracedAssertions.assertEqualsFloat(24, a.bottom);
        TracedAssertions.assertEqualsInt(4, b.range.start);
        TracedAssertions.assertEqualsInt(8, b.range.end);
        TracedAssertions.assertEqualsFloat(64, b.adjustedWidth);
        TracedAssertions.assertEqualsFloat(24, b.top);
        TracedAssertions.assertEqualsFloat(48, b.bottom);
        TracedAssertions.assertEqualsInt(2, r.debug.lineDecisions.length);
        var ok = true;
        for (i in 0...r.debug.lineDecisions.length) {
            if (r.debug.lineDecisions[i].kind != "greedy")
                ok = false;
        }
        TracedAssertions.assertTrue(ok);
        TracedAssertions.assertEqualsFloat(48, r.size.height);
    }

    @:test public static function hyphenatedCompoundBreaksAtExistingHyphenWithoutAddingOne():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("hyphenatedCompoundBreaksAtExistingHyphenWithoutAddingOne");
        final r = LineBreakRepairEngineTestSupport.layout("out-of-the-way", 128);
        TracedAssertions.assertEqualsInt(2, r.lines.length);
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.noHyphen(r));
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.hasText(r, "out-"));
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.hasText(r, "way"));
        var x = "";
        for (i in 0...r.clusters.length) {
            if (r.clusters[i].range.end <= r.lines[0].range.end)
                x = r.clusters[i].text;
        }
        TracedAssertions.assertTrue(StringTools.endsWith(x, "-"), "line 0 should end at the existing hyphen: " + x);
    }

    @:test public static function latinSolidusBreaksAfterSlashWithoutAddingHyphen():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("latinSolidusBreaksAfterSlashWithoutAddingHyphen");
        final r = LineBreakRepairEngineTestSupport.layoutWithGrid("TeX/LaTeX", 80, false);
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.hasText(r, "TeX/"));
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.hasText(r, "LaTeX"));
        TracedAssertions.assertEqualsString("TeX/", LineBreakRepairEngineTestSupport.lineText(r, 0));
        TracedAssertions.assertEqualsString("LaTeX", LineBreakRepairEngineTestSupport.lineText(r, 1));
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.noHyphen(r));
    }

    @:test public static function longAllCapsOpaqueTokenHardBreaksWithoutSyntheticHyphen():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("longAllCapsOpaqueTokenHardBreaksWithoutSyntheticHyphen");
        final s = "QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo";
        final r = LineBreakRepairEngineTestSupport.layout(s, 96, null, new NoHyphenator());
        TracedAssertions.assertTrue(r.lines.length > 1);
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.noHyphen(r));
        TracedAssertions.assertTrue(!LineBreakRepairEngineTestSupport.hasText(r, s));
    }

    @:test public static function longLetterBlobStaysOpaqueEvenWhenTailLooksHyphenatable():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("longLetterBlobStaysOpaqueEvenWhenTailLooksHyphenatable");
        LineBreakRepairEngineTestSupport.blobTestTail(t);
    }

    @:test public static function longOpaqueTokenCanBreakEvenWhenItFitsAloneButNotAfterCjkPrefix():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("longOpaqueTokenCanBreakEvenWhenItFitsAloneButNotAfterCjkPrefix");
        LineBreakRepairEngineTestSupport.blobTestFitsAlone(t);
    }

    @:test public static function nonLexicalLetterRunAfterCjkPullsPrefixOntoLooseLineWithoutSyntheticHyphen():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("nonLexicalLetterRunAfterCjkPullsPrefixOntoLooseLineWithoutSyntheticHyphen");
        LineBreakRepairEngineTestSupport.blobTestNonLexical(t);
    }

    @:test public static function opaqueLatinTokenAfterCjkPullsPrefixOntoLooseLine():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("opaqueLatinTokenAfterCjkPullsPrefixOntoLooseLine");
        final prefix = "为什么历史是 ";
        final r = LineBreakRepairEngineTestSupport.layout(prefix + "abc123def456ghi789", 160, new LookaheadLineBreaker(), new NoHyphenator());
        final firstLineText = LineBreakRepairEngineTestSupport.lineText(r, 0);
        TracedAssertions.assertTrue(firstLineText.length > 7,
            "first line should carry part of the opaque token instead of stretching only '"
            + prefix
            + "': "
            + firstLineText);
        TracedAssertions.assertTrue(r.lines[0].hyphenAdvance == 0);
    }

    @:test public static function overlongLatinWordHardBreaksWithAHangingHyphen():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("overlongLatinWordHardBreaksWithAHangingHyphen");
        final r = LineBreakRepairEngineTestSupport.layout("中English", 80, null, new NoHyphenator());
        TracedAssertions.assertTrue(!LineBreakRepairEngineTestSupport.hasText(r, "English"));
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.hasText(r, "En"));
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.hasText(r, "ish"));
        TracedAssertions.assertEqualsInt(2, r.lines.length);
        TracedAssertions.assertTrue(r.lines[0].hyphenAdvance > 0);
    }

    @:test public static function overlongOpaqueLatinTokenHardBreaksWithoutSyntheticHyphen():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("overlongOpaqueLatinTokenHardBreaksWithoutSyntheticHyphen");
        final r = LineBreakRepairEngineTestSupport.layout("abc123def456ghi789", 96, null, new NoHyphenator());
        TracedAssertions.assertTrue(r.lines.length > 1);
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.noHyphen(r));
        TracedAssertions.assertTrue(!LineBreakRepairEngineTestSupport.hasText(r, "abc123def456ghi789"));
        var allWithin = true;
        for (i in 0...r.lines.length) {
            if (r.lines[i].visualWidth > 96)
                allWithin = false;
        }
        TracedAssertions.assertTrue(allWithin);
    }

    @:test public static function progressiveTechnicalBreakFallsThroughStructuralTierBeforeOverstretchingOutsideText():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("progressiveTechnicalBreakFallsThroughStructuralTierBeforeOverstretchingOutsideText");
        final text = "中 ab/cdefghijk";
        final technical = new LineBreakSpan(new TextRange(2, 14), LineBreakPolicy.ProgressiveTechnical);
        final syllables = new SyllableHyphenator([2, 4, 6]);
        final breakers:Array<LineBreaker> = [new GreedyLineBreaker(), new LookaheadLineBreaker(), new ParagraphDpLineBreaker()];
        for (i in 0...breakers.length) {
            final breaker = breakers[i];
            final result = LineBreakRepairEngineTestSupport.layoutWithGrid(text, 100, false, breaker, syllables, [technical]);
            TracedAssertions.assertEqualsInt(7, result.lines[0].range.end, breaker.strategyName);
            TracedAssertions.assertEqualsFloat(0, result.lines[0].hyphenAdvance, breaker.strategyName);
            var hasNote = false;
            for (j in 0...result.debug.lineDecisions[0].notes.length) {
                if (result.debug.lineDecisions[0].notes[j] == "technical-break:Syllable")
                    hasNote = true;
            }
            TracedAssertions.assertTrue(hasNote,
                breaker.strategyName + ": " + LineBreakRepairEngineTestSupport.renderStrings(result.debug.lineDecisions[0].notes));

            var adjIndex = -1;
            for (j in 0...result.debug.justificationDecisions.length) {
                if (result.debug.justificationDecisions[j].lineRange.start == result.lines[0].range.start
                    && result.debug.justificationDecisions[j].lineRange.end == result.lines[0].range.end) {
                    adjIndex = j;
                    break;
                }
            }
            final adjustment = result.debug.justificationDecisions[adjIndex];
            var noneInSpan = true;
            for (j in 0...adjustment.allocations.length) {
                final alloc = adjustment.allocations[j];
                if (alloc.clusterRange.end > technical.range.start && alloc.clusterRange.end < technical.range.end) {
                    noneInSpan = false;
                }
            }
            TracedAssertions.assertTrue(noneInSpan, breaker.strategyName + ": " + LineBreakRepairEngineTestSupport.renderList(adjustment.allocations));
        }
    }

    @:test public static function progressiveTechnicalBreakKeepsCjkBodyUnstretchedInEveryStrategy():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("progressiveTechnicalBreakKeepsCjkBodyUnstretchedInEveryStrategy");
        final text = "中文abcdefghij";
        final technical = new LineBreakSpan(new TextRange(2, 12), LineBreakPolicy.ProgressiveTechnical);
        final syllables = new SyllableHyphenator([4, 7]);
        final breakers:Array<LineBreaker> = [new GreedyLineBreaker(), new LookaheadLineBreaker(), new ParagraphDpLineBreaker()];
        for (i in 0...breakers.length) {
            final breaker = breakers[i];
            final result = LineBreakRepairEngineTestSupport.layoutWithGrid(text, 104, false, breaker, syllables, [technical]);
            TracedAssertions.assertEqualsInt(6, result.lines[0].range.end, breaker.strategyName);
            TracedAssertions.assertEqualsFloat(0, result.lines[0].hyphenAdvance, breaker.strategyName);
            var hasEmergency = false;
            for (j in 0...result.debug.lineDecisions[0].notes.length) {
                if (result.debug.lineDecisions[0].notes[j] == "technical-break:Emergency")
                    hasEmergency = true;
            }
            TracedAssertions.assertTrue(hasEmergency,
                breaker.strategyName + ": " + LineBreakRepairEngineTestSupport.renderStrings(result.debug.lineDecisions[0].notes));

            var adjIndex = -1;
            for (j in 0...result.debug.justificationDecisions.length) {
                if (result.debug.justificationDecisions[j].lineRange.start == result.lines[0].range.start
                    && result.debug.justificationDecisions[j].lineRange.end == result.lines[0].range.end) {
                    adjIndex = j;
                    break;
                }
            }
            final adjustment = result.debug.justificationDecisions[adjIndex];
            TracedAssertions.assertTrue(adjustment.allocations.length > 0, breaker.strategyName);

            var noneCjk = true;
            for (j in 0...adjustment.allocations.length) {
                if (adjustment.allocations[j].kind == "CjkInterChar")
                    noneCjk = false;
            }
            TracedAssertions.assertTrue(noneCjk, breaker.strategyName + ": " + LineBreakRepairEngineTestSupport.renderList(adjustment.allocations));

            var hasEmergencyTracking = false;
            for (j in 0...adjustment.allocations.length) {
                final alloc = adjustment.allocations[j];
                if (alloc.kind == "EmergencyGraphemeTracking" && alloc.clusterRange.start >= technical.range.start) {
                    hasEmergencyTracking = true;
                }
            }
            TracedAssertions.assertTrue(hasEmergencyTracking,
                breaker.strategyName + ": " + LineBreakRepairEngineTestSupport.renderList(adjustment.allocations));
            TracedAssertions.assertEqualsFloatTolerance(0, adjustment.deficitAfter, 0.001, breaker.strategyName);
        }
    }

    @:test public static function progressiveTechnicalCleanBreakMayNotStretchEarlierOpaqueToken():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("progressiveTechnicalCleanBreakMayNotStretchEarlierOpaqueToken");
        final text = "deadbeef1234deadbeef1234 ab.cdEfghijklmnop";
        final terminalTechnicalRange = new TextRange(25, text.length);
        final result = LineBreakRepairEngineTestSupport.layoutWithGrid(text, 300, false, new LookaheadLineBreaker(), new SyllableHyphenator([2, 4, 6]),
            [new LineBreakSpan(terminalTechnicalRange, LineBreakPolicy.ProgressiveTechnical)]);

        var affectedLineIndex = -1;
        for (i in 0...result.debug.lineDecisions.length) {
            final dec = result.debug.lineDecisions[i];
            for (j in 0...dec.notes.length) {
                if (StringTools.startsWith(dec.notes[j], "technical-break:")) {
                    affectedLineIndex = i;
                    break;
                }
            }
            if (affectedLineIndex >= 0)
                break;
        }
        TracedAssertions.assertTrue(affectedLineIndex >= 0, LineBreakRepairEngineTestSupport.renderList(result.debug.lineDecisions));

        var hasEmergencyNote = false;
        for (j in 0...result.debug.lineDecisions[affectedLineIndex].notes.length) {
            if (result.debug.lineDecisions[affectedLineIndex].notes[j] == "technical-break:Emergency")
                hasEmergencyNote = true;
        }
        final lineStrings:Array<String> = [];
        for (i in 0...result.lines.length)
            lineStrings.push(LineBreakRepairEngineTestSupport.lineText(result, i));
        TracedAssertions.assertTrue(hasEmergencyNote,
            "lines="
            + LineBreakRepairEngineTestSupport.renderStrings(lineStrings)
            + " decisions="
            + LineBreakRepairEngineTestSupport.renderList(result.debug.lineDecisions)
            + " adjustments="
            + LineBreakRepairEngineTestSupport.renderList(result.debug.justificationDecisions));

        final affectedLine = result.lines[affectedLineIndex];
        var adjIndex = -1;
        for (i in 0...result.debug.justificationDecisions.length) {
            final dec = result.debug.justificationDecisions[i];
            if (dec.lineRange.start == affectedLine.range.start && dec.lineRange.end == affectedLine.range.end) {
                adjIndex = i;
                break;
            }
        }
        final affectedLineAdjustment = result.debug.justificationDecisions[adjIndex];
        final emergencyTracking:Array<JustificationAllocationInfo> = [];
        for (i in 0...affectedLineAdjustment.allocations.length) {
            if (affectedLineAdjustment.allocations[i].kind == "EmergencyGraphemeTracking") {
                emergencyTracking.push(affectedLineAdjustment.allocations[i]);
            }
        }
        TracedAssertions.assertTrue(emergencyTracking.length > 0, Std.string(affectedLineAdjustment));
        var allInTechnical = true;
        for (i in 0...emergencyTracking.length) {
            if (emergencyTracking[i].clusterRange.start < terminalTechnicalRange.start) {
                allInTechnical = false;
            }
        }
        TracedAssertions.assertTrue(allInTechnical,
            "a later clean break borrowed tracking from the earlier hash: " + LineBreakRepairEngineTestSupport.renderList(emergencyTracking));
    }

    @:test public static function progressiveTechnicalEmergencyIsExposedByCurrentLineStretchNotFullMeasure():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("progressiveTechnicalEmergencyIsExposedByCurrentLineStretchNotFullMeasure");
        final text = "Swift 这边是我最有体感的。JSONDecoder 慢是个老问题，" + "SR-6252[36] 那个 issue 里挖出的根因是底层走 NSJSONSerialization "
            + "再桥接回 Objective-C，swift_dynamicCast 吃掉大量时间。";
        final swiftRange = new TextRange(104, 121);
        final result = LineBreakRepairEngineTestSupport.layoutWithGrid(text, 579, false, new LookaheadLineBreaker(), new NoHyphenator(), [
            new LineBreakSpan(new TextRange(16, 27), LineBreakPolicy.ProgressiveTechnical),
            new LineBreakSpan(new TextRange(67, 86), LineBreakPolicy.ProgressiveTechnical),
            new LineBreakSpan(swiftRange, LineBreakPolicy.ProgressiveTechnical)
        ]);

        final lineTexts:Array<String> = [];
        for (i in 0...result.lines.length)
            lineTexts.push(LineBreakRepairEngineTestSupport.lineText(result, i));
        var affectedLineIndex = -1;
        for (i in 0...lineTexts.length) {
            if (lineTexts[i].indexOf("Objective-C") >= 0) {
                affectedLineIndex = i;
                break;
            }
        }
        TracedAssertions.assertTrue(affectedLineIndex >= 0, LineBreakRepairEngineTestSupport.renderStrings(lineTexts));
        final affectedLine = result.lines[affectedLineIndex];
        TracedAssertions.assertEqualsString("erialization 再桥接回 Objective-C，swift_dy", LineBreakRepairEngineTestSupport.lineText(result, affectedLineIndex));

        var hasEmergency = false;
        for (i in 0...result.debug.lineDecisions[affectedLineIndex].notes.length) {
            if (result.debug.lineDecisions[affectedLineIndex].notes[i] == "technical-break:Emergency")
                hasEmergency = true;
        }
        TracedAssertions.assertTrue(hasEmergency);

        var adjIndex = -1;
        for (i in 0...result.debug.justificationDecisions.length) {
            final dec = result.debug.justificationDecisions[i];
            if (dec.lineRange.start == affectedLine.range.start && dec.lineRange.end == affectedLine.range.end) {
                adjIndex = i;
                break;
            }
        }
        var cjkStretch = 0.0;
        if (adjIndex >= 0) {
            final allocs = result.debug.justificationDecisions[adjIndex].allocations;
            for (i in 0...allocs.length) {
                if (allocs[i].kind == "CjkInterChar") {
                    if (allocs[i].delta > cjkStretch)
                        cjkStretch = allocs[i].delta;
                }
            }
        }
        TracedAssertions.assertTrue(cjkStretch <= 0.001, "current line still stretched CJK body: " + cjkStretch);

        var hasBreakOpp = false;
        for (i in 0...result.debug.breakOpportunityDecisions.length) {
            final opp = result.debug.breakOpportunityDecisions[i];
            if (opp.range.start == swiftRange.start
                && opp.range.end == swiftRange.end
                && opp.tier == "Emergency"
                && opp.reason == "CurrentLineTechnicalEmergencyBreak") {
                hasBreakOpp = true;
                break;
            }
        }
        TracedAssertions.assertTrue(hasBreakOpp);

        var hasTrackingElig = false;
        for (i in 0...result.debug.emergencyTrackingEligibilityDecisions.length) {
            final elig = result.debug.emergencyTrackingEligibilityDecisions[i];
            if (elig.range.start == swiftRange.start
                && elig.range.end == swiftRange.end
                && StringTools.startsWith(elig.reason, "CurrentLineTechnicalTierRejection:")) {
                hasTrackingElig = true;
                break;
            }
        }
        TracedAssertions.assertTrue(hasTrackingElig);
    }

    @:test public static function progressiveTechnicalHardBreakOverridesNumberRunCohesion():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("progressiveTechnicalHardBreakOverridesNumberRunCohesion");
        final text = "aaaaa1234567890bbbb";
        final technical = new LineBreakSpan(new TextRange(0, text.length), LineBreakPolicy.ProgressiveTechnical);
        final breakers:Array<LineBreaker> = [new GreedyLineBreaker(), new LookaheadLineBreaker(), new ParagraphDpLineBreaker()];

        for (i in 0...breakers.length) {
            final breaker = breakers[i];
            final result = LineBreakRepairEngineTestSupport.layoutWithGrid(text, 160, false, breaker, new NoHyphenator(), [technical]);
            TracedAssertions.assertEqualsString("aaaaa12345", LineBreakRepairEngineTestSupport.lineText(result, 0), breaker.strategyName);
            var hasEmergency = false;
            for (j in 0...result.debug.lineDecisions[0].notes.length) {
                if (result.debug.lineDecisions[0].notes[j] == "technical-break:Emergency")
                    hasEmergency = true;
            }
            TracedAssertions.assertTrue(hasEmergency, breaker.strategyName + ": " + LineBreakRepairEngineTestSupport.renderList(result.debug.lineDecisions));
        }
    }

    @:test public static function progressiveTechnicalStructuralBreakFallsThroughToEmergencyBeforeTracking():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("progressiveTechnicalStructuralBreakFallsThroughToEmergencyBeforeTracking");
        final text = "中文ab.cdEfghij";
        final technical = new LineBreakSpan(new TextRange(2, 13), LineBreakPolicy.ProgressiveTechnical);
        final result = LineBreakRepairEngineTestSupport.layoutWithGrid(text, 124, false, new LookaheadLineBreaker(), new SyllableHyphenator([2, 4, 6]),
            [technical]);

        TracedAssertions.assertEqualsString("中文ab.cd", LineBreakRepairEngineTestSupport.lineText(result, 0));
        var hasEmergency = false;
        for (i in 0...result.debug.lineDecisions[0].notes.length) {
            if (result.debug.lineDecisions[0].notes[i] == "technical-break:Emergency")
                hasEmergency = true;
        }
        final lineStrings:Array<String> = [];
        for (i in 0...result.lines.length)
            lineStrings.push(LineBreakRepairEngineTestSupport.lineText(result, i));
        TracedAssertions.assertTrue(hasEmergency,
            "lines="
            + LineBreakRepairEngineTestSupport.renderStrings(lineStrings)
            + " decisions="
            + LineBreakRepairEngineTestSupport.renderList(result.debug.lineDecisions)
            + " adjustments="
            + LineBreakRepairEngineTestSupport.renderList(result.debug.justificationDecisions));

        var allNoHyphen = true;
        for (i in 0...result.lines.length) {
            if (result.lines[i].hyphenAdvance != 0)
                allNoHyphen = false;
        }
        TracedAssertions.assertTrue(allNoHyphen);

        final firstLineAdjustment = result.debug.justificationDecisions[0];
        var noneCjk = true;
        for (i in 0...firstLineAdjustment.allocations.length) {
            if (firstLineAdjustment.allocations[i].kind == "CjkInterChar")
                noneCjk = false;
        }
        TracedAssertions.assertTrue(noneCjk);

        var hasTracking = false;
        for (i in 0...firstLineAdjustment.allocations.length) {
            final alloc = firstLineAdjustment.allocations[i];
            if (alloc.kind == "EmergencyGraphemeTracking" && StringTools.startsWith(alloc.reason, "TerminalTechnicalEmergencyTracking")) {
                hasTracking = true;
                break;
            }
        }
        TracedAssertions.assertTrue(hasTracking);
    }

    @:test public static function unbrokenProgressiveSpanUsesSourceSpaceThenKeepsBodyOpportunitiesAvailable():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("unbrokenProgressiveSpanUsesSourceSpaceThenKeepsBodyOpportunitiesAvailable");
        final text = "甲乙ab cd丙丁戊己";
        final technical = new LineBreakSpan(new TextRange(2, 7), LineBreakPolicy.ProgressiveTechnical);
        final result = LineBreakRepairEngineTestSupport.layoutWithGrid(text, 129, false, null, new NoHyphenator(), [technical]);
        final baseline = LineBreakRepairEngineTestSupport.layoutWithGrid(text, 129, false, null, new NoHyphenator());

        var noneTech = true;
        for (i in 0...result.debug.lineDecisions[0].notes.length) {
            if (StringTools.startsWith(result.debug.lineDecisions[0].notes[i], "technical-break:"))
                noneTech = false;
        }
        TracedAssertions.assertTrue(noneTech);

        final adjustment = result.debug.justificationDecisions[0];
        TracedAssertions.assertTrue(adjustment.allocations.length > 0);

        final baselineRanges:Array<TextRange> = [];
        for (i in 0...baseline.lines.length)
            baselineRanges.push(baseline.lines[i].range);
        final resultRanges:Array<TextRange> = [];
        for (i in 0...result.lines.length)
            resultRanges.push(result.lines[i].range);
        TracedAssertions.assertEqualsTextRangeArray(baselineRanges, resultRanges);
        TracedAssertions.assertEqualsFloatTolerance(0, adjustment.deficitAfter, 0.001);

        var hasWhitespaceStretch = false;
        for (i in 0...adjustment.allocations.length) {
            final alloc = adjustment.allocations[i];
            if (alloc.clusterRange.start == 4
                && alloc.clusterRange.end == 5
                && alloc.kind == "ProgressiveTechnical"
                && alloc.reason == "ProgressiveTechnicalWhitespaceStretch") {
                hasWhitespaceStretch = true;
                break;
            }
        }
        TracedAssertions.assertTrue(hasWhitespaceStretch, LineBreakRepairEngineTestSupport.renderList(adjustment.allocations));

        var hasRemainingBodyOpp = false;
        for (i in 0...adjustment.allocations.length) {
            final alloc = adjustment.allocations[i];
            if (alloc.clusterRange.end <= technical.range.start || alloc.clusterRange.start >= technical.range.end) {
                hasRemainingBodyOpp = true;
                break;
            }
        }
        TracedAssertions.assertTrue(hasRemainingBodyOpp,
            "bounded technical whitespace must not freeze the remaining body opportunities: " +
            LineBreakRepairEngineTestSupport.renderList(adjustment.allocations));
    }

    @:test public static function urlLikeLatinTokenBreaksAtSeparatorsWithoutSyntheticHyphen():Void {
        final t = new TestTraceRecorder("LineBreakRepairEngineTest");
        t.section("urlLikeLatinTokenBreaksAtSeparatorsWithoutSyntheticHyphen");
        final url = "https://example.com/path/to/abc123def456ghi789";
        final result = LineBreakRepairEngineTestSupport.layout(url, 128, null, new NoHyphenator());

        TracedAssertions.assertTrue(result.lines.length > 1);
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.noHyphen(result));
        TracedAssertions.assertTrue(!LineBreakRepairEngineTestSupport.hasText(result, url));
        var anyEndsWithSlash = false;
        for (i in 0...result.clusters.length) {
            if (StringTools.endsWith(result.clusters[i].text, "/"))
                anyEndsWithSlash = true;
        }
        TracedAssertions.assertTrue(anyEndsWithSlash);
        TracedAssertions.assertTrue(LineBreakRepairEngineTestSupport.hasText(result, "example."));

        var noneForbidden = true;
        for (i in 0...result.debug.lineDecisions.length) {
            final dec = result.debug.lineDecisions[i];
            if (dec.repairDecision != null && dec.repairDecision.reasonCode == "ForbiddenAtLineStart") {
                noneForbidden = false;
            }
        }
        TracedAssertions.assertTrue(noneForbidden, "URL separators are LatinText and must not trigger CJK line-start kinsoku");
    }
}
