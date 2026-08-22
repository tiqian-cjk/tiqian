import type { AstroIntegration } from "astro";
import type {
  BuildFontFace,
  BuildFontStylesheet,
  SnapshotTypography,
} from "@tiqian/precompute/precompute";

export interface TiqianAstroPrecomputeOptions {
  readonly typography: SnapshotTypography;
  readonly fontStylesheets?: readonly BuildFontStylesheet[];
  readonly faces?: readonly BuildFontFace[];
  /** Only simple tag-name lists such as `p, li` are supported. */
  readonly paragraphSelector?: string;
  readonly skippedAncestorSelector?: string;
  /** Optional fixed-measure snapshot optimization; omitted by default. */
  readonly snapshot?: { readonly maxWidthPx: number };
}

export type TiqianAstroOptions = TiqianAstroPrecomputeOptions | {
  readonly typography?: undefined;
  readonly fontStylesheets?: undefined;
  readonly faces?: undefined;
  readonly snapshot?: undefined;
};

export declare function tiqian(options?: TiqianAstroOptions): AstroIntegration;
export default tiqian;
