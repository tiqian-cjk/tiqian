package org.tiqian.shared.prepared_dom;

/**
 * Decoration kind of one interlinear segment (prepared-dom-evidence.ts
 * EvidenceDecorationSegment.kind string union). The browser glue maps the
 * wire string to this enum and rejects any other value, which is where the TS
 * oracle threw UnsupportedPreparedDecorationSegment.
 */
enum EvidenceDecorationKind {
    ProperNoun;
    BookTitle;
}
