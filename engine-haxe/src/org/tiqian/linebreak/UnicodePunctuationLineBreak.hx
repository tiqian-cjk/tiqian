package org.tiqian.linebreak;

import org.tiqian.core.TiqianIllegalArgumentException;
import org.tiqian.core.TextRangeError;

enum UnicodePunctuationLineBreakClass {
    BreakAfter;
    BreakBoth;
    ClosePunctuation;
    CloseParenthesis;
    Exclamation;
    HyphenHH;
    Hyphen;
    Inseparable;
    InfixNumericSeparator;
    Nonstarter;
    OpenPunctuation;
    Quotation;
    SymbolsAllowingBreakAfter;
    Other;
}

class UnicodePunctuationLineBreak {
    public static inline final DATA_REVISION:String = "17.0.0";
    public static inline final DATA_SOURCE:String = "https://www.unicode.org/Public/17.0.0/ucd/LineBreak.txt";
    public static inline final DATA_SHA256:String = "e6a18fa91f8f6a6f8e534b1d3f128c21ada45bfe152eb6b1bcc5e15fd8ac92e6";

    public static function classOf(codePoint:Int):UnicodePunctuationLineBreakClass {
        if (codePoint < 0 || codePoint > 0x10FFFF)
            throw new TiqianIllegalArgumentException(Message("Not a Unicode scalar value: " + codePoint));
        if (codePoint >= 0xD800 && codePoint <= 0xDFFF)
            throw new TiqianIllegalArgumentException(Message("Surrogate is not a Unicode scalar value: " + codePoint));
        final kind:Int = UnicodePunctuationLineBreakData.lookup(codePoint);
        if (kind == 0)
            return BreakAfter;
        if (kind == 1)
            return BreakBoth;
        if (kind == 2)
            return ClosePunctuation;
        if (kind == 3)
            return CloseParenthesis;
        if (kind == 4)
            return Exclamation;
        if (kind == 5)
            return HyphenHH;
        if (kind == 6)
            return Hyphen;
        if (kind == 7)
            return Inseparable;
        if (kind == 8)
            return InfixNumericSeparator;
        if (kind == 9)
            return Nonstarter;
        if (kind == 10)
            return OpenPunctuation;
        if (kind == 11)
            return Quotation;
        if (kind == 12)
            return SymbolsAllowingBreakAfter;
        return Other;
    }
}
