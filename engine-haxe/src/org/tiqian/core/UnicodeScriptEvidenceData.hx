package org.tiqian.core;

/*
 * GENERATED from Unicode 17.0.0 Scripts.txt by
 * tools/unicode-script/generate_script_evidence_data.py.
 * Source: https://www.unicode.org/Public/17.0.0/ucd/Scripts.txt
 * SHA-256: 9f5e50d3abaee7d6ce09480f325c706f485ae3240912527e651954d2d6b035bf
 * Copyright © 2025 Unicode, Inc.
 * Terms of Use: https://www.unicode.org/terms_of_use.html
 */
@:build(DataTables.rangesField("engine-haxe/data/unicode-script-evidence-ranges.txt", "RANGES"))
class UnicodeScriptEvidenceData {
    public static function classify(codePoint:Int):UnicodeScriptEvidence {
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
            } else if (RANGES[base + 2] == 1) {
                return EastAsian;
            } else {
                return Other;
            }
        }
        return Neutral;
    }
}
