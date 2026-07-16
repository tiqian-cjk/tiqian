import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const stylesheet = readFileSync(new URL("./styles.css", import.meta.url), "utf8");

test("static stylesheet exposes a runtime readiness marker", () => {
  assert.match(stylesheet, /--tq-styles-ready:\s*1/u);
});

test("web lists keep native markers on a stable two-character body indent", () => {
  assert.match(stylesheet, /WebNativeTwoIcListIndent/u);
  assert.match(stylesheet, /:where\(ol, ul\):not\(\.footnotes-list\)/u);
  assert.match(
    stylesheet,
    /padding-inline-start:\s*var\(--tq-list-indent,\s*2ic\)\s*!important/u,
  );
  assert.match(
    stylesheet,
    /:where\(ol, ul\):not\(\.footnotes-list\)\s*>\s*li\s*\{\s*padding-inline:\s*0\s*!important/u,
  );
  assert.match(stylesheet, /list-style-position:\s*outside/u);
  assert.doesNotMatch(stylesheet, /data-tq-list-marker/u);
});

test("exact prepared DOM renders through the manifest font family contract", () => {
  assert.match(stylesheet, /ExactRenderFontContract/u);
  assert.match(stylesheet, /data-tiqian-exact-render-font="true"/u);
  assert.match(stylesheet, /var\(--tq-exact-render-font-family\)/u);
  assert.match(stylesheet, /:not\(\[data-tiqian-exact-layout-fallback\]\)/u);
  assert.match(stylesheet, /ExactPreparedShapingCss/u);
  assert.match(stylesheet, /font-kerning:\s*normal\s*!important/u);
  assert.match(stylesheet, /font-optical-sizing:\s*none\s*!important/u);
});

test("semantic and canonical paragraphs share the engine-owned line box", () => {
  assert.match(stylesheet, /EngineOwnedLineBox/u);
  assert.match(
    stylesheet,
    /\[data-tq-rendered="true"\]\s*\{\s*line-height:\s*0\s*!important/u,
  );
});

test("shaping boundaries outrank the generic geometry span reset", () => {
  assert.match(
    stylesheet,
    /\[data-tq-rendered="true"\] span\[data-tq-shaping-boundary\] \{/u,
  );
});

class FakeLink {
  dataset = {};
  href = "";
  isConnected = false;
  rel = "";
  sheet = null;
  #listeners = new Map();

  addEventListener(type, listener, options = {}) {
    const listeners = this.#listeners.get(type) ?? [];
    listeners.push({ listener, once: options.once === true });
    this.#listeners.set(type, listeners);
  }

  emit(type) {
    const listeners = this.#listeners.get(type) ?? [];
    this.#listeners.set(type, listeners.filter(({ once }) => !once));
    for (const { listener } of listeners) listener();
  }
}

test("reinstalls a stylesheet removed by a client router", async () => {
  const originalDocument = globalThis.document;
  const links = [];
  let currentLink = null;
  globalThis.document = {
    createElement(name) {
      assert.equal(name, "link");
      const link = new FakeLink();
      links.push(link);
      return link;
    },
    head: {
      append(link) {
        link.isConnected = true;
        currentLink = link;
      },
    },
    querySelector(selector) {
      assert.equal(selector, "link[data-tiqian-stylesheet]");
      return currentLink?.isConnected ? currentLink : null;
    },
  };

  try {
    const { ensureTiqianStyles } = await import(`./styles.js?test=${Date.now()}`);

    const firstLoad = ensureTiqianStyles();
    assert.equal(links.length, 1);
    assert.strictEqual(ensureTiqianStyles(), firstLoad);
    links[0].sheet = {};
    links[0].emit("load");
    assert.strictEqual(await firstLoad, links[0]);

    links[0].isConnected = false;
    currentLink = null;

    const secondLoad = ensureTiqianStyles();
    assert.equal(links.length, 2);
    assert.notStrictEqual(links[1], links[0]);
    links[1].sheet = {};
    links[1].emit("load");
    assert.strictEqual(await secondLoad, links[1]);

    assert.strictEqual(await ensureTiqianStyles(), links[1]);
    assert.equal(links.length, 2);
  } finally {
    globalThis.document = originalDocument;
  }
});

test("does not inject a duplicate link when the public CSS entry is already active", async () => {
  const originalDocument = globalThis.document;
  const originalGetComputedStyle = globalThis.getComputedStyle;
  let queried = false;
  globalThis.document = {
    querySelector() {
      queried = true;
      return null;
    },
  };
  globalThis.getComputedStyle = () => ({
    getPropertyValue(property) {
      return property === "--tq-styles-ready" ? "1" : "";
    },
  });
  try {
    const { ensureTiqianStyles } = await import(`./styles.js?static=${Date.now()}`);
    assert.equal(await ensureTiqianStyles({}), null);
    assert.equal(queried, false);
  } finally {
    globalThis.document = originalDocument;
    globalThis.getComputedStyle = originalGetComputedStyle;
  }
});
