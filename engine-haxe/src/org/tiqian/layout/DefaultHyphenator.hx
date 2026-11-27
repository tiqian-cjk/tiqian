package org.tiqian.layout;

import org.tiqian.linebreak.Hyphenator;
import org.tiqian.linebreak.EnglishHyphenation.EnglishHyphenatorSource;
import org.tiqian.linebreak.LazyHyphenator;

class DefaultHyphenator {
    /**
     * The hyphenator an engine uses when its caller passes none: a new `LazyHyphenator` slot over
     * the bundled en-US patterns for each engine, filled on the engine's first hyphenation
     * request, so constructing an engine loads no hyphenation data.
     */
    public static function defaultHyphenator():Hyphenator
        return new LazyHyphenator(new EnglishHyphenatorSource());
}
