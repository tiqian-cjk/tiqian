import assert from "node:assert/strict";
import test from "node:test";

import { registerSnapshotBundle } from "./snapshot-client.js";

function fakeDocument() {
  const elements = new Map();
  const headChildren = [];
  let replacements = 0;

  const templateNode = (id, manifest) => ({
    tagName: "TEMPLATE",
    id,
    content: {
      querySelector(selector) {
        return selector === "[data-tq-snapshot-manifest]" ? { textContent: manifest } : null;
      },
    },
    replaceWith(replacement) {
      replacements += 1;
      elements.set(id, replacement);
    },
  });

  const documentObject = {
    baseURI: "https://example.test/post/",
    head: {
      append(node) {
        headChildren.push(node);
        if (node.tagName === "TEMPLATE") elements.set(node.id, node);
      },
    },
    createElement(name) {
      if (name === "template") {
        const content = { firstElementChild: null, childElementCount: 0 };
        return {
          content,
          set innerHTML(value) {
            const id = /<template\s+id="([^"]+)"/u.exec(value)?.[1] ?? "";
            const manifest = /<script[^>]*data-tq-snapshot-manifest[^>]*>([^<]*)<\/script>/u
              .exec(value)?.[1] ?? "";
            content.firstElementChild = templateNode(id, manifest);
            content.childElementCount = 1;
          },
        };
      }
      const element = {
        tagName: name.toUpperCase(),
        attributes: new Map(),
        setAttribute(key, value) {
          this.attributes.set(key, value);
        },
      };
      if (name === "link") {
        let href = "";
        Object.defineProperty(element, "href", {
          get: () => href,
          set: (value) => {
            href = new URL(value, documentObject.baseURI).href;
          },
        });
      }
      return element;
    },
    getElementById(id) {
      return elements.get(id) ?? null;
    },
    querySelector(selector) {
      if (!selector.startsWith("style[")) return null;
      return headChildren.find((node) => node.tagName === "STYLE" &&
        (node.attributes.get("data-tq-initial-snapshot") === "tq-page" ||
          node.attributes.get("data-tq-client-snapshot") === "tq-page")) ?? null;
    },
    querySelectorAll(selector) {
      assert.equal(selector, 'link[rel="preload"][as="font"]');
      return headChildren.filter((node) => node.tagName === "LINK" &&
        node.rel === "preload" && node.as === "font");
    },
  };
  elements.set("tq-page", templateNode("tq-page", "stale"));
  return { documentObject, elements, headChildren, replacements: () => replacements };
}

test("client navigation replaces a stale manifest and registers assets once", () => {
  const setup = fakeDocument();
  const bundle = {
    id: "tq-page",
    clientTemplate: '<template id="tq-page"><script data-tq-snapshot-manifest>{"v":1}</script></template>',
    initialStyle: ':root{--fixture:1}',
    fontPreloads: ["/fonts/fixture-deadbeef.woff2"],
  };

  assert.equal(registerSnapshotBundle(bundle, setup.documentObject), "tq-page");
  assert.equal(setup.replacements(), 1);
  assert.equal(
    setup.elements.get("tq-page").content.querySelector("[data-tq-snapshot-manifest]").textContent,
    '{"v":1}',
  );
  assert.equal(setup.headChildren.filter((node) => node.tagName === "STYLE").length, 1);
  assert.equal(setup.headChildren.filter((node) => node.tagName === "LINK").length, 1);

  assert.equal(registerSnapshotBundle(bundle, setup.documentObject), "tq-page");
  assert.equal(setup.replacements(), 1);
  assert.equal(setup.headChildren.filter((node) => node.tagName === "STYLE").length, 1);
  assert.equal(setup.headChildren.filter((node) => node.tagName === "LINK").length, 1);
});

test("client snapshot registration rejects an id/template mismatch", () => {
  const setup = fakeDocument();
  assert.throws(() => registerSnapshotBundle({
    id: "tq-page",
    clientTemplate: '<template id="tq-other"></template>',
    initialStyle: "",
    fontPreloads: [],
  }, setup.documentObject), /SnapshotClientTemplateInvalid/u);
});
