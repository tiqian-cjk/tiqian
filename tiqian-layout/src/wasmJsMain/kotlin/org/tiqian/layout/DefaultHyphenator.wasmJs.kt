package org.tiqian.layout

import org.tiqian.linebreak.EnglishHyphenation
import org.tiqian.linebreak.Hyphenator

/**
 * Web (Wasm) default: the bundled en-US TeX hyphenator, same as JVM/Android. The
 * patterns are embedded into wasm at build time (see the linebreak module's
 * `generateWasmHyphenationPatterns`), so hyphenation is engine-owned and available
 * synchronously at first layout — no async fetch, no re-layout, no CLS (ADR 0039).
 */
internal actual fun defaultHyphenator(): Hyphenator = EnglishHyphenation.enUs
