export interface TiqianWebOptions {
  cjkFontFamily?: string;
  latinFontFamily?: string;
  monospaceFontFamily?: string;
  cjkSerifFontFamily?: string;
  latinSerifFontFamily?: string;
  fontSize?: number;
  lineHeight?: number;
  firstLineIndentIc?: number;
  emphasisDotCenterOffsetEm?: number;
  paragraphSelector?: string;
}

export interface TiqianWebGlobalApi {
  enhance(root?: HTMLElement, options?: TiqianWebOptions): HTMLElement;
  enhanceProgressively(root?: HTMLElement, options?: TiqianWebOptions): HTMLElement;
  destroy(root?: HTMLElement): void;
  enhanceAll(options?: TiqianWebOptions): void;
}

export declare function loadTiqianRuntime(): Promise<unknown>;
export declare function enhance(root?: HTMLElement, options?: TiqianWebOptions): Promise<HTMLElement>;
export declare function enhanceProgressively(
  root?: HTMLElement,
  options?: TiqianWebOptions,
): Promise<HTMLElement>;
export declare function destroy(root?: HTMLElement): Promise<void>;
export declare function enhanceAll(options?: TiqianWebOptions): Promise<HTMLElement[]>;

declare global {
  interface Window {
    TiqianWeb?: TiqianWebGlobalApi;
  }
}
