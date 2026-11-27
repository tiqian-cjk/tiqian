package org.tiqian.protocol;

/**
 * Golden byte-exact vectors for the context fingerprint (Stage2 protocol,
 * ADR 0052 parity oracle). Each vector is pinned identically to the Rust
 * lane's context.rs output: one bit of divergence would split every font-
 * session cache namespace, so the vectors assert byte-for-byte (not
 * "semantically equal"). The three goldens together also prove the two
 * reference properties -- a changed fontSizePx yields a different digest,
 * and an equal configuration yields an equal digest.
 */
class ContextFingerprintTest {
    @:test
    public static function emptyFaceSetGolden():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("ContextFingerprintTest");
        recorder.section("emptyFaceSetGolden");
        final digest = ContextFingerprint.contextFingerprint(
            ContextFingerprintTestSupport.typography(), [], ContextFingerprintTestSupport.harfbuzzVersion());
        org.tiqian.test.trace.TracedAssertions.assertEqualsString(
            "adc029fd65cfe3ad8cadd66dc8339885ef4369c12668a5b9984e3e9f27ad49c6",
            ContextFingerprintTestSupport.hexBytes(digest));
    }

    @:test
    public static function oneFaceGolden():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("ContextFingerprintTest");
        recorder.section("oneFaceGolden");
        final digest = ContextFingerprint.contextFingerprint(
            ContextFingerprintTestSupport.typography(), [ContextFingerprintTestSupport.face()],
            ContextFingerprintTestSupport.harfbuzzVersion());
        org.tiqian.test.trace.TracedAssertions.assertEqualsString(
            "46b7f03d94c2ab5c51b91bb91a7ed3a4c9ed9608ad54182941778cb41dbed4d4",
            ContextFingerprintTestSupport.hexBytes(digest));
    }

    @:test
    public static function fontSizeChangeAltersTheFingerprint():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("ContextFingerprintTest");
        recorder.section("fontSizeChangeAltersTheFingerprint");
        final digest = ContextFingerprint.contextFingerprint(
            ContextFingerprintTestSupport.typographyAt(19.0), [], ContextFingerprintTestSupport.harfbuzzVersion());
        org.tiqian.test.trace.TracedAssertions.assertEqualsString(
            "b0bed999f5a3e580299287820febf8a5b818090126b9dc7adcd64627cf7db0f5",
            ContextFingerprintTestSupport.hexBytes(digest));
    }

    @:test
    public static function equalConfigurationIsStable():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("ContextFingerprintTest");
        recorder.section("equalConfigurationIsStable");
        final a = ContextFingerprint.contextFingerprint(
            ContextFingerprintTestSupport.typography(), [], ContextFingerprintTestSupport.harfbuzzVersion());
        final b = ContextFingerprint.contextFingerprint(
            ContextFingerprintTestSupport.typography(), [], ContextFingerprintTestSupport.harfbuzzVersion());
        org.tiqian.test.trace.TracedAssertions.assertEqualsString(
            ContextFingerprintTestSupport.hexBytes(a), ContextFingerprintTestSupport.hexBytes(b));
    }
}
