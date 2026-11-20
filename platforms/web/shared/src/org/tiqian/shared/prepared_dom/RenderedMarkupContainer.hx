package org.tiqian.shared.prepared_dom;

/**
 * Lazy container render node: children may be appended after construction, so
 * html and artifact recompute on each access (the TS MarkupContainer getters
 * behave the same). _entries is the sorted attribute list captured at build.
 */
class RenderedMarkupContainer implements MarkupContainer implements MarkupNode {
    private final _tag:String;
    private final _entries:Array<AttributeEntry>;
    private final _children:Array<MarkupNode> = [];

    public function new(tag:String, entries:Array<AttributeEntry>) {
        this._tag = tag;
        this._entries = entries;
    }

    public var children(get, never):Array<MarkupNode>;
    function get_children():Array<MarkupNode> return _children;

    public var html(get, never):String;
    function get_html():String {
        var out = "<" + _tag;
        final ser = Markup.serializeAttributeEntries(_entries);
        if (ser.length > 0)
            out += " " + ser;
        out += ">";
        var i = 0;
        while (i < _children.length) {
            out += _children[i].html;
            i += 1;
        }
        out += "</" + _tag + ">";
        return out;
    }

    public var artifact(get, never):MarkupArtifact;
    function get_artifact():MarkupArtifact {
        final childArtifacts:Array<MarkupArtifact> = [];
        var i = 0;
        while (i < _children.length) {
            childArtifacts.push(_children[i].artifact);
            i += 1;
        }
        return Element(_tag, _entries, childArtifacts);
    }
}
