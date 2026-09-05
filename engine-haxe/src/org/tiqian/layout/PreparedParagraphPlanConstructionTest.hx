package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.layout.PreparedParagraph.PreparedParagraphFns;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class PreparedParagraphPlanConstructionTest {
    @:test public static function openTypeFeaturesAndRenderFontFamilyAttachPerCluster():Void {
        final t = new TestTraceRecorder("PreparedParagraphPlanConstructionTest");
        t.section("openTypeFeaturesAndRenderFontFamilyAttachPerCluster");
        final json = PreparedParagraphFns.toPreparedParagraphJson(PreparedParagraphPlanConstructionTestSupport.openTypeFeaturesAndRenderFontFamilyAttachPerCluster(),
            true);
        TracedAssertions.assertTrue(json.indexOf("\"openTypeFeatures\":[\"kern\",\"liga\"]") >= 0, json);
        TracedAssertions.assertTrue(json.indexOf("\"renderFontFamily\":\"Noto Serif CJK\"") >= 0, json);
        TracedAssertions.assertFalse(json.indexOf("shapingBoundary") >= 0, json);
    }

    @:test public static function multiUnitClusterMarksShapingBoundary():Void {
        final t = new TestTraceRecorder("PreparedParagraphPlanConstructionTest");
        t.section("multiUnitClusterMarksShapingBoundary");
        final json = PreparedParagraphFns.toPreparedParagraphJson(PreparedParagraphPlanConstructionTestSupport.multiUnitClusterMarksShapingBoundary());
        TracedAssertions.assertTrue(json.indexOf("\"shapingBoundary\":true") >= 0, json);
    }

    @:test public static function inlineObjectCellEmitsAdvanceOverride():Void {
        final t = new TestTraceRecorder("PreparedParagraphPlanConstructionTest");
        t.section("inlineObjectCellEmitsAdvanceOverride");
        final r = PreparedParagraphPlanConstructionTestSupport.inlineObjectCellEmitsAdvanceOverride();
        final json = PreparedParagraphFns.toPreparedParagraphJson(r, true);
        TracedAssertions.assertTrue(json.indexOf("\"inlineObject\":24") >= 0, json);
        TracedAssertions.assertTrue(json.indexOf("\"advance\":10") >= 0, json);
        final emptyClusters = [];
        for (i in 0...r.clusters.length) {
            final c = r.clusters[i];
            emptyClusters.push(new Cluster(c.range, c.text, c.fontKey, c.advance, c.range.start == 1 ? "" : c.displayText));
        }
        final emptyDisplay = new LayoutResult(r.input, r.size, emptyClusters, r.glyphRuns, r.lines, r.debug);
        final plain = PreparedParagraphFns.toPreparedParagraphJson(emptyDisplay, false);
        TracedAssertions.assertFalse(plain.indexOf("\"inlineObject\"") >= 0, plain);
        TracedAssertions.assertFalse(plain.indexOf("\"rangeStart\":1") >= 0, plain);
        final evidence = PreparedParagraphFns.toPreparedParagraphJson(emptyDisplay, true);
        TracedAssertions.assertTrue(evidence.indexOf("\"inlineObject\":24") >= 0, evidence);
    }

    @:test public static function styleDeltaListsOnlyPaintFields():Void {
        final t = new TestTraceRecorder("PreparedParagraphPlanConstructionTest");
        t.section("styleDeltaListsOnlyPaintFields");
        final json = PreparedParagraphFns.toPreparedParagraphJson(PreparedParagraphPlanConstructionTestSupport.styleDeltaListsOnlyPaintFields(), true);
        TracedAssertions.assertTrue(json.indexOf("\"style\":{\"fontSize\":20,\"fontWeight\":700,\"italic\":true}") >= 0, json);
        TracedAssertions.assertTrue(json.indexOf("\"style\":{}") >= 0, json);
        TracedAssertions.assertEquals(2, json.split("\"style\":").length - 1);
    }

    @:test public static function dashClusterEmitsShapingEvidenceBlock():Void {
        return PreparedParagraphPlanConstructionTestSupport.runEvidence("dashClusterEmitsShapingEvidenceBlock",
            PreparedParagraphPlanConstructionTestSupport.dashClusterEmitsShapingEvidenceBlock());
    }

    @:test public static function punctuationInkFloorAndLatinRoleMarkCells():Void {
        return PreparedParagraphPlanConstructionTestSupport.runPunctuation();
    }

    @:test public static function zeroWidthBreakClusterSurvivesEmptyDisplayText():Void {
        return PreparedParagraphPlanConstructionTestSupport.runZeroWidth();
    }

    @:test public static function paragraphEvidenceEmitsEverySection():Void {
        return PreparedParagraphPlanConstructionTestSupport.runParagraphEvidence();
    }

    @:test public static function negativeZeroAndExponentWidthsNormalize():Void {
        return PreparedParagraphPlanConstructionTestSupport.runNegativeZero();
    }

    @:test public static function jsonStringEscapesQuotesBackslashesAndControlCharacters():Void {
        return PreparedParagraphPlanConstructionTestSupport.runEscapes();
    }

    @:test public static function planWithDiagnosticsListsCapabilityIssuesAndAdvanceSuspects():Void {
        return PreparedParagraphPlanConstructionTestSupport.runDiagnostics();
    }
}
