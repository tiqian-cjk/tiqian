package org.tiqian.layout;

import org.tiqian.clreq.ClreqProfile;
import org.tiqian.font.*;
import org.tiqian.test.trace.*;
import std.SortedSet;

class UnicodeEmoji17RgiRoleAuditTest {
    @:test public static function fullyQualifiedEmojiSequencesResolveToOneEmojiRange():Void {
        final testTrace = new TestTraceRecorder("UnicodeEmoji17RgiRoleAuditTest");
        testTrace.section("fullyQualifiedEmojiSequencesResolveToOneEmojiRange");
        TracedAssertions.assertEqualsInt(3944, UnicodeEmoji17RgiRoleAuditTestSupport.FULLY_QUALIFIED_CODE_POINT_SEQUENCES.length);
        final classifier = new CjkFontRoleClassifier();
        var failures:Array<String> = [];
        for (codePoints in UnicodeEmoji17RgiRoleAuditTestSupport.FULLY_QUALIFIED_CODE_POINT_SEQUENCES) {
            final text = UnicodeEmoji17RgiRoleAuditTestSupport.toUnicodeString(codePoints);
            final ranges = ClusterRoleResolution.clusterRoleRanges(text, classifier, new FontRoleContext(), ClreqProfile.MainlandHorizontal,
                SortedSet.builder().build(), SortedSet.builder().build());
            if (ranges.length != 1 || ranges[0].role != FontRole.Emoji || ranges[0].range.start != 0 || ranges[0].range.end != text.length) {
                failures.push(codePoints + ": expected=[TextRange(start=0, end=" + text.length + ") to Emoji] actual=" + Std.string(ranges));
            }
        }
        TracedAssertions.assertEqualsInt(0, failures.length, failures.length + " RGI role mismatches: " + failures.slice(0, 20));
    }
}
