package org.tiqian.shared.prepared_dom;

/**
 * Eager leaf/terminal render node: html and artifact are computed once by the
 * Markup builder and stored. Dual of the TS closure-returned plain object for
 * renderedText / renderedElement.
 */
class RenderedMarkupNode implements MarkupNode {
    private final _html:String;
    private final _artifact:MarkupArtifact;

    public function new(html:String, artifact:MarkupArtifact) {
        this._html = html;
        this._artifact = artifact;
    }

    public var html(get, never):String;
    function get_html():String return _html;

    public var artifact(get, never):MarkupArtifact;
    function get_artifact():MarkupArtifact return _artifact;
}
