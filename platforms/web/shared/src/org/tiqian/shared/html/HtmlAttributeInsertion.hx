package org.tiqian.shared.html;

/**
 * One attribute injection: offset is the UTF-16 code-unit index where
 * attribute is inserted, and attribute is the verbatim text spliced at that
 * index. Mirrors the row of the Rust injection gate
 * (platforms/web/server/precompute/engine/src/precompute_html.rs:219-258).
 */
typedef HtmlAttributeInsertion = {
    var offset:Float;
    var attribute:String;
}
