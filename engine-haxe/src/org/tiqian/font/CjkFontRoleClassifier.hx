package org.tiqian.font;

import org.tiqian.font.FontRoleContext.FontRoleClassifier;

class CjkFontRoleClassifier implements FontRoleClassifier {
    public function new() {}

    public function classify(text:String, range:org.tiqian.core.TextRange, ?context:Null<FontRoleContext>):FontRole {
        var c = text.charCodeAt(range.start);
        if (c >= 0xD800 && c <= 0xDBFF && range.start + 1 < text.length) {
            var lo = text.charCodeAt(range.start + 1);
            if (lo >= 0xDC00 && lo <= 0xDFFF)
                c = 0x10000 + ((c - 0xD800) << 10) + (lo - 0xDC00);
        }
        if ((c >= 0x3105 && c <= 0x312F) || (c >= 0x31A0 && c <= 0x31BF) || (c >= 0x3400 && c <= 0x4DBF) || (c >= 0x4E00 && c <= 0x9FFF)
            || (c >= 0xF900 && c <= 0xFAFF) || (c >= 0x20000 && c <= 0x2A6DF) || (c >= 0x2A700 && c <= 0x2B73F) || (c >= 0x2B740 && c <= 0x2B81F)
            || (c >= 0x2B820 && c <= 0x2CEAF) || (c >= 0x30000 && c <= 0x3134F))
            return CjkText;
        if (c == 0x2018 || c == 0x2019 || c == 0x201C || c == 0x201D) {
            var l = range.start > 0 ? text.charCodeAt(range.start - 1) : null;
            var r = range.end < text.length ? text.charCodeAt(range.end) : null;
            return isLatin(l) && isLatin(r) ? LatinText : CjkPunctuation;
        }
        if (c >= 0x20 && c <= 0x7E || (c >= 0xC0 && c <= 0x24F))
            return LatinText;
        if (c >= 0x3000 && c <= 0x303F || c == 0x2014 || c == 0x2013 || c == 0x203C || c == 0x2047 || c == 0x2026 || c == 0x2027 || c == 0x22EF
            || c == 0x30FB || c == 0x2E3A || c == 0x00B7 || c == 0x2022 || c == 0xFF01 || c == 0xFF1F || c == 0xFF0C || c == 0xFF0E || c == 0xFF0F
            || c == 0xFF1A || c == 0xFF1B || c == 0xFF08 || c == 0xFF09 || c == 0xFF5E)
            return CjkPunctuation;
        if (UnicodeEmojiPresentationData.contains(c))
            return Emoji;
        // Mirrors Kotlin isSymbolCodePoint: toCharOrNull()?.category in {Sm, Sc, Sk, So},
        // so only the BMP classifies as Symbol; supplementary code points stay Unknown.
        if (c <= 0xFFFF && UnicodeSymbolData.contains(c))
            return Symbol;
        return Unknown;
    }

    // Mirrors Kotlin isLatinRunCodePoint: typed ASCII, Latin letters, plus the four
    // ambiguous curly quotes (a neighboring curly quote joins the Latin run too).
    static function isLatin(c:Null<Int>):Bool
        return c != null
            && (c >= 0x20 && c <= 0x7E || c >= 0xC0 && c <= 0x24F || c == 0x2018 || c == 0x2019 || c == 0x201C || c == 0x201D);
}
