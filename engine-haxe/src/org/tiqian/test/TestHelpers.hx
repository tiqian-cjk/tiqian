package org.tiqian.test;

class TestHelpers {
    public static function f32Literal(value:Float):Float {
        return haxe.io.FPHelper.i32ToFloat(haxe.io.FPHelper.floatToI32(value));
    }

    public static function f32Bits(bits:Int):Float {
        return haxe.io.FPHelper.i32ToFloat(bits);
    }

    public static function surrogateText(codeUnits:Array<Int>):String {
        var output = "";
        var index = 0;
        while (index < codeUnits.length) {
            final unit = codeUnits[index];
            // A high surrogate followed by a low surrogate forms one
            // scalar; emit it as a single fromCharCode so a target that
            // decodes one UTF-16 unit at a time keeps the pair intact.
            // A lone surrogate stays a unit (a target without unpaired
            // surrogates cannot represent it).
            if (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < codeUnits.length
                && codeUnits[index + 1] >= 0xDC00 && codeUnits[index + 1] <= 0xDFFF) {
                final low = codeUnits[index + 1];
                output += String.fromCharCode(0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00));
                index += 2;
            } else {
                output += String.fromCharCode(unit);
                index += 1;
            }
        }
        return output;
    }
}
