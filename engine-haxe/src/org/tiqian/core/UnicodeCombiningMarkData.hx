package org.tiqian.core;

/*
 * GENERATED from Unicode 17.0.0 DerivedGeneralCategory.txt (general
 * categories Mn, Mc, Me) into engine-haxe/data/unicode-combining-mark-ranges.txt.
 * Source: https://www.unicode.org/Public/17.0.0/ucd/extracted/DerivedGeneralCategory.txt
 * SHA-256: d62e5bab70ca74f099343f71224fa051cb1fdd61a1ab45c0488c44cfc0b6102e
 * Copyright © 2025 Unicode, Inc.
 * Terms of Use: https://www.unicode.org/terms_of_use.html
 * Callers restrict to the BMP with a codePoint <= 0xFFFF guard to mirror the
 * Kotlin `this <= 0xFFFF && toChar().category in {Mn, Mc, Me}` checks.
 */
@:build(DataTables.rangesField("engine-haxe/data/unicode-combining-mark-ranges.txt", "RANGES"))
class UnicodeCombiningMarkData {
    public static function contains(codePoint:Int):Bool {
        var low:Int = 0;
        var high:Int = Std.int(RANGES.length / 2) - 1;
        while (low <= high) {
            final middle:Int = (low + high) >> 1;
            final base:Int = middle * 2;
            final start:Int = RANGES[base];
            final end:Int = RANGES[base + 1];
            if (codePoint < start) {
                high = middle - 1;
            } else if (codePoint > end) {
                low = middle + 1;
            } else {
                return true;
            }
        }
        return false;
    }
}
