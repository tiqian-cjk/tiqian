package org.tiqian.shared.prepared_dom;

/**
 * Render node that carries child nodes (prepared-dom-markup.ts MarkupContainer
 * extends MarkupNode). Reflaxe does not emit interface `extends`, so html and
 * artifact are redeclared here and concrete classes dual-implement both.
 */
interface MarkupContainer {
    public var children(get, never):Array<MarkupNode>;
    public var html(get, never):String;
    public var artifact(get, never):MarkupArtifact;
}
