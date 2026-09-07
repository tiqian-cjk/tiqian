package org.tiqian.core;

/** Stable Unicode 17 Letter/Mark/Number membership for lexical boundaries. */
class UnicodeWordCharacter {
    public static final DATA_REVISION:String = "17.0.0";
    public static final DATA_SOURCE:String = "https://www.unicode.org/Public/17.0.0/ucd/extracted/DerivedGeneralCategory.txt";
    public static final DATA_SHA256:String = "d62e5bab70ca74f099343f71224fa051cb1fdd61a1ab45c0488c44cfc0b6102e";

    public static function contains(codePoint:Int):Bool {
        if (codePoint < 0 || codePoint > 0x10FFFF) {
            throw new TiqianIllegalArgumentException(Message("Not a Unicode scalar value: " + codePoint));
        }
        if (codePoint >= 0xD800 && codePoint <= 0xDFFF) {
            throw new TiqianIllegalArgumentException(Message("Surrogate is not a Unicode scalar value: " + codePoint));
        }
        return UnicodeWordCharacterData.contains(codePoint);
    }
}
