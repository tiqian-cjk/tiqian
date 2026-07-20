package org.tiqian.layout

import org.tiqian.linebreak.Hyphenator

/**
 * The platform's default Western [Hyphenator], used when the engine is built
 * without an explicit one — hyphenation is ON by default (mixed CJK/Western is
 * common; it helps most on short measures). JVM and Android bundle en-US TeX
 * patterns; platforms without a bundled hyphenator fall back to no hyphenation.
 * Pass `NoHyphenator` explicitly to opt out (e.g. deterministic unit tests).
 */
internal expect fun defaultHyphenator(): Hyphenator
