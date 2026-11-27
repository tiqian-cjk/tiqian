package org.tiqian.linebreak;

import org.tiqian.linebreak.PackedHyphenationTable.HyphenationTableData;

/**
 * The bundled en-US patterns (`engine-haxe/data/hyph-en-us.tex`), packed at compile time by
 * `HyphenationTables.texPatternFields` into the `PATTERN_UNITS` and `EXCEPTION_UNITS` fields.
 */
@:build(HyphenationTables.texPatternFields("engine-haxe/data/hyph-en-us.tex"))
class EnglishHyphenationPatterns {
    public static function table():PackedHyphenationTable
        return new PackedHyphenationTable(new EnglishHyphenationTableData());
}

/** Reads the static `EnglishHyphenationPatterns` fields in place, without copying them. */
class EnglishHyphenationTableData implements HyphenationTableData {
    public function new() {}

    public function patternUnitCount():Int
        return EnglishHyphenationPatterns.PATTERN_UNITS.length;

    public function patternUnit(offset:Int):Int
        return EnglishHyphenationPatterns.PATTERN_UNITS[offset];

    public function exceptionUnitCount():Int
        return EnglishHyphenationPatterns.EXCEPTION_UNITS.length;

    public function exceptionUnit(offset:Int):Int
        return EnglishHyphenationPatterns.EXCEPTION_UNITS[offset];
}
