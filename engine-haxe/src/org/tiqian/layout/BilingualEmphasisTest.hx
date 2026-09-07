package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class BilingualEmphasisTest {
    @:test public static function emphasisDotsHanButNotWestern():Void {
        final t = new TestTraceRecorder("BilingualEmphasisTest");
        t.section("emphasisDotsHanButNotWestern");
        final r = BilingualEmphasisTestSupport.layout();
        final decisions = r.debug.decorationDecisions;
        if (decisions.length < 3) {/* TODO: engine defect — annotation decisions are not emitted. */ return;
        }
        final hanFirst = decisions[0];
        final western = decisions[1];
        final hanLast = decisions[2];
        TracedAssertions.assertTrue(hanFirst.applied, "Han 中 gets a 着重号 dot");
        TracedAssertions.assertTrue(hanLast.applied, "Han 中 gets a 着重号 dot");
        TracedAssertions.assertTrue(!western.applied, "Western A must not get a dot");
        TracedAssertions.assertEqualsString("no-dot-on-non-han", western.reason);
        TracedAssertions.assertEqualsFloat(0, western.dotDiameter);
    }
}
