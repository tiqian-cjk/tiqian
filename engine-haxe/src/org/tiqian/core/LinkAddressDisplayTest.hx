package org.tiqian.core;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class LinkAddressDisplayTest {
    @:test
    public static function identicalDisplayAndTargetIsAnAddress():Void {
        new TestTraceRecorder("LinkAddressDisplayTest").section("identicalDisplayAndTargetIsAnAddress");
        TracedAssertions.assertTrue(LinkAddressDisplay.displaysAddress("https://example.com/a", "https://example.com/a"));
        TracedAssertions.assertTrue(LinkAddressDisplay.displaysAddress("footnote-1", "footnote-1"));
    }

    @:test
    public static function schemeLessDisplayOfTheTargetIsAnAddress():Void {
        new TestTraceRecorder("LinkAddressDisplayTest").section("schemeLessDisplayOfTheTargetIsAnAddress");
        TracedAssertions.assertTrue(LinkAddressDisplay.displaysAddress("example.com/b", "https://example.com/b"));
        TracedAssertions.assertTrue(LinkAddressDisplay.displaysAddress("example.com", "http://example.com"));
        TracedAssertions.assertTrue(LinkAddressDisplay.displaysAddress("a@example.com", "mailto:a@example.com"));
    }

    @:test
    public static function proseDisplayTextIsNotAnAddress():Void {
        new TestTraceRecorder("LinkAddressDisplayTest").section("proseDisplayTextIsNotAnAddress");
        TracedAssertions.assertFalse(LinkAddressDisplay.displaysAddress("Example", "https://example.com"));
        TracedAssertions.assertFalse(LinkAddressDisplay.displaysAddress("示例站", "https://example.com"));
        TracedAssertions.assertFalse(LinkAddressDisplay.displaysAddress("action", "generic"));
        TracedAssertions.assertFalse(LinkAddressDisplay.displaysAddress("", "https://example.com"));
        TracedAssertions.assertFalse(LinkAddressDisplay.displaysAddress("Example", ""));
    }
}
