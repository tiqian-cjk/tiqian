package org.tiqian.shared.html;

/**
 * The issue variants of the shared HTML scan, injection and selector lane.
 * The three names are the published issue names the Rust addon lane
 * produces (platforms/web/server/precompute/engine/src/precompute_html.rs:
 * to_offset at L210-212 emits HtmlOffsetConversion, the injection gate at
 * L219-258 emits InvalidHtmlAttributeInsertionOffset; html_parse.rs at
 * L509, L523 and L637 emits UnsupportedHtmlAncestorSelector); the
 * generated lane reuses the same names so the two error surfaces stay
 * byte-identical. Declaration order follows the Rust emission order.
 */
enum HtmlError {
    HtmlOffsetConversion;
    InvalidHtmlAttributeInsertionOffset;
    UnsupportedHtmlAncestorSelector;
}
