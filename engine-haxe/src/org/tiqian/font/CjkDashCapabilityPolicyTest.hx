package org.tiqian.font;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class CjkDashCapabilityPolicyTest {
    @:test public static function nullStatusNamesMissingConformingGlyphAndUnpreparedDetail():Void {
        new TestTraceRecorder("CjkDashCapabilityPolicyTest").section("nullStatusNamesMissingConformingGlyphAndUnpreparedDetail");
        TracedAssertions.assertEqualsString("NoConformingCjkDashGlyph", CjkDashCapabilityPolicy.issueNameFor(null));
        TracedAssertions.assertEqualsString("CjkDashFontShapingNotPrepared", CjkDashCapabilityPolicy.issueDetailFor(null, null));
    }

    @:test public static function conformingStatusWithBlankDetailNamesTheMissingSession():Void {
        new TestTraceRecorder("CjkDashCapabilityPolicyTest").section("conformingStatusWithBlankDetailNamesTheMissingSession");
        TracedAssertions.assertEqualsString("ConformingCjkDashRequiresExactFontSession", CjkDashCapabilityPolicy.issueNameFor("conforming"));
        TracedAssertions.assertEqualsString("status=conforming", CjkDashCapabilityPolicy.issueDetailFor("conforming", "  "));
    }

    @:test public static function conformingStatusWithDetailAppendsHostEvidence():Void {
        new TestTraceRecorder("CjkDashCapabilityPolicyTest").section("conformingStatusWithDetailAppendsHostEvidence");
        TracedAssertions.assertEqualsString("ConformingCjkDashRequiresExactFontSession", CjkDashCapabilityPolicy.issueNameFor("conforming"));
        TracedAssertions.assertEqualsString("status=conforming; FixtureDashFace", CjkDashCapabilityPolicy.issueDetailFor("conforming", "FixtureDashFace"));
    }

    @:test public static function nonConformingStatusWithDetailNamesMissingGlyphAndAppendsEvidence():Void {
        new TestTraceRecorder("CjkDashCapabilityPolicyTest").section("nonConformingStatusWithDetailNamesMissingGlyphAndAppendsEvidence");
        TracedAssertions.assertEqualsString("NoConformingCjkDashGlyph", CjkDashCapabilityPolicy.issueNameFor("unavailable"));
        TracedAssertions.assertEqualsString("status=unavailable; BrowserHarfBuzzDisabled",
            CjkDashCapabilityPolicy.issueDetailFor("unavailable", "BrowserHarfBuzzDisabled"));
    }

    @:test public static function nonConformingStatusWithBlankDetailKeepsOnlyStatusPrefix():Void {
        new TestTraceRecorder("CjkDashCapabilityPolicyTest").section("nonConformingStatusWithBlankDetailKeepsOnlyStatusPrefix");
        TracedAssertions.assertEqualsString("NoConformingCjkDashGlyph", CjkDashCapabilityPolicy.issueNameFor("unavailable"));
        TracedAssertions.assertEqualsString("status=unavailable", CjkDashCapabilityPolicy.issueDetailFor("unavailable", null));
    }
}
