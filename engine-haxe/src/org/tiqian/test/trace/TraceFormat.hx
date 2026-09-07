package org.tiqian.test.trace;

import std.StringBuf;

class TraceFormat {
    private static final HEX:String = "0123456789abcdef";

    public static function i(value:Int):String {
        return "" + value;
    }

    public static function f(value:Float):String {
        final rounded = f32Mirror(value);
        if (rounded != rounded) {
            return "NaN";
        }
        if (rounded == Math.POSITIVE_INFINITY) {
            return "Infinity";
        }
        if (rounded == Math.NEGATIVE_INFINITY) {
            return "-Infinity";
        }
        return fixedDecimalText(rounded, 1);
    }

    public static function fd(value:Float, decimals:Int):String {
        final rounded = f32Mirror(value);
        if (rounded != rounded) {
            return "NaN";
        }
        if (rounded == Math.POSITIVE_INFINITY) {
            return "Infinity";
        }
        if (rounded == Math.NEGATIVE_INFINITY) {
            return "-Infinity";
        }
        return fixedDecimalText(rounded, decimals);
    }

    public static function d(value:Float):String {
        if (value != value) {
            return "NaN";
        }
        if (value == Math.POSITIVE_INFINITY) {
            return "Infinity";
        }
        if (value == Math.NEGATIVE_INFINITY) {
            return "-Infinity";
        }
        return fixedDecimalText(value, 1);
    }

    public static function valueString(value:String):String {
        return "'" + escapeText(value) + "'";
    }

    public static function valueInt(value:Int):String {
        return i(value);
    }

    public static function valueLong(value:Int):String {
        return "" + value;
    }

    public static function valueFloat(value:Float):String {
        return fd(value, 1);
    }

    public static function valueDouble(value:Float):String {
        return d(value);
    }

    public static function valueBool(value:Bool):String {
        return value ? "true" : "false";
    }

    public static function valueNull():String {
        return "-";
    }

    public static function escapeText(value:String):String {
        final output = new StringBuf();
        var index = 0;
        while (index < value.length) {
            final codeUnit = value.charCodeAt(index);
            if (codeUnit == 10) {
                output.add("\\n");
            } else if (codeUnit == 13) {
                output.add("\\r");
            } else if (codeUnit == 11) {
                output.add("\\v");
            } else if (codeUnit == 12) {
                output.add("\\f");
            } else if (codeUnit == 133) {
                output.add("\\u0085");
            } else if (codeUnit == 8232) {
                output.add("\\u2028");
            } else if (codeUnit == 8233) {
                output.add("\\u2029");
            } else if (codeUnit == 8203) {
                output.add("\\u200B");
            } else {
                output.add(value.substring(index, index + 1));
            }
            index += 1;
        }
        return output.toString();
    }

    private static function fixedDecimalText(value:Float, decimals:Int):String {
        final negative = isNegative(value);
        final magnitude = Math.abs(value);
        final scale = pow10(decimals);
        final rounded = Math.floor(magnitude * scale + 0.5);
        final integerPart = Std.int(rounded / scale);
        final fractionPart = Std.int(rounded) % scale;
        var fractionText = "" + fractionPart;
        while (fractionText.length < decimals) {
            fractionText = "0" + fractionText;
        }
        return (negative ? "-" : "") + integerPart + "." + fractionText;
    }

    private static function isNegative(value:Float):Bool {
        return value < 0 || (value == 0 && 1 / value < 0);
    }

    private static function pow10(decimals:Int):Int {
        var scale = 1;
        var index = 0;
        while (index < decimals) {
            scale *= 10;
            index += 1;
        }
        return scale;
    }

    private static function f32Mirror(value:Float):Float {
        return haxe.io.FPHelper.i32ToFloat(haxe.io.FPHelper.floatToI32(value));
    }
}
