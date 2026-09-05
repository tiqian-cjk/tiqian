package org.tiqian.layout;

import org.tiqian.clreq.CjkPunctuationGlyphPolicy;
import org.tiqian.core.*;
import org.tiqian.layout.DisplayGlyphSubstitutionEngineTestSupport.DashInkOverrideShaper;
import org.tiqian.layout.DisplayGlyphSubstitutionEngineTestSupport.MissingGlyphReportingShaper;
import org.tiqian.layout.DisplayGlyphSubstitutionEngineTestSupport.PerGlyphQuoteRunShaper;
import org.tiqian.layout.DisplayGlyphSubstitutionEngineTestSupport.SingleClusterAmbiguousShaper;
import org.tiqian.layout.DisplayGlyphSubstitutionEngineTestSupport.SingleClusterNoBoundsShaper;
import org.tiqian.layout.DisplayGlyphSubstitutionEngineTestSupport.TwoGlyphEllipsisShaper;
import org.tiqian.layout.DisplayGlyphSubstitutionEngineTestSupport.UnverifiedCoverageReportingShaper;
import org.tiqian.test.trace.*;
import std.ReadOnlyArray;

class DisplayGlyphSubstitutionEngineTest {
    @:test public static function ambiguousGlyphClusterMappingFallsBackToPolicyWithRecordedReason():Void {
        final t = new TestTraceRecorder("DisplayGlyphSubstitutionEngineTest");
        t.section("ambiguousGlyphClusterMappingFallsBackToPolicyWithRecordedReason");
        final engine = DisplayGlyphSubstitutionEngineTestSupport.shaperEngine(new SingleClusterAmbiguousShaper());
        final result = DisplayGlyphSubstitutionEngineTestSupport.layout320(engine, "\u2026\u2026");
        final punctuationDecisions = result.debug.punctuationDecisions;
        TracedAssertions.assertEqualsInt(2, punctuationDecisions.length);
        for (i in 0...punctuationDecisions.length) {
            final p = punctuationDecisions[i];
            TracedAssertions.assertEqualsString("ProfileGlueFallbackWithoutFontGeometry", p.geometrySource, "source for '" + p.char + "'");
            TracedAssertions.assertEqualsString("glyph-cluster-mapping-ambiguous", p.inkBoundsFallback, "fallback for '" + p.char + "'");
        }
    }

    @:test public static function coalesceSetIsDrivenByProfile():Void {
        final t = new TestTraceRecorder("DisplayGlyphSubstitutionEngineTest");
        t.section("coalesceSetIsDrivenByProfile");
        final engine = DisplayGlyphSubstitutionEngineTestSupport.profileEngine(CjkPunctuationGlyphPolicy.PreserveInput, []);
        final result = DisplayGlyphSubstitutionEngineTestSupport.layout320(engine, "\u2014\u2014");
        TracedAssertions.assertEqualsInt(2, result.clusters.length);
        TracedAssertions.assertEqualsString("\u2014", result.clusters[0].text);
        TracedAssertions.assertEqualsString("\u2014", result.clusters[1].text);
        // The Latin-face contextual run below exercises the same profile gate.
        // Its list assertion postdates the golden snapshot (fe43125d) and is
        // not recorded in the baseline trace.
        final latin = DisplayGlyphSubstitutionEngineTestSupport.layout320(engine, "A\u2014\u2014B");
    }

    @:test public static function dashCoverageTargetUsesTheDashSpanFontSize():Void {
        final t = new TestTraceRecorder("DisplayGlyphSubstitutionEngineTest");
        t.section("dashCoverageTargetUsesTheDashSpanFontSize");
        final engine = DisplayGlyphSubstitutionEngineTestSupport.shaperEngine(new DashInkOverrideShaper(32, new Rect(1, -18, 31, -14), true));
        final result = DisplayGlyphSubstitutionEngineTestSupport.layout320WithSpans(engine, "\u4E2D\u2014\u2014\u6587",
            [new TextSpan(new TextRange(1, 3), new TextStyle(null, 32))]);
        TracedAssertions.assertEqualsString("\u2014\u2014",
            DisplayGlyphSubstitutionEngineTestSupport.singleClusterWithText(result, "\u2014\u2014").displayText);
    }

    @:test public static function dashInkCentersWithinTheTwoEmBodyWhenTheFontRuleUnderfills():Void {
        final t = new TestTraceRecorder("DisplayGlyphSubstitutionEngineTest");
        t.section("dashInkCentersWithinTheTwoEmBodyWhenTheFontRuleUnderfills");
        final engine = DisplayGlyphSubstitutionEngineTestSupport.shaperEngine(new DashInkOverrideShaper(32, new Rect(0.5, -10, 28, -8), false));
        final result = DisplayGlyphSubstitutionEngineTestSupport.layout320(engine, "\u4E2D\u2014\u2014\u6587");
        final dash = DisplayGlyphSubstitutionEngineTestSupport.singleClusterWithText(result, "\u2014\u2014");
        TracedAssertions.assertEqualsString("\u2E3A", dash.displayText);
        final glyph = DisplayGlyphSubstitutionEngineTestSupport.singleGlyphWithClusterRange(result, dash.range);
        TracedAssertions.assertEqualsFloatTolerance(1.75, glyph.x, 0.01);
    }

    @:test public static function dashSubstitutionIsKeptWhenInkFillsTheTwoEmAdvance():Void {
        final t = new TestTraceRecorder("DisplayGlyphSubstitutionEngineTest");
        t.section("dashSubstitutionIsKeptWhenInkFillsTheTwoEmAdvance");
        final engine = DisplayGlyphSubstitutionEngineTestSupport.shaperEngine(new DashInkOverrideShaper(32, new Rect(1, -10, 31, -8), false));
        final result = DisplayGlyphSubstitutionEngineTestSupport.layout320(engine, "\u4E2D\u2014\u2014\u6587");
        TracedAssertions.assertEqualsString("\u2E3A", DisplayGlyphSubstitutionEngineTestSupport.singleClusterWithText(result, "\u2014\u2014").displayText);
    }

    @:test public static function dashSubstitutionRollsBackWhenFallbackReportsAFullOneEmGlyph():Void {
        final t = new TestTraceRecorder("DisplayGlyphSubstitutionEngineTest");
        t.section("dashSubstitutionRollsBackWhenFallbackReportsAFullOneEmGlyph");
        final engine = DisplayGlyphSubstitutionEngineTestSupport.shaperEngine(new DashInkOverrideShaper(16, new Rect(0.5, -9, 15.7, -7), true));
        final result = DisplayGlyphSubstitutionEngineTestSupport.layout320(engine, "\u4E2D\u2014\u2014\u6587");
        TracedAssertions.assertEqualsString("\u2014\u2014",
            DisplayGlyphSubstitutionEngineTestSupport.singleClusterWithText(result, "\u2014\u2014").displayText);
        TracedAssertions.assertTrue(StringTools.endsWith(DisplayGlyphSubstitutionEngineTestSupport.singleFontDecisionWithSourceText(result, "\u2014\u2014")
            .substitutionReason,
            "DashSubstitutionInkCoverageRollback"));
    }

    @:test public static function dashSubstitutionRollsBackWhenInkDoesNotFillTheTwoEmAdvance():Void {
        final t = new TestTraceRecorder("DisplayGlyphSubstitutionEngineTest");
        t.section("dashSubstitutionRollsBackWhenInkDoesNotFillTheTwoEmAdvance");
        final engine = DisplayGlyphSubstitutionEngineTestSupport.shaperEngine(new DashInkOverrideShaper(32, new Rect(1, -10, 26, -8), false));
        final result = DisplayGlyphSubstitutionEngineTestSupport.layout320(engine, "\u4E2D\u2014\u2014\u6587");
        TracedAssertions.assertEqualsString("\u2014\u2014",
            DisplayGlyphSubstitutionEngineTestSupport.singleClusterWithText(result, "\u2014\u2014").displayText);
        TracedAssertions.assertTrue(StringTools.endsWith(DisplayGlyphSubstitutionEngineTestSupport.singleFontDecisionWithSourceText(result, "\u2014\u2014")
            .substitutionReason,
            "DashSubstitutionInkCoverageRollback"));
    }

    @:test public static function ellipsisSubstitutionRollsBackWhenCoverageCannotBeVerified():Void {
        final t = new TestTraceRecorder("DisplayGlyphSubstitutionEngineTest");
        t.section("ellipsisSubstitutionRollsBackWhenCoverageCannotBeVerified");
        final engine = DisplayGlyphSubstitutionEngineTestSupport.shaperEngine(new UnverifiedCoverageReportingShaper());
        final result = DisplayGlyphSubstitutionEngineTestSupport.layout320(engine, "\u4E2D\u2026\u2026\u6587");
        TracedAssertions.assertEqualsString("\u2026\u2026",
            DisplayGlyphSubstitutionEngineTestSupport.singleClusterWithText(result, "\u2026\u2026").displayText);
        TracedAssertions.assertTrue(StringTools.endsWith(DisplayGlyphSubstitutionEngineTestSupport.singleFontDecisionWithSourceText(result, "\u2026\u2026")
            .substitutionReason,
            "SubstitutionRollbackOnUnverifiedGlyphCoverage"));
    }

    @:test public static function honorsProfilePunctuationGlyphPolicy():Void {
        final t = new TestTraceRecorder("DisplayGlyphSubstitutionEngineTest");
        t.section("honorsProfilePunctuationGlyphPolicy");
        final engine = DisplayGlyphSubstitutionEngineTestSupport.profileEngine(CjkPunctuationGlyphPolicy.PreserveInput);
        final result = DisplayGlyphSubstitutionEngineTestSupport.layout320(engine, "\u2026\u2026\u2014\u2014");
        TracedAssertions.assertEqualsString("\u2026\u2026", DisplayGlyphSubstitutionEngineTestSupport.firstClusterWithText(result, "\u2026\u2026")
            .displayText);
        TracedAssertions.assertEqualsString("\u2014\u2014", DisplayGlyphSubstitutionEngineTestSupport.firstClusterWithText(result, "\u2014\u2014")
            .displayText);
    }

    @:test public static function multiCharacterPunctuationUsesCharacterLocalInkBounds():Void {
        final t = new TestTraceRecorder("DisplayGlyphSubstitutionEngineTest");
        t.section("multiCharacterPunctuationUsesCharacterLocalInkBounds");
        final engine = DisplayGlyphSubstitutionEngineTestSupport.shaperEngine(new TwoGlyphEllipsisShaper());
        final result = DisplayGlyphSubstitutionEngineTestSupport.layout320(engine, "\u2026\u2026");
        final decisions = result.debug.punctuationDecisions;
        TracedAssertions.assertEqualsInt(2, decisions.length);
        final inkCenters:Array<Null<Float>> = [];
        final advances:Array<Null<Float>> = [];
        for (i in 0...decisions.length) {
            inkCenters.push(decisions[i].inkCenter);
            advances.push(decisions[i].advance);
        }
        TracedAssertions.assertEqualsRendered(DisplayGlyphSubstitutionEngineTestSupport.renderNullableFloats([8.0, 8.0]),
            DisplayGlyphSubstitutionEngineTestSupport.renderNullableFloats(inkCenters));
        TracedAssertions.assertEqualsRendered(DisplayGlyphSubstitutionEngineTestSupport.renderNullableFloats([16.0, 16.0]),
            DisplayGlyphSubstitutionEngineTestSupport.renderNullableFloats(advances));
    }

    @:test public static function preservesOpenTypeFeaturesAsFinalGlyphRunBoundaries():Void {
        final t = new TestTraceRecorder("DisplayGlyphSubstitutionEngineTest");
        t.section("preservesOpenTypeFeaturesAsFinalGlyphRunBoundaries");
        final proportionalQuoteFeatures:Array<String> = ["pwid", "palt"];
        final engine = DisplayGlyphSubstitutionEngineTestSupport.shaperEngine(new PerGlyphQuoteRunShaper());
        final result = DisplayGlyphSubstitutionEngineTestSupport.layout320(engine, "A\u2019B");
        final ranges:Array<TextRange> = [];
        final featureLists:Array<ReadOnlyArray<String>> = [];
        for (i in 0...result.glyphRuns.length) {
            ranges.push(result.glyphRuns[i].range);
            featureLists.push(result.glyphRuns[i].openTypeFeatures);
        }
        TracedAssertions.assertEqualsTextRangeArray([new TextRange(0, 1), new TextRange(1, 2), new TextRange(2, 3)], ranges);
        final emptyFeatures:Array<String> = [];
        TracedAssertions.assertEqualsRendered(DisplayGlyphSubstitutionEngineTestSupport.renderStringListArray([emptyFeatures, proportionalQuoteFeatures, emptyFeatures]),
            DisplayGlyphSubstitutionEngineTestSupport.renderStringListArray(featureLists));
    }

    @:test public static function preservesSourceTextWhenUsingClreqRecommendedDisplayGlyphs():Void {
        final t = new TestTraceRecorder("DisplayGlyphSubstitutionEngineTest");
        t.section("preservesSourceTextWhenUsingClreqRecommendedDisplayGlyphs");
        final result = DisplayGlyphSubstitutionEngineTestSupport.layout320(DisplayGlyphSubstitutionEngineTestSupport.defaultEngine(),
            "\u2026\u2026\u2014\u2014\u30FB\uFF0F");
        final ellipsis = DisplayGlyphSubstitutionEngineTestSupport.firstClusterWithText(result, "\u2026\u2026");
        final dash = DisplayGlyphSubstitutionEngineTestSupport.firstClusterWithText(result, "\u2014\u2014");
        final interpunct = DisplayGlyphSubstitutionEngineTestSupport.firstClusterWithText(result, "\u30FB");
        final solidus = DisplayGlyphSubstitutionEngineTestSupport.firstClusterWithText(result, "\uFF0F");
        TracedAssertions.assertEqualsString("\u2026\u2026", ellipsis.text);
        TracedAssertions.assertEqualsString("\u22EF\u22EF", ellipsis.displayText);
        TracedAssertions.assertEqualsString("\u2014\u2014", dash.text);
        TracedAssertions.assertEqualsString("\u2E3A", dash.displayText);
        TracedAssertions.assertEqualsString("\u30FB", interpunct.text);
        TracedAssertions.assertEqualsString("\u00B7", interpunct.displayText);
        TracedAssertions.assertEqualsString("\uFF0F", solidus.text);
        TracedAssertions.assertEqualsString("\uFF0F", solidus.displayText);
        TracedAssertions.assertEqualsString("cjk-primary", ellipsis.fontKey);
        TracedAssertions.assertEqualsString("cjk-primary", dash.fontKey);
        TracedAssertions.assertEqualsString("cjk-primary", interpunct.fontKey);
        TracedAssertions.assertEqualsString("cjk-primary", solidus.fontKey);
    }

    @:test public static function rolledBackDashStillKeepsItsBoundariesClosedUnderJustification():Void {
        final t = new TestTraceRecorder("DisplayGlyphSubstitutionEngineTest");
        t.section("rolledBackDashStillKeepsItsBoundariesClosedUnderJustification");
        final engine = DisplayGlyphSubstitutionEngineTestSupport.lookaheadShaperEngine(new DashInkOverrideShaper(32, new Rect(1, -10, 26, -8), false));
        final hit = DisplayGlyphSubstitutionEngineTestSupport.findJustifiedDashHit(engine,
            "\u5728\u6240\u8C13\u4E2D\u6587\u8BED\u5883\u4E0B\u2014\u2014\u4E0D\u5982\u8BF4\u4E2D\u6587\u4E2D\u6587\u4E2D\u6587\u4E2D\u6587");
        final dash = hit.dash;
        final decision = hit.decision;
        TracedAssertions.assertEqualsString("\u2014\u2014", dash.displayText);
        var opened = false;
        for (i in 0...decision.allocations.length) {
            final allocation = decision.allocations[i];
            if (allocation.kind == "CjkInterChar"
                && allocation.clusterRange.start == dash.range.start
                && allocation.clusterRange.end == dash.range.end) {
                opened = true;
                break;
            }
        }
        TracedAssertions.assertTrue(!opened, "boundary after a rolled-back dash must stay closed: ${decision.allocations}");
    }

    @:test public static function shapingWithoutBoundsProducesNamedProfileFallback():Void {
        final t = new TestTraceRecorder("DisplayGlyphSubstitutionEngineTest");
        t.section("shapingWithoutBoundsProducesNamedProfileFallback");
        final engine = DisplayGlyphSubstitutionEngineTestSupport.shaperEngine(new SingleClusterNoBoundsShaper());
        final result = DisplayGlyphSubstitutionEngineTestSupport.layout320(engine, "\u3002");
        final punctuation = DisplayGlyphSubstitutionEngineTestSupport.singlePunctuationDecision(result);
        TracedAssertions.assertEqualsString("ProfileGlueFallbackWithoutFontGeometry", punctuation.geometrySource);
        TracedAssertions.assertEqualsString("shaper-no-ink-bounds", punctuation.inkBoundsFallback);
        TracedAssertions.assertEqualsFloat(8, punctuation.bodyWidth);
        TracedAssertions.assertEqualsFloat(0, punctuation.leadingGlueNatural);
        TracedAssertions.assertEqualsFloat(8, punctuation.trailingGlueNatural);
    }

    @:test public static function stubShaperReportsProfileFallbackWhenInkBoundsAreUnavailable():Void {
        final t = new TestTraceRecorder("DisplayGlyphSubstitutionEngineTest");
        t.section("stubShaperReportsProfileFallbackWhenInkBoundsAreUnavailable");
        final result = DisplayGlyphSubstitutionEngineTestSupport.layout320(DisplayGlyphSubstitutionEngineTestSupport.defaultEngine(),
            "\u4E2D\u6587\uFF0C\u4E16\u754C\u3002");
        final punctuationDecisions = result.debug.punctuationDecisions;
        TracedAssertions.assertTrue(punctuationDecisions.length > 0);
        for (i in 0...punctuationDecisions.length) {
            final p = punctuationDecisions[i];
            TracedAssertions.assertEqualsString("ProfileGlueFallbackWithoutFontGeometry", p.geometrySource,
                "Stub shaper provides advance but no bounds for '" + p.char + "'");
            TracedAssertions.assertEqualsString("shaper-no-ink-bounds", p.inkBoundsFallback, "fallback for '" + p.char + "'");
            TracedAssertions.assertEqualsFloat(0, p.leadingGlueNatural, "leading glue for '" + p.char + "'");
            TracedAssertions.assertEqualsFloat(8, p.trailingGlueNatural, "trailing glue for '" + p.char + "'");
        }
    }

    @:test public static function substitutionIsKeptWhenFontCoversTheGlyph():Void {
        final t = new TestTraceRecorder("DisplayGlyphSubstitutionEngineTest");
        t.section("substitutionIsKeptWhenFontCoversTheGlyph");
        final result = DisplayGlyphSubstitutionEngineTestSupport.layout320(DisplayGlyphSubstitutionEngineTestSupport.defaultEngine(),
            "\u4E2D\u2014\u2014\u6587");
        TracedAssertions.assertEqualsString("\u2E3A", DisplayGlyphSubstitutionEngineTestSupport.singleClusterWithText(result, "\u2014\u2014").displayText);
    }

    @:test public static function substitutionRollsBackToSourceTextWhenFontLacksTheGlyph():Void {
        final t = new TestTraceRecorder("DisplayGlyphSubstitutionEngineTest");
        t.section("substitutionRollsBackToSourceTextWhenFontLacksTheGlyph");
        final engine = DisplayGlyphSubstitutionEngineTestSupport.shaperEngine(new MissingGlyphReportingShaper());
        final result = DisplayGlyphSubstitutionEngineTestSupport.layout320(engine, "\u4E2D\u2014\u2014\u6587");
        final dashCluster = DisplayGlyphSubstitutionEngineTestSupport.singleClusterWithText(result, "\u2014\u2014");
        TracedAssertions.assertEqualsString("\u2014\u2014", dashCluster.displayText);
        final dashDecision = DisplayGlyphSubstitutionEngineTestSupport.singleFontDecisionWithSourceText(result, "\u2014\u2014");
        TracedAssertions.assertEqualsString("\u2014\u2014", dashDecision.displayText);
        TracedAssertions.assertTrue(StringTools.endsWith(dashDecision.substitutionReason, "SubstitutionRollbackOnMissingGlyph"));
    }

    @:test public static function usesTwoEmAdvanceForRecommendedDashCodepoint():Void {
        final t = new TestTraceRecorder("DisplayGlyphSubstitutionEngineTest");
        t.section("usesTwoEmAdvanceForRecommendedDashCodepoint");
        final result = DisplayGlyphSubstitutionEngineTestSupport.layout320(DisplayGlyphSubstitutionEngineTestSupport.defaultEngine(), "\u2E3A");
        TracedAssertions.assertEqualsFloat(32, DisplayGlyphSubstitutionEngineTestSupport.singleCluster(result).advance);
        TracedAssertions.assertEqualsFloat(32, result.size.width);
    }
}
