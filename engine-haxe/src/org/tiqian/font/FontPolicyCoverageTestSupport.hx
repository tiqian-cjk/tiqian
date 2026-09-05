package org.tiqian.font;

class FontPolicyCoverageTestSupport {
    public static function surrogateText(codes:Array<Int>):String {
        var result = "";
        var i = 0;
        while (i < codes.length) {
            result += String.fromCharCode(codes[i]);
            i++;
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
