package org.tiqian.shared.prepared_dom;

/**
 * One ordered line child (prepared-dom.ts LineChildEntry union). Modelled as a
 * flat record with a kind discriminator because reflaxe emits no union of
 * records; kind is "run" | "inlineObject" | "ruby" | "bopomofo" and only the
 * matching payload fields are read.
 */
typedef PreparedLineChild = {
    var kind: String;
    var run: Null<PreparedRunTyped>;
    var cell: Null<PreparedRunTyped>;
    var carrierMargin: Float;
    var ruby: Null<PlanRubyAnnotation>;
    var zone: Null<PlanBopomofoZone>;
    var width: Float;
    var lineTop: Float;
    var lineHeight: Float;
    var semanticPath: Array<PreparedSemanticSpan>;
}
