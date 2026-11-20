package org.tiqian.shared.prepared_dom;

/**
 * One inline edge from the plan (prepared-dom.ts InlineEdgeEntry). Either side
 * may be absent, in which case that edge contributes no box.
 */
typedef InlineEdgeEntry = {
    var offset: Float;
    var inlineStart: Null<Float>;
    var inlineEnd: Null<Float>;
}
