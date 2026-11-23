import { AsyncLocalStorage } from "node:async_hooks";
import { fileURLToPath } from "node:url";

import type { sequence } from "@sveltejs/kit/hooks";
import {
  createHtmlPreparer,
  renderSnapshotServerAssets,
  type HtmlPrepareOptions,
  type HtmlPreparer,
  type HtmlPreparerOptions,
  type PreparedHtml,
  type PreparedHtmlIssue,
  type SnapshotServerAssets,
} from "@tiqian/precompute/precompute-html";
import {
  createSnapshotTableFileTransport,
  type SnapshotTableFileTransport,
} from "@tiqian/precompute/transport";
import type { ClientSnapshotBundle } from "@tiqian/web-component/snapshot-client";

// Both SvelteKit 2 and 3 expose the handle hook as an argument to sequence.
type Handle = Parameters<typeof sequence>[number];

const SNAPSHOT_REFERENCE = /<tiqian-prose\b[^>]*\bsnapshot-ref=(["'])([A-Za-z][A-Za-z0-9_-]*)\1[^>]*>/giu;

export interface PreparedTiqianProse {
  readonly html: string;
  readonly rootAttributes: Readonly<Record<string, string>>;
  readonly snapshot: ClientSnapshotBundle | null;
  readonly issues: readonly PreparedHtmlIssue[];
}

export interface TiqianSvelteKitRetentionOptions {
  readonly maximumRetainedBundles?: number;
}

export interface TiqianSvelteKitTablesOptions {
  /** Only a production build writes this directory. */
  readonly directory: string | URL;
  /** Written instead of `directory` outside production builds. */
  readonly devDirectory?: string | URL;
  readonly urlPrefix?: string;
  readonly extension?: string;
}

export type TiqianSvelteKitOptions = TiqianSvelteKitRetentionOptions &
  { readonly tables?: TiqianSvelteKitTablesOptions } & (
  | {
    readonly htmlPreparer: HtmlPreparer;
    readonly precomputer?: never;
    readonly fontStylesheets?: never;
    readonly faces?: never;
    readonly typography?: never;
  }
  | (HtmlPreparerOptions & { readonly htmlPreparer?: undefined })
);

export type TiqianSvelteKitInput =
  | TiqianSvelteKitOptions
  | (TiqianSvelteKitRetentionOptions & {
      readonly tables?: TiqianSvelteKitTablesOptions;
      readonly htmlPreparer?: HtmlPreparer;
    });

export interface TiqianSvelteKit {
  prepare(html: string, options?: HtmlPrepareOptions): Promise<PreparedTiqianProse>;
  readonly handle: Handle;
  /** Present when a `tables` option was configured. */
  readonly tables?: SnapshotTableFileTransport;
  getServerAssets(id: string): SnapshotServerAssets | undefined;
  close(): Promise<void>;
}

export type SvelteKitAssetResolver = (id: string) => SnapshotServerAssets | undefined;

export interface SvelteKitTransformChunkInput {
  readonly html: string;
  readonly done: boolean;
}

/**
 * Builds the snapshot-table file transport of a `tables` option (ADR 0052
 * `TableTransport`) for hosts that own their preparation pipeline and call
 * the transport directly. Only a production build writes `directory`; dev,
 * test, and an unset NODE_ENV write `devDirectory` when it is configured.
 * The build directory therefore only changes through a build.
 */
export function createTiqianTables(
  options?: TiqianSvelteKitTablesOptions | unknown,
): SnapshotTableFileTransport {
  if (typeof options !== "object" || options === null) {
    throw new Error("TiqianSvelteKitTablesOptionsInvalid");
  }
  const input = options as TiqianSvelteKitTablesOptions;
  const directory = input.directory;
  if (typeof directory !== "string" && !(directory instanceof URL)) {
    throw new Error("TiqianSvelteKitTablesDirectoryRequired");
  }
  const devDirectory = input.devDirectory;
  if (devDirectory !== undefined && typeof devDirectory !== "string" && !(devDirectory instanceof URL)) {
    throw new Error("TiqianSvelteKitTablesOptionsInvalid");
  }
  const selectedDirectory = process.env.NODE_ENV === "production" ? directory : (devDirectory ?? directory);
  return createSnapshotTableFileTransport({
    directory: selectedDirectory instanceof URL ? fileURLToPath(selectedDirectory) : selectedDirectory,
    urlPrefix: input.urlPrefix,
    extension: input.extension,
  });
}

export function injectTiqianSsrAssets(
  htmlValue: unknown,
  resolveAssets: SvelteKitAssetResolver,
): string {
  const html = String(htmlValue);
  const matches = Array.from(html.matchAll(SNAPSHOT_REFERENCE));
  const ids = new Set<string>(matches.map((match: RegExpExecArray): string => match[2]));
  const assets = Array.from(ids, (id: string): SnapshotServerAssets | undefined => resolveAssets(id)).filter(
    (asset: SnapshotServerAssets | undefined): asset is SnapshotServerAssets => Boolean(asset),
  );
  if (assets.length === 0) return html;
  if (!html.includes("</head>")) throw new Error("TiqianSvelteKitHeadUnavailable");
  const rendered = assets.map((asset: SnapshotServerAssets): string => renderSnapshotServerAssets(asset)).join("");
  return html.replace("</head>", (): string => `${rendered}\n</head>`);
}

function sameServerAssets(left: SnapshotServerAssets, right: SnapshotServerAssets): boolean {
  return left.id === right.id &&
    left.initialStyle === right.initialStyle &&
    left.inertTemplate === right.inertTemplate &&
    left.fontPreloads.length === right.fontPreloads.length &&
    left.fontPreloads.every((href: string, index: number): boolean => href === right.fontPreloads[index]);
}

/**
 * One SvelteKit server boundary owns exact-font preparation, SSR head assets,
 * and the compact object serialized through route data for client navigation.
 * A `tables` option adds snapshot-table delivery: `prepare` writes each
 * per-item table the preparer freezes and stamps the root's `tq-tables`
 * attribute with the served URL; the exposed transport backs a prerendered
 * route so the built output ships the bytes the manifests pin.
 * `createTiqianTables` exports the same transport on its own for hosts that
 * run their own preparation pipeline.
 */
export function createTiqianSvelteKit(options: TiqianSvelteKitInput = {}): TiqianSvelteKit {
  const retainedAssets = new Map<string, SnapshotServerAssets>();
  const requestAssets = new AsyncLocalStorage<Map<string, SnapshotServerAssets>>();
  const maximumRetainedBundles = Number(options.maximumRetainedBundles ?? 256);
  if (!Number.isSafeInteger(maximumRetainedBundles) || maximumRetainedBundles <= 0) {
    throw new Error("InvalidMaximumRetainedTiqianBundles");
  }
  const tablesOptions = options.tables ?? null;
  const tableTransport = tablesOptions == null ? null : createTiqianTables(tablesOptions);
  const preparerPromise: Promise<HtmlPreparer> = "htmlPreparer" in options && options.htmlPreparer != null
    ? Promise.resolve(options.htmlPreparer)
    : createHtmlPreparer(options as HtmlPreparerOptions);

  const retain = (
    assets: SnapshotServerAssets | null | undefined,
    target: Map<string, SnapshotServerAssets> = requestAssets.getStore() ?? retainedAssets,
  ): void => {
    if (!assets) return;
    const existing = target.get(assets.id);
    if (existing && !sameServerAssets(existing, assets)) {
      throw new Error(`ConflictingTiqianSvelteKitAssets:${assets.id}`);
    }
    target.delete(assets.id);
    target.set(assets.id, assets);
    while (target.size > maximumRetainedBundles) {
      const firstKey = target.keys().next().value;
      if (firstKey !== undefined) {
        target.delete(firstKey);
      }
    }
  };

  const prepare = async (
    html: string,
    prepareOptions: HtmlPrepareOptions = {},
  ): Promise<PreparedTiqianProse> => {
    const preparer = await preparerPromise;
    const result: PreparedHtml = await preparer.prepare(html, prepareOptions);
    retain(result.serverAssets);
    // The native call freezes per-item table bytes; the transport serves
    // them and the root attribute points the runtime at the URL.
    const rootAttributes = result.tables != null && tableTransport != null
      ? { ...result.rootAttributes, "tq-tables": tableTransport.write(result.tables) }
      : result.rootAttributes;
    return Object.freeze({
      html: result.html,
      rootAttributes,
      snapshot: result.clientBundle,
      issues: result.issues,
    });
  };

  const handle: Handle = async ({ event, resolve }): Promise<Response> => {
    const scopedAssets = new Map<string, SnapshotServerAssets>();
    return requestAssets.run(scopedAssets, async (): Promise<Response> => {
      let bufferedHtml = "";
      return resolve(event, {
        transformPageChunk: ({ html, done }: SvelteKitTransformChunkInput): string => {
          bufferedHtml += html;
          if (!done) return "";
          return injectTiqianSsrAssets(
            bufferedHtml,
            (id: string): SnapshotServerAssets | undefined => scopedAssets.get(id) ?? retainedAssets.get(id),
          );
        },
      });
    });
  };

  return Object.freeze({
    prepare,
    handle,
    ...(tableTransport == null ? {} : { tables: tableTransport }),
    getServerAssets(id: string): SnapshotServerAssets | undefined {
      const key = String(id);
      return requestAssets.getStore()?.get(key) ?? retainedAssets.get(key);
    },
    async close(): Promise<void> {
      const preparer = await preparerPromise;
      preparer.close();
      retainedAssets.clear();
    },
  });
}
