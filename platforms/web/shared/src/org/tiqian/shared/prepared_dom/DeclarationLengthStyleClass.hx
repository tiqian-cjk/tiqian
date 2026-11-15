package org.tiqian.shared.prepared_dom;

/** Style-class resolver stand-in: tqc plus the declaration length, the corpus mode. */
class DeclarationLengthStyleClass implements StyleClassResolver {
    public function new() {}

    public function resolve(declaration:String):String {
        return "tqc-" + declaration.length;
    }
}
