package org.tiqian.test;

import std.StringBuf;

class TestHelpers {
    public static function f32Literal(value:Float):Float {
        return haxe.io.FPHelper.i32ToFloat(haxe.io.FPHelper.floatToI32(value));
    }

    public static function f32Bits(bits:Int):Float {
        return haxe.io.FPHelper.i32ToFloat(bits);
    }

    public static function surrogateText(codeUnits:Array<Int>):String {
        final output = new StringBuf();
        var index = 0;
        while (index < codeUnits.length) {
            output.addChar(codeUnits[index]);
            index += 1;
        }
        return output.toString();
    }
}
