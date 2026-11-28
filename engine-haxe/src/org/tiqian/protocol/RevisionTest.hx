package org.tiqian.protocol;

import org.tiqian.test.trace.TracedAssertions;

/**
 * The single-sourced revision constants pinned against the literals the
 * hand-written declarations carried before the cutover (Stage1-P4). The
 * same literals are pinned by the TypeScript lane (test/revision.test.ts
 * of @tiqian/precompute), the Rust lane (schema.rs unit tests of the
 * precompute engine crate, plus the tiqian ffi drift assertion) and the
 * Kotlin lane (LayoutAbiTest.kt for the C ABI constant), so the family
 * stays item-equal on every side: the criterion is the same set of
 * constants equal, item by item.
 */
class RevisionTest {
    @:test
    public static function revisionConstantsPinTheHandWrittenValues():Void {
        TracedAssertions.assertEquals(1, Revision.SNAPSHOT_SCHEMA, "SNAPSHOT_SCHEMA");
        TracedAssertions.assertEquals(2, Revision.SNAPSHOT_TABLES_SCHEMA, "SNAPSHOT_TABLES_SCHEMA");
        TracedAssertions.assertEqualsString("tiqian-layout-v2", Revision.LAYOUT_REVISION, "LAYOUT_REVISION");
        TracedAssertions.assertEqualsString("prebroken-dom-v17", Revision.RENDER_REVISION, "RENDER_REVISION");
        TracedAssertions.assertEqualsString(
            "host-compatible-stylesheet-v1", Revision.FONT_SOURCE_POLICY, "FONT_SOURCE_POLICY"
        );
        TracedAssertions.assertEqualsString(
            "tiqian-shared-harfbuzz-v5", Revision.FONT_BACKEND_REVISION, "FONT_BACKEND_REVISION"
        );
        TracedAssertions.assertEqualsString(
            "tiqian-server-shaping-replay-v1", Revision.FONT_REPLAY_REVISION, "FONT_REPLAY_REVISION"
        );
        TracedAssertions.assertEqualsString(
            "shared-strings-v1", Revision.FONT_REPLAY_TRANSPORT, "FONT_REPLAY_TRANSPORT"
        );
        TracedAssertions.assertEquals(
            2, Revision.FONT_BACKEND_PROTOCOL_REVISION, "FONT_BACKEND_PROTOCOL_REVISION"
        );
    }
}
