package org.tiqian.shared.html;

/**
 * One opening tag found by the scan. end is the UTF-16 code-unit index one
 * past the final '>' of the tag source, source is the verbatim tag text, and
 * tagName is the lowercased tag name. Mirrors the Rust struct
 * (platforms/web/server/precompute/engine/src/precompute_html.rs:82) and the
 * TS interface platforms/web/server/core/src/precompute-html.ts:112-116.
 */
typedef HtmlOpeningTag = {
    var end:Int;
    var source:String;
    var tagName:String;
}
