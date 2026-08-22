// Type surface of the browser-shared prepared-DOM module. The implementation
// is the exact file `@tiqian/prose` ships; this package re-exports
// `renderPreparedParagraph` so server embedders share one renderer.

export declare function renderPreparedParagraph(
  planOrJson: unknown,
  typographyOrLocale?: unknown,
): string;
