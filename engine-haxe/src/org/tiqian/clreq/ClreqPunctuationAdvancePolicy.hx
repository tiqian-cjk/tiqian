package org.tiqian.clreq;

class ClreqPunctuationAdvancePolicy {
    public static function advanceEm(sourceText:String, displayText:String):Float {
        if (displayText == TWO_EM_DASH) {
            return 2.0;
        }
        if (sourceText == TWO_EM_DASH) {
            return 2.0;
        }
        return codePointCount(sourceText);
    }

    private static final TWO_EM_DASH:String = "⸺";

    private static function codePointCount(text:String):Float {
        var count:Int = 0;
        var index:Int = 0;
        while (index < text.length) {
            index += charCount(codePointAtCompat(text, index));
            count += 1;
        }
        return count;
    }

    private static function codePointAtCompat(text:String, index:Int):Int {
        final high:Int = text.charCodeAt(index);
        if (high < 0xD800 || high > 0xDBFF || index + 1 >= text.length) {
            return high;
        }

        final low:Int = text.charCodeAt(index + 1);
        if (low < 0xDC00 || low > 0xDFFF) {
            return high;
        }

        return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);
    }

    private static function charCount(codePoint:Int):Int {
        if (codePoint > 0xFFFF) {
            return 2;
        }
        return 1;
    }
}
