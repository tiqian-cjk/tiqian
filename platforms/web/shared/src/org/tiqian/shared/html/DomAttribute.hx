package org.tiqian.shared.html;

/**
 * A single attribute of a parsed DOM element. `name` and `value` are the
 * linkedom attribute surface the query API reads
 * (platforms/web/server/precompute/engine/src/html_parse.rs: attribute
 * handling at L329-447).
 */
typedef DomAttribute = {
    final name:String;
    final value:String;
}
