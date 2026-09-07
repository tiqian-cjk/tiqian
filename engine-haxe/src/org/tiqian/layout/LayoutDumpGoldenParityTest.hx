package org.tiqian.layout;

import org.tiqian.test.LayoutFixtures.EarlyLayoutFixtures;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions.assertTrue;

class LayoutDumpGoldenParityTest {
    public static function layoutDecisionDumpsMatchEmbeddedGolden():Void {
        final t = new TestTraceRecorder("LayoutDumpGoldenParityTest");
        t.section("layoutDecisionDumpsMatchEmbeddedGolden");
        final failures = [];
        for (fixture in EarlyLayoutFixtures.all) {
            final golden = LayoutDumpGoldens.byId().get(fixture.id);
            if (golden == null) {
                failures.push("missing embedded golden for fixture '" + fixture.id + "' — run with TIQIAN_UPDATE_GOLDEN=1 on the JVM, then rebuild");
                continue;
            }
            final actual = LayoutDumpFormat.layoutFixtureDump(fixture);
            if (golden != actual)
                failures.push(LayoutDumpFormat.layoutDumpDiffMessage(fixture.id, golden, actual));
        }
        assertTrue(failures.length == 0,
            failures.join("\n\n") + "\n\nIf the change is intentional, regenerate with TIQIAN_UPDATE_GOLDEN=1 on the JVM and review the golden diff.");
    }
}
