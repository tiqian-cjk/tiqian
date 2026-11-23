package org.tiqian.shared.prepared_dom;

/**
 * Typed structured artifact emitted by prepared-dom markup lowering. Mirrors
 * the raw nested MarkupArtifact array the browser corpus gate JSON.stringify's
 * for byte comparison: Text is the ["#", text] leaf, Element is
 * [tag, [entries], [children]]. Raw wire assembly (Dynamic arrays) stays in
 * the browser glue, which pattern-matches this enum to rebuild the raw form.
 */
enum MarkupArtifact {
    Text(text:String);
    Element(tag:String, entries:Array<AttributeEntry>, children:Array<MarkupArtifact>);
}
