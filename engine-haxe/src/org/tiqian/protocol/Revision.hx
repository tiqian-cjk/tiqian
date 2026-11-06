package org.tiqian.protocol;

/**
 * The manifest-structure and revision constant family, single-sourced here
 * for the boring cutover (Stage1-P4, research 5.3 line "manifest 结构与
 * revision 常量族"). Every value is copied verbatim from the hand-written
 * declarations the generated outputs replace:
 *
 * - platforms/web/client/core/src/sampler/snapshot/snapshot-schema.ts:1-8
 *   (SNAPSHOT_SCHEMA, SNAPSHOT_TABLES_SCHEMA, LAYOUT_REVISION,
 *   RENDER_REVISION, FONT_SOURCE_POLICY, FONT_BACKEND_REVISION,
 *   FONT_REPLAY_REVISION, FONT_REPLAY_TRANSPORT)
 * - platforms/web/server/precompute/engine/src/schema.rs:9-27 (the same
 *   family minus SNAPSHOT_TABLES_SCHEMA)
 * - platforms/web/server/precompute/engine/src/plan.rs:16 (PLAN_
 *   LAYOUT_REVISION, the fifth "tiqian-layout-v2" declaration)
 * - engine/src/commonMain/kotlin/org/tiqian/layout/PreparedParagraph.kt:16
 *   (PREPARED_PARAGRAPH_LAYOUT_REVISION, the Kotlin declaration)
 * - platforms/web/client/core/src/engine/prepare-paragraph-layout.ts:128
 *   (PREPARED_LAYOUT_REVISION, the second TS declaration)
 * - engine/src/nativeInterop/cinterop/tiqian_font_backend.h:23 (the C ABI
 *   TIQIAN_FONT_BACKEND_PROTOCOL_REVISION)
 *
 * Zero value changes: the wire bytes, the golden fixtures and the parity
 * oracles all read the same strings and numbers through the generated
 * constants as before. The five "tiqian-layout-v2" sites and the C ABI
 * revision each keep one source after this cutover.
 *
 * Deliberately outside the single source (ruling, gate message S1): the
 * stableStringify and replay-key helpers of snapshot-schema.ts / schema.rs
 * (no algorithm crosses to this class; the helpers are shared P2/P3
 * surface), PLAN_SCHEMA (plan.rs:13) and PREPARED_PARAGRAPH_SCHEMA
 * (PreparedParagraph.kt:15, both P3), and HARFBUZZ_VERSION (session.rs:27,
 * an engine-identity output, not a revision constant).
 */
class Revision {

    /** SNAPSHOT_SCHEMA: the schema of every snapshot this revision understands. */
    public static final SNAPSHOT_SCHEMA:Int = 1;

    /** SNAPSHOT_TABLES_SCHEMA: the manifest schema of the snapshot tables. */
    public static final SNAPSHOT_TABLES_SCHEMA:Int = 2;

    /** LAYOUT_REVISION of every snapshot and plan this revision understands. */
    public static final LAYOUT_REVISION:String = "tiqian-layout-v2";

    /** RENDER_REVISION of the prepared DOM lowering. */
    public static final RENDER_REVISION:String = "prebroken-dom-v16";

    /** FONT_SOURCE_POLICY of the snapshot font evidence. */
    public static final FONT_SOURCE_POLICY:String = "host-compatible-stylesheet-v1";

    /** FONT_BACKEND_REVISION of the shared shaping backend. */
    public static final FONT_BACKEND_REVISION:String = "tiqian-shared-harfbuzz-v5";

    /** FONT_REPLAY_REVISION of the replay tables. */
    public static final FONT_REPLAY_REVISION:String = "tiqian-server-shaping-replay-v1";

    /** FONT_REPLAY_TRANSPORT of the compact replay encoding. */
    public static final FONT_REPLAY_TRANSPORT:String = "shared-strings-v1";

    /** TIQIAN_FONT_BACKEND_PROTOCOL_REVISION of the C ABI vtable protocol. */
    public static final FONT_BACKEND_PROTOCOL_REVISION:Int = 2;
}
