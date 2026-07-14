package org.tiqian.linebreak

/**
 * Kotlin/JS has no synchronous resource loading, so the en-US TeX patterns are
 * embedded at build time as a Kotlin constant generated from the SAME
 * `hyph-en-us.tex` the JVM/Android resource path reads (single source of truth;
 * see the `generateJsHyphenationPatterns` task). This closes the former
 * `WebBundledHyphenationDeferred` gap — English hyphenation now works on web
 * exactly as on the other platforms (ADR 0039).
 */
internal actual fun loadBundledEnglishHyphenationPatterns(): String = EN_US_HYPHENATION_PATTERNS
