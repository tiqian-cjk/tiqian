package org.tiqian.protocol;


/**
 * ECMAScript Number-stringification for plan JSON numbers (Stage1-P3).
 * Replaces three hand-written copies (research 5.3): the Kotlin commonMain
 * ecmaJsonNumber (PreparedParagraph.kt:418-550), the Rust js_compat.rs
 * js_number_string, and the engine Haxe PreparedParagraphFns.ecmaJsonNumber.
 */

typedef PlanJsonDigitsAndExponent = {digits:String, exponent:Int};
typedef PlanJsonDecomposed = {mantissa:String, exp2:Int};
typedef PlanJsonF32Decomposed = {mant24:Int, exp2:Int};

class PlanJsonNumber {
    // Rust has no representation for a nullable container static, so the caches
    // start empty and are filled lazily; an empty array means "not built yet".
    private static var fivePowers:Array<String> = [];
    private static var twoPowers:Array<String> = [];

    public static function ecmaJsonNumber(floatValue:Float):String {
        #if tiqian_ts
        return Std.string(haxe.io.FPHelper.i32ToFloat(haxe.io.FPHelper.floatToI32(floatValue)));
        #else
        if (Math.isNaN(floatValue))
            return "NaN";
        if (Math.isFinite(floatValue) == false)
            return floatValue < 0 ? "-Infinity" : "Infinity";
        if (floatValue == 0)
            return "0";
        final negative = floatValue < 0;
        final magnitudeValue = negative ? -floatValue : floatValue;
        final shortest = shortestRoundTripDigits(magnitudeValue);
        final digits = canonicalFloatDigits(magnitudeValue, shortest.digits);
        final k = digits.length;
        final n = shortest.exponent;
        final sign = negative ? "-" : "";
        if (k <= n && n <= 21)
            return sign + digits + zeros(n - k);
        if (0 < n && n <= 21)
            return sign + digits.substr(0, n) + "." + digits.substr(n);
        if (-6 < n && n <= 0)
            return sign + "0." + zeros(-n) + digits;
        final mantissa = k > 1 ? digits.substr(0, 1) + "." + digits.substr(1) : digits;
        final ev = n - 1;
        final esign = ev < 0 ? "-" : "+";
        final absoluteExponent:Int = ev < 0 ? -ev : ev;
        return sign + mantissa + "e" + esign + Std.string(absoluteExponent);
        #end
    }

    public static function appendJsonString(out:Array<String>, value:String):Void {
        out.push("\"");
        for (i in 0...value.length) {
            final c = value.charCodeAt(i);
            if (c == 34)
                out.push("\\\"");
            else if (c == 92)
                out.push("\\\\");
            else if (c == 8)
                out.push("\\b");
            else if (c == 12)
                out.push("\\f");
            else if (c == 10)
                out.push("\\n");
            else if (c == 13)
                out.push("\\r");
            else if (c == 9)
                out.push("\\t");
            else if (c < 32)
                out.push("\\u" + StringTools.hex(c, 4).toLowerCase());
            else
                out.push(String.fromCharCode(c));
        }
        out.push("\"");
    }

    public static function shortestRoundTripDigits(magnitude:Float):PlanJsonDigitsAndExponent {
        final d = decompose(magnitude);
        final f = d.exp2;
        final expansion = dyadicDecimal(d.mantissa, f);
        final exact = trimZeros(expansion.digits);
        final n = expansion.exponent;
        final base = d.mantissa;
        final doubled = timesSmall(base, 2);
        final hi = dyadicDecimalString(addDecimal(doubled, "1"), d.exp2 - 1);
        var lo:PlanJsonDigitsAndExponent;
        if (base == "4503599627370496") {
            lo = dyadicDecimalString(decrementDecimal(timesSmall(base, 4)), d.exp2 - 2);
        } else {
            lo = dyadicDecimalString(decrementDecimal(doubled), d.exp2 - 1);
        }
        final inclusive = (base.charCodeAt(base.length - 1) - 48) % 2 == 0;
        var length = 1;
        while (length <= 17) {
            final keep = exact.substr(0, length);
            final up = incrementDecimal(keep);
            final upN = n + up.length - length;
            if (inInterval(keep, n, lo, hi, inclusive) || inInterval(up, upN, lo, hi, inclusive)) {
                final rounded = roundToSignificant(exact, length);
                return {digits: rounded.digits, exponent: n + rounded.exponent};
            }
            length += 1;
        }
        return {digits: exact, exponent: n};
    }

    private static function inInterval(digits:String, n:Int, lo:PlanJsonDigitsAndExponent, hi:PlanJsonDigitsAndExponent,
            inclusive:Bool):Bool {
        final low = compareDecimal(digits, n, lo.digits, lo.exponent);
        final high = compareDecimal(digits, n, hi.digits, hi.exponent);
        return (low > 0 || (low == 0 && inclusive)) && (high < 0 || (high == 0 && inclusive));
    }

    private static function canonicalFloatDigits(magnitude:Float, doubleDigits:String):String {
        final d = decomposeF32(magnitude);
        final exact = d.mant24 == 0 ? "0" : (d.exp2 >= 0 ? timesLong(twoToThe(d.exp2), d.mant24) : timesLong(fiveToThe(-d.exp2), d.mant24));
        final stripped = trimZeros(exact);
        if (stripped.length <= doubleDigits.length)
            return doubleDigits;
        final rounded = roundToSignificant(stripped, doubleDigits.length);
        return rounded.digits.length == doubleDigits.length ? rounded.digits : doubleDigits;
    }

    private static function dyadicDecimal(p:String, f:Int):PlanJsonDigitsAndExponent {
        return dyadicDecimalString(p, f);
    }

    private static function dyadicDecimalString(p:String, f:Int):PlanJsonDigitsAndExponent {
        final digits = f < 0 ? multiplyDecimal(fiveToThe(-f), p) : multiplyDecimal(twoToThe(f), p);
        return {digits: digits, exponent: f < 0 ? digits.length + f : digits.length};
    }

    private static function multiplyDecimal(a:String, b:String):String {
        var result = "0";
        var shift = 0;
        var i = b.length - 1;
        while (i >= 0) {
            final digit = b.charCodeAt(i) - 48;
            if (digit != 0) {
                var part = timesSmall(a, digit);
                if (shift > 0)
                    part += zeros(shift);
                result = addDecimal(result, part);
            }
            shift++;
            i--;
        }
        return result;
    }


    // The Rust target guards each static access with its own lock instead of
    // holding one lock across a fill, so the former append-as-you-grow loops
    // let two threads interleave appends: the entries stopped matching their
    // indices, and every number formatted afterwards took the wrong power and
    // shifted its decimal point (a plan width of 144 serialized as 0.009216
    // once a concurrent fill had raced). Each table is now built to a fixed
    // length and published in one assignment, so a reader sees either the old
    // complete table or the new complete table, and the length never changes
    // between the length check and the index read. The size covers every
    // reachable exponent: the f32 decomposition bottoms out at exp2 = -149 and
    // the 16-digit extension lowers that by at most 29 more.
    private static inline var POWER_CACHE_ENTRIES:Int = 200;

    private static function fiveToThe(k:Int):String {
        if (fivePowers.length == 0)
            fivePowers = powerTable(5, POWER_CACHE_ENTRIES);
        if (k < fivePowers.length)
            return fivePowers[k];
        return powerTable(5, k + 1)[k];
    }

    private static function twoToThe(k:Int):String {
        if (twoPowers.length == 0)
            twoPowers = powerTable(2, POWER_CACHE_ENTRIES);
        if (k < twoPowers.length)
            return twoPowers[k];
        return powerTable(2, k + 1)[k];
    }

    private static function powerTable(base:Int, entries:Int):Array<String> {
        final table = ["1"];
        var digits = "1";
        var i = 1;
        while (i < entries) {
            digits = timesSmall(digits, base);
            table.push(digits);
            i++;
        }
        return table;
    }


        private static function timesLong(digits:String, factor:Int):String {
        if (factor == 0)
            return "0";
        var result:String = null;
        var shift = 0;
        var remaining = factor;
        while (remaining > 0) {
            final chunk = remaining % 100000000;
            remaining = Std.int(remaining / 100000000);
            if (chunk != 0) {
                var part = timesSmall(digits, chunk);
                if (shift > 0)
                    part += zeros(shift);
                result = result == null ? part : addDecimal(result, part);
            }
            shift += 8;
        }
        return result == null ? "0" : result;
    }

    private static function addDecimal(a:String, b:String):String {
        final out:Array<String> = [];
        var i = a.length - 1;
        var j = b.length - 1;
        var carry = 0;
        while (i >= 0 || j >= 0 || carry > 0) {
            final sum = (i >= 0 ? a.charCodeAt(i) - 48 : 0) + (j >= 0 ? b.charCodeAt(j) - 48 : 0) + carry;
            out.push(String.fromCharCode(48 + sum % 10));
            carry = Std.int(sum / 10);
            i--;
            j--;
        }
        final text = out.join("");
        return reverse(text);
    }

    private static function roundToSignificant(exact:String, length:Int):PlanJsonDigitsAndExponent {
        if (length >= exact.length)
            return {digits: exact, exponent: 0};
        final keep = exact.substr(0, length);
        final rem = exact.substr(length);
        var up = false;
        if (rem.charCodeAt(0) > 53)
            up = true;
        else if (rem.charCodeAt(0) == 53) {
            var tail = 1;
            while (tail < rem.length && rem.charCodeAt(tail) == 48)
                tail++;
            up = tail < rem.length || ((keep.charCodeAt(keep.length - 1) - 48) % 2 != 0);
        }
        final rounded = up ? incrementDecimal(keep) : keep;
        return {digits: trimZeros(rounded), exponent: rounded.length - length};
    }

    private static function compareDecimal(a:String, nA:Int, b:String, nB:Int):Int {
        final eA = nA - a.length;
        final eB = nB - b.length;
        final aa = eA >= eB ? a + zeros(eA - eB) : a;
        final bb = eB >= eA ? b + zeros(eB - eA) : b;
        if (aa.length != bb.length)
            return aa.length - bb.length;
        return compareDigitStrings(aa, bb);
    }

    private static function timesSmall(digits:String, factor:Int):String {
        final out:Array<String> = [];
        var carry = 0;
        var i = digits.length - 1;
        while (i >= 0) {
            final product = (digits.charCodeAt(i) - 48) * factor + carry;
            out.push(String.fromCharCode(48 + product % 10));
            carry = Std.int(product / 10);
            i--;
        }
        while (carry > 0) {
            out.push(String.fromCharCode(48 + carry % 10));
            carry = Std.int(carry / 10);
        }
        final text = out.join("");
        return reverse(text);
    }

    private static function incrementDecimal(digits:String):String {
        var a = digits.split("");
        var i = a.length - 1;
        while (true) {
            if (a[i] != "9") {
                a[i] = String.fromCharCode(a[i].charCodeAt(0) + 1);
                return a.join("");
            }
            a[i] = "0";
            if (i == 0)
                return "1" + a.join("");
            i--;
        }
    }

    private static function decrementDecimal(digits:String):String {
        var a = digits.split("");
        var i = a.length - 1;
        while (i >= 0 && a[i] == "0") {
            a[i] = "9";
            i--;
        }
        if (i >= 0)
            a[i] = String.fromCharCode(a[i].charCodeAt(0) - 1);
        var out = a.join("");
        var start = 0;
        while (start < out.length - 1 && out.charCodeAt(start) == 48)
            start++;
        return out.substr(start);
    }

    private static function decompose(v:Float):PlanJsonDecomposed {
        final f = decomposeF32(v);
        var mantissa = Std.string(f.mant24);
        var exponent = f.exp2;
        if (f.mant24 >= 0x800000) {
            mantissa = timesLong(mantissa, 536870912);
            exponent -= 29;
        }
        while (mantissa.length < 16 || (mantissa.length == 16 && compareDigitStrings(mantissa, "4503599627370496") < 0)) {
            mantissa = timesSmall(mantissa, 2);
            exponent--;
        }
        return {mantissa: mantissa, exp2: exponent};
    }

    private static function decomposeF32(v:Float):PlanJsonF32Decomposed {
        final bits = haxe.io.FPHelper.floatToI32(v);
        final rawExponent = (bits >>> 23) & 0xff;
        final rawMantissa = bits & 0x7fffff;
        if (rawExponent == 0)
            return {mant24: rawMantissa, exp2: -149};
        return {mant24: rawMantissa | 0x800000, exp2: rawExponent - 150};
    }

    private static function compareDigitStrings(a:String, b:String):Int {
        if (a.length != b.length)
            return a.length - b.length;
        var i = 0;
        while (i < a.length) {
            final da = a.charCodeAt(i);
            final db = b.charCodeAt(i);
            if (da != db)
                return da - db;
            i++;
        }
        return 0;
    }

    private static function zeros(n:Int):String {
        final buf = new StringBuf();
        var i = 0;
        while (i < n) {
            buf.addChar(48);
            i++;
        }
        return buf.toString();
    }

    private static function trimZeros(s:String):String {
        var e = s.length;
        while (e > 1 && s.charCodeAt(e - 1) == 48)
            e--;
        return s.substr(0, e);
    }

    private static function reverse(s:String):String {
        final buf = new StringBuf();
        var i = s.length - 1;
        while (i >= 0) {
            buf.addChar(s.charCodeAt(i));
            i--;
        }
        return buf.toString();
    }
}