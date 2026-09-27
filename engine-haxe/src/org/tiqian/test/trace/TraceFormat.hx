package org.tiqian.test.trace;

class TraceFormat {

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
        var output = "";
        var index = 0;
        while (index < value.length) {
            final codeUnit = value.charCodeAt(index);
            if (codeUnit == 10) {
                output += "\\n";
            } else if (codeUnit == 13) {
                output += "\\r";
            } else if (codeUnit == 11) {
                output += "\\v";
            } else if (codeUnit == 12) {
                output += "\\f";
            } else if (codeUnit == 133) {
                output += "\\u0085";
            } else if (codeUnit == 8232) {
                output += "\\u2028";
            } else if (codeUnit == 8233) {
                output += "\\u2029";
            } else if (codeUnit == 8203) {
                output += "\\u200B";
            } else {
                output += value.substring(index, index + 1);
            }
            index += 1;
        }
        return output;
    }

    private static function fixedDecimalText(value:Float, decimals:Int):String {
        final negative = isNegative(value);
        final magnitude = Math.abs(value);
        final scale = pow10(decimals);
        final rounded = scaledMagnitude(magnitude, scale);
        final integerPart = integerPartOf(magnitude, rounded, scale);
        final fractionPart = (rounded - multiply(integerPart, scale)).low;
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

    /**
        Floor of the binary64 expression the Kotlin reference evaluates:
        `floor(magnitude * scale + 0.5)` with `magnitude` a binary64
        holding the input's binary32 value and `scale` the exact integer
        10^decimals. The product needs at most 24 + 30 significant bits,
        so it is exact in binary64; this function reaches the same integer
        through binary32 exponent decomposition and binary64-width integer
        arithmetic, which the module real width does not narrow.

        The value is `mantissa * 2^exponent`; the product with `scale` is
        built with shifted additions because the translatable subset has no
        Int64 multiplication, and the halved shift implements the half-up
        rounding of `+ 0.5` followed by `floor`.
    **/
    private static function scaledMagnitude(magnitude:Float, scale:Int):haxe.Int64 {
        final bits = haxe.io.FPHelper.floatToI32(magnitude);
        final exponentField = (bits >>> 23) & 0xFF;
        final mantissaBits = bits & 0x7FFFFF;
        final mantissa = exponentField == 0 ? mantissaBits : mantissaBits | 0x800000;
        final exponent = exponentField == 0 ? -149 : exponentField - 150;

        final product = multiply(mantissa, scale);

        if (exponent >= 0) {
            return product << exponent;
        }
        final divisorShift = -exponent;
        if (divisorShift >= 64) {
            return haxe.Int64.ofInt(0);
        }
        return (product + (haxe.Int64.ofInt(1) << (divisorShift - 1))) >>> divisorShift;
    }

    /**
        The digits left of the point. The scaled value is at least
        `floor(magnitude) * scale` and never reaches one scale step past
        `(floor(magnitude) + 1) * scale`, so one comparison with that bound
        decides the whole part and the subtraction in the caller yields a
        remainder below `scale`, which binary32-width integer arithmetic
        then renders. Dividing the scaled value directly would need Int64
        division, which the translatable subset does not carry.
    **/
    private static function integerPartOf(magnitude:Float, rounded:haxe.Int64, scale:Int):Int {
        var whole = Std.int(Math.floor(magnitude));
        if (rounded >= multiply(whole + 1, scale)) {
            whole += 1;
        }
        return whole;
    }

    /** `left * right` as Int64, built from shifted additions. */
    private static function multiply(left:Int, right:Int):haxe.Int64 {
        var product = haxe.Int64.ofInt(0);
        var factor = right;
        var shift = 0;
        while (factor > 0) {
            if (factor & 1 != 0) {
                product = product + (haxe.Int64.ofInt(left) << shift);
            }
            factor = factor >> 1;
            shift += 1;
        }
        return product;
    }

    private static function f32Mirror(value:Float):Float {
        return haxe.io.FPHelper.i32ToFloat(haxe.io.FPHelper.floatToI32(value));
    }
}
