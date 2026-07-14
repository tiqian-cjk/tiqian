import assert from "node:assert/strict";
import test from "node:test";

function preserveGlobals(names) {
  return names.map((name) => ({
    name,
    own: Object.prototype.hasOwnProperty.call(globalThis, name),
    value: globalThis[name],
  }));
}

function restoreGlobals(entries) {
  for (const { name, own, value } of entries) {
    if (own) globalThis[name] = value;
    else delete globalThis[name];
  }
}

test("element entry imports without browser globals during SSR", async () => {
  const globals = preserveGlobals(["document", "HTMLElement", "customElements"]);
  try {
    delete globalThis.document;
    delete globalThis.HTMLElement;
    delete globalThis.customElements;

    const module = await import(`./element.js?ssr=${Date.now()}`);

    assert.equal(typeof module.TiqianProseElement, "function");
  } finally {
    restoreGlobals(globals);
  }
});

test("element entry still registers the browser custom element", async () => {
  const globals = preserveGlobals(["document", "HTMLElement", "customElements"]);
  const elements = new Map();
  class FakeHTMLElement {}
  try {
    delete globalThis.document;
    globalThis.HTMLElement = FakeHTMLElement;
    globalThis.customElements = {
      define(name, constructor) {
        assert.equal(elements.has(name), false);
        elements.set(name, constructor);
      },
      get(name) {
        return elements.get(name);
      },
    };

    const module = await import(`./element.js?browser=${Date.now()}`);

    assert.strictEqual(elements.get("tiqian-prose"), module.TiqianProseElement);
    assert.ok(module.TiqianProseElement.prototype instanceof FakeHTMLElement);
  } finally {
    restoreGlobals(globals);
  }
});
