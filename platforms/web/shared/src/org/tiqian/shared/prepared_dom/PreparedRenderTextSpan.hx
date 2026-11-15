package org.tiqian.shared.prepared_dom;

/**
 * One validated render-text span (prepared-dom.ts RenderTextSpanEntry) plus the
 * JSON.stringify(fontFamilies) signature the conflict check compares. The glue
 * keeps both in sync by computing the signature from the same array.
 */
typedef PreparedRenderTextSpan = {
    var start: Float;
    var end: Float;
    var fontFamilies: Array<String>;
    var signature: String;
}
