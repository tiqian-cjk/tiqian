package org.tiqian.shared.prepared_dom;

/**
 * Typed result of the artifact lowering (prepared-dom.ts
 * PreparedParagraphArtifactResult). artifact is the typed node tree; the glue
 * serializes it to the nested wire arrays the corpus gate stringifies.
 */
typedef PreparedArtifactResult = {
    var html: String;
    var artifact: Array<MarkupArtifact>;
    var liveSemanticCount: Int;
    var inlineObjectCount: Int;
    var markerCount: Int;
}
