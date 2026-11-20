package org.tiqian.shared.prepared_dom;

/** Test resolver that ignores the declaration and returns a fixed class name. */
class FixedStyleClassResolver implements StyleClassResolver {
    private final value:String;

    public function new(value:String) {
        this.value = value;
    }

    public function resolve(declaration:String):String {
        return value;
    }
}
