import assert from "node:assert/strict";
import test from "node:test";

import { parseBuildFontStylesheet } from "./precompute-node-fonts.js";

test("build font stylesheets reuse host families and resolve both asset namespaces", () => {
  const faces = parseBuildFontStylesheet(`
    @font-face {
      font-family: "Fixture CJK";
      font-style: normal;
      font-weight: 500;
      src: local("Fixture CJK Medium"), url("./shards/fixture-001.woff2") format("woff2");
      unicode-range: U+4E00-4EFF;
    }
  `, {
    source: new URL("./fixtures/host-fonts.css", import.meta.url),
    publicUrl: "/fonts/host-fonts.css",
  });

  assert.equal(faces.length, 1);
  assert.equal(faces[0].family, "Fixture CJK");
  assert.equal(faces[0].source, new URL(
    "./fixtures/shards/fixture-001.woff2",
    import.meta.url,
  ).pathname);
  assert.equal(faces[0].publicUrl, "/fonts/shards/fixture-001.woff2");
  assert.equal(faces[0].weight, 500);
  assert.equal(faces[0].style, "normal");
  assert.equal(faces[0].unicodeRange, "U+4E00-4EFF");
});

test("relative font assets require the stylesheet's browser URL", () => {
  assert.throws(() => parseBuildFontStylesheet(`
    @font-face { font-family: Fixture; src: url(fixture.woff2); }
  `, {
    source: new URL("./fixtures/host-fonts.css", import.meta.url),
  }), /MissingFontStylesheetPublicUrl/u);
});
