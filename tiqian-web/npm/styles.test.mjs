import assert from "node:assert/strict";
import test from "node:test";

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
