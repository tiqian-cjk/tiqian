import type { sequence } from "@sveltejs/kit/hooks";
import type {
  HtmlPrepareOptions,
  HtmlPreparer,
  HtmlPreparerOptions,
  PreparedHtmlIssue,
  SnapshotServerAssets,
} from "@tiqian/precompute/precompute-html";
import type { SnapshotTableFileTransport } from "@tiqian/precompute/transport";
import type { ClientSnapshotBundle } from "@tiqian/web-component/snapshot-client";

// Both SvelteKit 2 and 3 expose the handle hook as an argument to sequence.
type Handle = Parameters<typeof sequence>[number];

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

export interface TiqianSvelteKit {
  prepare(html: string, options?: HtmlPrepareOptions): Promise<PreparedTiqianProse>;
  readonly handle: Handle;
  /** Present when a `tables` option was configured. */
  readonly tables?: SnapshotTableFileTransport;
  getServerAssets(id: string): SnapshotServerAssets | undefined;
  close(): Promise<void>;
}

export declare function injectTiqianSsrAssets(
  html: string,
  resolveAssets: (id: string) => SnapshotServerAssets | undefined,
): string;
export declare function createTiqianSvelteKit(options: TiqianSvelteKitOptions): TiqianSvelteKit;
export declare function createTiqianTables(
  options: TiqianSvelteKitTablesOptions,
): SnapshotTableFileTransport;
