import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

// Single source of truth: the stylesheet ships from @tiqian/core.
const stylesheet: string = readFileSync(
  new URL("../../core/styles.css", import.meta.url),
  "utf8"
);

test("static stylesheet exposes a runtime readiness marker", () => {
  assert.match(stylesheet, /:is\(tiqian-prose, \[data-tiqian-root\]\)/u);
  assert.match(stylesheet, /--tq-styles-ready:\s*1/u);
});

test("web lists keep native markers on a stable two-character body indent", () => {
  assert.match(stylesheet, /WebNativeTwoIcListIndent/u);
  assert.match(stylesheet, /DisabledRootKeepsHostListGeometry/u);
  assert.match(
    stylesheet,
    /:is\(tiqian-prose:not\(:where\(\[disabled\]\)\), \[data-tiqian-root\]\) :where\(ol, ul\)/u
  );
  assert.doesNotMatch(
    stylesheet,
    /:is\(tiqian-prose, \[data-tiqian-root\]\) :where\(ol, ul\)/u
  );
  assert.match(stylesheet, /:where\(ol, ul\):not\(\.footnotes-list\)/u);
  assert.match(
    stylesheet,
    /padding-inline-start:\s*var\(--tq-list-indent,\s*2ic\)\s*!important/u
  );
  assert.match(
    stylesheet,
    /:where\(ol, ul\):not\(\.footnotes-list\)\s*>\s*li\s*\{\s*padding-inline:\s*0\s*!important/u
  );
  assert.match(stylesheet, /list-style-position:\s*outside/u);
  assert.doesNotMatch(stylesheet, /data-tq-list-marker/u);
});

test("prepared DOM inherits the host font family contract", () => {
  assert.match(
    stylesheet,
    /Prepared DOM inherits the host's font-family unchanged/u
  );
  assert.match(stylesheet, /data-tiqian-snapshot-render-font="true"/u);
  assert.doesNotMatch(stylesheet, /--tq-(?:snapshot|runtime)-render-font-family/u);
  assert.match(stylesheet, /:not\(\[data-tiqian-snapshot-layout-fallback\]\)/u);
  assert.match(stylesheet, /\[data-tq-canonical-plain="true"\]/u);
  assert.match(stylesheet, /\[data-tq-snapshot-prepared-dom="true"\]/u);
  assert.match(stylesheet, /SnapshotPreparedShapingCss/u);
  assert.match(stylesheet, /font-kerning:\s*normal\s*!important/u);
  assert.match(stylesheet, /font-optical-sizing:\s*none\s*!important/u);
});

test("semantic and canonical paragraphs share the engine-owned line box", () => {
  assert.match(stylesheet, /EngineOwnedLineBox/u);
  assert.match(
    stylesheet,
    /\[data-tq-rendered="true"\]\s*\{[\s\S]*?line-height:\s*0\s*!important/u
  );
});

test("rendered paragraphs keep browser punctuation shaping out of engine geometry", () => {
  assert.match(stylesheet, /EngineOwnedPunctuationOpenTypeFeatures/u);
  assert.match(
    stylesheet,
    /font-feature-settings:\s*"halt" 0, "chws" 0, "palt" 0\s*!important/u
  );
  assert.match(
    stylesheet,
    /font-feature-settings:\s*"halt" 0, "chws" 0, "palt" 1\s*!important/u
  );
});

test("shaping boundaries outrank the generic geometry span reset", () => {
  assert.match(
    stylesheet,
    /\[data-tq-rendered="true"\] span\[data-tq-shaping-boundary\] \{/u
  );
  assert.match(
    stylesheet,
    /span\[data-tq-shaping-boundary\][^{]*\{[^}]*display:\s*inline-block\s*!important/u
  );
});

interface EventListenerEntry {
  listener: VoidFunction;
  once: boolean;
}

type AddEventListenerOptions = { once?: boolean };

class FakeLink {
  dataset: Record<string, string | undefined> = {};
  href: string = "";
  isConnected: boolean = false;
  rel: string = "";
  sheet: Record<string, unknown> | null = null;
  #listeners: Map<string, EventListenerEntry[]> = new Map();

  addEventListener(
    type: string,
    listener: VoidFunction,
    options: AddEventListenerOptions = {}
  ): void {
    const listeners: EventListenerEntry[] = this.#listeners.get(type) ?? [];
    listeners.push({ listener, once: options.once === true });
    this.#listeners.set(type, listeners);
  }

  emit(type: string): void {
    const listeners: EventListenerEntry[] = this.#listeners.get(type) ?? [];
    this.#listeners.set(
      type,
      listeners.filter(({ once }) => !once)
    );
    for (const { listener } of listeners) listener();
  }
}

interface MockDocumentHead {
  append(link: FakeLink): void;
}

interface MockDocument {
  createElement(name: string): FakeLink;
  head: MockDocumentHead;
  querySelector(selector: string): FakeLink | null;
}

test("reinstalls a stylesheet removed by a client router", async () => {
  const originalDocument: typeof globalThis.document = globalThis.document;
  const links: FakeLink[] = [];
  let currentLink: FakeLink | null = null;

  type EnsureTiqianStylesFunction = (doc: Document) => Promise<FakeLink | null>;

  const createElementFn = (name: string): FakeLink => {
    assert.equal(name, "link");
    const link: FakeLink = new FakeLink();
    links.push(link);
    return link;
  };

  const appendFn = (link: FakeLink): void => {
    link.isConnected = true;
    currentLink = link;
  };

  const querySelectorFn = (selector: string): FakeLink | null => {
    assert.equal(selector, "link[data-tiqian-stylesheet]");
    return currentLink?.isConnected ? currentLink : null;
  };

  const mockHead: MockDocumentHead = { append: appendFn };

  // Delete the real document and replace with our mock
  delete (globalThis as Record<string, unknown>).document;
  
  const mockDocBase: Record<string, unknown> = {
    createElement: createElementFn,
    head: mockHead,
    querySelector: querySelectorFn,
  };

  (globalThis as Record<string, unknown>).document = mockDocBase;

  try {
    interface EnsureTiqianStylesResult {
      ensureTiqianStyles: EnsureTiqianStylesFunction;
    }

    const module: EnsureTiqianStylesResult = await import(
      `@tiqian/core/src/engine/loaders/styles.js?test=${Date.now()}`
    );
    const ensureTiqianStyles: EnsureTiqianStylesFunction =
      module.ensureTiqianStyles;

    const firstLoad: Promise<FakeLink | null> =
      ensureTiqianStyles(globalThis.document);
    assert.equal(links.length, 1);
    assert.strictEqual(ensureTiqianStyles(globalThis.document), firstLoad);
    links[0].sheet = {};
    links[0].emit("load");
    assert.strictEqual(await firstLoad, links[0]);

    links[0].isConnected = false;
    currentLink = null;

    const secondLoad: Promise<FakeLink | null> =
      ensureTiqianStyles(globalThis.document);
    assert.equal(links.length, 2);
    assert.notStrictEqual(links[1], links[0]);
    links[1].sheet = {};
    links[1].emit("load");
    assert.strictEqual(await secondLoad, links[1]);

    assert.strictEqual(
      await ensureTiqianStyles(globalThis.document),
      links[1]
    );
    assert.equal(links.length, 2);
  } finally {
    globalThis.document = originalDocument;
  }
});

test("does not inject a duplicate link when the public CSS entry is already active", async () => {
  const originalDocument: Document | undefined = globalThis.document;
  const originalGetComputedStyle: typeof globalThis.getComputedStyle =
    globalThis.getComputedStyle;
  let queried: boolean = false;

  interface MockDocumentPartial extends Partial<Document> {
    querySelector(): null;
  }

  type GetComputedStyleFunction = () => Partial<CSSStyleDeclaration>;

  interface EnsureTiqianStylesModule {
    ensureTiqianStyles: EnsureTiqianStylesWithOptions;
  }

  type EnsureTiqianStylesWithOptions = (
    doc: Document,
    opts?: Record<string, unknown>
  ) => Promise<null>;

  const mockDocument: MockDocumentPartial = {
    querySelector(): null {
      queried = true;
      return null;
    },
  };

  const mockComputedStyle: Partial<CSSStyleDeclaration> = {
    getPropertyValue(property: string): string {
      return property === "--tq-styles-ready" ? "1" : "";
    },
  };

  globalThis.document = mockDocument as Document;
  const getComputedStyleFn: GetComputedStyleFunction = () => mockComputedStyle;
  globalThis.getComputedStyle = getComputedStyleFn as typeof globalThis.getComputedStyle;

  try {
    const module: EnsureTiqianStylesModule = await import(
      `@tiqian/core/src/engine/loaders/styles.js?static=${Date.now()}`
    );
    const ensureTiqianStyles: EnsureTiqianStylesWithOptions = module.ensureTiqianStyles;

    assert.equal(await ensureTiqianStyles(globalThis.document, {}), null);
    assert.equal(queried, false);
  } finally {
    globalThis.document = originalDocument;
    globalThis.getComputedStyle = originalGetComputedStyle;
  }
});
