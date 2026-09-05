package org.tiqian.layout;

import org.tiqian.linebreak.Hyphenator;
import org.tiqian.linebreak.EnglishHyphenation;

class DefaultHyphenator {
    // JVM, Android, JS, and native actuals agree, so Haxe folds them into one function.
    public static function defaultHyphenator():Hyphenator
        return EnglishHyphenation.enUs();
}
