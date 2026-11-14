// The precompute entry over the native addon (ADR 0050). The exported
// surface matches the former `@tiqian/prose/precompute` module; every
// computation runs in Rust behind registry handles, and this file owns the
// object shapes the js API promises. File reading and URL resolution stay
// here: the crate never touches the filesystem.

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { addon } from "./load.js";
import {
  renderPreparedParagraph as sharedRenderPreparedParagraph,
  renderPreparedParagraphArtifact as sharedRenderPreparedParagraphArtifact,
} from "@tiqian/prose/prepared-dom";
import { Revision } from "./protocol-gen/Revision.js";
import { SnapshotValueStyle } from "./shared-gen/org/tiqian/shared/SnapshotValueStyle.js";
import { ValueStyleInterner } from "./shared-gen/org/tiqian/shared/ValueStyleInterner.js";
import { sha256Hex, stableStringify } from "./stable-stringify.js";
import { createCacheBridge } from "./cache.js";
import type { CacheBridge } from "./cache.js";
const SHARED_RUNTIME_STYLE = readFileSync(
  new URL(import.meta.resolve("@tiqian/core/styles.css")),
  "utf8",
);
const URL_SCHEME_PREFIX = /^[a-z][a-z0-9+.-]*:/iu;
const WINDOWS_DRIVE_ABSOLUTE_PATH = /^[a-z]:[\\/]/iu;

/**
 * Parses a JSON string produced by the shared Rust emitters; parsing happens
 * only at this boundary.
 */
function parse<T>(json: string): T {
  return JSON.parse(json) as T;
}

function toBuffer(source: Uint8Array | Buffer): Buffer {
  return Buffer.isBuffer(source) ? source : Buffer.from(source);
}

// WindowsDrivePathBeforeUrlScheme: a drive letter is syntactically a valid
// URL scheme, but Node callers pass path.resolve()/path.join() results here
// as ordinary local sources. File paths must win before URL handling.
function isExplicitUrlString(source: string): boolean {
  return URL_SCHEME_PREFIX.test(source) && !WINDOWS_DRIVE_ABSOLUTE_PATH.test(source);
}

async function readSource(source: BuildFontFace["source"]): Promise<Uint8Array> {
  if (source instanceof Uint8Array) return source;
  if (source instanceof ArrayBuffer) return new Uint8Array(source);
  if (source instanceof URL) {
    if (source.protocol !== "file:") throw new Error(`RemoteFontSourceNotSupported:${source.href}`);
    return new Uint8Array(await readFile(fileURLToPath(source)));
  }
  if (typeof source === "string") {
    if (isExplicitUrlString(source)) {
      const url = new URL(source);
      if (url.protocol !== "file:") throw new Error(`RemoteFontSourceNotSupported:${source}`);
      return new Uint8Array(await readFile(fileURLToPath(url)));
    }
    return new Uint8Array(await readFile(source));
  }
  throw new Error("UnsupportedFontSource");
}

function stylesheetFileUrl(source: BuildFontStylesheet["source"]): URL {
  if (source instanceof URL) {
    if (source.protocol !== "file:") {
      throw new Error(`RemoteFontStylesheetNotSupported:${source.href}`);
    }
    return source;
  }
  if (typeof source !== "string" || !source.trim()) {
    throw new Error("UnsupportedFontStylesheetSource");
  }
  if (isExplicitUrlString(source)) {
    const url = new URL(source);
    if (url.protocol !== "file:") throw new Error(`RemoteFontStylesheetNotSupported:${source}`);
    return url;
  }
  return pathToFileURL(resolve(source));
}

/** One face the native stylesheet parse resolved; `source` is a file path. */
interface StylesheetFace {
  family: string;
  source: string;
  publicUrl: string;
  weight: number | [number, number] | null;
  style: string;
  unicodeRange: string;
}

/** The wire face + font byte arrays the native create calls consume. */
export interface ResolvedFaces {
  faces: Array<{
    family: string;
    publicUrl: string;
    font: number;
    faceIndex: number | null;
    weight?: number | readonly [number, number];
    style?: string;
    unicodeRange: string | null;
    sourceOrder: number | null;
  }>;
  sources: Buffer[];
}

/**
 * Resolves the face inputs of the create calls. Explicit faces carry their
 * bytes; the stylesheet lane reads the CSS here, parses it in Rust and reads
 * the font files the parse resolved. `sourceOrder` accumulates across
 * stylesheets, the js order.
 */
export async function resolveFaces(options: CreatePrecomputerOptions): Promise<ResolvedFaces> {
  const explicitFaces = Array.from(options.faces ?? []);
  const stylesheets = Array.from(options.fontStylesheets ?? []);
  if (explicitFaces.length > 0 && stylesheets.length > 0) {
    throw new Error("ConflictingBuildFontSources");
  }
  const sources: Buffer[] = [];
  if (explicitFaces.length > 0) {
    for (const face of explicitFaces) {
      sources.push(toBuffer(await readSource(face.source)));
    }
    return {
      faces: explicitFaces.map((face, index) => ({
        family: face.family,
        publicUrl: face.publicUrl,
        font: index,
        faceIndex: face.faceIndex ?? null,
        weight: face.weight,
        style: face.style,
        unicodeRange: face.unicodeRange ?? null,
        sourceOrder: null,
      })),
      sources,
    };
  }
  // Stylesheet lane: the wrapper reads the CSS, Rust parses it and resolves
  // every asset URL; `sourceOrder` accumulates across stylesheets.
  const stylesheetFaces: StylesheetFace[] = [];
  for (const stylesheet of stylesheets) {
    if (!stylesheet || typeof stylesheet !== "object") throw new Error("InvalidFontStylesheet");
    const fileUrl = stylesheetFileUrl(stylesheet.source);
    const css = await readFile(fileURLToPath(fileUrl), "utf8");
    stylesheetFaces.push(
      ...parse<StylesheetFace[]>(
        addon.parseBuildFontStylesheet(css, fileUrl.href, stylesheet.publicUrl ?? null),
      ),
    );
  }
  if (stylesheetFaces.length === 0) throw new Error("MissingBuildFontSource");
  for (const face of stylesheetFaces) {
    sources.push(toBuffer(await readFile(face.source)));
  }
  return {
    faces: stylesheetFaces.map((face, index) => ({
      family: face.family,
      publicUrl: face.publicUrl,
      font: index,
      faceIndex: null,
      weight: face.weight ?? undefined,
      style: face.style,
      unicodeRange: face.unicodeRange,
      sourceOrder: index,
    })),
    sources,
  };
}

export interface BuildFontFace {
  /** Host CSS family used for both build-time measurement and browser paint. */
  family: string;
  source: string | URL | Uint8Array | ArrayBuffer;
  publicUrl: string;
  faceIndex?: 0;
  weight?: number | readonly [number, number];
  style?: "normal" | "italic";
  unicodeRange?: string;
}

export interface BuildFontStylesheet {
  /** Local CSS file read by the Node precomputer. */
  source: string | URL;
  /** URL where the host serves that same stylesheet; relative font URLs resolve from here. */
  publicUrl?: string;
}

export interface SnapshotTypography {
  readonly fontFamilies: readonly string[];
  readonly fontSizePx: number;
  readonly lineHeightPx: number;
  readonly locale?: "zh-Hans";
  readonly fontWeight?: number;
  readonly italic?: boolean;
  readonly firstLineIndentIc?: 0;
  readonly lineLengthGridEnabled?: true;
  readonly letterSpacingPx?: 0;
  readonly fontFeatureSettings?: "normal";
  readonly fontVariationSettings?: "normal";
  readonly fontVariantNumeric?: "normal" | "lining-nums";
}

/** The normalized typography the precomputer froze at creation. */
export interface NormalizedTypography {
  readonly fontFamilies: readonly string[];
  readonly fontSizePx: number;
  readonly lineHeightPx: number;
  readonly locale: string;
  readonly fontWeight: number;
  readonly italic: boolean;
  readonly firstLineIndentIc: number;
  readonly lineLengthGridEnabled: boolean;
  readonly letterSpacingPx: number;
  readonly fontFeatureSettings: string;
  readonly fontVariationSettings: string;
  readonly fontVariantNumeric: string;
}

export interface SnapshotSemanticSpan {
  readonly start: number;
  readonly end: number;
  readonly tagName: "a" | "abbr" | "b" | "bdi" | "bdo" | "cite" | "code" | "data" |
    "del" | "dfn" | "em" | "i" | "ins" | "kbd" | "mark" | "q" | "s" | "samp" |
    "small" | "span" | "strong" | "sub" | "sup" | "time" | "u" | "var";
  readonly attributes?: Readonly<Record<string, string>> | readonly (readonly [string, string])[];
}

export interface SnapshotTextSpan {
  readonly start: number;
  readonly end: number;
  readonly fontFamilies?: readonly string[];
  readonly fontSizePx?: number;
  readonly fontWeight?: number;
  readonly italic?: boolean;
  readonly baselineShiftPx?: number;
}

export interface SnapshotInlineBox {
  readonly start: number;
  readonly end: number;
  readonly inlineStartPx?: number;
  readonly inlineEndPx?: number;
}

export interface SnapshotParagraphInput {
  key: string;
  text: string;
  maxWidthPx: number;
  semantics?: readonly SnapshotSemanticSpan[];
  /** Required with full explicit metrics for every `code` semantic range. */
  textSpans?: readonly SnapshotTextSpan[];
  /** Required even for zero edges for every `code` semantic range. */
  inlineBoxes?: readonly SnapshotInlineBox[];
  sourceBoundaries?: readonly number[];
}

export interface FontContractInput {
  key: string;
  text: string;
  semantics?: readonly SnapshotSemanticSpan[];
  textSpans?: readonly SnapshotTextSpan[];
  inlineBoxes?: readonly SnapshotInlineBox[];
  sourceBoundaries?: readonly number[];
  /** @deprecated Font evidence is width-independent; this value is ignored. */
  maxWidthPx?: number;
}

export type PreparedParagraph =
  | {
    readonly status: "prepared";
    readonly schema: 1;
    readonly layoutRevision: string;
    readonly renderRevision: string;
    readonly key: string;
    readonly sourceText: string;
    readonly sourceSha256: string;
    readonly sourceArtifactSha256: string;
    readonly semantics: readonly SnapshotSemanticSpan[];
    readonly inlineBoxes: readonly SnapshotInlineBox[];
    readonly renderTextSpans: readonly {
      readonly start: number;
      readonly end: number;
      readonly fontFamilies: readonly string[];
    }[];
    readonly typographySha256: string;
    readonly maxWidthPx: number;
    readonly typography: NormalizedTypography;
    readonly renderFontFamilies: readonly string[];
    readonly fontEvidence: unknown;
    readonly plan: unknown;
    readonly html: string;
    readonly renderArtifactSha256: string;
  }
  | {
    readonly status: "unsupported";
    readonly key: string;
    readonly issue: string;
    readonly detail?: string;
  };

export type PreparedEntry = PreparedParagraph;

export interface Precomputer {
  readonly typography: NormalizedTypography;
  readonly renderFontFamilies: readonly string[];
  prepareParagraph(input: SnapshotParagraphInput): Promise<PreparedEntry>;
  /**
   * The batch snapshot lane: every paragraph in one native call, the loop in
   * Rust. Session evidence accumulates in input order, matching the sequence
   * of individual `prepareParagraph` calls.
   */
  prepareParagraphs(inputs: readonly SnapshotParagraphInput[]): Promise<PreparedEntry[]>;
  /** Capture exact-font and server-replay evidence for runtime-only or semantic prose. */
  prepareFontContract(input: FontContractInput): Promise<PreparedEntry>;
  /**
   * The batch contract lane: every contract in one native call, the loop in
   * Rust. Entries come back in input order with the lowest failing index
   * reported as an error, matching the sequence of individual
   * `prepareFontContract` calls.
   */
  prepareFontContracts(inputs: readonly FontContractInput[]): Promise<PreparedEntry[]>;
  /**
   * The cache and submission bridge of this precomputer (ADR 0052). The
   * property is present only when the platform build carries the bridge;
   * the batch renderer and the layered cache live behind it.
   */
  readonly cache: CacheBridge;
  close(): void;
}

/**
 * The write-budget posture of a precomputer's drain queue (ADR 0052): the
 * host picks a tier by environment, the engine owns the tier-to-bytes table.
 * Every tier clears the largest single record; a submit past the budget
 * throws `CacheWriteBufferFull` until the host flushes.
 */
export type CacheWriteBudget = "tight" | "normal" | "generous";

/** Name constants of {@link CacheWriteBudget}. */
export const CacheWriteBudget = Object.freeze({
  Tight: "tight",
  Normal: "normal",
  Generous: "generous",
} as const);

const writeBudgetCodes = new Map<CacheWriteBudget, number>([
  ["tight", 0],
  ["normal", 1],
  ["generous", 2],
]);

function writeBudgetCode(value: CacheWriteBudget): number {
  const code = writeBudgetCodes.get(value);
  if (code === undefined) {
    throw new TypeError(`UnknownCacheWriteBudget:${String(value)}`);
  }
  return code;
}

let defaultCacheWriteBudget: CacheWriteBudget = CacheWriteBudget.Normal;

/**
 * Sets the process default every later `createPrecomputer` call uses when its
 * options name no tier. Precomputers already created keep theirs.
 */
export function setCacheWriteBudget(budget: CacheWriteBudget): void {
  writeBudgetCode(budget);
  defaultCacheWriteBudget = budget;
}

export interface CreatePrecomputerOptions {
  /** Normal integration: reuse the host's existing @font-face stylesheet. */
  fontStylesheets?: readonly BuildFontStylesheet[];
  /** Low-level integration for generated font systems. Mutually exclusive with fontStylesheets. */
  faces?: readonly BuildFontFace[];
  typography: SnapshotTypography;
  /**
   * The drain-queue write budget of this precomputer; defaults to the
   * process default, initially "normal".
   */
  cacheWriteBudget?: CacheWriteBudget;
}

const precomputerHandles = new WeakMap<Precomputer, string>();

/**
 * Internal: the native registry handle of a precomputer created by this
 * package, for the HTML preparer entry in `precompute-html.ts`.
 */
export function precomputerHandle(precomputer: Precomputer): string | null {
  return precomputerHandles.get(precomputer) ?? null;
}

interface PrecomputerInfo {
  typography: NormalizedTypography;
  renderFontFamilies: string[];
}

function freezeEntry(entry: PreparedEntry): PreparedEntry {
  return Object.freeze(entry);
}

/**
 * Replays the shared prepared-DOM renderer in Node to recompute the html field
 * and the renderArtifactSha256 field for one prepared entry. The options replay
 * the exact set precomputer.rs builds in render_options (precomputer.rs L305-327)
 * before handing the plan to render_prepared_paragraph_artifact_from_plan:
 * semantics, inlineBoxes, renderTextSpans and sourceText are supplied, while
 * cjkStrongSemantics and styleClassFor stay unset. The options value carries a
 * cast because the shared module declares its option types in a normalized
 * form; the runtime values entry.semantics, entry.inlineBoxes and
 * entry.renderTextSpans carry back are the raw objects the Rust renderer fed the
 * shared renderer, so the replay is byte-faithful.
 */
function computeRenderArtifact(
  entry: Extract<PreparedEntry, { readonly status: "prepared" }>,
): { html: string; renderArtifactSha256: string } {
  if (!isSharedPlanInput(entry.plan)) {
    throw new TypeError("prepareParagraph returned a prepared entry without a renderable plan");
  }
  const rendered = sharedRenderPreparedParagraphArtifact(entry.plan, entry.typography.locale, {
    sourceText: entry.sourceText,
    semantics: entry.semantics,
    renderTextSpans: entry.renderTextSpans,
    inlineBoxes: entry.inlineBoxes,
  } as NonNullable<Parameters<typeof sharedRenderPreparedParagraphArtifact>[2]>);
  return {
    html: rendered.html,
    renderArtifactSha256: createHash("sha256")
      .update(stableStringify(rendered.artifact))
      .digest("hex"),
  };
}

/**
 * Overwrites the render fields of a prepared entry with the Node-computed
 * values, then freezes the entry. Unsupported entries pass through untouched;
 * font-contract entries carry renderable capture plans and use the same fields.
 */
export function backfillRenderFields(entry: PreparedEntry): PreparedEntry {
  if (entry.status !== "prepared") {
    return freezeEntry(entry);
  }
  const { html, renderArtifactSha256 } = computeRenderArtifact(entry);
  return freezeEntry({ ...entry, html, renderArtifactSha256 });
}

/**
 * Creates a precomputer from explicit faces or a host font stylesheet. The
 * typography is normalized in Rust; every named validation error of the js
 * implementation is thrown at the same step.
 */
export async function createPrecomputer(options: CreatePrecomputerOptions): Promise<Precomputer> {
  const typographyJson = JSON.stringify(options.typography ?? {});
  // Typography validates before any font file is read, the js order; the
  // native create normalizes the same value again behind its boundary.
  addon.normalizeTypography(typographyJson);
  // The tier validates before any font IO for the same reason.
  const budgetCode = writeBudgetCode(options.cacheWriteBudget ?? defaultCacheWriteBudget);
  const { faces, sources } = await resolveFaces(options);
  const handle = addon.createPrecomputer(typographyJson, faces, sources, budgetCode);
  const info = parse<PrecomputerInfo>(addon.precomputerInfo(handle));
  const precomputer: Precomputer = {
    typography: Object.freeze(info.typography),
    renderFontFamilies: Object.freeze(info.renderFontFamilies),
    cache: createCacheBridge(handle),
    async prepareParagraph(input: SnapshotParagraphInput): Promise<PreparedEntry> {
      return backfillRenderFields(
        parse<PreparedEntry>(addon.prepareParagraph(handle, JSON.stringify(input ?? {}))),
      );
    },
    async prepareParagraphs(inputs: readonly SnapshotParagraphInput[]): Promise<PreparedEntry[]> {
      return parse<PreparedEntry[]>(
        addon.prepareParagraphs(handle, JSON.stringify(Array.from(inputs ?? []))),
      ).map(backfillRenderFields);
    },
    async prepareFontContract(input: FontContractInput): Promise<PreparedEntry> {
      return backfillRenderFields(
        parse<PreparedEntry>(addon.prepareFontContract(handle, JSON.stringify(input ?? {}))),
      );
    },
    async prepareFontContracts(
      inputs: readonly FontContractInput[],
    ): Promise<PreparedEntry[]> {
      return parse<PreparedEntry[]>(
        addon.prepareFontContracts(handle, JSON.stringify(Array.from(inputs ?? []))),
      ).map(backfillRenderFields);
    },
    close(): void {
      addon.closePrecomputer(handle);
    },
  };
  precomputerHandles.set(precomputer, handle);
  return Object.freeze(precomputer);
}

type SharedPlanInput = Parameters<typeof sharedRenderPreparedParagraph>[0];

/**
 * Narrows the public `unknown` plan input to what the shared renderer accepts.
 * The structural check stays coarse on purpose: the shared module owns plan
 * validation, and this gate only rejects values no plan form can take.
 */
function isSharedPlanInput(value: unknown): value is SharedPlanInput {
  return typeof value === "string" || (typeof value === "object" && value !== null);
}

/**
 * Widens the local typography interface to the record shape the shared
 * renderer accepts. Interfaces carry no implicit index signature, so the
 * spread produces a structurally identical anonymous type that does.
 */
function toSharedTypography(typography: SnapshotTypography): Record<string, unknown> {
  return { ...typography };
}

/**
 * Renders one prepared plan to prepared DOM. The implementation is the exact
 * browser-shared module `@tiqian/prose` ships, so server embedders and the
 * browser agree on every revision.
 */
export function renderPreparedParagraph(plan: unknown, typography: SnapshotTypography): string {
  if (!isSharedPlanInput(plan)) {
    throw new TypeError("renderPreparedParagraph expects a plan JSON string or object");
  }
  return sharedRenderPreparedParagraph(plan, toSharedTypography(typography));
}

/** The named plain-text gate of the snapshot lane. */
export function snapshotPlainTextIssue(text: string): string | null {
  return parse<string | null>(addon.snapshotPlainTextIssue(text));
}

export interface SnapshotBundle {
  readonly id: string;
  /** Backward-compatible alias of inertTemplate. */
  readonly template: string;
  /** Inert manifest and prepared DOM adopted only after live geometry validation. */
  readonly inertTemplate: string;
  /** Compact exact-font and server-replay manifest for client-side navigation fallback. */
  readonly clientTemplate: string;
  readonly initialStyle: string;
  readonly renderFontFamilies: readonly string[];
  readonly fontPreloads: readonly string[];
  readonly rootAttributes: Readonly<Partial<Record<"data-tiqian-snapshot-render-font", "true">>>;
  readonly entries: readonly {
    readonly key: string;
    readonly html: string;
  }[];
}

interface BundleOptionsJson {
  id?: string;
  paragraphSelector?: string | null;
  fontContractParagraphs?: PreparedEntry[] | null;
  snapshotTables: string;
}

function freezeBundle(bundle: SnapshotBundle): SnapshotBundle {
  return Object.freeze({
    ...bundle,
    renderFontFamilies: Object.freeze([...bundle.renderFontFamilies]),
    fontPreloads: Object.freeze([...bundle.fontPreloads]),
    rootAttributes: Object.freeze({ ...bundle.rootAttributes }),
    entries: Object.freeze(bundle.entries.map((entry) => Object.freeze({ ...entry }))),
  });
}

/** One build's snapshot tables (ADR 0052 `BundleLayering`): the shared rows
 * every article of the build shares. Absorb first, render every article,
 * then finalize; the finalized bytes are content-addressed by their sha256.
 *
 * Value styles are a TS-side concern: the shared layer
 * (`ValueStyleInterner`/`SnapshotValueStyle`) mints the `tqv-` classes and
 * the first-paint rules, so the native table carries no value-style rows.
 */
export interface SnapshotTables {
  readonly kind: "snapshot-tables";
  readonly handle: string;
  /** The build's value-style rows in first-seen order; TS-side only. */
  readonly valueStyles: ValueStyleInterner;
}

/** The finalized table file a host serves verbatim under its sha address. */
export interface FinalizedSnapshotTables {
  readonly bytes: Buffer;
  readonly sha256: string;
}

/**
 * The data phase of one bundle (ADR 0052 schema 2): rendered bodies plus the
 * table indexes the classes used. Hold this until every article of the build
 * rendered and the table froze, then assemble.
 */
export interface SnapshotBundleData {
  readonly kind: "snapshot-bundle-data";
  /** The wire form the native assembly reads. */
  readonly json: string;
  /** The template id the first-paint rules scope to. */
  readonly id: string;
  /** Value-style rows this bundle's classes used, in first-mint order. */
  readonly usedValueStyleIndexes: readonly number[];
}

/** Creates the empty, unfrozen table set of one build. */
export function createSnapshotTables(): SnapshotTables {
  return {
    kind: "snapshot-tables",
    handle: addon.createSnapshotTables(),
    valueStyles: new ValueStyleInterner(),
  };
}

/** Restores a previous build's frozen table so a rebuild extends the union. */
export function restoreSnapshotTables(bytes: Buffer): SnapshotTables {
  return {
    kind: "snapshot-tables",
    handle: addon.restoreSnapshotTables(bytes),
    valueStyles: new ValueStyleInterner(),
  };
}

/**
 * Absorbs one batch of prepared entries into the table; returns the absorbed
 * entry count. Absorb and data-phase calls share one mutable table and may
 * interleave in any order; both throw once the table froze.
 */
export function absorbSnapshotTables(
  tables: SnapshotTables,
  prepared: readonly PreparedEntry[],
): number {
  return addon.absorbSnapshotTables(tables.handle, JSON.stringify(Array.from(prepared ?? [])));
}

/**
 * Absorbs table-scoped render metadata; value styles append to the TS-side
 * interner in first-seen order, and re-absorbing an existing declaration
 * keeps its index. The native table rows stay untouched, so the table hash
 * does not change.
 */
export function absorbSnapshotTablesMetadata(
  tables: SnapshotTables,
  metadata: { readonly valueStyles: readonly string[] },
): void {
  const rows = (metadata as { valueStyles?: unknown } | undefined)?.valueStyles;
  if (!Array.isArray(rows)) return;
  for (const row of rows) {
    if (typeof row !== "string") throw new Error("SnapshotTableValueStylesInvalid");
    tables.valueStyles.intern(row);
  }
}

/**
 * Freezes the rows and returns `{bytes, sha256}`; hosts serve the binary
 * verbatim under the sha address. The handle stays usable for assembly.
 */
export function finalizeSnapshotTables(tables: SnapshotTables): FinalizedSnapshotTables {
  const file = addon.finalizeSnapshotTables(tables.handle);
  return Object.freeze({ bytes: file.bytes, sha256: file.sha256 });
}

/** Drops the table set once every bundle assembled. */
export function closeSnapshotTables(tables: SnapshotTables): void {
  addon.closeSnapshotTables(tables.handle);
}

const SNAPSHOT_SCHEMA = Revision.SNAPSHOT_SCHEMA;
const LAYOUT_REVISION = Revision.LAYOUT_REVISION;
const RENDER_REVISION = Revision.RENDER_REVISION;
const DEFAULT_LOCALE = "zh-Hans";
/** `PLAIN_PARAGRAPH_SELECTOR`: canonical plain paragraphs of a snapshot root. */
const PLAIN_PARAGRAPH_SELECTOR = ":is(p, li)[data-tq-snapshot-key]";
/** `RUNTIME_PARAGRAPH_SELECTOR`: every live paragraph of a semantic root. */
const RUNTIME_PARAGRAPH_SELECTOR = ":is(p, li):not([data-tiqian-skip])";

/** Options of the shared artifact renderer. */
type SharedArtifactOptions = NonNullable<
  Parameters<typeof sharedRenderPreparedParagraphArtifact>[2]
>;

/** The ts entry of one bundle data phase. */
interface BundleRenderOptions {
  id: string;
  paragraphSelector?: string;
  fontContractParagraphs?: readonly PreparedEntry[];
  snapshotTables: SnapshotTables;
}

/** `preparedLocale`: a string typography is its locale, an object carries it. */
function preparedLocale(typography: unknown): string {
  if (typeof typography === "string") return typography;
  if (typography !== null && typeof typography === "object") {
    const locale = (typography as { locale?: unknown }).locale;
    if (typeof locale === "string") return locale;
    if (typeof locale === "number") return String(locale);
    if (typeof locale === "boolean") return String(locale);
  }
  return DEFAULT_LOCALE;
}

/** The corpus gates of the data phase, in the order the Rust port ran them. */
function bundleCorpus(
  entries: readonly PreparedEntry[],
  fontContractEntries: readonly PreparedEntry[],
): PreparedEntry[] {
  if (entries.length === 0) throw new Error("MissingPreparedParagraphs");
  const corpus = [...entries, ...fontContractEntries];
  if (corpus.some((entry) => (entry as { status?: unknown })?.status !== "prepared")) {
    throw new Error("SnapshotTemplateContainsUnsupportedParagraph");
  }
  if (corpus.some((entry) => {
    const row = entry as Record<string, unknown>;
    return row.schema !== SNAPSHOT_SCHEMA ||
      row.layoutRevision !== LAYOUT_REVISION ||
      row.renderRevision !== RENDER_REVISION ||
      typeof row.renderArtifactSha256 !== "string";
  })) {
    throw new Error("SnapshotTemplateContainsStalePreparedParagraph");
  }
  const seen = new Set<string>();
  for (const entry of corpus) {
    const key = (entry as { key?: unknown }).key ?? null;
    const rendered = stableStringify(key);
    if (seen.has(rendered)) throw new Error("DuplicateSnapshotKey");
    seen.add(rendered);
  }
  return corpus;
}

/** The exact render font families every corpus entry must share. */
function renderFontFamiliesOf(entries: readonly PreparedEntry[]): readonly string[] {
  const families = (entries[0] as { renderFontFamilies?: unknown } | undefined)?.renderFontFamilies;
  if (!Array.isArray(families) || families.length === 0) {
    throw new Error("MissingExactRenderFontFamilies");
  }
  for (const family of families) {
    if (typeof family !== "string" || family.trim().length === 0) {
      throw new Error("MissingExactRenderFontFamilies");
    }
  }
  return families as readonly string[];
}

/**
 * Renders one prepared entry with the shared renderer and hashes its artifact
 * tree with the same stable encoding the Rust renderer used, so the entry
 * keeps its byte identity when the render loop moves here.
 */
function renderBundleEntry(
  entry: PreparedEntry,
  styleClassFor: (declaration: string) => string,
): Record<string, unknown> {
  const row = entry as Record<string, unknown>;
  const plan = row.plan;
  if (plan === undefined || plan === null) throw new Error("InvalidPreparedParagraphGeometry");
  const planText = typeof plan === "string" ? plan : JSON.stringify(plan);
  const rendered = sharedRenderPreparedParagraphArtifact(
    planText,
    preparedLocale(row.typography),
    {
      semantics: row.semantics,
      inlineBoxes: row.inlineBoxes,
      renderTextSpans: row.renderTextSpans,
      sourceText: typeof row.sourceText === "string" ? row.sourceText : undefined,
      styleClassFor,
    } as SharedArtifactOptions,
  );
  return {
    ...row,
    html: rendered.html,
    renderArtifactSha256: sha256Hex(stableStringify(rendered.artifact)),
  };
}

/**
 * The data phase over one entry list: gates, per-entry render with the shared
 * renderer, and the class indexes this bundle minted. First-paint rules are
 * appended at assembly from these indexes.
 */
function renderBundleData(
  preparedParagraphs: readonly PreparedEntry[],
  options: BundleRenderOptions,
  supportedParagraphSelector: string,
): SnapshotBundleData {
  const entries = Array.from(preparedParagraphs ?? []);
  const fontContractEntries = Array.from(options.fontContractParagraphs ?? []);
  const corpus = bundleCorpus(entries, fontContractEntries);
  const families = renderFontFamiliesOf(entries);
  const familySignature = stableStringify(families);
  for (const entry of corpus) {
    const entryFamilies = (entry as { renderFontFamilies?: unknown }).renderFontFamilies;
    const signature = entryFamilies === undefined ? "" : stableStringify(entryFamilies);
    if (signature !== familySignature) throw new Error("SnapshotRenderFontFamilyConflict");
  }
  const id = typeof options.id === "string" ? options.id.trim() : "";
  if (id.length === 0) throw new Error("MissingSnapshotTemplateId");
  if (!/^[A-Za-z][A-Za-z0-9_-]*$/u.test(id)) throw new Error("InvalidSnapshotTemplateId");
  const paragraphSelector = typeof options.paragraphSelector === "string"
    ? options.paragraphSelector
    : supportedParagraphSelector;
  if (paragraphSelector !== supportedParagraphSelector) {
    throw new Error("UnsupportedSnapshotParagraphSelector");
  }
  const interner = options.snapshotTables.valueStyles;
  const usedValueStyleIndexes: number[] = [];
  const styleClassFor = (declaration: string): string => {
    const index = interner.intern(declaration);
    if (!usedValueStyleIndexes.includes(index)) usedValueStyleIndexes.push(index);
    return SnapshotValueStyle.snapshotValueStyleClass(index);
  };
  const renderedEntries = entries.map((entry) => renderBundleEntry(entry, styleClassFor));
  return Object.freeze({
    kind: "snapshot-bundle-data",
    id,
    usedValueStyleIndexes: Object.freeze([...usedValueStyleIndexes]),
    json: JSON.stringify({
      id,
      paragraphSelector,
      renderFontFamilies: families,
      renderedEntries,
      fontContractEntries,
    }),
  });
}

/**
 * The data phase for plain snapshot bundles: renders the bodies with the
 * shared TS renderer and mints `tqv-` classes into the build's TS interner.
 */
export function renderSnapshotBundleData(
  preparedParagraphs: readonly PreparedEntry[],
  options: BundleRenderOptions,
): SnapshotBundleData {
  return renderBundleData(preparedParagraphs, options, PLAIN_PARAGRAPH_SELECTOR);
}

/** The data phase for font-contract bundles. */
export function renderFontContractBundleData(
  preparedParagraphs: readonly PreparedEntry[],
  options: BundleRenderOptions,
): SnapshotBundleData {
  return renderBundleData(preparedParagraphs, options, RUNTIME_PARAGRAPH_SELECTOR);
}

function assembleWireValues(data: SnapshotBundleData, tables: SnapshotTables): [string, string] {
  return [
    data.json,
    JSON.stringify({ snapshotTables: tables.handle } satisfies BundleOptionsJson),
  ];
}

/** `escapeAttribute`: ampersand, quote, and left angle, in that order. */
function escapeBundleAttribute(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;");
}

/**
 * The first-paint rules of the value-style classes this bundle used, in
 * first-mint order. The native assembly owns the templates and the manifest;
 * the declarations live in the shared layer, so the rules append here in the
 * byte form the Rust assembly emitted.
 */
function valueStyleRules(data: SnapshotBundleData, tables: SnapshotTables): string {
  let rules = "";
  for (const index of data.usedValueStyleIndexes) {
    const declaration = tables.valueStyles.at(index);
    if (typeof declaration !== "string") throw new Error("SnapshotTableValueStyleMissing");
    rules += `tiqian-prose[snapshot-ref="${escapeBundleAttribute(data.id)}"] ` +
      `[data-tq-rendered="true"] .${SnapshotValueStyle.snapshotValueStyleClass(index)}{${declaration}}`;
  }
  return rules;
}

/**
 * The assembly phase: compacts the manifest against the frozen table, builds
 * the templates and the first-paint style. Requires finalizeSnapshotTables.
 */
export function assembleSnapshotBundle(
  data: SnapshotBundleData,
  tables: SnapshotTables,
): SnapshotBundle {
  const [dataJson, optionsJson] = assembleWireValues(data, tables);
  const bundle = parse<SnapshotBundle>(
    addon.assembleSnapshotBundle(dataJson, optionsJson, SHARED_RUNTIME_STYLE),
  );
  return freezeBundle({ ...bundle, initialStyle: bundle.initialStyle + valueStyleRules(data, tables) });
}

/** The assembly phase for font-contract bundles. */
export function assembleFontContractBundle(
  data: SnapshotBundleData,
  tables: SnapshotTables,
): SnapshotBundle {
  const [dataJson, optionsJson] = assembleWireValues(data, tables);
  return freezeBundle(
    parse<SnapshotBundle>(
      addon.assembleFontContractBundle(dataJson, optionsJson, SHARED_RUNTIME_STYLE),
    ),
  );
}
