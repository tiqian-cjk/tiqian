// The DOM projection behind the HTML preparer (Html-B2). It replaces the
// Rust walk that html_parse.rs prepared for snapshot_source.rs
// (snapshot_source_artifact_from_dom / append_dom_node / projected_normal_flow)
// and precompute_html.rs's projectedTextOnly, reading the linkedom tree through
// the shared DomNode surface and folding whitespace with the generated
// SnapshotSource lane.
//
// The server lane rejects a host projector, so a projection only has to answer
// two questions: the projected text, and whether any safe inline semantic
// survives the fold (a semantic paragraph stays with the host and declines the
// snapshot). The semantic ranges are still collected because an element whose
// range collapses to nothing in the fold does not count.
import type { DomAttribute } from "@tiqian/shared/org/tiqian/shared/html/DomAttribute";
import type { DomNode } from "@tiqian/shared/org/tiqian/shared/html/DomNode";
import { SnapshotSource } from "@tiqian/shared/org/tiqian/shared/snapshot/SnapshotSource";

export interface RawSemanticSpan {
    readonly start: number;
    readonly end: number;
    readonly tagName: string;
    readonly attributes: readonly (readonly [string, string])[];
    readonly order: number;
}

export interface SourceArtifact {
    readonly text: string;
    readonly semantics: readonly RawSemanticSpan[];
}

const ELEMENT_NODE = 1;
const TEXT_NODE = 3;

interface WalkState {
    text: string;
    spans: RawSemanticSpan[];
    hardBreaks: number[];
    order: number;
}

function textOf(node: DomNode): string {
    const value = node.nodeValue;
    return typeof value === "string" ? value : "";
}

function attributesOf(node: DomNode): (readonly [string, string])[] {
    const attributes: readonly DomAttribute[] = node.attributes;
    const pairs: (readonly [string, string])[] = [];
    for (let index = 0; index < attributes.length; index += 1) {
        pairs.push([attributes[index].name, attributes[index].value]);
    }
    return pairs;
}

/**
 * The appendDomNode walk: text appends verbatim, br records a hard break, a
 * safe semantic tag opens a range around its children, and any other element
 * declines the artifact (the caller falls back to the contract lane).
 */
function appendDomNode(node: DomNode, state: WalkState): boolean {
    if (node.nodeType === TEXT_NODE) {
        state.text += textOf(node);
        return true;
    }
    if (node.nodeType !== ELEMENT_NODE)
        return true;
    const tagName = node.tagName.toLowerCase();
    if (tagName === "br") {
        state.hardBreaks.push(state.text.length);
        state.text += "\n";
        return true;
    }
    if (!SnapshotSource.isSafeTag(tagName))
        return false;
    const start = state.text.length;
    const order = state.order;
    state.order += 1;
    for (let index = 0; index < node.childNodes.length; index += 1) {
        if (!appendDomNode(node.childNodes[index], state))
            return false;
    }
    const end = state.text.length;
    if (end > start) {
        state.spans.push({ start, end, tagName, attributes: attributesOf(node), order });
    }
    return true;
}

/**
 * snapshotSourceArtifactFromDom: collects the raw text, the hard breaks and the
 * semantic ranges of one paragraph, folds the normal flow and maps the ranges
 * through the fold. A null result is a declined artifact.
 */
export function snapshotSourceArtifactFromDom(element: DomNode): SourceArtifact | null {
    const node = element;
    const state: WalkState = { text: "", spans: [], hardBreaks: [], order: 0 };
    for (let index = 0; index < node.childNodes.length; index += 1) {
        if (!appendDomNode(node.childNodes[index], state))
            return null;
    }
    const fold = SnapshotSource.foldNormalFlow(state.text, state.hardBreaks);
    const semantics: RawSemanticSpan[] = [];
    for (const span of state.spans) {
        const start: number | undefined = fold.boundaryMap[span.start];
        const end: number | undefined = fold.boundaryMap[span.end];
        if (start === undefined || end === undefined || end <= start)
            continue;
        semantics.push(Object.freeze({ ...span, start, end }));
    }
    return Object.freeze({ text: fold.text, semantics: Object.freeze(semantics) });
}

/**
 * snapshotProjection: the canonical artifact first, then the plain-only rule.
 * A paragraph with any surviving inline semantics declines the snapshot; an
 * artifact that failed (an unsafe tag or an invalid range) declines as well.
 */
export function snapshotProjection(element: DomNode): { readonly text: string } | null {
    const artifact = snapshotSourceArtifactFromDom(element);
    if (artifact === null)
        return null;
    if (artifact.semantics.length > 0)
        return null;
    return Object.freeze({ text: artifact.text });
}

function appendProjectedRaw(node: DomNode, state: WalkState): void {
    if (node.nodeType === TEXT_NODE) {
        state.text += textOf(node);
        return;
    }
    if (node.nodeType !== ELEMENT_NODE)
        return;
    const tagName = node.tagName.toLowerCase();
    if (tagName === "br") {
        state.hardBreaks.push(state.text.length);
        state.text += "\n";
        return;
    }
    if (tagName === "script" || tagName === "style" || tagName === "template")
        return;
    for (let index = 0; index < node.childNodes.length; index += 1) {
        appendProjectedRaw(node.childNodes[index], state);
    }
}

/**
 * projectedTextOnly: text content with br kept as a hard break and every other
 * whitespace run collapsed to one space. It is the contract-lane text the Rust
 * lane used for paragraphs without a snapshot projection.
 */
export function projectedTextOnly(element: DomNode): string {
    const node = element;
    const state: WalkState = { text: "", spans: [], hardBreaks: [], order: 0 };
    for (let index = 0; index < node.childNodes.length; index += 1) {
        appendProjectedRaw(node.childNodes[index], state);
    }
    const hardBreaks = new Set(state.hardBreaks);
    let output = "";
    let pendingWhitespace = false;
    let offset = 0;
    for (const character of state.text) {
        if (character === "\n" && hardBreaks.has(offset)) {
            pendingWhitespace = false;
            output += "\n";
        }
        else if (character === " " ||
            character === "\t" ||
            character === "\n" ||
            character === "\r" ||
            character === "\f") {
            pendingWhitespace = output.length > 0 && !output.endsWith("\n");
        }
        else {
            if (pendingWhitespace)
                output += " ";
            pendingWhitespace = false;
            output += character;
        }
        offset += character.length;
    }
    return output;
}

