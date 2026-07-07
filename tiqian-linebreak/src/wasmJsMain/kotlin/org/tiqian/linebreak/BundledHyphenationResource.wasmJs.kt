package org.tiqian.linebreak

/**
 * Web (Wasm) ships NO bundled hyphenation patterns yet — synchronous resource
 * loading isn't available in the browser, and embedding the ~30KB TeX pattern
 * blob as a Wasm string constant is deferred to a follow-up. This is only ever
 * hit if `EnglishHyphenation.enUs` is referenced explicitly; the web default
 * ([defaultHyphenator]) is `NoHyphenator`, so it isn't on the default path.
 * Named gap: `WebBundledHyphenationDeferred` (ADR 0039).
 */
internal actual fun loadBundledEnglishHyphenationPatterns(): String = ""
