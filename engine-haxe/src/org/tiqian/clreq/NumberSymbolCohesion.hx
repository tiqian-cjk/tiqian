package org.tiqian.clreq;

import org.tiqian.core.IntRange;
import org.tiqian.core.UnicodeNumberData;

class NumberSymbolCohesion {
    public static function unbreakableRanges(text:String):Array<IntRange> {
        final result:Array<IntRange> = [];
        var i:Int = 0;
        while (i < text.length) {
            if (!UnicodeNumberData.contains(text.charCodeAt(i))) {
                i += 1;
                continue;
            }
            var end:Int = i;
            while (end + 1 < text.length) {
                final unit:Int = text.charCodeAt(end + 1);
                if (UnicodeNumberData.contains(unit)) {
                    end += 1;
                } else if ((unit == 0x2E || unit == 0x2C)
                    && end + 2 < text.length
                    && UnicodeNumberData.contains(text.charCodeAt(end + 2))) {
                    end += 2;
                } else {
                    break;
                }
            }
            var start:Int = i;
            if (start > 0 && (isPrefixSign(text.charCodeAt(start - 1)) || isFrontCurrency(text.charCodeAt(start - 1)))) {
                start -= 1;
            }
            while (end + 1 < text.length && isSuffixUnit(text.charCodeAt(end + 1))) {
                end += 1;
            }
            if (end + 1 < text.length && isBackCurrency(text.charCodeAt(end + 1))) {
                end += 1;
            }

            result.push(new IntRange(start, end));
            i = end + 1;
        }
        return result;
    }

    private static function isPrefixSign(unit:Int):Bool {
        return unit == 0x2B || unit == 0x2D || unit == 0x00B1;
    }

    private static function isSuffixUnit(unit:Int):Bool {
        return unit == 0x25 || unit == 0x2030 || unit == 0x00B0 || unit == 0x2103 || unit == 0x2109 || unit == 0x2032 || unit == 0x2033;
    }

    private static function isFrontCurrency(unit:Int):Bool {
        return unit == 0x00A5 || unit == 0xFFE5 || unit == 0x24 || unit == 0xFF04 || unit == 0x20AC || unit == 0x00A3 || unit == 0x20A9 || unit == 0x20BD
            || unit == 0x20B9 || unit == 0x0E3F;
    }

    private static function isBackCurrency(unit:Int):Bool {
        return unit == 0x20AB;
    }
}
