package org.tiqian.linebreak;

@:build(DataTables.rangesField("engine-haxe/data/punctuation-line-break-ranges.txt", "RANGES"))
class UnicodePunctuationLineBreakData {
    public static function lookup(codePoint:Int):Int {
        var low = 0;
        var high = Std.int(RANGES.length / 3) - 1;
        while (low <= high) {
            final middle = (low + high) >> 1;
            final base = middle * 3;
            if (codePoint < RANGES[base])
                high = middle - 1;
            else if (codePoint > RANGES[base + 1])
                low = middle + 1;
            else
                return RANGES[base + 2];
        }
        return -1;
    }
}
