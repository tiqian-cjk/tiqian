package org.tiqian.test.trace;

import haxe.io.FPHelper;
import std.ReadOnlyArray;
import std.StringBuf;

class TestTraceRender {
    private static final MAX_OPERAND_CHARS:Int = 240;
    private static final HEX:String = "0123456789abcdef";
    private static final MAX_SIGNIFICANT_DIGITS:Int = 9;

    public static function escapeOperand(value:String):String {
        return cap(escape(value));
    }

    public static function renderString(value:String):String {
        return cap("'" + escape(value) + "'");
    }

    public static function renderInt(value:Int):String {
        return cap(TraceFormat.i(value));
    }

    public static function renderLong(value:Int):String {
        return cap(TraceFormat.valueLong(value));
    }

    public static function renderFloat(value:Float):String {
        return cap(TraceFormat.fd(value, 6));
    }

    /**
     * Renders a Float the way the JVM golden generator's string
     * templates do: the shortest decimal digit string that round-trips
     * to the same f32 bits, with a trailing ".0" for whole numbers
     * (canonicalNumbers at the record choke point strips it). Plain
     * decimal form; values outside the normal range fall back to
     * Std.string.
     */
    public static function floatText(value:Float):String {
        var negative = value < 0;
        var v = Math.abs(value);
        if (v == 0)
            return negative ? "-0.0" : "0.0";

        // The window and the candidate distances are read off the decimal
        // digits of the value's shortest round-trip text rather than from
        // arithmetic on the value itself. Dividing by a power of ten and
        // subtracting two near-equal candidates both need more significant
        // bits than a binary32 carries once the search reaches eight or
        // nine digits: a 24-bit real puts the window in the wrong decade
        // slot and reads every accepted candidate as equidistant.
        final shape = decimalShape(v);
        if (shape == null)
            return (negative ? "-" : "") + Std.string(v);

        final digits = shape.digits;
        final width = digits.length;
        final position = shape.position;
        final targetBits = FPHelper.floatToI32(v);
        var p = 1;
        while (p <= 9) {
            final exp = position - p;
            final base:Int = p >= width
                ? decimalInt(digits) * pow10Int(p - width)
                : decimalInt(digits.substring(0, p));
            final frac:Float = fractionAfter(digits, p, shape.extended);
            var best = -1;
            var bestDist = Math.POSITIVE_INFINITY;
            var c = base - 1;
            while (c <= base + 2) {
                if (c >= 1) {
                    final candidateText:String = Std.string(c) + "e" + Std.string(exp);
                    final cand:Float = cast(Std.parseFloat(candidateText), Float);
                    if (FPHelper.floatToI32(cand) == targetBits) {
                        // The offset and the fraction both stay within a
                        // few units, so the comparison keeps every bit it
                        // needs at any real width.
                        final dist:Float = Math.abs((c - base) - frac);
                        if (dist < bestDist || (dist == bestDist && (c % 2 == 0))) {
                            best = c;
                            bestDist = dist;
                        }
                    }
                }
                c += 1;
            }
            if (best >= 0)
                return floatTextRender(best, position - 1, p, negative);
            p += 1;
        }
        return (negative ? "-" : "") + Std.string(v);
    }

    /** The integer that a digit string of at most nine digits spells. */
    private static function decimalInt(digits:String):Int {
        var value = 0;
        var index = 0;
        while (index < digits.length) {
            value = value * 10 + digits.charCodeAt(index) - 48;
            index += 1;
        }
        return value;
    }

    private static function pow10Int(exponent:Int):Int {
        var value = 1;
        var index = 0;
        while (index < exponent) {
            value *= 10;
            index += 1;
        }
        return value;
    }

    /**
        The fractional digits the value carries beyond its first p
        significant ones, as a Float in [0, 1). A digit the shape dropped
        past its kept prefix makes any exact half an upper half.
    **/
    private static function fractionAfter(digits:String, p:Int, extended:Bool):Float {
        if (p >= digits.length)
            return 0.0;
        final frac:Float = cast(Std.parseFloat("0." + digits.substring(p)), Float);
        if (extended && frac == 0.5)
            return 0.75;
        return frac;
    }

    /**
        The decimal that the runtime's shortest round-trip text of the
        value spells: its significant digits with leading and trailing
        zeros removed, the power of ten position with value == 0.<digits>
        * 10^position, and whether digits past the kept prefix were
        dropped. That text names a value within half an ulp of the input,
        which is all the digit-driven window search needs; a non-finite
        input has no such text.
    **/
    private static function decimalShape(v:Float):Null<DecimalShape> {
        if (!Math.isFinite(v))
            return null;
        final plain = expandScientific(Std.string(v));
        var point = plain.length;
        var index = 0;
        while (index < plain.length) {
            if (plain.charCodeAt(index) == 46) {
                point = index;
                break;
            }
            index += 1;
        }
        final all = plain.substring(0, point) + plain.substring(point + 1);
        var first = 0;
        while (first < all.length && all.charCodeAt(first) == 48) {
            first += 1;
        }
        if (first == all.length)
            return null;
        var last = all.length;
        while (last > first + 1 && all.charCodeAt(last - 1) == 48) {
            last -= 1;
        }
        var digits = "";
        var extended = false;
        var cursor = first;
        while (cursor < last) {
            if (digits.length < MAX_SIGNIFICANT_DIGITS) {
                digits += all.substring(cursor, cursor + 1);
            } else if (all.charCodeAt(cursor) != 48) {
                extended = true;
            }
            cursor += 1;
        }
        return new DecimalShape(digits, point - first, extended);
    }

    private static function floatTextRender(c:Int, e:Int, p:Int, negative:Bool):String {
        var s = Std.string(c);
        if (s.length < p)
            s = StringTools.lpad(s, "0", p);
        var pointAfter = e + 1;
        final out = new StringBuf();
        if (negative)
            out.add("-");
        if (pointAfter <= 0) {
            out.add("0.");
            var k = 0;
            while (k < -pointAfter) {
                out.add("0");
                k += 1;
            }
            out.add(s);
        } else if (pointAfter >= p) {
            out.add(s);
            var k = p;
            while (k < pointAfter) {
                out.add("0");
                k += 1;
            }
            out.add(".0");
        } else {
            out.add(s.substring(0, pointAfter));
            out.add(".");
            out.add(s.substring(pointAfter));
        }
        return out.toString();
    }

    public static function renderBool(value:Bool):String {
        return cap(TraceFormat.valueBool(value));
    }

    public static function renderNull():String {
        return "-";
    }

    public static function renderIntArray(values:Array<Int>):String {
        final output = new StringBuf();
        output.add("[");
        var index = 0;
        while (index < values.length) {
            if (index > 0) {
                output.add(", ");
            }
            output.add(renderInt(values[index]));
            index += 1;
        }
        output.add("]");
        final text = output.toString();
        return cap(text);
    }

    public static function renderStringArray(values:ReadOnlyArray<String>):String {
        final output = new StringBuf();
        output.add("[");
        var index = 0;
        while (index < values.length) {
            if (index > 0) {
                output.add(", ");
            }
            output.add(renderString(values[index]));
            index += 1;
        }
        output.add("]");
        final text = output.toString();
        return cap(text);
    }

    /**
     * The text the Kotlin reference's string template gives a List: each
     * element in its own printed form, joined with ", " inside brackets.
     * Std.string of a collection is not portable — the Haxe/JS target joins
     * an Array with "," while the Kotlin target joins with ", " — so a trace
     * operand that has to read the same on both targets builds the list text
     * here from the parts it renders itself, instead of calling Std.string on
     * the collection.
     */
    public static function legacyListText(parts:Array<String>):String {
        return "[" + parts.join(", ") + "]";
    }

    public static function canonicalNumbers(value:String):String {
        return stripWholeFraction(expandScientific(value));
    }

    public static function cap(value:String):String {
        final canonical = canonicalNumbers(value);
        if (canonical.length <= MAX_OPERAND_CHARS) {
            return canonical;
        }
        return canonical.substring(0, MAX_OPERAND_CHARS) + "~" + canonical.length + "#" + fnv1a(canonical);
    }

    private static function escape(value:String):String {
        var output = "";
        var index = 0;
        while (index < value.length) {
            final codeUnit = value.charCodeAt(index);
            if (codeUnit == 0) {
                output += "\\u0000";
            } else {
                output += TraceFormat.escapeText(value.substring(index, index + 1));
            }
            index += 1;
        }
        return output;
    }

    private static function expandScientific(value:String):String {
        final output = new StringBuf();
        var copied = 0;
        var index = 0;
        while (index < value.length) {
            final codeUnit = value.charCodeAt(index);
            if (codeUnit != 69 && codeUnit != 101) {
                index += 1;
                continue;
            }

            final match = scientificMatch(value, index, copied);
            if (match == null) {
                index += 1;
                continue;
            }

            output.add(value.substring(copied, match.start));
            output.add(expandMantissa(value.substring(match.start, match.mantissaEnd), match.exponent));
            copied = match.end;
            index = match.end;
        }
        output.add(value.substring(copied, value.length));
        return output.toString();
    }

    private static function stripWholeFraction(value:String):String {
        final output = new StringBuf();
        var index = 0;
        while (index < value.length) {
            if (value.charCodeAt(index) == 46 && index > 0 && isDigit(value.charCodeAt(index - 1))) {
                var cursor = index + 1;
                while (cursor < value.length && value.charCodeAt(cursor) == 48) {
                    cursor += 1;
                }
                if (cursor > index + 1
                    && (cursor == value.length || (!isDigit(value.charCodeAt(cursor)) && value.charCodeAt(cursor) != 46))) {
                    index = cursor;
                    continue;
                }
            }
            output.add(value.substring(index, index + 1));
            index += 1;
        }
        return output.toString();
    }

    private static function scientificMatch(s:String, eIndex:Int, floor:Int):Null<ScientificMatch> {
        var i = eIndex + 1;
        if (i < s.length && (s.charCodeAt(i) == 43 || s.charCodeAt(i) == 45)) {
            i += 1;
        }
        final digitsStart = i;
        while (i < s.length && isDigit(s.charCodeAt(i))) {
            i += 1;
        }
        if (i == digitsStart) {
            return null;
        }
        final end = i;
        final exponent = parseExponent(s, eIndex + 1, end);

        final last = eIndex - 1;
        if (last < floor || !isDigit(s.charCodeAt(last))) {
            return null;
        }
        var runStart = last;
        while (runStart > floor && isDigit(s.charCodeAt(runStart - 1))) {
            runStart -= 1;
        }
        var lead = -1;
        if (runStart > floor + 1 && s.charCodeAt(runStart - 1) == 46 && isDigit(s.charCodeAt(runStart - 2))) {
            lead = runStart - 2;
        } else {
            if (runStart != last) {
                return null;
            }
            lead = last;
        }

        if (lead > 0 && s.charCodeAt(lead - 1) == 45 && lead - 1 >= floor) {
            final beforeMinus = lead >= 2 && (isDigit(s.charCodeAt(lead - 2)) || s.charCodeAt(lead - 2) == 46);
            if (!beforeMinus) {
                return new ScientificMatch(lead - 1, eIndex, end, exponent);
            }
            return new ScientificMatch(lead, eIndex, end, exponent);
        }
        final beforeDigit = lead > 0 && (isDigit(s.charCodeAt(lead - 1)) || s.charCodeAt(lead - 1) == 46);
        if (!beforeDigit) {
            return new ScientificMatch(lead, eIndex, end, exponent);
        }
        return null;
    }

    static function parseExponent(s:String, from:Int, to:Int):Int {
        var index = from;
        var negative = false;
        if (index < to && (s.charCodeAt(index) == 43 || s.charCodeAt(index) == 45)) {
            negative = s.charCodeAt(index) == 45;
            index += 1;
        }
        var value = 0;
        while (index < to) {
            value = value * 10 + s.charCodeAt(index) - 48;
            index += 1;
        }
        return negative ? -value : value;
    }

    private static function expandMantissa(mantissa:String, exponent:Int):String {
        var sign = "";
        var value = mantissa;
        if (value.length > 0 && value.charCodeAt(0) == 45) {
            sign = "-";
            value = value.substring(1);
        }

        var dotIndex = -1;
        var index = 0;
        while (index < value.length) {
            if (value.charCodeAt(index) == 46) {
                dotIndex = index;
                break;
            }
            index += 1;
        }
        var digits = dotIndex < 0 ? value : value.substring(0, dotIndex) + value.substring(dotIndex + 1);
        while (digits.length > 1 && digits.charCodeAt(digits.length - 1) == 48) {
            digits = digits.substring(0, digits.length - 1);
        }
        final decimalPosition = (dotIndex < 0 ? value.length : dotIndex) + exponent;
        if (decimalPosition <= 0) {
            return sign + "0." + zeroes(-decimalPosition) + digits;
        }
        if (decimalPosition >= digits.length) {
            return sign + digits + zeroes(decimalPosition - digits.length);
        }
        return sign + digits.substring(0, decimalPosition) + "." + digits.substring(decimalPosition);
    }

    private static function zeroes(count:Int):String {
        final output = new StringBuf();
        var index = 0;
        while (index < count) {
            output.add("0");
            index += 1;
        }
        return output.toString();
    }

    private static function isDigit(codeUnit:Int):Bool {
        return codeUnit >= 48 && codeUnit <= 57;
    }

    private static function fnv1a(value:String):String {
        var hash:Int = -2128831035;
        var index = 0;
        while (index < value.length) {
            hash = (hash ^ value.charCodeAt(index));
            hash = multiplyFNVPrime(hash);
            index += 1;
        }

        final first = (hash >>> 24) & 255;
        final second = (hash >>> 16) & 255;
        final third = (hash >>> 8) & 255;
        final fourth = hash & 255;
        var output = hexByte(first) + hexByte(second) + hexByte(third) + hexByte(fourth);
        while (output.length > 1 && output.charCodeAt(0) == 48) {
            output = output.substring(1);
        }
        return output;
    }

    private static function multiplyFNVPrime(value:Int):Int {
        // Split the 32-bit product into sixteen-bit limbs. JavaScript's ordinary
        // multiplication rounds the full product above 2^53, while this form
        // preserves the modulo-2^32 FNV-1a result on every target.
        final low:Int = value & 0xFFFF;
        final high:Int = (value >>> 16) & 0xFFFF;
        final lowProduct:Int = low * 0x0193;
        final highProduct:Int = high * 0x0193 + low * 0x0100 + Std.int(lowProduct / 0x10000);
        return ((highProduct & 0xFFFF) << 16) | (lowProduct & 0xFFFF);
    }

    private static function hexByte(value:Int):String {
        return HEX.substring((value >>> 4) & 15, ((value >>> 4) & 15) + 1) + HEX.substring(value & 15, (value & 15) + 1);
    }
}

private class DecimalShape {
    public final digits:String;
    public final position:Int;
    public final extended:Bool;

    public function new(digits:String, position:Int, extended:Bool) {
        this.digits = digits;
        this.position = position;
        this.extended = extended;
    }
}

private class ScientificMatch {
    public final start:Int;
    public final mantissaEnd:Int;
    public final end:Int;
    public final exponent:Int;

    public function new(start:Int, mantissaEnd:Int, end:Int, exponent:Int) {
        this.start = start;
        this.mantissaEnd = mantissaEnd;
        this.end = end;
        this.exponent = exponent;
    }
}