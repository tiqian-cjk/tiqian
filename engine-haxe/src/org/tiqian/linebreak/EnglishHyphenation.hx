package org.tiqian.linebreak;

import org.tiqian.linebreak.ParseTexHyphenationPatterns;

class EnglishHyphenation {
    private static var enUsCache:Null<Hyphenator> = null;

    public static function enUs():Hyphenator {
        if (enUsCache == null) {
            final parsed = ParseTexHyphenationPatterns.parse(EnglishHyphenationPatterns.load());
            enUsCache = new LiangHyphenator(parsed.patterns, parsed.exceptions, 2, 3);
        }
        return enUsCache;
    }
}
