package org.tiqian.font;

import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;

class FontRoleTailCoverageTest {
    @:test public static function supplementarySymbolIsUnknownBecauseItHasNoBmpCategory():Void {
        new TestTraceRecorder("FontRoleTailCoverageTest").section("supplementarySymbolIsUnknownBecauseItHasNoBmpCategory");
        TracedAssertions.assertEqualsRendered("Unknown", Std.string(new CjkFontRoleClassifier().classify("𝐀", new org.tiqian.core.TextRange(0, 2))));
    }

    @:test public static function bmpMathAndCurrencySymbolsResolveToSymbolRole():Void {
        new TestTraceRecorder("FontRoleTailCoverageTest").section("bmpMathAndCurrencySymbolsResolveToSymbolRole");
        var xs = ["±", "€"];
        var xi = 0;
        while (xi < xs.length) {
            var x = xs[xi];
            TracedAssertions.assertEqualsRendered("Symbol", Std.string(new CjkFontRoleClassifier().classify(x, new org.tiqian.core.TextRange(0, 1))));
            xi++;
        }
    }
}
