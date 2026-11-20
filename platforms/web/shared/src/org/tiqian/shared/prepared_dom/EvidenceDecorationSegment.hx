package org.tiqian.shared.prepared_dom;

/**
 * One interlinear decoration segment (prepared-dom-evidence.ts
 * EvidenceDecorationSegment): a straight line under a proper noun or a wavy
 * line under a book title.
 */
typedef EvidenceDecorationSegment = {
    var left: Float;
    var top: Float;
    var right: Float;
    var kind: EvidenceDecorationKind;
}
