import assert from "node:assert/strict";
import test from "node:test";
import {
  captureViewportAnchor,
  compensateViewportAnchor,
  holdNativeScrollAnchoring,
  releaseNativeScrollAnchoring,
} from "./viewport-anchor.js";

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

// The gesture tracker installs window listeners once per module instance; a
// per-test fake window would only see them in the first test. One shared fake
// view receives the listeners and every test drives it.
const listeners = new Map();
const view = {
  innerHeight: 844,
  scrollY: 100,
  addEventListener(type, listener) {
    const bucket = listeners.get(type) ?? new Set();
    bucket.add(listener);
    listeners.set(type, bucket);
  },
  removeEventListener(type, listener) {
    listeners.get(type)?.delete(listener);
  },
  scrollBy(_x, delta) {
    this.scrollY += delta;
  },
  fire(type) {
    for (const listener of listeners.get(type) ?? []) listener({ type });
  },
};

let now = 0;
const clock = {
  advance(ms) {
    now += ms;
  },
};

function installFakeBrowser() {
  let layoutShift = 0;
  const paragraph = {
    isConnected: true,
    closest: (selector) => (selector === "tiqian-prose, [data-tiqian-root]" ? root : null),
    getBoundingClientRect() {
      const top = 420 + layoutShift - view.scrollY;
      return { top, bottom: top + 120 };
    },
  };
  const properties = new Map();
  const documentElementProperties = new Map();
  const documentElement = {
    style: {
      getPropertyValue: (name) => documentElementProperties.get(name)?.value ?? "",
      getPropertyPriority: (name) => documentElementProperties.get(name)?.priority ?? "",
      setProperty(name, value, priority = "") {
        documentElementProperties.set(name, { value, priority });
      },
      removeProperty(name) {
        documentElementProperties.delete(name);
      },
    },
  };
  const root = {
    ownerDocument: { defaultView: view, scrollingElement: null, documentElement },
    parentElement: null,
    isConnected: true,
    style: {
      getPropertyValue: (name) => properties.get(name)?.value ?? "",
      getPropertyPriority: (name) => properties.get(name)?.priority ?? "",
      setProperty(name, value, priority = "") {
        properties.set(name, { value, priority });
      },
      removeProperty(name) {
        properties.delete(name);
      },
    },
    closest: () => root,
    querySelectorAll: () => [paragraph],
    getBoundingClientRect: () => ({ top: 0 - view.scrollY + 100, bottom: 1700 - view.scrollY + 100 }),
  };
  globalThis.performance = { now: () => now };
  globalThis.getComputedStyle = () => ({ overflowY: "visible", overflow: "visible" });
  globalThis.window = view;
  return {
    root,
    paragraph,
    set layoutShift(value) {
      layoutShift = value;
    },
  };
}

const globalNames = ["performance", "getComputedStyle", "window"];

test("a capture/compensate pair around a commit keeps the anchor paragraph in place", () => {
  const globals = preserveGlobals(globalNames);
  const browser = installFakeBrowser();
  view.scrollY = 100;
  clock.advance(10_000);
  try {
    const initialTop = browser.paragraph.getBoundingClientRect().top;
    const anchor = captureViewportAnchor(browser.root);
    assert.ok(anchor);
    assert.equal(anchor.node, browser.paragraph);
    browser.layoutShift = 80;
    assert.equal(compensateViewportAnchor(browser.root, anchor), true);
    assert.equal(view.scrollY, 180);
    assert.equal(browser.paragraph.getBoundingClientRect().top, initialTop);
  } finally {
    restoreGlobals(globals);
  }
});

test("sub-pixel displacement is left alone", () => {
  const globals = preserveGlobals(globalNames);
  const browser = installFakeBrowser();
  view.scrollY = 100;
  clock.advance(10_000);
  try {
    const anchor = captureViewportAnchor(browser.root);
    browser.layoutShift = 0.25;
    assert.equal(compensateViewportAnchor(browser.root, anchor), false);
    assert.equal(view.scrollY, 100);
  } finally {
    restoreGlobals(globals);
  }
});

test("an active gesture suppresses capture and momentum scrolling extends the grace", () => {
  const globals = preserveGlobals(globalNames);
  const browser = installFakeBrowser();
  view.scrollY = 100;
  clock.advance(10_000);
  try {
    view.fire("wheel");
    assert.equal(captureViewportAnchor(browser.root), null);

    // MomentumScrollContinuation: scroll events shortly after a gesture keep
    // the grace alive even though no further input events arrive.
    clock.advance(400);
    view.fire("scroll");
    assert.equal(captureViewportAnchor(browser.root), null);

    // An isolated scroll long after the last gesture (such as this module's
    // own correction) does not open a grace window.
    clock.advance(2_000);
    view.fire("scroll");
    assert.ok(captureViewportAnchor(browser.root));
  } finally {
    restoreGlobals(globals);
  }
});

test("a scroller at its top is never adjusted", () => {
  const globals = preserveGlobals(globalNames);
  const browser = installFakeBrowser();
  clock.advance(10_000);
  try {
    view.scrollY = 0;
    assert.equal(captureViewportAnchor(browser.root), null);
    view.scrollY = 1;
    assert.ok(captureViewportAnchor(browser.root));
  } finally {
    restoreGlobals(globals);
  }
});

test("a root above the viewport anchors on its bottom edge; one below is left alone", () => {
  const globals = preserveGlobals(globalNames);
  const browser = installFakeBrowser();
  clock.advance(10_000);
  try {
    view.scrollY = 5_000;
    let shrink = 0;
    browser.root.getBoundingClientRect = () => ({ top: -4_900, bottom: -3_300 - shrink });
    const anchor = captureViewportAnchor(browser.root);
    assert.equal(anchor?.edge, "bottom");
    // Content inside the above-viewport root shrinks by 60px; the viewport is
    // scrolled up by the same amount so visible content stays put.
    shrink = 60;
    assert.equal(compensateViewportAnchor(browser.root, anchor), true);
    assert.equal(view.scrollY, 4_940);

    browser.root.getBoundingClientRect = () => ({ top: 900, bottom: 2_500 });
    assert.equal(captureViewportAnchor(browser.root), null);
  } finally {
    restoreGlobals(globals);
  }
});

test("a detached anchor node cancels the compensation", () => {
  const globals = preserveGlobals(globalNames);
  const browser = installFakeBrowser();
  view.scrollY = 100;
  clock.advance(10_000);
  try {
    const anchor = captureViewportAnchor(browser.root);
    browser.paragraph.isConnected = false;
    browser.layoutShift = 80;
    assert.equal(compensateViewportAnchor(browser.root, anchor), false);
    assert.equal(view.scrollY, 100);
  } finally {
    restoreGlobals(globals);
  }
});

test("the scroller's native anchoring is held during a job and handed back afterwards", () => {
  const globals = preserveGlobals(globalNames);
  const browser = installFakeBrowser();
  try {
    const owner = browser.root.ownerDocument.documentElement;
    owner.style.setProperty("overflow-anchor", "auto", "important");
    holdNativeScrollAnchoring(browser.root);
    assert.equal(owner.style.getPropertyValue("overflow-anchor"), "none");
    // A second hold from the same root is idempotent and one release restores.
    holdNativeScrollAnchoring(browser.root);
    releaseNativeScrollAnchoring(browser.root);
    assert.equal(owner.style.getPropertyValue("overflow-anchor"), "auto");
    assert.equal(owner.style.getPropertyPriority("overflow-anchor"), "important");
    releaseNativeScrollAnchoring(browser.root);
    assert.equal(owner.style.getPropertyValue("overflow-anchor"), "auto");
  } finally {
    restoreGlobals(globals);
  }
});

test("compensation targets the nearest scrollable ancestor before the window", () => {
  const globals = preserveGlobals(globalNames);
  const browser = installFakeBrowser();
  view.scrollY = 100;
  clock.advance(10_000);
  try {
    const scroller = {
      parentElement: null,
      scrollTop: 40,
      scrollHeight: 4_000,
      clientHeight: 800,
    };
    browser.root.parentElement = scroller;
    globalThis.getComputedStyle = (element) => element === scroller
      ? { overflowY: "auto", overflow: "auto" }
      : { overflowY: "visible", overflow: "visible" };
    const anchor = captureViewportAnchor(browser.root);
    browser.layoutShift = 60;
    assert.equal(compensateViewportAnchor(browser.root, anchor), true);
    assert.equal(scroller.scrollTop, 100);
    assert.equal(view.scrollY, 100);
  } finally {
    restoreGlobals(globals);
  }
});
