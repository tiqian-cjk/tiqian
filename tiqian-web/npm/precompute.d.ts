export interface BuildFontFace {
  family: string;
  source: string | URL | Uint8Array | ArrayBuffer;
  publicUrl: string;
  faceIndex?: 0;
  weight?: number | readonly [number, number];
  style?: "normal" | "italic";
  unicodeRange?: string;
}

export interface SnapshotTypography {
  fontFamilies: readonly string[];
  fontSizePx: number;
  lineHeightPx: number;
  locale?: "zh-Hans";
  fontWeight?: number;
  italic?: boolean;
  firstLineIndentIc?: 0;
  lineLengthGridEnabled?: true;
  letterSpacingPx?: 0;
  fontFeatureSettings?: "normal";
  fontVariationSettings?: "normal";
  fontVariantNumeric?: "normal" | "lining-nums";
}

export interface PreparedParagraph {
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
  readonly typographySha256: string;
  readonly maxWidthPx: number;
  readonly typography: SnapshotTypography;
  readonly renderFontFamilies: readonly string[];
  readonly fontEvidence: unknown;
  readonly plan: unknown;
  readonly html: string;
  readonly renderArtifactSha256: string;
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

export interface UnsupportedPreparedParagraph {
  readonly status: "unsupported";
  readonly key: string;
  readonly issue: string;
  readonly detail?: string;
}

export interface Precomputer {
  readonly typography: SnapshotTypography;
  readonly renderFontFamilies: readonly string[];
  prepareParagraph(input: SnapshotParagraphInput): Promise<PreparedParagraph | UnsupportedPreparedParagraph>;
  /** Capture exact-font and server-replay evidence for runtime-only or semantic prose. */
  prepareFontContract(input: {
    key: string;
    text: string;
    maxWidthPx: number;
  }): Promise<PreparedParagraph | UnsupportedPreparedParagraph>;
  close(): void;
}

export declare function createPrecomputer(options: {
  faces: readonly BuildFontFace[];
  typography: SnapshotTypography;
}): Promise<Precomputer>;

export declare function renderPreparedParagraph(plan: unknown, typography: SnapshotTypography): string;
export declare function snapshotPlainTextIssue(text: string): string | null;
export interface SnapshotBundle {
  readonly id: string;
  /** Manifest-only template for HTML that already contains `entries`. */
  readonly template: string;
  /** Inert manifest and prepared DOM adopted only after live geometry validation. */
  readonly inertTemplate: string;
  /** Compact exact-font and server-replay manifest for client-side navigation fallback. */
  readonly clientTemplate: string;
  readonly initialStyle: string;
  readonly renderFontFamilies: readonly string[];
  readonly fontPreloads: readonly string[];
  readonly rootAttributes: Readonly<Record<"data-tiqian-exact-render-font", "true">>;
  readonly entries: readonly {
    readonly key: string;
    readonly html: string;
  }[];
}
export declare function renderSnapshotBundle(
  preparedParagraphs: readonly PreparedParagraph[],
  options: {
    id: string;
    paragraphSelector?: "p[data-tq-snapshot-key]";
    fontContractParagraphs?: readonly PreparedParagraph[];
  },
): SnapshotBundle;
export declare function renderSnapshotTemplate(
  preparedParagraphs: readonly PreparedParagraph[],
  options: {
    id: string;
    paragraphSelector?: "p[data-tq-snapshot-key]";
    fontContractParagraphs?: readonly PreparedParagraph[];
  },
): string;
