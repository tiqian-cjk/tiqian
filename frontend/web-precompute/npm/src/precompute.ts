// The precompute entry over the native addon (ADR 0050). The exported
// surface matches the former `@tiqian/prose/precompute` module; every
// computation runs in Rust behind registry handles, and this file owns the
// object shapes the js API promises. File reading and URL resolution stay
// here: the crate never touches the filesystem.

import { readFileSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { addon } from "./load.js";
import { createCacheBridge, type CacheBridge } from "./cache.js";
import { renderPreparedParagraph as sharedRenderPreparedParagraph } from "../shared/prepared-dom.js";

const SHARED_RUNTIME_STYLE = readFileSync(
  new URL("../shared/styles.css", import.meta.url),
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
      return freezeEntry(
        parse<PreparedEntry>(addon.prepareParagraph(handle, JSON.stringify(input ?? {}))),
      );
    },
    async prepareParagraphs(inputs: readonly SnapshotParagraphInput[]): Promise<PreparedEntry[]> {
      return parse<PreparedEntry[]>(
        addon.prepareParagraphs(handle, JSON.stringify(Array.from(inputs ?? []))),
      ).map(freezeEntry);
    },
    async prepareFontContract(input: FontContractInput): Promise<PreparedEntry> {
      return freezeEntry(
        parse<PreparedEntry>(addon.prepareFontContract(handle, JSON.stringify(input ?? {}))),
      );
    },
    async prepareFontContracts(
      inputs: readonly FontContractInput[],
    ): Promise<PreparedEntry[]> {
      return parse<PreparedEntry[]>(
        addon.prepareFontContracts(handle, JSON.stringify(Array.from(inputs ?? []))),
      ).map(freezeEntry);
    },
    close(): void {
      addon.closePrecomputer(handle);
    },
  };
  precomputerHandles.set(precomputer, handle);
  return Object.freeze(precomputer);
}

/**
 * Renders one prepared plan to prepared DOM. The implementation is the exact
 * browser-shared module `@tiqian/prose` ships, so server embedders and the
 * browser agree on every revision.
 */
export function renderPreparedParagraph(plan: unknown, typography: SnapshotTypography): string {
  return sharedRenderPreparedParagraph(plan, typography);
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
  readonly rootAttributes: Readonly<Partial<Record<"data-tiqian-exact-render-font", "true">>>;
  readonly entries: readonly {
    readonly key: string;
    readonly html: string;
  }[];
}

interface BundleOptionsJson {
  id?: string;
  paragraphSelector?: string | null;
  fontContractParagraphs?: PreparedEntry[] | null;
}

function bundleWireValues(
  preparedParagraphs: readonly PreparedEntry[],
  options: { id: string; paragraphSelector?: string; fontContractParagraphs?: readonly PreparedEntry[] },
): [string, string] {
  return [
    JSON.stringify(Array.from(preparedParagraphs ?? [])),
    JSON.stringify({
      id: options.id,
      paragraphSelector: options.paragraphSelector ?? null,
      fontContractParagraphs: options.fontContractParagraphs
        ? Array.from(options.fontContractParagraphs)
        : null,
    } satisfies BundleOptionsJson),
  ];
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

/**
 * Produces an inert prepared-DOM template plus the compact manifests used by
 * server and client-navigation adapters. Responsive SSR should inject
 * `inertTemplate` without replacing the keyed source paragraphs; the custom
 * element adopts it only after validating live geometry and font evidence.
 */
export function renderSnapshotBundle(
  preparedParagraphs: readonly PreparedEntry[],
  options: {
    id: string;
    paragraphSelector?: ":is(p, li)[data-tq-snapshot-key]";
    fontContractParagraphs?: readonly PreparedEntry[];
  },
): SnapshotBundle {
  const [preparedJson, optionsJson] = bundleWireValues(preparedParagraphs, options);
  return freezeBundle(
    parse<SnapshotBundle>(addon.renderSnapshotBundle(preparedJson, optionsJson, SHARED_RUNTIME_STYLE)),
  );
}

/**
 * Build a compact exact-font contract for roots that keep semantic source DOM
 * and perform all paragraph layout in the browser.
 */
export function renderFontContractBundle(
  preparedParagraphs: readonly PreparedEntry[],
  options: {
    id: string;
    paragraphSelector?: ":is(p, li):not([data-tiqian-skip])";
    fontContractParagraphs?: readonly PreparedEntry[];
  },
): SnapshotBundle {
  const [preparedJson, optionsJson] = bundleWireValues(preparedParagraphs, options);
  return freezeBundle(
    parse<SnapshotBundle>(
      addon.renderFontContractBundle(preparedJson, optionsJson, SHARED_RUNTIME_STYLE),
    ),
  );
}

export function renderSnapshotTemplate(
  preparedParagraphs: readonly PreparedEntry[],
  options: {
    id: string;
    paragraphSelector?: ":is(p, li)[data-tq-snapshot-key]";
    fontContractParagraphs?: readonly PreparedEntry[];
  },
): string {
  const [preparedJson, optionsJson] = bundleWireValues(preparedParagraphs, options);
  return addon.renderSnapshotTemplate(preparedJson, optionsJson, SHARED_RUNTIME_STYLE);
}
