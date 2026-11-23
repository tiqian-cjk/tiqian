package org.tiqian.shared.prepared_dom;

/**
 * Mutable traversal state of the artifact lowering: the output node list and
 * the currently open semantic container path. Replaces the closures the TS
 * oracle uses (semanticContainerFor) because reflaxe closures cannot mutate
 * captured locals.
 */
typedef PreparedArtifactState = {
    var nodes: Array<MarkupNode>;
    var activeSemantics: Array<PreparedSemanticSpan>;
    var activeContainers: Array<RenderedMarkupContainer>;
    var cjkStrong: Array<PreparedCjkStrongSemantic>;
    var liveSource: Bool;
}
