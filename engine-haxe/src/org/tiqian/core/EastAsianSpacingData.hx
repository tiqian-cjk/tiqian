package org.tiqian.core;

/*
 * GENERATED from Unicode Proposed Draft UTR #59 east-asian-spacing.txt.
 * Source date: 2024-12-16
 * Source: https://www.unicode.org/reports/tr59/east-asian-spacing.txt
 * SHA-256: 49fe340a964a6e8e0ebc30099709c665cc6138d444b5c36dc336604047f1010f
 * Copyright © 2024 Unicode, Inc.
 * Terms of Use: https://www.unicode.org/terms_of_use.html
 *
 * Explicit Other ranges are omitted because Other is the @missing default. Adjacent ranges
 * with the same value are merged mechanically. Values: 0=Wide, 1=Narrow, 3=Conditional.
 */
@:build(DataTables.rangesField("engine-haxe/data/east-asian-spacing-ranges.txt", "RANGES"))
class EastAsianSpacingData {
    public static function lookup(codePoint:Int):EastAsianSpacingValue {
        var low:Int = 0;
        var high:Int = Std.int(RANGES.length / 3) - 1;
        while (low <= high) {
            final middle:Int = (low + high) >> 1;
            final base:Int = middle * 3;
            final start:Int = RANGES[base];
            final end:Int = RANGES[base + 1];
            if (codePoint < start) {
                high = middle - 1;
            } else if (codePoint > end) {
                low = middle + 1;
            } else {
                final value:Int = RANGES[base + 2];
                if (value == 0) {
                    return EastAsianSpacingValue.Wide;
                }
                if (value == 1) {
                    return EastAsianSpacingValue.Narrow;
                }
                if (value == 3) {
                    return EastAsianSpacingValue.Conditional;
                }
                throw new TiqianIllegalArgumentException(Message("Invalid generated East_Asian_Spacing value"));
            }
        }
        return EastAsianSpacingValue.Other;
    }
}
