package;

/**
 * Stage-one implementation of the std.UStringPlatform cursor primitives
 * (docs/specs/stdlib/10-unicode-string-access.md). The haxe stage compiles
 * to JavaScript, whose strings are UTF-16, so cursors are unit indices and
 * the surrogate pairs combine here. TestMain and Main bind this class as
 * globalThis.std.UStringPlatform before any test runs; the transpiled
 * targets lower the same primitives inline instead.
 */
class UStringPlatform {
    public static function end(s:String):Int {
        return s.length;
    }

    public static function codeAt(s:String, cursor:Int):Int {
        final unit = s.charCodeAt(cursor);
        if (unit >= 0xD800 && unit <= 0xDBFF && cursor + 1 < s.length) {
            final next = s.charCodeAt(cursor + 1);
            if (next >= 0xDC00 && next <= 0xDFFF) {
                return 0x10000 + ((unit - 0xD800) << 10) + (next - 0xDC00);
            }
        }
        return unit;
    }

    public static function advance(s:String, cursor:Int):Int {
        return cursor + (codeAt(s, cursor) > 0xFFFF ? 2 : 1);
    }

    public static function substringBetween(s:String, startCursor:Int, stopCursor:Int):String {
        return s.substring(startCursor, stopCursor);
    }

    public static function fromCodePoint(code:Int):String {
        if (code < 0x10000) {
            return String.fromCharCode(code);
        }
        final offset = code - 0x10000;
        return String.fromCharCode(0xD800 + ((offset >> 10) & 0x3FF)) + String.fromCharCode(0xDC00 + (offset & 0x3FF));
    }
}
