package org.tiqian.core;

/** Unicode 17 Number membership for contextual punctuation policies. */
class UnicodeNumber {
    public static function contains(codePoint:Int):Bool {
        if (codePoint < 0 || codePoint > 0x10FFFF) {
            throw new TiqianIllegalArgumentException(Message("Not a Unicode scalar value: " + codePoint));
        }
        if (codePoint >= 0xD800 && codePoint <= 0xDFFF) {
            throw new TiqianIllegalArgumentException(Message("Surrogate is not a Unicode scalar value: " + codePoint));
        }
        return UnicodeNumberData.contains(codePoint);
    }
}
