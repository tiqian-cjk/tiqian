package ink.duo3.tiqian.layout

import ink.duo3.tiqian.linebreak.EnglishHyphenation
import ink.duo3.tiqian.linebreak.Hyphenator

/** JVM default: the bundled en-US TeX hyphenator (lazy-loaded once). */
internal actual fun defaultHyphenator(): Hyphenator = EnglishHyphenation.enUs
