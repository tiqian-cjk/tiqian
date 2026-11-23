package org.tiqian.shared.prepared_dom;

/**
 * Render node emitted by renderRun / prepared-dom markup lowering. Matches the
 * TS MarkupNode in prepared-dom-markup.ts: html is the serialized open+body
 * string and artifact is the typed MarkupArtifact the browser glue lowers to
 * the nested-array form the corpus gate JSON.stringify's for byte comparison.
 */
interface MarkupNode {
    public var html(get, never):String;
    public var artifact(get, never):MarkupArtifact;
}
