package org.tiqian.shared.prepared_dom;

/**
 * One serialized HTML attribute as a name/value string pair. The attribute
 * keys in prepared-dom output (data-tq-*, aria-hidden, lang, class, style)
 * contain hyphens and a reserved word, so boring cannot emit them as Haxe
 * struct field names (TsDecl.hx emits raw field.name, no @:native). They are
 * therefore modelled as a finite ordered list of {name,value} string pairs
 * (D1 table-driven), which the (b) glue re-serializes in sorted order.
 */
typedef AttributeEntry = {
    var name: String;
    var value: String;
}
