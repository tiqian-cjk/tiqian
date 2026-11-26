package org.tiqian.protocol;

/**
 * The JSON lane's value coercions, single-sourced so the canonical encoder
 * applies one reading on every platform. Each function mirrors the semantics
 * the Rust engine implements in js_compat.rs and snapshot_source.rs and the
 * TypeScript lane inherits from the host runtime.
 */
class JsCoerce {
    /** `Number(value)` over a wire value: absent coerces through WNull. */
    public static function toNumber(value:WireValue):Float {
        return switch (value) {
            case WNum(inner): inner;
            case WStr(inner): toNumberFromString(inner);
            case WBool(inner): inner ? 1.0 : 0.0;
            case WNull: 0.0;
            case WArr(_) | WObj(_): toNumberFromString(toString(value));
        };
    }

    /** `String(value)` over a wire value. */
    public static function toString(value:WireValue):String {
        return switch (value) {
            case WStr(inner): inner;
            case WNum(inner): numberToString(inner);
            case WBool(inner): inner ? "true" : "false";
            case WNull: "null";
            case WArr(items): joinItems(items);
            case WObj(_): "[object Object]";
        };
    }

    static function joinItems(items:Array<WireValue>):String {
        final parts = new Array<String>();
        var itemIndexIdx:Int = 0;
        while (itemIndexIdx < items.length) {
            final item = items[itemIndexIdx];
            // JavaScript's Array.prototype.join turns null and
            // absent into the empty string.
            parts.push(itemText(item));
            itemIndexIdx++;
        }
        return parts.join(",");
    }

    static function itemText(item:WireValue):String {
        return switch (item) {
            case WNull: "";
            case WBool(_): toString(item);
            case WNum(_): toString(item);
            case WStr(_): toString(item);
            case WArr(_): toString(item);
            case WObj(_): toString(item);
        };
    }

    /**
     * The ECMAScript Number::toString(10) shape for one finite double:
     * integral values below 1e21 print as plain digits, everything else
     * falls through to the platform's shortest round-trip form. Values in
     * the exponent ranges are outside the canonical envelope (the same
     * envelope note the TypeScript mirror carries).
     */
    public static function numberToString(value:Float):String {
        if (Math.isNaN(value)) {
            return "NaN";
        }
        if (value == Math.POSITIVE_INFINITY) {
            return "Infinity";
        }
        if (value == Math.NEGATIVE_INFINITY) {
            return "-Infinity";
        }
        if (value == 0.0) {
            return "0";
        }
        if (value == Math.floor(value) && Math.abs(value) < 1e21) {
            var rest = Math.abs(value);
            var digits = "";
            while (rest >= 10) {
                final digit = Math.floor(rest % 10);
                digits = String.fromCharCode(48 + digit) + digits;
                rest = Math.floor(rest / 10);
            }
            digits = String.fromCharCode(48 + Math.floor(rest)) + digits;
            return value < 0 ? "-" + digits : digits;
        }
        return Std.string(value);
    }

    /** The strict ECMAScript ToNumber over text. */
    public static function toNumberFromString(text:String):Float {
        final trimmed = jsTrim(text);
        if (trimmed.length == 0) {
            return 0.0;
        }
        var negative = false;
        var body = trimmed;
        final first = body.charAt(0);
        if (first == "-") {
            negative = true;
            body = body.substr(1);
        } else if (first == "+") {
            body = body.substr(1);
        }
        if (body == "Infinity") {
            return negative ? Math.NEGATIVE_INFINITY : Math.POSITIVE_INFINITY;
        }
        if (body == "NaN") {
            return Math.NaN;
        }
        final radix = radixPrefix(body);
        if (radix > 0) {
            final digits = body.substr(2);
            var value = 0.0;
            var indexIdx:Int = 0;
            while (indexIdx < digits.length) {
                final digit = hexDigit(digits.charCodeAt(indexIdx));
                if (digit < 0) {
                    return Math.NaN;
                }
                value = value * radix + digit;
                indexIdx++;
            }
            return negative ? -value : value;
        }
        if (!isStrictDecimal(body)) {
            return Math.NaN;
        }
        final parsed = Std.parseFloat(body);
        return negative ? -parsed : parsed;
    }

    static function radixPrefix(body:String):Int {
        if (body.length < 3) {
            return 0;
        }
        final marker = body.substr(0, 2);
        if (marker == "0x" || marker == "0X") {
            return 16;
        }
        if (marker == "0o" || marker == "0O") {
            return 8;
        }
        if (marker == "0b" || marker == "0B") {
            return 2;
        }
        return 0;
    }

    static function hexDigit(code:Int):Int {
        if (code >= 48 && code <= 57) {
            return code - 48;
        }
        if (code >= 65 && code <= 70) {
            return code - 55;
        }
        if (code >= 97 && code <= 102) {
            return code - 87;
        }
        return -1;
    }

    static function isStrictDecimal(body:String):Bool {
        var index = 0;
        var seenDigit = false;
        while (index < body.length && isDecimalDigit(body.charCodeAt(index))) {
            index++;
            seenDigit = true;
        }
        if (index < body.length && body.charCodeAt(index) == 46) {
            index++;
            while (index < body.length && isDecimalDigit(body.charCodeAt(index))) {
                index++;
                seenDigit = true;
            }
        }
        if (!seenDigit) {
            return false;
        }
        if (index < body.length && (body.charCodeAt(index) == 101 || body.charCodeAt(index) == 69)) {
            index++;
            if (index < body.length && (body.charCodeAt(index) == 43 || body.charCodeAt(index) == 45)) {
                index++;
            }
            var exponentDigits = false;
            while (index < body.length && isDecimalDigit(body.charCodeAt(index))) {
                index++;
                exponentDigits = true;
            }
            if (!exponentDigits) {
                return false;
            }
        }
        return index == body.length;
    }

    static function isDecimalDigit(code:Int):Bool {
        return code >= 48 && code <= 57;
    }

    /** The ECMAScript TrimString over ASCII whitespace and NBSP. */
    static function jsTrim(text:String):String {
        var start = 0;
        var end = text.length;
        while (start < end && isJsWhitespace(text.charCodeAt(start))) {
            start++;
        }
        while (end > start && isJsWhitespace(text.charCodeAt(end - 1))) {
            end--;
        }
        return start == 0 && end == text.length ? text : text.substr(start, end - start);
    }

    static function isJsWhitespace(code:Int):Bool {
        return code == 32 || code == 9 || code == 10 || code == 13 || code == 12 || code == 11 || code == 160;
    }

    /**
     * The `JSON.stringify` text of one wire value. Attribute arrays are the
     * only consumers inside the canonical form, so the shape stays compact:
     * no spaces, every key quoted, numbers in the Number::toString shape.
     */
    public static function renderJson(value:WireValue):String {
        return switch (value) {
            case WNull: "null";
            case WBool(inner): inner ? "true" : "false";
            case WNum(inner): numberToString(inner);
            case WStr(inner): quoteJson(inner);
            case WArr(items): renderArray(items);
            case WObj(fields): renderObject(fields);
        };
    }

    static function renderArray(items:Array<WireValue>):String {
        final parts = new Array<String>();
        var itemIndexIdx:Int = 0;
        while (itemIndexIdx < items.length) {
            final item = items[itemIndexIdx];
            parts.push(renderJson(item));
            itemIndexIdx++;
        }
        return "[" + parts.join(",") + "]";
    }

    static function renderObject(fields:Array<WireField>):String {
        final parts = new Array<String>();
        var fieldIndexIdx:Int = 0;
        while (fieldIndexIdx < fields.length) {
            final field = fields[fieldIndexIdx];
            parts.push(quoteJson(field.name) + ":" + renderJson(field.value));
            fieldIndexIdx++;
        }
        return "{" + parts.join(",") + "}";
    }

    static function quoteJson(text:String):String {
        final out = new StringBuf();
        out.add('"');
        var indexIdx:Int = 0;
        while (indexIdx < text.length) {
            final code = text.charCodeAt(indexIdx);
            if (code == 34) {
                out.add('\\\"');
            } else if (code == 92) {
                out.add('\\\\');
            } else if (code == 8) {
                out.add('\\b');
            } else if (code == 12) {
                out.add('\\f');
            } else if (code == 10) {
                out.add('\\n');
            } else if (code == 13) {
                out.add('\\r');
            } else if (code == 9) {
                out.add('\\t');
            } else if (code < 32) {
                out.add('\\u00');
                out.add("0123456789abcdef".charAt((code >> 4) & 15));
                out.add("0123456789abcdef".charAt(code & 15));
            } else {
                out.add(String.fromCharCode(code));
            }
            indexIdx++;
        }
        out.add('"');
        return out.toString();
    }
}