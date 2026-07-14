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
}

export interface PreparedParagraph {
  readonly status: "prepared";
  readonly schema: 1;
  readonly layoutRevision: string;
  readonly renderRevision: string;
  readonly key: string;
  readonly sourceSha256: string;
  readonly typographySha256: string;
  readonly maxWidthPx: number;
  readonly typography: SnapshotTypography;
  readonly renderFontFamilies: readonly string[];
  readonly fontEvidence: unknown;
  readonly plan: unknown;
  readonly html: string;
  readonly renderArtifactSha256: string;
}

export interface UnsupportedPreparedParagraph {
  readonly status: "unsupported";
  readonly key: string;
  readonly issue: string;
}

export interface Precomputer {
  readonly typography: SnapshotTypography;
  readonly renderFontFamilies: readonly string[];
  prepareParagraph(input: {
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
  /** Compact exact-font manifest for client-side navigation fallback. */
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
  options: { id: string; paragraphSelector?: "p[data-tq-snapshot-key]" },
): SnapshotBundle;
export declare function renderSnapshotTemplate(
  preparedParagraphs: readonly PreparedParagraph[],
  options: { id: string; paragraphSelector?: "p[data-tq-snapshot-key]" },
): string;
