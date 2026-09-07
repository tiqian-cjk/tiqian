package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class InlineBoxLayoutTest {
    @:test public static function inlineEdgesReserveAdvanceAndMoveTheGlyphOrigin():Void {
        final t = new TestTraceRecorder("InlineBoxLayoutTest");
        t.section("inlineEdgesReserveAdvanceAndMoveTheGlyphOrigin");
        final plain = InlineBoxLayoutTestSupport.plain();
        final boxed = InlineBoxLayoutTestSupport.boxedEdges();
        final p = plain.clusters[1];
        final b = boxed.clusters[1];
        final positioned = LayoutQueries.positionedClusters(boxed)[1];
        TracedAssertions.assertEqualsFloatTolerance(p.advance + 8, b.advance, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(3, b.leadingLayoutAdvance, 0.001);
        TracedAssertions.assertEqualsFloatTolerance(positioned.left + 3, positioned.drawX, 0.001);
        TracedAssertions.assertEqualsInt(1, boxed.debug.inlineBoxDecisions.length);
        TracedAssertions.assertEqualsString("InlineBoxBoundaryAdvance", boxed.debug.inlineBoxDecisions[0].reason);
    }

    @:test public static function everyNarrowInlineBoxGetsOuterAutospaceWithoutRoleSpecificCode():Void {
        final t = new TestTraceRecorder("InlineBoxLayoutTest");
        t.section("everyNarrowInlineBoxGetsOuterAutospaceWithoutRoleSpecificCode");
        final boxed = InlineBoxLayoutTestSupport.layout(InlineBoxOuterSpacing.Narrow);
        final reasons = [];
        var roles = true;
        for (d in boxed.debug.autoSpaceDecisions) {
            reasons.push(d.reason);
            if (d.boundaryRole != "InlineBox.Narrow")
                roles = false;
        }
        TracedAssertions.assertEqualsStringArray(["InlineBoxOuterAutoSpace:leading-W-N", "InlineBoxOuterAutoSpace:trailing-N-W"], reasons);
        TracedAssertions.assertTrue(roles);
        TracedAssertions.assertEqualsString("Narrow", boxed.debug.inlineBoxDecisions[0].outerSpacing);
        final source = InlineBoxLayoutTestSupport.layout(InlineBoxOuterSpacing.Source);
        TracedAssertions.assertTrue(source.debug.autoSpaceDecisions.length == 0);
        TracedAssertions.assertEqualsString("Source", source.debug.inlineBoxDecisions[0].outerSpacing);
    }
}
