package org.tiqian.shaping;

import org.tiqian.core.TextRange;
import org.tiqian.core.TextStyle;
import org.tiqian.font.FontPolicy.FontCandidate;
import org.tiqian.font.FontPolicy.FontDecision;
import org.tiqian.font.FontRole;
import org.tiqian.shaping.TextShaper.ShapingInput;
import org.tiqian.shaping.TextShaper.ExplainableStubTextShaper;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class ExplainableStubTextShaperTest {
    @:test public static function shapesSingleCjkClusterWithOneEmAdvance():Void {
        new TestTraceRecorder("ExplainableStubTextShaperTest").section("shapesSingleCjkClusterWithOneEmAdvance");
        var result = new ExplainableStubTextShaper().shape(ExplainableStubTextShaperTestSupport.input("\u4E2D", FontRole.CjkText));
        TracedAssertions.assertEqualsInt(1, result.clusters.length);
        TracedAssertions.assertEqualsString("中", result.clusters[0].text);
        TracedAssertions.assertEqualsString("中", result.clusters[0].displayText);
        TracedAssertions.assertEqualsFloat(16.0, result.clusters[0].advance);
        TracedAssertions.assertEqualsInt(1, result.glyphRuns[0].glyphs.length);
        TracedAssertions.assertEqualsString("Stub", result.decisions[0].source);
    }

    @:test public static function keepsLatinRunAsSingleShapedClusterWithNominalGlyphs():Void {
        new TestTraceRecorder("ExplainableStubTextShaperTest").section("keepsLatinRunAsSingleShapedClusterWithNominalGlyphs");
        var result = new ExplainableStubTextShaper().shape(ExplainableStubTextShaperTestSupport.input("Hello", FontRole.LatinText));
        TracedAssertions.assertEqualsInt(1, result.clusters.length);
        TracedAssertions.assertEqualsString("Hello", result.clusters[0].text);
        TracedAssertions.assertEqualsFloat(80.0, result.clusters[0].advance);
        TracedAssertions.assertEqualsInt(5, result.glyphRuns[0].glyphs.length);
        TracedAssertions.assertEqualsInt(5, result.decisions[0].glyphCount);
    }

    @:test public static function shapesClreqDashSubstitutionAsTwoEmDisplayCluster():Void {
        new TestTraceRecorder("ExplainableStubTextShaperTest").section("shapesClreqDashSubstitutionAsTwoEmDisplayCluster");
        var result = new ExplainableStubTextShaper().shape(ExplainableStubTextShaperTestSupport.input("\u2014\u2014", FontRole.CjkPunctuation, "\u2E3A"));
        TracedAssertions.assertEqualsString("\u2014\u2014", result.clusters[0].text);
        TracedAssertions.assertEqualsString("\u2E3A", result.clusters[0].displayText);
        TracedAssertions.assertEqualsFloat(32.0, result.clusters[0].advance);
        TracedAssertions.assertEqualsInt(1, result.glyphRuns[0].glyphs.length);
        TracedAssertions.assertEqualsFloat(32.0, result.glyphRuns[0].glyphs[0].advance);
    }
}
