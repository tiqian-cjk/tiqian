// The HTML preparer entry over the native addon (ADR 0050). The exported
// surface matches the former `@tiqian/prose/precompute-html` module; the
// whole document is prepared in one native call with the paragraph loop in
// Rust. The DOM projection callback needs a host DOM, so this lane rejects
// it by name.

import { readFileSync } from "node:fs";

import { addon } from "./load.js";
import {
  precomputerHandle,
  resolveFaces,
  type BuildFontFace,
  type BuildFontStylesheet,
  type NormalizedTypography,
  type Precomputer,
  type ResolvedFaces,
  type SnapshotBundle,
  type SnapshotTypography,
} from "./precompute.js";

const SHARED_RUNTIME_STYLE = readFileSync(
  new URL("../shared/styles.css", import.meta.url),
  "utf8",
);

/**
 * Parses a JSON string produced by the shared Rust emitters; parsing happens
 * only at this boundary.
 */
function parse<T>(json: string): T {
  return JSON.parse(json) as T;
}

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

/** The station-table file one `prepare` call emitted (ADR 0052 schema 2). */
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
  readonly snapshot?: { readonly maxWidthPx: number };
}

export interface HtmlPreparer {
  readonly typography: NormalizedTypography;
  /** Prepares the whole document in one native call. */
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
} & (
  | {
    /** Reuse an existing precomputer instead of opening another exact-font session. */
    readonly precomputer: Precomputer;
    readonly fontStylesheets?: never;
    readonly faces?: never;
    readonly typography?: never;
  }
  | {
    readonly precomputer?: undefined;
    readonly fontStylesheets?: readonly BuildFontStylesheet[];
    readonly faces?: readonly BuildFontFace[];
    readonly typography: SnapshotTypography;
  }
);

export interface HtmlOpeningTag {
  readonly end: number;
  readonly source: string;
  readonly tagName: string;
}

/**
 * Locates source opening tags without serializing the host's HTML; the scan
 * runs in Rust on UTF-16 code units and skips raw-text containers and inert
 * templates so a literal `<p>` example never receives a live snapshot key.
 */
export function findHtmlOpeningTags(
  html: string,
  tagNames: readonly string[] = ["p", "li"],
): readonly HtmlOpeningTag[] {
  return parse<HtmlOpeningTag[]>(
    addon.findHtmlOpeningTags(html, JSON.stringify(Array.from(tagNames ?? []))),
  );
}

/** Inserts attribute strings at the given offsets, highest offset first. */
export function injectHtmlAttributes(
  html: string,
  insertions: readonly { readonly offset: number; readonly attribute: string }[],
): string {
  return addon.injectHtmlAttributes(html, JSON.stringify(Array.from(insertions ?? [])));
}

/** The payload a server template inlines. */
export function snapshotServerAssets(bundle: SnapshotBundle | null): SnapshotServerAssets | null {
  if (!bundle) return null;
  return parse<SnapshotServerAssets>(addon.snapshotServerAssets(JSON.stringify(bundle)));
}

/** Preload links, the first paint style and the inert template, concatenated. */
export function renderSnapshotServerAssets(assets: SnapshotServerAssets | null): string {
  if (!assets) return "";
  return addon.renderSnapshotServerAssets(JSON.stringify(assets));
}

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
  const shared = options.precomputer ? precomputerHandle(options.precomputer) : null;
  if (options.precomputer && !shared) {
    throw new Error("ForeignPrecomputer");
  }
  let typographyJson = "null";
  let faces: ResolvedFaces["faces"] = [];
  let sources: Buffer[] = [];
  if (!options.precomputer) {
    typographyJson = JSON.stringify(options.typography ?? {});
    // Typography validates before any font file is read, the js order; the
    // native create normalizes the same value again behind its boundary.
    addon.normalizeTypography(typographyJson);
    const resolved = await resolveFaces({
      typography: options.typography,
      faces: options.faces,
      fontStylesheets: options.fontStylesheets,
    });
    faces = resolved.faces;
    sources = resolved.sources;
  }
  const handle = addon.createHtmlPreparer(
    shared,
    typographyJson,
    faces,
    sources,
    options.paragraphSelector ?? null,
    options.skippedAncestorSelector ?? null,
    SHARED_RUNTIME_STYLE,
  );
  const info = parse<{ typography: NormalizedTypography }>(addon.htmlPreparerInfo(handle));
  return Object.freeze({
    typography: Object.freeze(info.typography),
    async prepare(html: string, prepareOptions: HtmlPrepareOptions = {}): Promise<PreparedHtml> {
      const call = addon.prepareHtml(
        handle,
        String(html),
        JSON.stringify(prepareOptions ?? {}),
      );
      const prepared = parse<PreparedHtml>(call.result);
      return Object.freeze({
        ...prepared,
        tables: call.tablesBytes && call.tablesSha256
          ? Object.freeze({ bytes: call.tablesBytes, sha256: call.tablesSha256 })
          : null,
      });
    },
    close(): void {
      addon.closeHtmlPreparer(handle);
    },
  });
}
