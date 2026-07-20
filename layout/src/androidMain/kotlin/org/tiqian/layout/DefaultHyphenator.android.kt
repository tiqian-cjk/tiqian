package org.tiqian.layout

import org.tiqian.linebreak.EnglishHyphenation
import org.tiqian.linebreak.Hyphenator

/** Android default: the shared bundled en-US TeX hyphenator (lazy-loaded once). */
internal actual fun defaultHyphenator(): Hyphenator = EnglishHyphenation.enUs
