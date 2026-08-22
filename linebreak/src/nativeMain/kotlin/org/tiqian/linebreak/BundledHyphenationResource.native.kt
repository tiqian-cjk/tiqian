package org.tiqian.linebreak

/**
 * Kotlin/Native has no synchronous JVM-style resource loading, so the en-US
 * TeX patterns are embedded at build time as a Kotlin constant generated from the SAME
 * `hyph-en-us.tex` the JVM/Android resource path reads — identical to the Kotlin/JS path
 * (single source of truth; see the `generateEmbeddedHyphenationPatterns` task). ADR 0039.
 */
internal actual fun loadBundledEnglishHyphenationPatterns(): String = EN_US_HYPHENATION_PATTERNS
