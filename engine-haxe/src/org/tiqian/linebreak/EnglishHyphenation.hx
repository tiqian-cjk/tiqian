package org.tiqian.linebreak;

import org.tiqian.linebreak.LazyHyphenator.HyphenatorSource;

class EnglishHyphenation {
    /**
     * The en-US hyphenator over the compile-time packed table, left margin 2, right margin 3.
     * Construction reads the static table fields and parses nothing.
     */
    public static function enUs():Hyphenator
        return new PackedLiangHyphenator(EnglishHyphenationPatterns.table(), 2, 3);
}

/** The `HyphenatorSource` of the bundled en-US patterns. */
class EnglishHyphenatorSource implements HyphenatorSource {
    public function new() {}

    public function createHyphenator():Hyphenator
        return EnglishHyphenation.enUs();
}
