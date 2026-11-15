package org.tiqian.shared.prepared_dom;

/** Test resolver that prefixes the declaration with a fixed string. */
class PrefixedStyleClassResolver implements StyleClassResolver {
    private final prefix:String;

    public function new(prefix:String) {
        this.prefix = prefix;
    }

    public function resolve(declaration:String):String {
        return prefix + declaration;
    }
}
