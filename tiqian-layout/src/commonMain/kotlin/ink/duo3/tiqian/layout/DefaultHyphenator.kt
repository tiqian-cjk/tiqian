package ink.duo3.tiqian.layout

import ink.duo3.tiqian.linebreak.Hyphenator

/**
 * The platform's default Western [Hyphenator], used when the engine is built
 * without an explicit one — hyphenation is ON by default (mixed CJK/Western is
 * common; it helps most on short measures). JVM bundles en-US TeX patterns;
 * platforms without a bundled/native hyphenator fall back to no hyphenation.
 * Pass `NoHyphenator` explicitly to opt out (e.g. deterministic unit tests).
 */
internal expect fun defaultHyphenator(): Hyphenator
