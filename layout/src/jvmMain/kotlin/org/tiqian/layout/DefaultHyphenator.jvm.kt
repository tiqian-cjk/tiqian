package org.tiqian.layout

import org.tiqian.linebreak.EnglishHyphenation
import org.tiqian.linebreak.Hyphenator

/** JVM default: the bundled en-US TeX hyphenator (lazy-loaded once). */
internal actual fun defaultHyphenator(): Hyphenator = EnglishHyphenation.enUs
