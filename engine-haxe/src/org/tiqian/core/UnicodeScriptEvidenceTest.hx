package org.tiqian.core;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class UnicodeScriptEvidenceTest {
    @:test
    public static function commonAndInheritedScalarsDoNotVote():Void {
        new TestTraceRecorder("UnicodeScriptEvidenceTest").section("commonAndInheritedScalarsDoNotVote");
        final codePoints:Array<Int> = [0x20, 0x30, 0x201C, 0xFF1F, 0x0301, 0x1F600];
        var index:Int = 0;
        while (index < codePoints.length) {
            final codePoint:Int = codePoints[index];
            TracedAssertions.assertEqualsRendered(Std.string(UnicodeScriptEvidence.Neutral), Std.string(UnicodeScriptEvidenceClassifier.classify(codePoint)),
                "U+" + StringTools.hex(codePoint, 0).toLowerCase());
            index += 1;
        }
    }

    @:test
    public static function eastAsianScriptsAreDistinctFromOtherStrongScripts():Void {
        new TestTraceRecorder("UnicodeScriptEvidenceTest").section("eastAsianScriptsAreDistinctFromOtherStrongScripts");
        final eastAsianCodePoints:Array<Int> = [0x400D, 0x3105, 0x3042, 0x30A2, 0xAC00, 0x20000];
        var index:Int = 0;
        while (index < eastAsianCodePoints.length) {
            final codePoint:Int = eastAsianCodePoints[index];
            TracedAssertions.assertEqualsRendered(Std.string(UnicodeScriptEvidence.EastAsian),
                Std.string(UnicodeScriptEvidenceClassifier.classify(codePoint)), "U+" + StringTools.hex(codePoint, 0).toLowerCase());
            index += 1;
        }
        final otherCodePoints:Array<Int> = [0x41, 0x03C0, 0x0416, 0x0627];
        index = 0;
        while (index < otherCodePoints.length) {
            final codePoint:Int = otherCodePoints[index];
            TracedAssertions.assertEqualsRendered(Std.string(UnicodeScriptEvidence.Other), Std.string(UnicodeScriptEvidenceClassifier.classify(codePoint)),
                "U+" + StringTools.hex(codePoint, 0).toLowerCase());
            index += 1;
        }
    }
}
