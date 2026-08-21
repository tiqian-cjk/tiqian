// Loads the platform-specific build of the addon on the current system.
// The four platforms are the first-version targets of ADR 0050. The debug
// path serves local builds placed by `neon dist` (`bun run debug:native`);
// when it is absent the proxy falls back to the installed platform package.

import { createRequire } from "node:module";
import { currentPlatform, proxy } from "@neon-rs/load";

// `proxy` needs synchronous CommonJS requires for the platform packages and
// the local `.node` file, so this ESM module carries its own require.
const require = createRequire(import.meta.url);

/** One face entry of the `createFontSession` wire protocol. */
export interface NativeFaceSpec {
  family: string;
  publicUrl: string;
  /** Index into the `sources` array passed alongside the face list. */
  font: number;
  faceIndex: number | null;
  weight?: number | readonly [number, number];
  style?: string;
  unicodeRange: string | null;
  sourceOrder: number | null;
}

/** Session options of the `createFontSession` wire protocol. */
export interface NativeSessionOptions {
  sessionPrefix: string | null;
  baseFeatures: string[] | null;
}

/** Boundary style of the `sourceBoundaries` wire protocol. */
export interface NativeBoundaryStyle {
  fontFamilies: string[];
  fontSizePx: number;
  fontWeight: number;
  italic: boolean;
  baselineShiftPx?: number | null;
}

/** Boundary span of the `sourceBoundaries` wire protocol. */
export interface NativeBoundarySpan {
  start: number;
  end: number;
  style: NativeBoundaryStyle;
}

/** One styled span of the `precomputeParagraph` protocol. */
export interface NativeTextSpan {
  start: number;
  end: number;
  families: string[];
  fontSizePx: number;
  fontWeight: number;
  italic: boolean;
  baselineShiftPx: number;
}

/** One inline box of the `precomputeParagraph` protocol. */
export interface NativeInlineBox {
  start: number;
  end: number;
  inlineStartPx: number;
  inlineEndPx: number;
  /** Omitted boxes use the `Narrow` default of the protocol. */
  outerSpacing?: "Narrow" | "Source";
}

/** One line-break policy span of the `precomputeParagraph` protocol. */
export interface NativeLineBreakSpan {
  start: number;
  end: number;
  policy: "ProgressiveTechnical";
}

/**
 * The native surface exported by `tiqian-precompute-neon`. Structured results
 * arrive as JSON strings produced by the shared Rust emitters; flat arguments
 * mirror the backend protocol used by the Kotlin/JS oracle.
 */
export interface NativeAddon {
  backendRevision(): string;
  harfbuzzVersion(): string;
  createFontSession(
    faces: NativeFaceSpec[],
    sources: Buffer[],
    options: NativeSessionOptions,
  ): string;
  sessionFaces(sessionId: string): string;
  shape(
    sessionId: string,
    displayText: string,
    families: string,
    fontSize: number,
    fontWeight: number,
    italic: boolean,
    locale: string,
    role: string | null,
    sourceText: string | null,
  ): string;
  metrics(
    sessionId: string,
    families: string,
    fontSize: number,
    fontWeight: number,
    italic: boolean,
    role: string | null,
    faceSelectionText: string | null,
  ): string;
  renderFamilies(sessionId: string, requestedFamilies: string[]): string;
  sourceBoundaries(
    sessionId: string,
    text: string,
    baseStyle: NativeBoundaryStyle,
    textSpans: NativeBoundarySpan[],
  ): string;
  /**
   * The structured form of the js facade call: arrays and span objects arrive
   * as themselves. Returns the plan JSON. An addon built without the engine
   * archive throws `EngineNotLinked`.
   */
  precomputeParagraph(
    sessionId: string,
    text: string,
    maxWidthPx: number,
    families: string[],
    fontSizePx: number,
    lineHeightPx: number,
    locale: string,
    fontWeight: number,
    italic: boolean,
    firstLineIndentIc: number,
    lineLengthGridEnabled: boolean,
    sourceBoundaries: number[],
    textSpans: NativeTextSpan[],
    inlineBoxes: NativeInlineBox[],
    lineBreakSpans: NativeLineBreakSpan[],
  ): string;
  beginCapture(sessionId: string): void;
  captureEvidence(sessionId: string): string;
  closeSession(sessionId: string): void;
  /**
   * The precompute lane (ADR 0050). Structured values cross as JSON strings;
   * every object shape belongs to the wrapper entries in `precompute.ts` and
   * `precompute-html.ts`. Handles address the process-wide registries.
   */
  normalizeTypography(typographyJson: string): string;
  createPrecomputer(typographyJson: string, faces: NativeFaceSpec[], sources: Buffer[]): string;
  precomputerInfo(handle: string): string;
  prepareParagraph(handle: string, inputJson: string): string;
  /** The batch snapshot lane; the paragraph loop stays inside Rust. */
  prepareParagraphs(handle: string, inputsJson: string): string;
  prepareFontContract(handle: string, inputJson: string): string;
  /** The batch contract lane; the loop stays inside Rust. */
  prepareFontContracts(handle: string, inputsJson: string): string;
  closePrecomputer(handle: string): void;
  htmlPreparerInfo(handle: string): string;
  createHtmlPreparer(
    precomputerHandle: string | null,
    typographyJson: string,
    faces: NativeFaceSpec[],
    sources: Buffer[],
    paragraphSelector: string | null,
    skippedAncestorSelector: string | null,
    sharedRuntimeStyle: string,
  ): string;
  /** The whole document in one call; the paragraph loop stays inside Rust. */
  prepareHtml(handle: string, html: string, optionsJson: string): string;
  closeHtmlPreparer(handle: string): void;
  renderSnapshotBundle(
    preparedParagraphsJson: string,
    optionsJson: string,
    sharedRuntimeStyle: string,
  ): string;
  renderFontContractBundle(
    preparedParagraphsJson: string,
    optionsJson: string,
    sharedRuntimeStyle: string,
  ): string;
  renderSnapshotTemplate(
    preparedParagraphsJson: string,
    optionsJson: string,
    sharedRuntimeStyle: string,
  ): string;
  snapshotPlainTextIssue(text: string): string;
  findHtmlOpeningTags(html: string, tagNamesJson: string): string;
  injectHtmlAttributes(html: string, insertionsJson: string): string;
  snapshotServerAssets(bundleJson: string): string;
  renderSnapshotServerAssets(assetsJson: string): string;
  parseBuildFontStylesheet(css: string, sourceFileUrl: string, publicUrl: string | null): string;
  /**
   * The cache and submission bridge (ADR 0052). Binary buffers in and out;
   * the packers and readers live in `cache.ts`, no JSON crosses.
   */
  cacheContext(handle: string): string;
  cacheSubmitHashes(handle: string, hashes: Buffer): Buffer;
  cacheSubmitContents(handle: string, submissions: Buffer): Buffer;
  cachePrefillContents(handle: string, submissions: Buffer): number;
  cachePrefetch(handle: string, records: Buffer): number;
  cacheDrainWrites(handle: string): Buffer;
  cacheEvictExcept(handle: string, keys: Buffer): void;
}

export const addon: NativeAddon = proxy({
  platforms: {
    "win32-x64-msvc": () => require("@tiqian/precompute-win32-x64-msvc"),
    "darwin-arm64": () => require("@tiqian/precompute-darwin-arm64"),
    "linux-x64-gnu": () => require("@tiqian/precompute-linux-x64-gnu"),
    "linux-arm64-gnu": () => require("@tiqian/precompute-linux-arm64-gnu"),
  },
  debug: () => require(`../platforms/${currentPlatform()}/index.node`),
});
