package org.tiqian.web.precompute

import org.tiqian.shaping.HarfBuzzSessionFontMetricsResolver
import org.tiqian.shaping.HarfBuzzSessionTextShaper

/**
 * Synchronous Kotlin side of the Node font session prepared by `precompute-fonts.js`.
 * Font loading, WOFF2 decoding and hashing stay async in Node; layout only sees an
 * immutable session and therefore keeps the normal synchronous platform contracts.
 */
@OptIn(ExperimentalWasmJsInterop::class)
internal typealias HarfBuzzBuildTextShaper = HarfBuzzSessionTextShaper
internal typealias HarfBuzzBuildFontMetricsResolver = HarfBuzzSessionFontMetricsResolver
