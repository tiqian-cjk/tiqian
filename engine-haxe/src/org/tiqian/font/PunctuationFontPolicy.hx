package org.tiqian.font;

@:mainOnly
enum PunctuationFontPolicy {
    PreferCjkForAmbiguousPunctuation;
    PreferLatinForAscii;
    PreserveRunFont;
    CustomMap;
}
