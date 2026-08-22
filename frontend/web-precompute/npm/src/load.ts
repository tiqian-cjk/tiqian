// Loads the platform-specific build of the addon on the current system.
// The four platforms are the first-version targets of ADR 0050. The debug
// path serves local builds placed by `neon dist` (`bun run debug:native`);
// when it is absent the proxy falls back to the installed platform package.

import { readFileSync } from "node:fs";
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
  createPrecomputer(
    typographyJson: string,
    faces: NativeFaceSpec[],
    sources: Buffer[],
    budgetCode: number,
  ): string;
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
  /**
   * The whole document in one call; the paragraph loop stays inside Rust.
   * Returns the result json plus the station-table file the emitted manifest
   * pins (`tablesBytes`/`tablesSha256`, or null/undefined without one).
   */
  prepareHtml(
    handle: string,
    html: string,
    optionsJson: string,
  ): { result: string; tablesBytes: Buffer | null; tablesSha256: string | undefined };
  closeHtmlPreparer(handle: string): void;
  /** The split render of ADR 0052 schema 2: data phase, then assembly. */
  renderSnapshotBundleData(
    preparedParagraphsJson: string,
    optionsJson: string,
    sharedRuntimeStyle: string,
  ): string;
  renderFontContractBundleData(
    preparedParagraphsJson: string,
    optionsJson: string,
    sharedRuntimeStyle: string,
  ): string;
  assembleSnapshotBundle(
    dataJson: string,
    optionsJson: string,
    sharedRuntimeStyle: string,
  ): string;
  assembleFontContractBundle(
    dataJson: string,
    optionsJson: string,
    sharedRuntimeStyle: string,
  ): string;
  /** The snapshot-tables lane of one build (ADR 0052 `BundleLayering`). */
  createSnapshotTables(): string;
  restoreSnapshotTables(bytes: Buffer): string;
  absorbSnapshotTables(handle: string, preparedJson: string): number;
  absorbSnapshotTablesMetadata(handle: string, metadataJson: string): void;
  finalizeSnapshotTables(handle: string): { bytes: Buffer; sha256: string };
  closeSnapshotTables(handle: string): void;
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

// The platform packages resolve under the scope of this package's own name,
// so a snapshot publication under a different scope loads without a source
// patch (GitHub Packages requires the npm scope to equal the repository
// owner; the snapshot workflow swaps the manifests temporarily).
const manifestUrl = new URL("../package.json", import.meta.url);
const manifest = JSON.parse(readFileSync(manifestUrl, "utf8")) as { name?: unknown };
const ownName = typeof manifest.name === "string" ? manifest.name : "";
const slash = ownName.indexOf("/");
const ownScope = ownName.startsWith("@") && slash > 0 ? ownName.slice(0, slash) : null;

const platformPackage = (platform: string): string => {
  if (ownScope === null) {
    throw new Error("PlatformPackageScopeMissing");
  }
  return `${ownScope}/precompute-${platform}`;
};

export const addon: NativeAddon = proxy({
  platforms: {
    "win32-x64-msvc": () => require(platformPackage("win32-x64-msvc")),
    "darwin-arm64": () => require(platformPackage("darwin-arm64")),
    "linux-x64-gnu": () => require(platformPackage("linux-x64-gnu")),
    "linux-arm64-gnu": () => require(platformPackage("linux-arm64-gnu")),
  },
  debug: () => require(`../platforms/${currentPlatform()}/index.node`),
});
