package org.tiqian.layout

import org.tiqian.linebreak.EnglishHyphenation
import org.tiqian.linebreak.Hyphenator

/**
 * Kotlin/Native default: the bundled en-US TeX hyphenator, same as JVM/Android/JS.
 * Patterns are embedded at build time (see the linebreak module's
 * `generateEmbeddedHyphenationPatterns`), so hyphenation is engine-owned and available
 * synchronously at first layout. ADR 0039.
 */
internal actual fun defaultHyphenator(): Hyphenator = EnglishHyphenation.enUs
