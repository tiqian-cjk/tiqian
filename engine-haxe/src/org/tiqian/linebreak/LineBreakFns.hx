package org.tiqian.linebreak;

class LineBreakFns {
    @:topLevel
    public static function isMandatoryBreakCodePoint(codePoint:Int):Bool {
        return codePoint == 0x000A || codePoint == 0x000B || codePoint == 0x000C || codePoint == 0x000D || codePoint == 0x0085 || codePoint == 0x2028
            || codePoint == 0x2029;
    }

    @:topLevel
    public static function isZeroWidthSpaceCodePoint(codePoint:Int):Bool
        return codePoint == 0x200B;
}
