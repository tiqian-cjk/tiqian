package org.tiqian.layout;

import org.tiqian.test.LayoutFixtures.EarlyLayoutFixtures;
import org.tiqian.test.ShapingEvidence.RecordedEvidenceFontMetricsResolver;
import org.tiqian.test.ShapingEvidence.RecordedEvidenceTextShaper;
import org.tiqian.test.ShapingEvidenceJson;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class RecordedEvidenceGoldenParityTest {
    @:test
    public static function recordedEvidenceLayoutMatchesGolden():Void {
        final testTrace = new TestTraceRecorder("RecordedEvidenceGoldenParityTest");
        testTrace.section("recordedEvidenceLayoutMatchesGolden");
        if (RecordedShapingEvidenceData.evidenceJson().length == 0) {
            TracedAssertions.fail("No recorded shaping evidence embedded — record on the JVM with "
                + "TIQIAN_RECORD_SHAPING=1 ./gradlew :engine:jvmTest --tests '*ShapingEvidenceRecorder*'");
        }
        final evidence = ShapingEvidenceJson.parse(RecordedShapingEvidenceData.evidenceJson());
        final shaper = new RecordedEvidenceTextShaper(evidence);
        final metrics = new RecordedEvidenceFontMetricsResolver(evidence);
        final failures:Array<String> = [];
        for (fixture in EarlyLayoutFixtures.all) {
            final golden = RecordedLayoutDumpGoldens.byId().get(fixture.id);
            if (golden == null) {
                failures.push("missing recorded golden for fixture '" + fixture.id + "' — re-record");
                continue;
            }
            final dump = LayoutDumpFormat.layoutFixtureDump(fixture, shaper, metrics);
            if (golden != dump)
                failures.push(LayoutDumpFormat.layoutDumpDiffMessage(fixture.id, golden, dump));
        }
        TracedAssertions.assertTrue(failures.length == 0,
            failures.join("\n\n") + "\n\nIf the change is intentional, re-record with " + "TIQIAN_RECORD_SHAPING=1 on the JVM and review the golden diff.");
    }
}
