package org.tiqian.font;

class FontPolicyCoverageTestSupport {
    public static function surrogateText(codes:Array<Int>):String {
        var result = "";
        var i = 0;
        while (i < codes.length) {
            final unit = codes[i];
            // A high surrogate followed by a low surrogate forms one
            // scalar; emit it as a single fromCharCode so a target that
            // decodes one UTF-16 unit at a time keeps the pair intact.
            // A lone surrogate stays a unit (a target without unpaired
            // surrogates cannot represent it).
            if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < codes.length
                && codes[i + 1] >= 0xDC00 && codes[i + 1] <= 0xDFFF) {
                final low = codes[i + 1];
                result += String.fromCharCode(0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00));
                i += 2;
            } else {
                result += String.fromCharCode(unit);
                i += 1;
            }
        }
        return result;
    }

    public static function copyStrings(values:std.ReadOnlyArray<String>):Array<String> {
        final result:Array<String> = [];
        var i = 0;
        while (i < values.length) {
            result.push(values[i]);
            i++;
        }
        return result;
    }
}
