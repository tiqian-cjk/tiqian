package org.tiqian.shared.prepared_dom;

/**
 * Typed options of the artifact lowering (prepared-dom.ts
 * PreparedParagraphRenderOptions after the glue has parsed the wire form and
 * normalized the semantics). Everything that needs DOM access, JSON parsing or
 * wire validation stays in the glue; this record is already validated.
 */
typedef PreparedArtifactOptions = {
    var styleClassFor: Null<StyleClassResolver>;
    var liveSource: Bool;
    var semantics: Array<PreparedSemanticSpan>;
    var renderTextSpans: Array<PreparedRenderTextSpan>;
    var cjkStrongSemantics: Array<PreparedCjkStrongSemantic>;
    var inlineBoxes: Array<InlineBoxEntry>;
    var emphasisDotColor: Null<EmphasisDotColorResolver>;
}
