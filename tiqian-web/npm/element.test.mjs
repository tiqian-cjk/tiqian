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

test("initial font timeout retries the latest attributes and disconnect cancels stale work", async () => {
  const globalNames = [
    "document",
    "HTMLElement",
    "customElements",
    "getComputedStyle",
    "MutationObserver",
    "requestAnimationFrame",
    "cancelAnimationFrame",
    "setTimeout",
    "clearTimeout",
    "window",
    "TiqianWeb",
    "__tiqianCopyHandlerInstalled",
  ];
  const globals = preserveGlobals(globalNames);
  const documentListeners = new Map();
  const fontListeners = new Map();
  const fontLoads = [];
  const timers = new Set();
  let nextTimer = 1;

  class FakeMutationObserver {
    constructor(callback) {
      this.callback = callback;
    }
    observe() {}
    disconnect() {}
  }

  class FakeHTMLElement {
    constructor() {
      this.attributes = new Map();
      this.dataset = {};
      this.isConnected = true;
      this.parentElement = null;
      this.listeners = new Map();
      this.paragraph = {
        textContent: "正文",
        hasAttribute() {
          return false;
        },
        getAttribute() {
          return null;
        },
        querySelectorAll() {
          return [];
        },
      };
    }
    addEventListener(name, listener) {
      this.listeners.set(name, listener);
    }
    removeEventListener(name, listener) {
      if (this.listeners.get(name) === listener) this.listeners.delete(name);
    }
    getAttribute(name) {
      return this.attributes.get(name) ?? null;
    }
    hasAttribute(name) {
      return this.attributes.has(name);
    }
    setAttribute(name, value) {
      this.attributes.set(name, String(value));
    }
    removeAttribute(name) {
      this.attributes.delete(name);
    }
    toggleAttribute(name, force) {
      if (force) this.setAttribute(name, "");
      else this.removeAttribute(name);
    }
    querySelector() {
      return null;
    }
    querySelectorAll(selector) {
      return selector === "p, li" ? [this.paragraph] : [];
    }
    getBoundingClientRect() {
      return { width: 640 };
    }
  }

  const fonts = {
    status: "loading",
    load() {
      return new Promise((resolve) => fontLoads.push(resolve));
    },
    addEventListener(name, listener) {
      fontListeners.set(name, listener);
    },
    removeEventListener(name, listener) {
      if (fontListeners.get(name) === listener) fontListeners.delete(name);
    },
  };
  const documentObject = {
    fonts,
    addEventListener(name, listener) {
      documentListeners.set(name, listener);
    },
    removeEventListener(name, listener) {
      if (documentListeners.get(name) === listener) documentListeners.delete(name);
    },
    dispatchEvent() {},
    getElementById() {
      return null;
    },
    querySelectorAll() {
      return [];
    },
  };
  const elements = new Map();

  try {
    globalThis.document = documentObject;
    globalThis.HTMLElement = FakeHTMLElement;
    globalThis.customElements = {
      define(name, constructor) {
        elements.set(name, constructor);
      },
      get(name) {
        return elements.get(name);
      },
    };
    globalThis.getComputedStyle = (element) => ({
      getPropertyValue(property) {
        if (element instanceof FakeHTMLElement && property === "--tq-styles-ready") return "1";
        return {
          "font-family": '"Example CJK", sans-serif',
          "font-size": "16px",
          "font-style": "normal",
          "font-weight": "400",
          "font-stretch": "100%",
        }[property] ?? "";
      },
    });
    globalThis.MutationObserver = FakeMutationObserver;
    globalThis.requestAnimationFrame = (callback) => {
      queueMicrotask(() => callback(0));
      return 1;
    };
    globalThis.cancelAnimationFrame = () => {};
    globalThis.setTimeout = (callback) => {
      const id = nextTimer++;
      queueMicrotask(() => {
        if (!timers.has(id)) callback();
      });
      return id;
    };
    globalThis.clearTimeout = (id) => timers.add(id);
    globalThis.window = {
      addEventListener() {},
      removeEventListener() {},
    };
    delete globalThis.__tiqianCopyHandlerInstalled;

    const module = await import(`./element.js?font-lifecycle=${Date.now()}`);
    const element = new module.TiqianProseElement();
    element.connectedCallback();
    await new Promise((resolve) => setImmediate(resolve));

    assert.equal(element.dataset.tiqianFontWait, "timeout");
    assert.equal(element.hasAttribute("data-tiqian-enhanced"), false);
    assert.equal(fontLoads.length, 1);
    assert.equal(fontListeners.has("loadingdone"), true);
    assert.equal(fontListeners.has("loadingerror"), true);

    fontListeners.get("loadingdone")({
      fontfaces: [{ family: "Example CJK", weight: "400", style: "normal" }],
    });
    await new Promise((resolve) => setImmediate(resolve));

    assert.equal(fontLoads.length, 2);
    assert.equal(element.dataset.tiqianFontWait, "timeout");

    element.setAttribute("emphasis-dot-gap-em", "0.2");
    element.attributeChangedCallback("emphasis-dot-gap-em", null, "0.2");
    await new Promise((resolve) => setImmediate(resolve));

    assert.equal(fontLoads.length, 3);
    assert.equal(element.dataset.tiqianFontWait, "timeout");

    element.isConnected = false;
    element.disconnectedCallback();
    fontLoads.forEach((resolve) => resolve([]));
    await new Promise((resolve) => setImmediate(resolve));

    assert.equal(fontLoads.length, 3);
    assert.equal(fontListeners.has("loadingdone"), false);
    assert.equal(fontListeners.has("loadingerror"), false);
    assert.equal(element.dataset.tiqianFontWait, undefined);
  } finally {
    restoreGlobals(globals);
  }
});
