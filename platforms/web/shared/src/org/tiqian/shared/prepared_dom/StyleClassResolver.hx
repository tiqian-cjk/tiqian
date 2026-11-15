package org.tiqian.shared.prepared_dom;

/**
 * Style-class resolver callback as an interface, per the D1 ruling (function
 * values become interface callbacks; a raw Haxe function type would emit a
 * return type of string-or-null into TypeScript and break use sites there).
 * Absence of a resolver (inline style mode) is modelled by the nullable
 * interface reference at the call site.
 */
interface StyleClassResolver {
    public function resolve(declaration:String):String;
}
