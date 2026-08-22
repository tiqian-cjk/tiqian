import type { Handle } from "@sveltejs/kit";
import type {
  HtmlPrepareOptions,
  HtmlPreparer,
  HtmlPreparerOptions,
  PreparedHtmlIssue,
  SnapshotServerAssets,
} from "@tiqian/precompute/precompute-html";
import type { ClientSnapshotBundle } from "@tiqian/prose/snapshot-client";

export interface PreparedTiqianProse {
  readonly html: string;
  readonly rootAttributes: Readonly<Record<string, string>>;
  readonly snapshot: ClientSnapshotBundle | null;
  readonly issues: readonly PreparedHtmlIssue[];
}

export interface TiqianSvelteKitRetentionOptions {
  readonly maximumRetainedBundles?: number;
}

export type TiqianSvelteKitOptions = TiqianSvelteKitRetentionOptions & (
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
  getServerAssets(id: string): SnapshotServerAssets | undefined;
  close(): Promise<void>;
}

export declare function injectTiqianSsrAssets(
  html: string,
  resolveAssets: (id: string) => SnapshotServerAssets | undefined,
): string;
export declare function createTiqianSvelteKit(options: TiqianSvelteKitOptions): TiqianSvelteKit;
