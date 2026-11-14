// The HTML preparer entry over the generated shared lanes (Html-B2). The
// exported surface matches the former `@tiqian/prose/precompute-html` module.
// Parsing, selection, projection and the prepare orchestration run here in
// TypeScript over linkedom and the B1 generated modules; the paragraph and
// font-contract lanes, the snapshot tables and the bundle assembly stay in the
// native precomputer calls the precompute module wraps. The DOM projection
// callback needs a host DOM, so this lane rejects it by name.
import { createHash } from "node:crypto";
import { parseHTML } from "linkedom";
import { absorbSnapshotTables, assembleFontContractBundle, assembleSnapshotBundle, closeSnapshotTables, createPrecomputer, createSnapshotTables, finalizeSnapshotTables, precomputerHandle, renderFontContractBundleData, renderSnapshotBundleData, } from "./precompute.js";
import { projectedTextOnly, snapshotProjection } from "./precompute-html-projection.js";
import { CompoundSelector } from "tiqian-shared/org/tiqian/shared/html/CompoundSelector";
import { DomParser } from "tiqian-shared/org/tiqian/shared/html/DomParser";
import { HtmlParseException } from "tiqian-shared/org/tiqian/shared/html/HtmlParseException";
import { HtmlScan } from "tiqian-shared/org/tiqian/shared/html/HtmlScan";
import { type BuildFontFace, type BuildFontStylesheet, type NormalizedTypography, type Precomputer, type SnapshotBundle, type SnapshotTypography } from "./precompute.js";
import type { FontContractInput, PreparedEntry, SnapshotParagraphInput } from "./precompute.js";
import type { DomNode } from "tiqian-shared/org/tiqian/shared/html/DomNode";

const DEFAULT_PARAGRAPH_SELECTOR = "p, li";
const DEFAULT_SKIPPED_ANCESTOR_SELECTOR = "[data-tiqian-skip], pre, table, .not-prose, .katex, .katex-display, .expressive-code";
const SOURCE_MAP_IGNORED_ANCESTOR_SELECTOR = "iframe, noembed, noframes, noscript, plaintext, xmp";
const LIST_ITEM_CONTAINER_TAGS = new Set(["p", "ul", "ol", "blockquote", "pre", "table"]);
const PREPARE_ROOT_MARKUP = "<main data-tq-html-prepare-root>";

export interface SnapshotServerAssets {
    readonly id: string;
    readonly initialStyle: string;
    readonly inertTemplate: string;
    readonly fontPreloads: readonly string[];
}

export interface ClientSnapshotBundle {
    readonly id: string;
    readonly clientTemplate: string;
    readonly initialStyle: string;
    readonly fontPreloads: readonly string[];
}

export interface PreparedHtmlIssue {
    readonly index: number;
    readonly key: string;
    readonly stage: "snapshot" | "font-contract";
    readonly issue: string;
}

/** The snapshot-table file one `prepare` call emitted (ADR 0052 schema 2). */
export interface PreparedHtmlTables {
    readonly bytes: Buffer;
    readonly sha256: string;
}

export interface PreparedHtml {
    readonly html: string;
    readonly rootAttributes: Readonly<Record<string, string>>;
    readonly bundle: SnapshotBundle | null;
    readonly clientBundle: ClientSnapshotBundle | null;
    readonly serverAssets: SnapshotServerAssets | null;
    /** Hosts serve `bytes` under the sha address; the manifest pins the sha. */
    readonly tables: PreparedHtmlTables | null;
    readonly issues: readonly PreparedHtmlIssue[];
}

export interface HtmlPrepareOptions {
    /** Distinct retained asset payloads must not share an explicit id within one adapter scope. */
    readonly id?: string;
    /** Optional fixed-measure prepared geometry; omit for width-independent font evidence. */
    readonly snapshot?: {
        readonly maxWidthPx: number;
    };
}

export interface HtmlPreparer {
    readonly typography: NormalizedTypography;
    /** Prepares the whole document: parse, project, then run the native lanes. */
    prepare(html: string, options?: HtmlPrepareOptions): Promise<PreparedHtml>;
    close(): void;
}

export type HtmlPreparerOptions = {
    /** Only simple tag-name lists such as `p, li` are supported. */
    readonly paragraphSelector?: string;
    readonly skippedAncestorSelector?: string;
    /**
     * Rejected in this lane with `UnsupportedHtmlProjector`: projection needs a
     * host DOM. Kept for type parity with the `@tiqian/prose` entry.
     */
    readonly projectSnapshotParagraph?: (...args: never[]) => unknown;
} & ({
    /** Reuse an existing precomputer instead of opening another exact-font session. */
    readonly precomputer: Precomputer;
    readonly fontStylesheets?: never;
    readonly faces?: never;
    readonly typography?: never;
} | {
    readonly precomputer?: undefined;
    readonly fontStylesheets?: readonly BuildFontStylesheet[];
    readonly faces?: readonly BuildFontFace[];
    readonly typography: SnapshotTypography;
});

export interface HtmlOpeningTag {
    readonly end: number;
    readonly source: string;
    readonly tagName: string;
}

/**
 * Locates source opening tags without serializing the host's HTML; the scan
 * runs on UTF-16 code units and skips raw-text containers and inert templates
 * so a literal `<p>` example never receives a live snapshot key.
 */
export function findHtmlOpeningTags(html: string, tagNames: readonly string[] = ["p", "li"]): readonly HtmlOpeningTag[] {
    return HtmlScan.findHtmlOpeningTags(html, Array.from(tagNames ?? []));
}

/** Inserts attribute strings at the given offsets, highest offset first. */
export function injectHtmlAttributes(html: string, insertions: readonly {
    readonly offset: number;
    readonly attribute: string;
}[]): string {
    const rows = Array.from(insertions ?? []).map(({ offset, attribute }) => ({ offset, attribute }));
    try {
        return HtmlScan.injectHtmlAttributes(html, rows);
    }
    catch (error) {
        if (error instanceof HtmlParseException) {
            throw new Error(error.message, { cause: error });
        }
        throw error;
    }
}

/** The payload a server template inlines. */
export function snapshotServerAssets(bundle: SnapshotBundle | null): SnapshotServerAssets | null {
    if (!bundle)
        return null;
    return Object.freeze({
        id: bundle.id,
        initialStyle: bundle.initialStyle,
        inertTemplate: bundle.inertTemplate,
        fontPreloads: Object.freeze([...bundle.fontPreloads]),
    });
}

/** Preload links, the first paint style and the inert template, concatenated. */
export function renderSnapshotServerAssets(assets: SnapshotServerAssets | null): string {
    if (!assets)
        return "";
    const preloads = assets.fontPreloads
        .map((href) => `<link rel="preload" as="font" type="font/woff2" crossorigin href="${escapeAttribute(href)}">`)
        .join("");
    return `${preloads}<style data-tq-initial-snapshot="${escapeAttribute(assets.id)}">${assets.initialStyle}</style>${assets.inertTemplate}`;
}

function escapeAttribute(value: string): string {
    return value.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
}

function parseSelectorList(selector: string): CompoundSelector[] {
    try {
        return CompoundSelector.parseCompoundSelectorList(selector);
    }
    catch (error) {
        if (error instanceof HtmlParseException)
            throw new Error(error.message, { cause: error });
        throw error;
    }
}

/** selectedTagNames: comma separated tag names only, trimmed and lowercased. */
function selectedTagNames(selector: string): string[] {
    const names = selector.split(",").map((item) => item.trim().toLowerCase());
    const valid = (name: string) => /^[a-z][a-z0-9-]*$/u.test(name);
    if (names.some((name) => !valid(name))) {
        throw new Error("UnsupportedHtmlParagraphSelector");
    }
    return names;
}

function parseDocument(markup: string): DomParser {
    const window = parseHTML(markup);
    return new DomParser(window.document as DomNode);
}

/** nestedListItem: a list item that owns a block container keeps its layout in the host. */
function nestedListItem(parser: DomParser, element: DomNode): boolean {
    if (parser.tagName(element) !== "li")
        return false;
    return parser
        .elementChildren(element)
        .some((child) => LIST_ITEM_CONTAINER_TAGS.has(parser.tagName(child)));
}

function prepareId(html: string, width: number | null, explicit: string | undefined): string {
    if (typeof explicit === "string")
        return explicit;
    const hash = createHash("sha256").update(html, "utf8").update(Buffer.from([0]));
    hash.update(width === null ? "runtime" : String(width), "utf8");
    return `tq-prose-${hash.digest("hex").slice(0, 16)}`;
}

type Plan = {
    index: number;
    openingTagEnd: number;
    projected: { readonly text: string } | null;
    text: string;
};

/**
 * Creates the framework-neutral server boundary consumed by SvelteKit and
 * Astro integrations. Host HTML remains byte-for-byte intact except for
 * snapshot keys inserted into paragraphs that produced reusable geometry.
 * `projectSnapshotParagraph` needs a host DOM and throws
 * `UnsupportedHtmlProjector` here; hosts projecting rich semantics keep the
 * `@tiqian/prose` entry.
 */
export async function createHtmlPreparer(options: HtmlPreparerOptions): Promise<HtmlPreparer> {
    if (typeof options.projectSnapshotParagraph === "function") {
        throw new Error("UnsupportedHtmlProjector");
    }
    let precomputer: Precomputer;
    let ownsPrecomputer: boolean;
    if (options.precomputer) {
        if (precomputerHandle(options.precomputer) === null) {
            throw new Error("ForeignPrecomputer");
        }
        precomputer = options.precomputer;
        ownsPrecomputer = false;
    }
    else {
        // The typography validates before any font file is read, the js order.
        precomputer = await createPrecomputer({
            typography: options.typography,
            faces: options.faces,
            fontStylesheets: options.fontStylesheets,
        });
        ownsPrecomputer = true;
    }
    const tagNames = selectedTagNames(options.paragraphSelector ?? DEFAULT_PARAGRAPH_SELECTOR);
    const skipped = parseSelectorList(options.skippedAncestorSelector ?? DEFAULT_SKIPPED_ANCESTOR_SELECTOR);
    const sourceMapIgnored = parseSelectorList(SOURCE_MAP_IGNORED_ANCESTOR_SELECTOR);
    let closed = false;
    async function prepare(html: string, prepareOptions: HtmlPrepareOptions = {}): Promise<PreparedHtml> {
        if (closed)
            throw new Error("HtmlPreparerClosed");
        const rawWidth = prepareOptions.snapshot?.maxWidthPx;
        const width = rawWidth === undefined || rawWidth === null ? null : Number(rawWidth);
        if (width !== null && (!Number.isFinite(width) || width <= 0)) {
            throw new Error("InvalidMaximumMeasure");
        }
        const id = prepareId(String(html), width, prepareOptions.id);
        const parser = parseDocument(`${PREPARE_ROOT_MARKUP}${html}</main>`);
        const root = parser
            .descendantsByTag(parser.documentNode(), ["main"])
            .find((element) => parser.attributeValue(element, "data-tq-html-prepare-root") !== null);
        if (root === undefined)
            throw new Error("HtmlPrepareRootUnavailable");
        const sourceElements = parser
            .descendantsByTag(root, tagNames)
            .filter((element) => !parser.closest(element, sourceMapIgnored));
        const openingTags = HtmlScan.findHtmlOpeningTags(String(html), tagNames);
        if (sourceElements.length !== openingTags.length) {
            throw new Error(`HtmlParagraphSourceMapMismatch:${sourceElements.length}:${openingTags.length}`);
        }
        const plans: Plan[] = [];
        for (let index = 0; index < sourceElements.length; index += 1) {
            const element = sourceElements[index];
            const openingTag = openingTags[index];
            if (openingTag.tagName !== parser.tagName(element)) {
                throw new Error(`HtmlParagraphSourceOrderMismatch:${index}`);
            }
            if (parser.closest(element, skipped) || nestedListItem(parser, element))
                continue;
            const projected = snapshotProjection(element);
            const text = projected === null ? projectedTextOnly(element) : projected.text;
            if (text.trim().length === 0)
                continue;
            plans.push({ index, openingTagEnd: openingTag.end, projected, text });
        }
        // Phase one: one whole element sequence per native batch. The snapshot
        // attempt runs first and the contract fallback runs after it, so an element
        // keeps the sequential lane's branching and issue order.
        const snapshotByIndex = new Map<number, PreparedEntry>();
        const snapshotPlans = width === null ? [] : plans.filter((plan) => plan.projected !== null);
        if (snapshotPlans.length > 0 && width !== null) {
            const inputs: SnapshotParagraphInput[] = snapshotPlans.map((plan) => ({
                key: `p-${plan.index}`,
                text: plan.projected!.text,
                maxWidthPx: width,
                semantics: [],
                textSpans: [],
                inlineBoxes: [],
                sourceBoundaries: [],
            }));
            const entries = await precomputer.prepareParagraphs(inputs);
            for (let index = 0; index < snapshotPlans.length; index += 1) {
                snapshotByIndex.set(snapshotPlans[index].index, entries[index]);
            }
        }
        const contractPlans = plans.filter((plan) => {
            const snapshot = snapshotByIndex.get(plan.index);
            return snapshot === undefined || snapshot.status !== "prepared";
        });
        const contractByIndex = new Map<number, PreparedEntry>();
        if (contractPlans.length > 0) {
            const inputs: FontContractInput[] = contractPlans.map((plan) => ({
                key: `f-${plan.index}`,
                text: plan.text,
                ...(plan.projected === null
                    ? {}
                    : { semantics: [], textSpans: [], inlineBoxes: [], sourceBoundaries: [] }),
            }));
            const entries = await precomputer.prepareFontContracts(inputs);
            for (let index = 0; index < contractPlans.length; index += 1) {
                contractByIndex.set(contractPlans[index].index, entries[index]);
            }
        }
        // Phase two: rebuild the sequential arrays. Document order holds, and an
        // element's snapshot issue stays ahead of its contract issue.
        const preparedParagraphs: PreparedEntry[] = [];
        const fontContracts: PreparedEntry[] = [];
        const insertions: { offset: number; attribute: string; }[] = [];
        const issues: PreparedHtmlIssue[] = [];
        for (const plan of plans) {
            const snapshot = snapshotByIndex.get(plan.index);
            if (snapshot !== undefined) {
                if (snapshot.status === "prepared") {
                    preparedParagraphs.push(snapshot);
                    insertions.push({
                        offset: plan.openingTagEnd,
                        attribute: ` data-tq-snapshot-key="p-${plan.index}"`,
                    });
                }
                else {
                    issues.push({ index: plan.index, key: `p-${plan.index}`, stage: "snapshot", issue: snapshot.issue });
                }
            }
            const contract = contractByIndex.get(plan.index);
            if (contract !== undefined) {
                if (contract.status === "prepared") {
                    fontContracts.push(contract);
                }
                else {
                    issues.push({
                        index: plan.index,
                        key: `f-${plan.index}`,
                        stage: "font-contract",
                        issue: contract.issue,
                    });
                }
            }
        }
        let bundle: SnapshotBundle | null = null;
        let tables: PreparedHtmlTables | null = null;
        if (preparedParagraphs.length > 0) {
            const handles = createSnapshotTables();
            try {
                absorbSnapshotTables(handles, [...preparedParagraphs, ...fontContracts]);
                const data = renderSnapshotBundleData(preparedParagraphs, {
                    id,
                    fontContractParagraphs: fontContracts,
                    snapshotTables: handles,
                });
                const file = finalizeSnapshotTables(handles);
                bundle = assembleSnapshotBundle(data, handles);
                tables = Object.freeze({ bytes: file.bytes, sha256: file.sha256 });
            }
            finally {
                closeSnapshotTables(handles);
            }
        }
        else if (fontContracts.length > 0) {
            const handles = createSnapshotTables();
            try {
                absorbSnapshotTables(handles, fontContracts);
                const data = renderFontContractBundleData(fontContracts, { id, snapshotTables: handles });
                const file = finalizeSnapshotTables(handles);
                bundle = assembleFontContractBundle(data, handles);
                tables = Object.freeze({ bytes: file.bytes, sha256: file.sha256 });
            }
            finally {
                closeSnapshotTables(handles);
            }
        }
        const preparedHtml = injectHtmlAttributes(String(html), insertions);
        const rootAttributes: Record<string, string> = {};
        if (bundle) {
            rootAttributes["snapshot-ref"] = bundle.id;
            for (const [name, value] of Object.entries(bundle.rootAttributes)) {
                rootAttributes[name] = String(value);
            }
        }
        const clientBundle: ClientSnapshotBundle | null = bundle
            ? Object.freeze({
                id: bundle.id,
                clientTemplate: bundle.clientTemplate,
                initialStyle: bundle.initialStyle,
                fontPreloads: Object.freeze([...bundle.fontPreloads]),
            })
            : null;
        const serverAssets: SnapshotServerAssets | null = bundle
            ? Object.freeze({
                id: bundle.id,
                initialStyle: bundle.initialStyle,
                inertTemplate: bundle.inertTemplate,
                fontPreloads: Object.freeze([...bundle.fontPreloads]),
            })
            : null;
        return Object.freeze({
            html: preparedHtml,
            rootAttributes: Object.freeze(rootAttributes),
            bundle,
            clientBundle,
            serverAssets,
            tables,
            issues: Object.freeze(issues),
        });
    }
    return Object.freeze({
        typography: precomputer.typography,
        prepare,
        close() {
            if (closed)
                return;
            closed = true;
            if (ownsPrecomputer)
                precomputer.close();
        },
    });
}

