// Computed letter-spacing and word-spacing for the fake DOM text measurement.

type ComputedStyleReader = (element: Element) => CSSStyleDeclaration | undefined;

function pxValue(raw: string): number {
  const match = /^(-?\d+(?:\.\d+)?)px/.exec(raw.trim());
  return match ? Number.parseFloat(match[1]) : 0;
}

function computedStyleOf(element: Element): CSSStyleDeclaration | undefined {
  const computed = (globalThis as Record<string, unknown>).getComputedStyle as ComputedStyleReader | undefined;
  return computed?.(element);
}

export function computedLetterSpacingPx(element: Element | null): number {
  if (!element || element.nodeType !== 1) return 0;
  return pxValue(String(computedStyleOf(element)?.getPropertyValue("letter-spacing") ?? ""));
}

/** word-spacing a browser adds to each U+0020 and U+00A0; `classValue` reads a prepared value-style class. */
export function computedWordSpacingPx(element: Element | null, classValue: (element: Element) => string): number {
  if (!element || element.nodeType !== 1) return 0;
  const computedValue = String(computedStyleOf(element)?.getPropertyValue("word-spacing") ?? "").trim();
  return pxValue(computedValue === "" || computedValue === "normal" ? classValue(element) : computedValue);
}
