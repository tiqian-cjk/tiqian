package org.tiqian.layout

import org.tiqian.linebreak.Hyphenator
import org.tiqian.linebreak.NoHyphenator

/**
 * Web (Wasm) default: `NoHyphenator` — the browser port ships without bundled
 * en-US patterns for now (see `loadBundledEnglishHyphenationPatterns` wasm
 * actual). This is a platform capability gap, NOT a model change: hyphenation
 * stays engine-owned (ADR 0039 `EngineOwnedHyphenation`) — inject a real
 * `Hyphenator` and the DOM renderer draws its hyphens faithfully. Named gap:
 * `WebBundledHyphenationDeferred`.
 */
internal actual fun defaultHyphenator(): Hyphenator = NoHyphenator
